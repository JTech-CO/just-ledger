// 데모 셸 — GitHub Pages UI 데모 전용. vite --mode demo 에서 App.jsx 를 대체한다.
//
// 배너는 장식이 아니라 **고지**다: 이 화면은 브라우저 안 모의 데이터로만 돌고
// 서버·데이터베이스에 연결돼 있지 않다는 사실을 첫 화면에서 분명히 말한다.

import { useState } from 'react';
import LedgerPage from '../../pages/LedgerPage.jsx';
import { useLedgerStore } from '../../store/ledgerStore.js';
import { setDemoProfile } from './mockApi.js';
import styles from './DemoBanner.module.css';

const REPO = 'https://github.com/JTech-CO/just-ledger';

export default function DemoApp() {
  const [profile, setProfile] = useState('household');
  const [busy, setBusy] = useState(false);

  async function load(name) {
    setBusy(true);
    setDemoProfile(name);
    try {
      await useLedgerStore.getState().loadAll();
      setProfile(name);
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
          <strong>데모</strong> · 모의 데이터입니다. 새로고침하면 초기화됩니다.
        </p>
        <div className={styles.controls}>
          <button type="button" onClick={() => load('household')} disabled={busy || profile === 'household'}>
            가계 · 1,500건
          </button>
          <button type="button" onClick={() => load('company')} disabled={busy || profile === 'company'}>
            회사 · 10만건
          </button>
          <a className={styles.link} href={REPO} target="_blank" rel="noreferrer">
            GitHub
          </a>
        </div>
      </aside>
      <div className={styles.appSlot}>
        <LedgerPage />
      </div>
    </div>
  );
}
