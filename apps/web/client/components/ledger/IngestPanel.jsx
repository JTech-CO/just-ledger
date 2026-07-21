// 명세서 업로드 패널 최소판 (M3-C). 파일 드롭/선택 → Worker 파싱 → 패스프레이즈로
// 암호화 → 업로드(202) → 상태 폴링. 서버에는 지문·일자·금액·통화만 간다 (INV-6).
// 진행률 실시간 스트리밍은 M7, 세련된 UI 는 M8.

import { useState, useRef } from 'react';
import { useIngestWorker } from '../../hooks/useIngestWorker.js';
import { api } from '../../lib/api.js';
import { formatMinor } from '../../lib/money.js';

/**
 * @param {{ accounts: Array<Object>, onDone: () => void }} props
 */
export default function IngestPanel({ accounts, onDone }) {
  const { parse, buildPayload } = useIngestWorker();
  const [accountId, setAccountId] = useState('');
  const [passphrase, setPassphrase] = useState('');
  const [phase, setPhase] = useState('idle'); // idle|parsing|encrypting|uploading|processing|done|error
  const [summary, setSummary] = useState(null);
  const [error, setError] = useState(null);
  const fileRef = useRef(null);

  const bankAccounts = accounts.filter((a) => a.type === 'asset' && !a.is_closed);

  async function handleFile(file) {
    setError(null);
    setSummary(null);
    if (!accountId) {
      setError('명세서가 속한 계정을 먼저 선택하세요');
      return;
    }
    if (passphrase.length < 8) {
      setError('암호화 패스프레이즈는 8자 이상이어야 합니다');
      return;
    }
    try {
      const bytes = new Uint8Array(await file.arrayBuffer());

      setPhase('parsing');
      const records = await parse(bytes, passphrase);

      setPhase('encrypting');
      const payload = await buildPayload(records, passphrase, accountId, file.name, bytes);

      setPhase('uploading');
      const res = await api('/api/ingest', { method: 'POST', body: payload });

      setPhase('processing');
      // 워커 처리 완료 폴링 (M7 전 임시 — NOTIFY 채널이 붙으면 대체)
      let state = res.state;
      for (let i = 0; i < 30 && state !== 'done' && state !== 'failed'; i += 1) {
        await new Promise((r) => setTimeout(r, 1000));
        const b = await api(`/api/ingest/${res.batch_id}`);
        state = b.state;
      }
      if (state !== 'done') {
        throw new Error(state === 'failed' ? '배치 처리 실패 — 파일 형식을 확인하세요' : '처리 대기 시간 초과 (워커 상태 확인)');
      }

      const total = records.length;
      setSummary({ total, amountPreview: records.slice(0, 3) });
      setPhase('done');
      onDone();
    } catch (e) {
      setError(e.message);
      setPhase('error');
    } finally {
      if (fileRef.current) fileRef.current.value = '';
    }
  }

  const busy = ['parsing', 'encrypting', 'uploading', 'processing'].includes(phase);
  const phaseLabel = {
    parsing: '파싱 중 (Worker)…',
    encrypting: '암호화 중…',
    uploading: '업로드 중…',
    processing: '거래 생성 중…',
  }[phase];

  return (
    <div>
      <label>
        계정{' '}
        <select value={accountId} onChange={(e) => setAccountId(e.target.value)} disabled={busy}>
          <option value="">선택</option>
          {bankAccounts.map((a) => (
            <option key={a.id} value={a.id}>{a.code} {a.name}</option>
          ))}
        </select>
      </label>{' '}
      <label>
        패스프레이즈{' '}
        <input
          type="password"
          value={passphrase}
          onChange={(e) => setPassphrase(e.target.value)}
          placeholder="암호화 키 (서버 미저장)"
          autoComplete="new-password"
          disabled={busy}
        />
      </label>{' '}
      <label>
        명세서 CSV{' '}
        <input
          ref={fileRef}
          type="file"
          accept=".csv"
          disabled={busy}
          onChange={(e) => e.target.files?.[0] && handleFile(e.target.files[0])}
        />
      </label>
      {busy && <p className="muted" aria-live="polite">{phaseLabel}</p>}
      {phase === 'done' && summary && (
        <p aria-live="polite">
          {summary.total}건 처리 완료.{' '}
          <span className="muted">
            미리보기: {summary.amountPreview.map((r) => `${r.occurred_on} ${formatMinor(r.amount_minor)}`).join(' · ')}
          </span>
        </p>
      )}
      {error && <p role="alert" className="negative">{error}</p>}
      <p className="muted">
        적요·상대처는 브라우저에서 암호화되어 서버는 볼 수 없습니다. 같은 파일을 다시 올려도 거래가 중복되지 않습니다.
      </p>
    </div>
  );
}
