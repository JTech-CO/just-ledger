// 3열 셸 (디자인 백서 §2.1). 좌 사이드바 240px + 중앙 fluid + 우 상세 320px.
// 최대 1440px 중앙 정렬. Inspector 는 선택 시에만 등장한다.

import styles from './AppShell.module.css';

/**
 * @param {object} props
 * @param {React.ReactNode} props.topbar
 * @param {React.ReactNode} props.sidebar
 * @param {React.ReactNode} props.main
 * @param {React.ReactNode} [props.inspector]  선택 시에만
 * @param {boolean} [props.dragActive]  전역 드롭존 진입(테두리 인셋)
 */
export default function AppShell({ topbar, sidebar, main, inspector, dragActive }) {
  return (
    <div className={`${styles.shell} ${dragActive ? styles.dragging : ''}`}>
      {topbar}
      <div className={styles.body}>
        <aside className={styles.sidebar} aria-label="사이드바">{sidebar}</aside>
        <main className={styles.main} aria-label="원장">{main}</main>
        {inspector}
      </div>
    </div>
  );
}
