// 데모에서 명세서 업로드를 대체하는 안내 패널.
//
// 왜 비활성화하는가: 실제 앱의 명세서 파싱·지문·암호화는 전부 브라우저 안(Rust/WASM)
// 에서 일어나 원문이 서버로 가지 않는다(INV-6). 그렇더라도 **공개 데모 페이지에
// 방문자의 실제 은행·카드 명세서를 올리도록 유도하는 것은 옳지 않다.** 그래서
// 데모에서는 업로더를 아예 렌더하지 않고 설명만 보여준다.

import styles from './DemoNotice.module.css';

/**
 * @param {{ accounts?: Array<Object>, onDone?: () => void }} _props 실제 패널과 시그니처만 맞춘다
 */
export default function DemoIngestPanel(_props) {
  return (
    <section className={styles.notice} aria-labelledby="demo-ingest-title">
      <h2 id="demo-ingest-title" className={styles.title}>
        명세서 가져오기 — 데모에서는 비활성화
      </h2>
      <p className={styles.body}>
        실제 앱에서는 카드·은행 명세서를 브라우저 안에서 파싱·암호화해 업로드하며, 원문은 서버에 평문으로 남지
        않습니다. 다만 공개 데모에 실제 명세서를 올리도록 권하지 않기 위해 이 화면에서는 업로더를 제공하지
        않습니다.
      </p>
    </section>
  );
}
