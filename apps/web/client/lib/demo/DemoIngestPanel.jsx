// 데모에서 명세서 업로드 자리 — 한 줄 안내로 대체한다.
// 공개 데모에 방문자의 실제 명세서를 올리도록 유도하지 않기 위함.

import styles from './DemoNotice.module.css';

export default function DemoIngestPanel() {
  return <p className={styles.line}>명세서 가져오기는 데모에서 비활성화되어 있습니다.</p>;
}
