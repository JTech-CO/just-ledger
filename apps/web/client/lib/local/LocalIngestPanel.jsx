// 로컬 앱의 명세서 업로드 자리 — 안내로 대체한다.
// 명세서 파싱·지문·암호화는 Rust/WASM 과 서버 인제스트 경로에 얹혀 있어 오프라인
// 단일 사용자 앱 범위 밖이다. 수기 입력으로 거래를 남기면 된다.

import styles from './LocalApp.module.css';

export default function LocalIngestPanel() {
  return <p className={styles.infoLine}>명세서 자동 가져오기는 서버판 기능입니다.</p>;
}
