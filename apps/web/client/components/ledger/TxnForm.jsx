// 수기 거래 입력 (M2 DoD 4 — 입력→저장→재조회 문자열 왕복 무손실).
// 금액 입력은 normalizeAmountInput 으로 정규화한다 — 입력 중에도 float 미사용 (§2.2).
// 최소판: 차변 1 + 대변 1 (동일 금액 → 균형 보장). 복합 분개 편집기는 M8.

import { useState } from 'react';
import { normalizeAmountInput, formatMinor } from '../../lib/money.js';

/**
 * @param {{ accounts: Array<Object>, onSubmit: (txn: Object) => Promise<void> }} props
 */
/** 로컬 타임존 기준 오늘 (toISOString 은 UTC 라 KST 새벽엔 어제가 된다) */
function localToday() {
  const d = new Date();
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${d.getFullYear()}-${mm}-${dd}`;
}

export default function TxnForm({ accounts, onSubmit }) {
  const today = localToday();
  const [occurredOn, setOccurredOn] = useState(today);
  const [memo, setMemo] = useState('');
  const [debitAccount, setDebitAccount] = useState('');
  const [creditAccount, setCreditAccount] = useState('');
  const [rawAmount, setRawAmount] = useState('');
  const [error, setError] = useState(null);
  const [busy, setBusy] = useState(false);

  const amount = normalizeAmountInput(rawAmount);
  const open = accounts.filter((a) => !a.is_closed);

  async function handleSubmit(e) {
    e.preventDefault();
    setError(null);
    if (!amount) {
      setError('금액은 최소 화폐 단위의 양의 정수여야 합니다 (소수점 불가)');
      return;
    }
    if (!debitAccount || !creditAccount) {
      setError('차변·대변 계정을 선택하세요');
      return;
    }
    if (debitAccount === creditAccount) {
      setError('차변과 대변에 같은 계정을 쓸 수 없습니다');
      return;
    }
    const debit = accounts.find((a) => a.id === debitAccount);
    const credit = accounts.find((a) => a.id === creditAccount);
    if (debit.currency !== credit.currency) {
      setError('차변·대변 계정의 통화가 같아야 합니다 (다통화 분개는 이후 버전)');
      return;
    }
    setBusy(true);
    try {
      await onSubmit({
        occurred_on: occurredOn,
        memo,
        status: 'posted',
        entries: [
          { account_id: debitAccount, direction: 'debit', amount_minor: amount, currency: debit.currency },
          { account_id: creditAccount, direction: 'credit', amount_minor: amount, currency: credit.currency },
        ],
      });
      setMemo('');
      setRawAmount('');
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <form onSubmit={handleSubmit} aria-label="수기 거래 입력">
      <label>
        날짜{' '}
        <input type="date" value={occurredOn} onChange={(e) => setOccurredOn(e.target.value)} required />
      </label>{' '}
      <label>
        적요{' '}
        <input value={memo} onChange={(e) => setMemo(e.target.value)} maxLength={512} placeholder="적요" />
      </label>{' '}
      <label>
        차변{' '}
        <select value={debitAccount} onChange={(e) => setDebitAccount(e.target.value)} required>
          <option value="">계정 선택</option>
          {open.map((a) => (
            <option key={a.id} value={a.id}>{a.code} {a.name}</option>
          ))}
        </select>
      </label>{' '}
      <label>
        대변{' '}
        <select value={creditAccount} onChange={(e) => setCreditAccount(e.target.value)} required>
          <option value="">계정 선택</option>
          {open.map((a) => (
            <option key={a.id} value={a.id}>{a.code} {a.name}</option>
          ))}
        </select>
      </label>{' '}
      <label>
        금액{' '}
        <input
          className="mono"
          value={rawAmount}
          onChange={(e) => setRawAmount(e.target.value)}
          inputMode="numeric"
          placeholder="최소 단위 정수"
          aria-label="금액"
          required
        />
      </label>{' '}
      <span className="mono muted" aria-live="polite">
        {amount ? formatMinor(amount) : ''}
      </span>{' '}
      <button type="submit" className="primary" disabled={busy || !amount}>
        기입
      </button>
      {error && <p role="alert" className="negative">{error}</p>}
    </form>
  );
}
