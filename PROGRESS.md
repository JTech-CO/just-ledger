# PROGRESS — just-ledger

이 파일만 읽으면 이어서 작업할 수 있어야 한다. 세션 종료 시 반드시 갱신한다.

---

## 현재 phase

**M7 — 실시간 계층 (Elixir)** (착수 전)

M0~M6 게이트 통과. **M6(2026-07-23):** 분석 계층 완성 —
- **R `modules/analytics`**: STL(robust) + MAD robust z > 3.5 이상치, 부트스트랩 10,000회 예산 초과확률, 디자인 토큰(tokens.css SSOT) 파싱 → ggplot 테마 → **라이트/다크 SVG 2벌**. `--cache-dir` 캐시(키 = stdin + 토큰 + 모듈 코드).
- **Julia `modules/simulation`**: 가우시안 KDE 리샘플링 몬테카를로(Xoshiro 명시 시드), 상환 순서 **Int128 전수 순열 최적화**(가지치기 + 사전순 타이브레이크), warmup(JIT 예열), SHA-256 캐시.
- **DoD 실측**: ① 재실행·CI 양쪽 stdout·SVG 바이트 동일 ② 재현율 1.000 / FPR 0.0000~0.0049 (골든 구성 + 주입 밀도 4종 + 주입0 + 상수계열) ③ 10,000 경로 NaN·발산 0, CI 폭 0.008916 ≤ 0.01 ④ SVG 2벌 + **실제 사용 색 기반** AA ⑤ 캐시 히트·무효화.
- **적대 검증 4렌즈 52건 → 확증 22건(중복 제거 12건) 전부 수정.** blocker 5: STL 스미어링으로 DoD 2 실패(게이트는 유리한 구성만 측정), CSS 주석 파싱으로 토큰 SSOT 무력화, `formatC` 32비트 절단 침묵 실패, 캐시 키가 토큰 미포함 + 환경성 실패 영구 캐시, AA 검사가 실제 SVG 색 미검증.
- 테스트: analytics 58검사 / simulation 50건.

**M5(2026-07-22):** 정산 계층 완성 —
- **COBOL**: `settle.cbl`(다통화 KRW 환산·계정 집계, NEAREST-EVEN) + `amort.cbl`(원리금 균등 상각, 마지막 회차 잔여 흡수 → 잔액 정확히 0). copybook 2종이 SSOT.
- **JS 참조 정본** `scripts/parity/lib.mjs`(전 과정 BigInt) + INV-7 대조 하네스: 10,000 entry 마감 + 상각 481행 + **0.5 경계 전수 400건** — 폐형식·JS·COBOL 삼자 일치, **차이 0원**. 컨테이너(GnuCOBOL 3.2.0)와 CI(3.1.2) 이종 버전에서 골든 바이트 동일 실측.
- **Go 사전 게이트**: PIC 폭·수치 범위(S9(18) 보수적 상계)·고유 계정 5000·회차 1..360 — COBOL 실행 전 거절 (DoD 4).
- **Haskell 규칙 DSL**: megaparsec 파서·타입검사(통화 정합 포함)·정확 유리수 평가기·JSONL 프로토콜. 유효 20/오류 20+9종(전부 줄·열 exact)·parseMoney 14종 (DoD 5).
- **적대 검증 4렌즈 19건 → 확증 15건 전부 수정** (blocker 2: COBOL 오버플로 침묵 절삭, CI 필터의 INV-7 게이트 우회). 성능: 마감 10,000 entry 193ms (≤2s).

**M4(2026-07-22):** Prolog 추론 서비스(분류 정확도 97.4%/500·이체 매칭 거짓양성 0·정기결제·1000건 0.02s) + Lua 샌드박스(탈출 11종 차단·100ms 타임아웃·메모리 폭탄 격리). plunit 19 + go sandbox 전 통과. 적대 검증 4렌즈 10건(INV-8 blocker 0) 전부 수정.

**M3-C (웹 연결) 완료분:**
- `POST /api/ingest`(봉투 계약 검증→batch+payload 원자 저장→202→워커 nudge, 실패 시 스캔 폴백) + `GET /api/ingest/:id` 상태 조회 — 통합 테스트 5종(202 왕복·400·INV-6 표면)
- worker 어댑터를 실제 Unix socket 클라이언트로 구현 (Go 소켓 프로토콜 1:1)
- 클라이언트: `ingest.worker.js`(WASM Web Worker, **기동 예열** — bench 웜 게이트 전제 이행), `useIngestWorker` 훅, `IngestPanel`(파일→파싱→암호화→업로드→상태 폴링)
- vite 가 wasm pkg 를 자산 편입(519KB), Makefile `build-web`→`build-wasm` 의존, CI web 잡에 wasm 선행 빌드
- 실측: lint·check-no-float(32파일 0)·test:api 21/21·test:ui 12/12·build 그린

**M3 DoD 최종:** 1 골든 3종 완전 일치 ✔ / 2 재업로드 신규 0 ✔ / 3 50MB 웜 1704·1465ms + Worker 구조·기동 예열 ✔ / 4 봉투 평문 부재(바이트 검사 3계층) ✔ / 5 미완료 배치 자동 재개 ✔ / INV-6 ✔

M0·M1·M2 게이트 통과(전부 2026-07-21). 미결질문 #3 해소: 골든 3종 = **하나·국민·토스뱅크** (사용자 확정).

**M3 완료분 (로컬 컨테이너 실측 그린):**
- M3-A Rust `statement-wasm`: 3사 파서(CP949/UTF-8 BOM·따옴표 천단위·`△` 음수·전각 NFKC), keyed BLAKE3 지문, Argon2id+ChaCha20-Poly1305(AAD) 봉투. cargo test 31종(골든 4)·fmt·clippy·CI wasm 잡 그린. `make bench-wasm` 웜 UTF-8 1704ms·CP949 1465ms ≤ 3000ms (DoD 3, 게이트는 웜 — 아래 예열 항목 참조)
- M3-B Go `services/worker`: DB 상태기계 큐(+소켓 nudge)·인제스트 프로세서(draft 생성)·환율 폴러(유리수 쌍). go test 그린 — **DoD 2**(재업로드 신규 0)·**DoD 5**(미완료 배치 재개·멱등)·INV-6 서버측(DB·로그 평문 부재) 실측
- db 확장: ingest_batch.account_id(복합 FK)·ingest_payload 테이블·fn_pending_ingest_batches(DEFINER 최소 투영)·RLS — `make test-db` 회귀 그린
- 적대적 검증 4렌즈 10건 전부 처리 (blocker 0): keyed 지문(무키 사전공격 차단), 토스 메모 지문 분리(가변 필드 중복제거 파괴), nonce/파라미터 봉투 강건성, AAD blob 스왑 거절, 공란 금액, CP949 벤치 경로

---

## 직전에 끝낸 것

- 폴리글랏 기획 확정 (11개 언어, 각 5% 이상, 메인 JavaScript 28%)
- `docs/…/TECH-WHITEPAPER.md` v1.0, `DESIGN-WHITEPAPER.md` v1.0, `HARNESS.md` v0.1
- 루트 `CLAUDE.md`, `.gitattributes`, `Makefile`, devcontainer 정의
- **[M0] 저장소 초기화**: `git init` (main), `.gitignore`(deps/target/_build/dist-newstyle/node_modules), `.env.example`
- **[M0] 구조 정리**: `Dockerfile → infra/devcontainer/Dockerfile`, `devcontainer.json → .devcontainer/`, 문서화된 디렉터리 트리 생성(빈 디렉터리 `.gitkeep`)
- **[M0] `infra/compose.yaml`**: db/web/worker/prolog/realtime — `docker compose config` 검증 통과
- **[M0] 계약 골격** `contracts/`: `common`(uuid/currency/date/금액문자열/유리수쌍/enum) + `account`/`entry`/`txn`/`ingest-batch`/`notify-event`. **ajv `strict:true`(+strictTypes) 컴파일·교차 `$ref`·금액문자열(부동소수점 거부)·i64 18자리 경계 전부 검증됨**(`contracts/check.mjs`)
- **[M0] 언어 게이트** `scripts/linguist-gate.lua` + 골든 테스트 `scripts/tests/linguist-gate.test.lua` (실행 검증은 컨테이너 대기 — 호스트에 Lua 없음)
- **[M0] CI** `.github/workflows/ci.yaml`: 경로 매트릭스(paths-filter) + 모듈 소스 존재 게이트 → 착수 전 모듈 잡 자동 스킵. YAML 파싱 검증 통과(14 잡)
- **[M0] 모듈별 `CLAUDE.md`** 11종(apps/web, services/{worker,worker/sandbox,prolog,realtime}, modules/{statement-wasm,rules-dsl,settlement,analytics,simulation}, db), `README.md`(언어 선정 근거표)
- **[M0] 적대적 검증 워크플로**(5 렌즈) 실행 → 6건 발견, 전부 해소
- **[M0] 툴체인 이미지 빌드 성공** (`just-ledger-dev:local`, 10.1GB, 12분) — 빌드 중 2건 수정: ① hexpm/elixir 태그 실존본(`…noble-20260509.1`)으로 교체 ② `luarocks --lua-version=5.4 install dkjson` (기본 5.1 트리에 설치되던 문제) + 빌드 시 `require` 스모크 검사 추가
- **[M0] `make toolchain-check` 통과** (컨테이너 내부, 11개 전부 버전 출력·성공 종료) → **DoD 1 ✔**
- **[M0] 게이트 스크립트 듀얼 모드 리팩터링**: 컨테이너 seccomp 에서 Lua `os.execute` 가 ENOSYS(38) 로 차단됨 → 테스트가 서브프로세스 없이 `require` 로 판정 함수를 직접 검증하도록 재작성. 컨테이너에서 골든 테스트 7/7 통과 + CLI 통과/위반 양 경로(exit 0/1) 실측 확인
- **[M0] CI 툴체인 핀을 컨테이너 확정 버전에 정렬** (OTP 27.3.3 / GHC 9.10.3 / cabal 3.16.1.0 / R 4.3.3)
- **[M1] 스키마** `db/migrations/0001_init.{up,down}.pgsql`: 11개 도메인 테이블 + app_user(RLS 주체)·account_balance(잔액 유지)·transfer_link_member(INV-5 유니크). enum 7종, 복합 FK·CHECK·부분 인덱스. up/down/up 왕복 스키마 diff 0
- **[M1] 불변식 트리거** `db/triggers/inv_triggers.pgsql`: INV-1 **deferrable constraint trigger**(커밋 시점, `SECURITY DEFINER row_security=off` 로 RLS·GUC 우회 차단), INV-3 settled 불변, INV-5 멤버십 유니크. 커스텀 SQLSTATE JL001/JL003/JL005
- **[M1] 잔액·NOTIFY** `db/triggers/balance_notify.pgsql`: 증분 잔액 유지(상태 전이·entry·삭제 매트릭스), `FOR SHARE` 동시성 락, 문장 단위 NOTIFY(balance_changed/ingest_progress/settlement_done — 금액 문자열)
- **[M1] 롤업·RLS** `db/functions/{rollup,rls}.pgsql`: 계정·계층·기간 잔액 함수, owner_id + `current_owner()`(GUC) RLS(fail-closed), 서비스 역할 BYPASSRLS 없음, 내부 함수 PUBLIC EXECUTE 회수
- **[M1] 테스트 하네스** `db/tests/run.sh` + 6개 스크립트: `make test-db` 컨테이너 실측 전체 그린 (10만 txn ~87s). RLS 역할+GUC 우회에도 INV-1 강제 회귀 테스트 포함
- **[M1] 적대적 검증 2라운드**: 1차 5렌즈 13건(blocker 3 = INV-1 RLS 블라인딩) + 재검증 중 fn_inv1_check EXECUTE 오라클 1건 → 전부 수정. 재검증 3렌즈 0건
- **[M2] 계약 확정**: `balance.schema.json` 신설(잔액 row SSOT), notify-event 가 `$ref` 로 공유(와이어 형태 불변 — db 무영향 실측). JSDoc 생성기(`apps/web/scripts/gen-typedefs.mjs` → `types/contracts.gen.js`, linguist-generated)
- **[M2] Fastify 서버**: 계약 로더(2020-12 ajv, 파생 스키마 기계 생성, **응답도 계약 검증 — 위반 500**), 계정 CRUD·txn 생성/조회·잔액·기간잔액 라우트, DB 불변식 → 상태코드 매핑(JL001→422 등), RLS 연동(`onConnect` SET ROLE fail-closed + 요청 트랜잭션 GUC)
- **[M2] 어댑터 시그니처 확정** (스텁): worker/prolog/realtime — 전 호출에 `ownerId` 명시(미결질문 #7 (a)안 확정). prolog 분류는 `rule_name` 필수 반환
- **[M2] React 셸 + LedgerTable 최소판**: 디자인 토큰(§5 1:1)·money.js(문자열/BigInt 전용)·TxnForm(정규화 입력)·ErrorBoundary·로드 실패 표면화. Zustand `applyRealtime` 단일 진입점
- **[M2] `scripts/check-no-float.mjs`** (INV-4 게이트): parseFloat/toFixed 전면 금지, pg 파서 재정의 전 경로 차단, 금액 프로퍼티 직접 산술·Intl.NumberFormat 차단, `no-float-ok:` 사유 필수 탈출구
- **[M2] 적대적 검증 5렌즈 19건 전부 수정**: SET ROLE fail-open(major), limit 무제한(major), INV-4 게이트 우회 구멍(major), UTC 날짜, 실패 침묵, 테스트 공허 단언 등 + db 측 3건(잔액 계약 상한 CHECK, 로그인 롤 멤버십, 계정 순환 방지 JL006)

---

## 다음 할 일

1. **M7 착수** (Elixir 단일 언어 세션): `services/realtime` — Phoenix 채널 + PostgreSQL `LISTEN` 브리지 + 예산 임계 감시 GenServer + 감독 트리. 진입조건(M1·M2)은 이미 충족.
2. 미접속 배선(모듈은 완성, 오케스트레이션은 후속 phase):
   - 정산: worker 월말 마감 스케줄 → `BuildSettleInput` → COBOL → 결과 DB 반영
   - 분석: 야간 스케줄 → R/Julia 배치 → `report_artifact` 등록·캐시 서빙
   - DSL: eval 요청에 `txn.currency` 전달 (M5 계약 변경 — 소비자 미갱신)
3. 백서 §2.1/§3.1 버전 표기 개정(docs: 커밋) 미결 유지

---

## 멈춤 기록 (STOP — HARNESS §3.2)

(해소) 2026-07-20 Docker 데몬 미기동 블로커 — 사용자가 Docker Desktop 을 데스크톱 세션에서 직접 실행하여 해소(2026-07-21). 교훈: GUI 프론트엔드는 프로그램적 `Start-Process` 로 유지되지 않음, 권한 서비스(`com.docker.service`)만으로는 WSL 엔진이 기동되지 않음.

---

## 미결 질문

| # | 질문 | 상태 |
|---|---|---|
| 1 | ~~Erlang/Elixir 설치 방식~~ | **해소(2026-07-21)**: `hexpm/elixir` 멀티스테이지 COPY 성공 — 실존 태그 `1.18.3-erlang-27.3.3-ubuntu-noble-20260509.1` 로 고정, `mix local.hex/rebar` 정상 |
| 2 | ~~GnuCOBOL 소스 빌드 vs 배포판 (`COMP-3` 재현성)~~ | **해소(2026-07-22, M5)**: 입출력을 DISPLAY 텍스트 고정폭으로 설계해 COMP-3(PACKED-DECIMAL) 바이트를 와이어에 노출하지 않음 — 재현성 문제가 구조적으로 소멸. 실증: 컨테이너 3.2.0 과 CI 배포판 3.1.2 가 동일 골든 바이트 산출 (settlement 잡 그린) |
| 3 | 은행 CSV 골든 픽스처 3종 포맷 | M3 착수 전 결정 |
| 4 | ~~R 패키지 CRAN apt vs `renv`~~ | **해소(2026-07-23, M6)**: renv 미도입. 컨테이너 실설치본을 `modules/analytics/DEPENDS.lock`(경량 잠금)에 고정하고, CI 는 그 `snapshot` 날짜의 P3M 바이너리로 동일 버전을 복원한다. `tests/run.R` 의 version-lock 단언이 드리프트를 골든 비교 전에 잡는다. 실증: 로컬 컨테이너와 CI 러너가 SVG 골든 바이트 동일 |
| 5 | 프로덕션 배포 대상 | M9 전까지 |
| 6 | ~~GitHub 원격 연결~~ | **해소(2026-07-21)**: `JTech-CO/just-ledger` push 완료, CI 실측 완료 |
| 7 | ~~워커의 RLS 컨텍스트~~ | **해소(2026-07-21, M2)**: (a)안 확정 — 어댑터 계약(worker/prolog 시그니처)의 전 호출이 `ownerId` 를 명시로 받고, 워커는 작업 단위로 `set_config('app.user_id', ownerId)` 수행 |

---

## 툴체인 상태

`make toolchain-check` **통과** (컨테이너 내부, 2026-07-21). 확정 버전:

| 언어 | 확정 버전 | 확인일 |
|---|---|---|
| Node.js | v24.16.0 (+pnpm) | 2026-07-21 |
| Go | 1.26.5 linux/amd64 | 2026-07-21 |
| Rust / wasm-pack | rustc 1.97.1 / wasm-pack 0.15.0 (stable, 이미지에 고정. `rust-toolchain.toml` 은 M3 착수 시 1.97.1 로 도입) | 2026-07-21 |
| GHC / cabal | 9.10.3 / 3.16.1.0 | 2026-07-21 |
| GnuCOBOL (`cobc`) | 3.2.0 (소스 빌드) | 2026-07-21 |
| SWI-Prolog | 10.0.2 | 2026-07-21 |
| R | 4.3.3 (+ggplot2/jsonlite/svglite) | 2026-07-21 |
| Julia | 1.11.5 (+Distributions/StatsBase/JSON3) | 2026-07-21 |
| Elixir / OTP | 1.18.3 / 27.3.3 (erts-15.2.6) | 2026-07-21 |
| Lua / LuaRocks | 5.4.6 / 3.8.0 (+dkjson 2.10, `--lua-version=5.4` 필수) | 2026-07-21 |
| PostgreSQL | psql 18.4 (client; 서버는 compose `postgres:18`) | 2026-07-21 |
| github-linguist | 9.6.0 | 2026-07-21 |

**컨테이너 이미지**: `just-ledger-dev:local`, ImageID `sha256:6c5220f92a49b86b151dd7a42ada7bd2d34bbf477a548ffea1fe35aa125dbfc9` (10.1GB, 2026-07-21 빌드). `COMP-3` 재현성을 위해 레지스트리 푸시 시 다이제스트로 재고정한다.

> 참고: 백서 §2.1/§3.1 은 Node 22 LTS / PG 16 / React 18 을 명시하나, 툴체인 확정(2026-07-21)에서 Node 24 / PG 18 로 상향했다(Dockerfile·CI 반영). CI 는 컨테이너 확정 버전(OTP 27.3.3, GHC 9.10.3, cabal 3.16.1.0, R 4.3.3)에 정렬됨. 백서 개정은 별도 `docs:` 커밋으로.

---

## 계약 변경 로그

| 날짜 | 계약 파일 | 변경 내용 | 영향 모듈 | 갱신 완료 |
|---|---|---|---|---|
| 2026-07-20 | `contracts/{common,account,entry,txn,ingest-batch,notify-event}.schema.json` | M0 골격 신설 (SSOT 최초 정의) | 소비 예정: web(M2), db(M1), statement-wasm(M3), settlement(M5), realtime(M7). 현재 소비자 코드 없음 | 계약만 (소비자는 각 phase) |
| 2026-07-21 | `contracts/account.schema.json` | `code` 유니크 스코프를 전역→**소유자 내**로 설명 변경(존재 오라클·사용자 간 충돌 차단, 적대 검증 발견). JSON Schema 는 유니크성을 표현 못 하므로 pattern 불변, description 만 갱신 | db(M1, 반영됨: `UNIQUE(owner_id, code)`), web(M2 소비 시 반영) | db ✔ / web ✔ |
| 2026-07-21 | `contracts/balance.schema.json` (신설), `notify-event.schema.json` | 잔액 row 형태를 별도 계약으로 추출, notify-event 의 balance_changed.row 가 `$ref` 로 공유 — **와이어 형태 불변**(db NOTIFY 검증 그린 실측) | db(변경 불요, 실측 확인), web(M2 잔액 API 소비), realtime(M7 소비 예정) | db ✔ / web ✔ / realtime 대기 |
| 2026-07-21 | `contracts/statement-record.schema.json`, `ingest-payload.schema.json` (신설) | 인제스트 계약: 정규화 레코드(클라이언트 전용·평문 서버 금지) + 업로드 봉투(서버 가시 최소 필드 + 암호화 blob) | statement-wasm(M3-A ✔), worker(M3-B ✔ — 봉투 records 소비), web(M3-C 업로드 API 대기) | wasm ✔ / worker ✔ / web 대기 |
| 2026-07-21 | `statement-record.schema.json` (개정) | source_hash 를 **keyed BLAKE3**(패스프레이즈 파생 키)로, **memo 필드 신설**(가변 — 지문 제외). 적대 검증: 무키 지문은 서버 사전공격으로 상대처 복원 가능, 메모 포함 지문은 메모 편집만으로 중복제거 파괴 | statement-wasm ✔(골든 재생성·검토·동결), worker(지문 불투명 취급 — 무영향), web 대기 | wasm ✔ |
| 2026-07-21 | `ingest-batch.schema.json` (개정) | `account_id`(선택) 추가 — 명세서가 속한 은행 계정(draft 다리) | db ✔(컬럼+복합 FK), worker ✔, web(M3-C 대기) | db ✔ / worker ✔ |
| 2026-07-22 | `modules/settlement/copybook/{settle-io,amort-io}.cpy` (신설) | 정산·상각 고정폭 레코드 SSOT — SETTLE-IN 81 / SETTLE-OUT 51 / AMORT-IN 67 / AMORT-OUT 79. 상각 A 는 JS 참조가 계산해 입력(AI-PAYMENT) | settlement ✔, worker(records.go 미러) ✔, parity(records.mjs 미러·gen.mjs) ✔ | 전부 ✔ |
| 2026-07-22 | `settle-io.cpy`, `amort-io.cpy` (개정 — 적대검증) | 계약 한계 명문화: direction D\|C 강제, 고유 계정 ≤5000, S9(18) 범위 정책(생성기 사전 거절 + COBOL ON SIZE ERROR), AI-PERIODS 1..360, **상각 클램프 의미론**(원금 = clamp(A−이자, 0, 잔액) — 음수 상각 미표현) | settlement ✔, worker ✔, parity(lib/records.mjs) ✔ — 골든 재생성(LN0005 조기완제·LN0006 360회차 추가) | 전부 ✔ |
| 2026-07-22 | rules-dsl JSONL 프로토콜 (개정 — 적대검증) | eval `txn.currency` **필수화**(리터럴 통화 ≠ txn 통화면 rule 불발 — 환산·근사 없음), 응답에 `skipped_budgets` 추가, `parseMoney` 를 contracts moneyMinor 패턴과 동일 수용 집합으로 | dsl ✔, worker/web(M7+ 소비 시 currency 전달 필요 — 어댑터 계약에 반영 예정) | dsl ✔ / 소비자 대기 |
| 2026-07-23 | `apps/web/client/styles/tokens.css` (소비자 추가 — 파일 불변) | R 리포트가 SVG 색상을 이 파일에서 **파싱해 쓴다**(하드코딩 hex 0). 토큰 값이 바뀌면 analytics 골든 SVG 가 갈라지므로 CI analytics 잡 필터에 tokens.css 를 포함했고, 캐시 키에도 토큰 해시가 들어간다 | web(변경 불요 — 소유·형태 불변), analytics ✔(파서·AA 테스트) | analytics ✔ |
| 2026-07-23 | analytics JSONL 프로토콜 (신설), simulation JSONL 프로토콜 (신설) | analytics: `anomaly`/`forecast`/`report` 요청, 확률은 고정 자릿수 **문자열**, 금액은 최소단위 정수 문자열(2^53 초과 거절). simulation: `montecarlo`/`repayment`/`warmup`, 확률·CI 고정 자릿수 문자열, 금액 문자열(통계 경로 2^53 가드 / repayment 는 Int128 로 18자리 수용). 두 모듈 모두 `--cache-dir` 캐시 규약 | analytics ✔, simulation ✔, worker(야간 스케줄 오케스트레이션 미접속) | 모듈 ✔ / worker 대기 |

---

## 결정 로그

| 날짜 | 결정 | 이유 |
|---|---|---|
| 2026-07-20 | 프로젝트명 `just-ledger` | 밋밋한 이름일수록 Linguist 언어 바와의 낙차가 큼 |
| 2026-07-20 | 셀프호스팅 복식부기 가계부로 확정 | 언어마다 도메인상 정당화 존재. 'Hello world 모음집' 비판 차단 |
| 2026-07-20 | 메인 JavaScript(ESM+JSDoc), TS 미도입 | 계약이 11개 언어를 가로지름 → JSON Schema→JSDoc 이 적합 |
| 2026-07-20 | 금액=최소단위 정수, 환율=유리수 쌍 | 부동소수점 오차 원천 차단 (INV-4) |
| 2026-07-20 | 인프라 언어 `.gitattributes`로 Linguist 제외 | "메인 제외 각 5% 이상" = 5% 미달 언어 부재 |
| 2026-07-20 | 언어 비율은 CI 게이트로 강제, 조정은 기능·테스트로만 | 주석 패딩은 전제 붕괴 |
| 2026-07-20 | 툴체인 고정은 devcontainer(단일 Docker 이미지) | 재현성 과투자 회피, 배포 Dockerfile 재사용, 세션이 컨테이너서 구동 |
| 2026-07-20 | 시그니처 UI = '마감선'(회계 이중선) | 마감을 장부 관습으로 표현, 편집 컨트롤은 DOM에서 제거 |
| 2026-07-20 | **[M0] 계약 금액 문자열 상한을 18자리로 캡** | 19자리는 i64/BIGINT(9.22e18) 초과 가능 → SSOT가 데이터모델 범위보다 lax 하지 않게 (검증 워크플로 발견) |
| 2026-07-20 | **[M0] CI 언어 잡 = 경로변경 AND 모듈소스존재 게이트** | 착수 전 모듈(코드 부재)에서 빌드 잡이 오탐 실패하는 것 방지. 각 phase 코드 착수 시 자동 활성 |
| 2026-07-20 | **[M0] `linguist` 게이트는 M9 전까지 non-blocking** | 계측 언어가 점증적으로 채워져 M0~M8 동안 정당하게 실패. 게이트 로직은 불변, 강제 시점만 M9. `continue-on-error` 는 M9 에서 제거 |
| 2026-07-20 | **[M0] DoD 해석**: M0 = 툴체인 이미지+스캐폴딩+계약+CI 구조 | DoD 2·3의 "전체 빌드/lint 그린"은 모듈 코드가 있어야 성립. 빈 스텁으로 억지 통과는 'Hello world 모음집' 금지 원칙 위반. 언어별 빌드/테스트는 M1+ 에서 점증 그린 |
| 2026-07-21 | **[M0] Elixir 는 hexpm 멀티스테이지 COPY 로 확정** (미결질문 #1 해소) | 실존 태그 고정 후 빌드·`mix local.hex` 정상. Erlang Solutions apt 불필요 |
| 2026-07-21 | **[M0] luarocks 는 `--lua-version=5.4` 명시 필수** | Ubuntu luarocks 기본이 5.1 트리에 설치 → lua5.4 에서 모듈 미발견. Dockerfile 에 빌드 시 `require` 스모크 검사 추가로 회귀 차단 |
| 2026-07-21 | **[M0] Lua 게이트를 듀얼 모드(CLI+require)로, 테스트는 서브프로세스 금지** | 컨테이너 seccomp 에서 `os.execute` 가 ENOSYS(38). 판정 로직을 순수 함수로 분리해 직접 검증 — 더 견고하고 이식성 있음 |
| 2026-07-21 | **[M0] CI 툴체인 핀 = 컨테이너 확정 버전** (OTP 27.3.3/GHC 9.10.3/cabal 3.16.1.0/R 4.3.3) | 컨테이너가 정본. M6 골든 "바이트 동일" 전제상 R 버전 일치가 특히 중요 |
| 2026-07-21 | **[M1] RLS 를 위해 `owner_id` 컬럼·`app_user` 테이블 추가** | 백서 §2.3 엔 없지만 §7 "계정 소유자 격리" 요건의 구현 수단. API 계약엔 미노출(서버 내부 컬럼) |
| 2026-07-21 | **[M1] INV-5 를 멤버십 테이블 PK 로 강제** | `transfer_link(txn_a, txn_b)` 두 컬럼을 가로지르는 유니크는 부분 인덱스로 표현 불가 → `transfer_link_member.txn_id` PK 로 "한 txn 1 링크" 보장 |
| 2026-07-21 | **[M1] 불변식·잔액·알림 트리거 함수를 전부 `SECURITY DEFINER`** | 데이터 계층 로직은 세션 사용자 권한·RLS·GUC 와 무관하게 항상 실행돼야 한다. INVOKER 로 두면 ① 커밋 직전 GUC 조작으로 INV-1 검사 스킵 ② 회수된 내부 헬퍼 호출 시 42501. 트리거 함수는 직접 호출 불가라 오라클 아님 |
| 2026-07-21 | **[M1] 소유자 스코프 유니크 + 크로스 테넌트 복합 FK** | 전역 유니크(account.code, txn.source_hash)는 존재 오라클. FK 의 RI 는 RLS 를 우회하므로, transfer_link 는 `(txn, owner_id)` 복합 FK 로, entry 는 정책 WITH CHECK 로 계정 소유를 강제 |
| 2026-07-21 | **[M2] M2 는 단일 사용자 'local' 부트스트랩, 인증·다중 사용자는 후속 phase** | M2 DoD 는 API 골격이 대상. 서버가 기동 시 기본 소유자를 만들고 전 요청에 그 컨텍스트를 쓴다. 세션·로그인은 이후(M7 채널 티켓과 함께) 확정 |
| 2026-07-21 | **[M2] querystring 만 강제변환 ajv, body/params/응답은 엄격** | HTTP 쿼리는 항상 문자열 도착. 금액은 계약상 type:string 이라 변환 대상 아님(INV-4 안전). `useDefaults` 는 쿼리 인스턴스에만 |
| 2026-07-21 | **[M2] 응답도 계약으로 '검증'(위반 500), fast-json-stringify 강제 변환 미사용** | 계약 위반 응답은 조용히 교정되지 않고 시끄럽게 실패해야 한다. 검증 부재 회귀는 테스트(미니 앱 위반 라우트→500)로 고정 |
| 2026-07-21 | **[M2] 잔액도 계약 18자리 상한을 DB CHECK 로 강제** | entry 상한만으론 잔액 누적이 19자리(i64)로 계약(moneyMinor) 표현 밖에 도달 가능 → NOTIFY/API 직렬화가 계약 위반. account_balance CHECK 로 fail-closed (0001 은 pre-release 라 직접 수정, 결정 기록) |
| 2026-07-21 | **[M3] 지문 = keyed BLAKE3 + 발생 순번, 상점 성분은 불변 필드만** | ① 무키면 서버가 평문 일자·금액 + 상점 사전으로 상대처 복원(INV-6 우회) → 패스프레이즈 파생 키(사용자 고정 → 재업로드 결정론 유지) ② 백서 공식 그대로면 정당한 동일 거래 유실 → 파일 내 순번 추가 ③ 가변 메모를 지문에 넣으면 편집만으로 중복제거 파괴 → memo 분리 |
| 2026-07-21 | **[M3] 암호화 = Argon2id + ChaCha20-Poly1305(AAD), age 미사용** | age 의 패스프레이즈 모드는 scrypt 라 백서의 Argon2id 요구와 충돌 — Argon2id 우선. AAD(account_id‖file_hash)로 blob 스왑 거절, 봉투 파라미터 범위 강제(OOM 차단) |
| 2026-07-21 | **[M3] 서버 가시 필드 = 지문·일자·금액·통화만, draft 는 은행 다리 1개** | 적요·상대처·메모는 blob 에만(INV-6). draft 는 불균형 허용이므로 은행 계정 한 다리만 만들고 상대 다리는 분류(M4)가 채운다 |
| 2026-07-21 | **[M3] 워커 큐의 진실원천은 DB 상태 기계** | 소켓 nudge 는 힌트일 뿐 — 주기 스캔(fn_pending_ingest_batches)이 미완료 배치를 집으므로 강제 종료 후 재시작 시 자동 재개(DoD 5). draft 생성은 ON CONFLICT 멱등 |
| 2026-07-21 | **[M3] bench-wasm 게이트는 웜(티어업 후), 콜드는 참고 보고** | V8 는 wasm 을 Liftoff 로 먼저 돌리고 백그라운드 TurboFan — 첫 대형 호출은 수 배 느림. 클라이언트 Worker 가 기동 시 예열(M3-C 필수 항목으로 추적). UTF-8·CP949 양 경로 계측 |
| 2026-07-22 | **[M4] Prolog 는 무상태 순수 추론** | DB 를 보지 않고 요청에 사실을 실어 받는다. merchant 는 클라이언트 복호화 후 일시 전달, 서비스는 영속·로그하지 않는다 (INV-6) |
| 2026-07-22 | **[M4] 이체 매칭 모호성 보수 정책** | 후보가 '상호 유일'할 때만 확정 — A 후보가 B뿐이고 B 후보도 A뿐. 모호하면 미매칭. 거짓양성 0(INV-8)이 재현율보다 우선. 금액은 정확 일치만(근사 금지) |
| 2026-07-22 | **[M4] 소득 규칙은 부호(Amount>0)와 결합** | '이자'/'급여' 는 부분문자열이라 부호 없이 매칭하면 음수 '대출이자'(지출)를 interest(소득)로 뒤집는다. income_rule/4 를 분리해 양수일 때만 시도 (적대 검증) |
| 2026-07-22 | **[M4] 분류 골든은 적대적 케이스 포함** | 규칙 키워드를 라벨로 베끼면 정확도가 공허하게 부풀려짐 — 부분문자열 충돌(이자카야)·순서 함정(쿠팡이츠/쿠팡)·음수 소득키워드를 넣어 규칙 품질을 실제로 시험 |
| 2026-07-22 | **[M4] Lua 샌드박스: print 차단·string.rep 상한·panic recover** | print 는 stdout(→로그)으로 새 INV-6 위반. string.rep 단일 빌트인 대량 할당은 명령어 경계가 없어 100ms 타임아웃을 우회 → 총길이 상한 래퍼. 빌트인 panic 은 recover 로 워커 보호 (적대 검증) |

---

## 게이트 통과 현황

| Phase | 상태 | 통과일 |
|---|---|---|
| M0 툴체인·스캐폴딩 | **통과** (DoD 4: CI 런 29776630994 — 언어 잡 10개 스킵, changes/contracts/lua-gate 그린) | 2026-07-21 |
| M1 데이터·영속화 | **통과** (`make test-db` 로컬 컨테이너 + CI 런 29787725390 db 잡 양쪽 그린 — INV-1/2/3/5 + RLS + NOTIFY 실측) | 2026-07-21 |
| M2 API·서버 골격 | **통과** (로컬 + CI 런 29802235905 web 잡 그린 — DoD 1~5 실측) | 2026-07-21 |
| M3 인제스트 | **통과** (DoD 1~5 + INV-6 실측 — 골든 3사·재업로드 0·웜 벤치·봉투 평문 부재·배치 재개) | 2026-07-22 |
| M4 추론 | **통과** (분류 97.4%·이체 거짓양성 0/INV-8·정기결제·Lua 샌드박스 — plunit 19+sandbox 그린 + CI 런 29867115754 prolog 잡 그린) | 2026-07-22 |
| M5 정산 | **통과** (INV-7 차이 0원: 10,000 entry·상각 481행·0.5 경계 400건 삼자 일치, 로컬 3.2.0 + CI 3.1.2 이종 재현 — CI 런 29895860120 settlement·worker 그린. DSL 스펙 유효 20/오류 29/위치 exact. 적대 검증 15건 수정) | 2026-07-22 |
| M6 분석 | **통과** (DoD 1~5 실측: 바이트 결정론·재현율 1.000/FPR ≤0.0049·NaN 0/CI 0.0089·SVG 2벌 AA·캐시. analytics 58 + simulation 50 그린, CI analytics/simulation 잡 그린. 적대 검증 22건 수정) | 2026-07-23 |
| M7 실시간 | 대기 | — |
| M8 UI·접근성 | 대기 | — |
| M9 언어 구성·배포 | 대기 | — |
