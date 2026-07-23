// 3열 셸 (디자인 백서 §2.1). 좌 사이드바 240px + 중앙 fluid + 우 상세 320px.
// 최대 1440px 중앙 정렬. Inspector 는 선택 시에만. 태블릿 이하에서 사이드바는
// 오버레이 — sidebarOpen 으로 열고, 백드롭 클릭·Esc 로 닫는다(유일한 네비게이션이
// 므로 여는 수단이 반드시 있어야 한다, DoD 3).

import styles from './AppShell.module.css';

/**
 * @param {object} props
 * @param {React.ReactNode} props.topbar
 * @param {React.ReactNode} props.sidebar
 * @param {React.ReactNode} props.main
 * @param {React.ReactNode} [props.inspector]
 * @param {boolean} [props.dragActive]
 * @param {boolean} [props.sidebarOpen]
 * @param {()=>void} [props.onCloseSidebar]
 */
export default function AppShell({ topbar, sidebar, main, inspector, dragActive, sidebarOpen, onCloseSidebar }) {
  return (
    <div className={`${styles.shell} ${dragActive ? styles.dragging : ''}`}>
      {topbar}
      <div className={styles.body}>
        {/* 태블릿 오버레이 백드롭 — 열렸을 때만. 클릭하면 닫힌다. */}
        {sidebarOpen && (
          <button
            type="button"
            className={styles.backdrop}
            aria-label="사이드바 닫기"
            onClick={onCloseSidebar}
          />
        )}
        <aside className={styles.sidebar} aria-label="사이드바" data-open={sidebarOpen ? 'true' : 'false'}>
          {sidebar}
        </aside>
        <main className={styles.main} aria-label="원장">{main}</main>
        {inspector}
      </div>
    </div>
  );
}
