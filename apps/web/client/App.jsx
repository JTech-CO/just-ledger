// 앱 셸 최소판 (M2). 사이드바·기간 네비게이션·테마 토글은 M8.

import LedgerPage from './pages/LedgerPage.jsx';

export default function App() {
  return (
    <>
      <header
        style={{
          padding: 'var(--sp-3) var(--sp-5)',
          borderBottom: '1px solid var(--border-strong)',
          background: 'var(--surface)',
        }}
      >
        <strong>just-ledger</strong> <span className="muted">복식부기 개인 원장</span>
      </header>
      <LedgerPage />
    </>
  );
}
