# modules/statement-wasm — Rust (WASM)

명세서 파싱(CSV/OFX/QIF) → 정규화 → BLAKE3 지문 → Argon2id 키 파생 및 암호화. `wasm-pack --target web`, 브라우저 Web Worker 에서 실행.

## 소유 범위
`modules/statement-wasm/`. 산출물 `pkg/` 는 `linguist-generated`, `target/` 는 `.gitignore`.

## 명령
```
cd modules/statement-wasm && cargo fmt
cd modules/statement-wasm && cargo clippy -- -D warnings   # make lint (일부)
cd modules/statement-wasm && cargo test                    # make test-ingest (Rust 측)
cd modules/statement-wasm && wasm-pack build --target web --release   # make build-wasm
```

## 규율 (INV-6)
- **명세서 원문이 서버 로그·DB·임시 파일에 평문으로 남는 경로 0개.** 암호화는 클라이언트(WASM)에서, 키는 사용자 패스프레이즈 Argon2id 파생 — 서버에 저장하지 않고 서버는 복호화 불가.
- 인코딩(CP949, UTF-8 BOM), 날짜 형식, 천단위 구분자, 음수 표기(`△`, 괄호)는 은행마다 다르다. 골든 픽스처 3사 포맷에 전부 맞춘다.
- 동일 파일 재업로드 시 신규 txn 0건(BLAKE3 지문 중복 제거).
- 50MB CSV 파싱 3초 이내, 메인 스레드 롱태스크 0. WASM 은 반드시 Web Worker 에서.
- 금액은 정수(`i64`/문자열). 부동소수점 경유 금지.

## 참조
기술 백서 §3.2, §4.2, §4.3(중복 제거) / 담당 phase: M3.
