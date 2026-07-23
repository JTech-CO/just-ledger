// 데모 셸 — GitHub Pages UI 데모 전용. vite --mode demo 에서 App.jsx 를 대체한다.
//
// 배너는 장식이 아니라 **고지**다: 이 화면은 브라우저 안 모의 데이터로만 돌고
// 서버·데이터베이스에 연결돼 있지 않다는 사실을 첫 화면에서 분명히 말한다.

import { useState } from 'react';
import LedgerPage from '../../pages/LedgerPage.jsx';
import { useLedgerStore } from '../../store/ledgerStore.js';
import { setDemoRowTarget } from './mockApi.js';
import styles from './DemoBanner.module.css';

const REPO = 'https://github.com/JTech-CO/just-ledger';

export default function DemoApp() {
  const [rows, setRows] = useState(1500);
  const [busy, setBusy] = useState(false);

  async function reseed(n) {
    setBusy(true);
    setDemoRowTarget(n);
    try {
      await useLedgerStore.getState().loadAll();
      setRows(n);
    } catch {
      // loadAll 이 스토어에 오류를 남긴다 — 배너에서 따로 표시하지 않는다
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className={styles.demoRoot}>
      <aside className={styles.banner} role="note">
        <p className={styles.line}>
          <strong>데모</strong> — 브라우저 안에서만 도는 <strong>모의 데이터</strong>입니다. 실제 서버·데이터베이스에
          연결되어 있지 않으며, 입력한 내용은 새로고침하면 사라집니다.
        </p>
        <p className={styles.line}>
          복식부기 강제·마감 정합성·자동 분류는 서버(PostgreSQL 트리거·COBOL·Prolog)에서 동작하므로 이 화면에서는
          확인할 수 없습니다. 전체 스택은{' '}
          <a className={styles.link} href={REPO} target="_blank" rel="noreferrer">
            저장소
          </a>
          에서 직접 띄울 수 있습니다.
        </p>
        <p className={styles.controls}>
          <span className={styles.rowsLabel}>표시 중인 거래 {rows.toLocaleString('ko-KR')}건</span>
          <button type="button" onClick={() => reseed(1500)} disabled={busy || rows === 1500}>
            1,500건
          </button>
          <button type="button" onClick={() => reseed(100000)} disabled={busy || rows === 100000}>
            10만건 부하 걸기
          </button>
        </p>
      </aside>
      <div className={styles.appSlot}>
        <LedgerPage />
      </div>
    </div>
  );
}
