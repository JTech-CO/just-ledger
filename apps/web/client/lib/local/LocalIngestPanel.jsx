// 로컬 앱의 명세서 업로드 자리 — 안내로 대체한다.
// 명세서 파싱·지문·암호화는 Rust/WASM 과 서버 인제스트 경로에 얹혀 있어 오프라인
// 단일 사용자 앱 범위 밖이다. 수기 입력으로 거래를 남기면 된다.

import styles from './LocalApp.module.css';

export default function LocalIngestPanel() {
  return (
    <section className={styles.infoPanel} aria-labelledby="local-ingest-title">
      <h2 id="local-ingest-title" className={styles.infoTitle}>
        명세서 자동 가져오기는 서버판 기능입니다
      </h2>
      <p className={styles.infoBody}>
        카드·은행 명세서 파싱은 서버 인제스트 경로(브라우저 내 파싱·암호화)에 얹혀 있어 이 오프라인 앱에는
        포함되지 않습니다. 거래는 위의 수기 입력으로 남기세요.
      </p>
    </section>
  );
}
