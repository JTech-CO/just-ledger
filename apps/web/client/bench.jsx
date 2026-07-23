// LedgerTable 성능 벤치 (M8 DoD 1 — 10만행 스크롤 60fps). dev 전용 진입점으로
// 서버·DB 없이 10만 행을 렌더하고, 자동 스크롤 중 프레임 시간을 측정한다.
// 결과(평균 fps·p95 프레임 시간·최대 렌더 DOM 노드)를 화면과 window 에 남긴다.
// mcp Browser 또는 수동으로 열어 프로파일을 캡처한다.

import { createRoot } from 'react-dom/client';
import { useEffect, useRef, useState } from 'react';
import LedgerTable from './components/ledger/LedgerTable.jsx';
import './styles/tokens.css';
import './styles/global.css';

const N = 100_000;
const accountName = new Map([['a1', '1010 현금'], ['a2', '5210 식비']]);

const rows = Array.from({ length: N }, (_, i) => ({
  id: `t${i}`,
  occurred_on: `2026-${String((i % 12) + 1).padStart(2, '0')}-${String((i % 28) + 1).padStart(2, '0')}`,
  memo: `벤치 거래 ${i}`,
  status: i % 500 === 0 ? 'settled' : 'posted',
  entries: [
    { id: `t${i}-d`, account_id: 'a2', direction: 'debit', amount_minor: String(1000 + i), currency: 'KRW' },
    { id: `t${i}-c`, account_id: 'a1', direction: 'credit', amount_minor: String(1000 + i), currency: 'KRW' },
  ],
}));

function Bench() {
  const [active, setActive] = useState(-1);
  const [result, setResult] = useState(null);
  const scrollRef = useRef(null);

  useEffect(() => {
    // 스크롤 컨테이너(가상 스크롤 영역) 찾기
    const el = document.querySelector('[aria-label="원장 스크롤 영역"]');
    scrollRef.current = el;
    if (!el) return;

    const total = el.scrollHeight;
    const frames = [];
    let maxNodes = 0;
    let last = performance.now();
    let raf;

    function step(now) {
      const dt = now - last;
      last = now;
      frames.push(dt);
      maxNodes = Math.max(maxNodes, document.querySelectorAll('[data-txn-id]').length);
      // 매 프레임 조금씩 아래로 스크롤 — 3초 or 끝까지
      el.scrollTop += total / 180;
      if (el.scrollTop < total - el.clientHeight - 4 && frames.length < 600) {
        raf = requestAnimationFrame(step);
      } else {
        finish(frames, maxNodes);
      }
    }

    function finish(fs, nodes) {
      const measured = fs.slice(1); // 첫 프레임(스케줄 지연) 제외
      const sorted = [...measured].sort((a, b) => a - b);
      const p95 = sorted[Math.floor(sorted.length * 0.95)] ?? 0;
      const avg = measured.reduce((s, x) => s + x, 0) / measured.length;
      const fps = 1000 / avg;
      const r = {
        frames: measured.length,
        avg_ms: +avg.toFixed(2),
        p95_ms: +p95.toFixed(2),
        avg_fps: +fps.toFixed(1),
        max_dom_rows: nodes,
        total_rows: N,
        // 60fps = 프레임당 16.67ms. p95 가 이 아래면 60fps 유지.
        pass_60fps: p95 <= 16.7,
      };
      setResult(r);
      window.__benchResult = r;
    }

    raf = requestAnimationFrame(step);
    return () => cancelAnimationFrame(raf);
  }, []);

  return (
    <div style={{ height: '100vh', display: 'flex', flexDirection: 'column' }}>
      <div style={{ padding: '8px 16px', fontFamily: 'var(--font-mono)', fontSize: 13 }}>
        {result ? (
          <span id="bench-result">
            rows={result.total_rows} · avg {result.avg_fps}fps · p95 {result.p95_ms}ms ·
            maxDOM {result.max_dom_rows} · {result.pass_60fps ? 'PASS 60fps' : 'FAIL'}
          </span>
        ) : (
          <span>측정 중… (자동 스크롤)</span>
        )}
      </div>
      <div style={{ flex: 1, minHeight: 0, display: 'flex' }}>
        <LedgerTable rows={rows} accountName={accountName} activeIndex={active} onSelect={setActive} />
      </div>
    </div>
  );
}

createRoot(document.getElementById('bench')).render(<Bench />);
