// 상단바 (디자인 백서 §2.3). 높이 48px, 로고(텍스트) 좌측, 기간 선택기,
// 검색·테마 토글·사용자 우측. sticky, 그림자 없음, 하단 1px --border.

import { forwardRef } from 'react';
import { Search, Sun, Moon, Menu } from 'lucide-react';
import styles from './Topbar.module.css';

/**
 * @param {object} props
 * @param {string} props.period  선택 기간 (YYYY-MM)
 * @param {Array<string>} props.periods  선택 가능한 기간 목록
 * @param {(p:string)=>void} props.onPeriod
 * @param {string} props.query
 * @param {(q:string)=>void} props.onQuery
 * @param {'light'|'dark'} props.theme
 * @param {()=>void} props.onToggleTheme
 */
const Topbar = forwardRef(function Topbar(
  { period, periods, onPeriod, query, onQuery, theme, onToggleTheme, onMenuClick },
  searchRef,
) {
  return (
    <header className={styles.bar}>
      {/* 태블릿 이하에서만 보이는 사이드바 토글 (데스크톱은 CSS 로 숨김) */}
      <button type="button" className={styles.menuBtn} onClick={onMenuClick} aria-label="사이드바 열기">
        <Menu size={16} strokeWidth={1.75} aria-hidden="true" />
      </button>
      <span className={styles.logo}>just-ledger</span>

      <label className={styles.periodLabel}>
        <span className="sr-only">기간 선택</span>
        <select
          className={styles.period}
          value={period}
          onChange={(e) => onPeriod(e.target.value)}
          aria-label="기간 선택"
        >
          {periods.map((p) => (
            <option key={p} value={p}>{p}</option>
          ))}
        </select>
      </label>

      <div className={styles.spacer} />

      <label className={styles.searchWrap}>
        <Search className={styles.searchIcon} size={16} strokeWidth={1.75} aria-hidden="true" />
        <span className="sr-only">거래 검색</span>
        <input
          ref={searchRef}
          className={styles.search}
          type="search"
          value={query}
          onChange={(e) => onQuery(e.target.value)}
          placeholder="검색 (/)"
          aria-label="거래 검색"
        />
      </label>

      <button
        type="button"
        className={styles.iconBtn}
        onClick={onToggleTheme}
        aria-label={theme === 'dark' ? '라이트 모드로' : '다크 모드로'}
      >
        {theme === 'dark'
          ? <Sun size={16} strokeWidth={1.75} aria-hidden="true" />
          : <Moon size={16} strokeWidth={1.75} aria-hidden="true" />}
      </button>
    </header>
  );
});

export default Topbar;
