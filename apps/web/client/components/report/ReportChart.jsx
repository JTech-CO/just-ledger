// R 산출 SVG 리포트 뷰어 (디자인 백서 §4.3).
//   · R 이 디자인 토큰에 맞춰 생성한 SVG 를 그대로 표시(배경 투명·격자 --border).
//   · 다크 모드는 필터 반전이 아니라 R 측 다크 테마 산출물을 별도로 쓴다 —
//     현재 테마에 맞는 URL 을 골라 넘긴다.
//
// 보안: SVG 를 dangerouslySetInnerHTML 로 인라인하지 않고 <img> 로 로드한다.
// R 산출물은 신뢰 경계 안(자기 서버)이지만, 스크립트 실행 표면을 두지 않는다.

import styles from './ReportChart.module.css';

/**
 * @param {object} props
 * @param {string} props.lightSrc  라이트 테마 SVG URL
 * @param {string} props.darkSrc   다크 테마 SVG URL
 * @param {'light'|'dark'} props.theme  현재 유효 테마
 * @param {string} props.alt  차트 대체 텍스트(데이터 요약 — 접근성)
 */
export default function ReportChart({ lightSrc, darkSrc, theme, alt }) {
  const src = theme === 'dark' ? darkSrc : lightSrc;
  return (
    <figure className={styles.figure}>
      <img className={styles.chart} src={src} alt={alt} />
    </figure>
  );
}
