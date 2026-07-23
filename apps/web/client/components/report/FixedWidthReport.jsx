// COBOL 마감 리포트 뷰어 (디자인 백서 §4.3).
//   · --font-mono, white-space: pre, 줄바꿈 금지, 가로 스크롤 허용(유일한 예외)
//   · 좌측 3px --accent 인셋으로 "기계가 생성한 산출물"임을 표시
// 리포트 텍스트는 서버가 준 고정폭 문자열 그대로 — 클라이언트가 재포맷하지 않는다.

import styles from './FixedWidthReport.module.css';

/**
 * @param {object} props
 * @param {string} props.text  COBOL 배치가 낸 고정폭 텍스트
 * @param {string} [props.label]  접근성 라벨
 */
export default function FixedWidthReport({ text, label = '마감 리포트' }) {
  return (
    <figure className={styles.figure} aria-label={label}>
      <pre className={styles.report} tabIndex={0}>{text}</pre>
    </figure>
  );
}
