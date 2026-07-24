// 로컬 앱 셸 — vite --mode app (PWA, 오프라인 실사용) 에서 App.jsx 를 대체한다.
//
// 데모(DemoApp)와 다른 점:
//   · 데이터가 이 기기(IndexedDB)에 영속된다 — 새로고침해도 남는다.
//   · 모의 데이터를 자동으로 채우지 않는다(빈 장부로 시작, 원하면 샘플 넣기).
//   · 백업 수단(내보내기/가져오기)과 초기화를 제공한다 — 동기화가 없으므로 필수.
//   · 서비스워커를 등록해 오프라인에서도 앱이 열린다(PWA).
//   · '설치' 버튼(beforeinstallprompt)으로 홈/시작메뉴에 앱으로 설치한다.

import { useEffect, useRef, useState } from 'react';
import LedgerPage from '../../pages/LedgerPage.jsx';
import { useLedgerStore } from '../../store/ledgerStore.js';
import { isEmpty, seedSample, exportData, importData, resetData } from './localApi.js';
import styles from './LocalApp.module.css';

const REPO = 'https://github.com/JTech-CO/just-ledger';

export default function LocalApp() {
  const [installEvt, setInstallEvt] = useState(null);
  const [empty, setEmpty] = useState(false);
  const [msg, setMsg] = useState(null);
  const fileRef = useRef(null);

  // 서비스워커 등록 (오프라인 셸). base 하위에 sw.js 를 둔다.
  useEffect(() => {
    if (!('serviceWorker' in navigator)) return;
    const base = import.meta.env.BASE_URL || '/';
    navigator.serviceWorker.register(`${base}sw.js`, { scope: base }).catch(() => {
      // 등록 실패는 치명적이지 않다 — 온라인에서는 정상 동작한다
    });
  }, []);

  // 설치 프롬프트 포착
  useEffect(() => {
    const onPrompt = (e) => {
      e.preventDefault();
      setInstallEvt(e);
    };
    window.addEventListener('beforeinstallprompt', onPrompt);
    return () => window.removeEventListener('beforeinstallprompt', onPrompt);
  }, []);

  // 첫 실행(빈 장부) 안내
  useEffect(() => {
    isEmpty().then(setEmpty).catch(() => {});
  }, []);

  async function refresh() {
    try {
      await useLedgerStore.getState().loadAll();
    } catch {
      /* 스토어가 오류를 표시한다 */
    }
    isEmpty().then(setEmpty).catch(() => {});
  }

  async function onInstall() {
    if (!installEvt) return;
    installEvt.prompt();
    try {
      await installEvt.userChoice;
    } finally {
      setInstallEvt(null);
    }
  }

  async function onSeed() {
    await seedSample();
    setMsg('샘플 계정·거래를 채웠습니다.');
    await refresh();
  }

  async function onExport() {
    const text = await exportData();
    const blob = new Blob([text], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = 'just-ledger-backup.json';
    a.click();
    URL.revokeObjectURL(url);
    setMsg('백업 파일을 내보냈습니다.');
  }

  async function onImportFile(e) {
    const file = e.target.files?.[0];
    if (!file) return;
    try {
      await importData(await file.text());
      setMsg('가져오기 완료 — 기존 데이터를 대체했습니다.');
      await refresh();
    } catch (err) {
      setMsg(`가져오기 실패: ${err.message}`);
    } finally {
      e.target.value = '';
    }
  }

  async function onReset() {
    if (!window.confirm('이 기기에 저장된 모든 계정·거래를 삭제합니다. 되돌릴 수 없습니다. 계속할까요?')) return;
    await resetData();
    setMsg('빈 장부로 초기화했습니다.');
    await refresh();
  }

  return (
    <div className={styles.appRoot}>
      <header className={styles.bar}>
        <div className={styles.barMain}>
          <p className={styles.line}>
            <strong>로컬 앱</strong> — 데이터는 <strong>이 기기의 브라우저에만</strong> 저장됩니다(서버·동기화 없음).
            기기를 바꾸거나 브라우저 데이터를 지우면 사라지니, 내보내기로 백업하세요.
          </p>
          <p className={styles.line}>
            복식부기(차변=대변)는 이 앱 안에서 검사합니다. 다만 마감 정합성(COBOL)·자동 분류(Prolog)·다중
            사용자는 서버판 기능이라 여기서는 동작하지 않습니다.{' '}
            <a className={styles.link} href={REPO} target="_blank" rel="noreferrer">
              전체 스택
            </a>
          </p>
        </div>
        <div className={styles.actions}>
          {installEvt && (
            <button type="button" className={styles.primaryBtn} onClick={onInstall}>
              앱 설치
            </button>
          )}
          <button type="button" onClick={onExport}>내보내기</button>
          <button type="button" onClick={() => fileRef.current?.click()}>가져오기</button>
          <button type="button" onClick={onReset}>초기화</button>
          <input
            ref={fileRef}
            type="file"
            accept="application/json"
            className={styles.hiddenFile}
            onChange={onImportFile}
          />
        </div>
      </header>

      {empty && (
        <div className={styles.firstRun} role="note">
          <span>빈 장부입니다. 왼쪽에서 계정을 만들고 아래에서 거래를 입력하거나, </span>
          <button type="button" className={styles.linkBtn} onClick={onSeed}>
            샘플 데이터로 둘러보기
          </button>
          <span>를 눌러 시작하세요.</span>
        </div>
      )}

      {msg && (
        <p className={styles.toast} role="status" onAnimationEnd={() => setMsg(null)}>
          {msg}
        </p>
      )}

      <div className={styles.appSlot}>
        <LedgerPage />
      </div>
    </div>
  );
}
