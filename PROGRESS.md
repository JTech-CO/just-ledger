# PROGRESS — just-ledger

이 파일만 읽으면 이어서 작업할 수 있어야 한다. 세션 종료 시 반드시 갱신한다.

---

## 현재 phase

**M2 — API 및 서버 골격 (JavaScript)** (착수 전)

M0(2026-07-21)·M1(2026-07-21) 게이트 통과. M1: `make test-db` 컨테이너 실측 전체 그린 — 스키마 up/down/up diff 0, 불변식 음성 테스트 전수, 10만 txn INV-1 위반 0, 잔액 롤업 전수 일치, RLS 소유자 격리, NOTIFY 계약 준수. 적대적 검증 2라운드(1차 13건 + 재검증 1건) 발견 전부 해소, 재검증 3렌즈 0건.

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

---

## 다음 할 일

1. **M2 착수** (JavaScript 단일 언어 세션): `contracts/` 확정 → JSDoc `@typedef` 생성 → Fastify 라우트(계정 CRUD, txn 조회·생성, 기간 잔액) → 어댑터 인터페이스 스텁(worker/prolog/realtime 시그니처 확정) → React 셸 → `LedgerTable` 최소판
2. M2 요점: 요청/응답 `contracts/*.schema.json` 검증(위반 400), **금액 문자열 왕복 무손실**, **`Number` 경유 코드 경로 0개**(`make check-no-float`, INV-4). RLS 연동 — 서버가 인증 후 세션 GUC `app.user_id` 설정(M1 미결질문 #7 워커 모델도 이때 확정)
3. `GET /health` 200(3초 내), 핵심 엔드포인트 왕복 테스트 (M2 DoD)

---

## 멈춤 기록 (STOP — HARNESS §3.2)

(해소) 2026-07-20 Docker 데몬 미기동 블로커 — 사용자가 Docker Desktop 을 데스크톱 세션에서 직접 실행하여 해소(2026-07-21). 교훈: GUI 프론트엔드는 프로그램적 `Start-Process` 로 유지되지 않음, 권한 서비스(`com.docker.service`)만으로는 WSL 엔진이 기동되지 않음.

---

## 미결 질문

| # | 질문 | 상태 |
|---|---|---|
| 1 | ~~Erlang/Elixir 설치 방식~~ | **해소(2026-07-21)**: `hexpm/elixir` 멀티스테이지 COPY 성공 — 실존 태그 `1.18.3-erlang-27.3.3-ubuntu-noble-20260509.1` 로 고정, `mix local.hex/rebar` 정상 |
| 2 | GnuCOBOL 소스 빌드 vs 배포판 (`COMP-3` 재현성) | 소스 빌드 3.2.0 설치 성공. `COMP-3` 바이트 재현성은 M5 골든 픽스처에서 최종 검증 |
| 3 | 은행 CSV 골든 픽스처 3종 포맷 | M3 착수 전 결정 |
| 4 | R 패키지 CRAN apt vs `renv` | M6 착수 전 결정 (R 4.3.3 확정을 전제로) |
| 5 | 프로덕션 배포 대상 | M9 전까지 |
| 6 | ~~GitHub 원격 연결~~ | **해소(2026-07-21)**: `JTech-CO/just-ledger` push 완료, CI 실측 완료 |
| 7 | **워커의 RLS 컨텍스트** — `ledger_worker` 는 `owner_id=current_owner()` 정책상 소유자 GUC 없이는 어떤 행도 못 본다. M4(Prolog 매칭)·M3(인제스트) 워커가 다수 소유자를 처리하는 흐름과 충돌. (a) 잡/NOTIFY 페이로드에 `owner_id` 포함해 워커가 작업 단위로 `set_config` (b) 워커 전용 무소유자 큐 (c) 워커에 `BYPASSRLS`(§7 위반이라 배제) 중 택일 | **M3/M4 착수 전 결정** — (a) 유력 |

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
| 2026-07-21 | `contracts/account.schema.json` | `code` 유니크 스코프를 전역→**소유자 내**로 설명 변경(존재 오라클·사용자 간 충돌 차단, 적대 검증 발견). JSON Schema 는 유니크성을 표현 못 하므로 pattern 불변, description 만 갱신 | db(M1, 반영됨: `UNIQUE(owner_id, code)`), web(M2 소비 시 반영) | db ✔ / web 대기 |

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

---

## 게이트 통과 현황

| Phase | 상태 | 통과일 |
|---|---|---|
| M0 툴체인·스캐폴딩 | **통과** (DoD 4: CI 런 29776630994 — 언어 잡 10개 스킵, changes/contracts/lua-gate 그린) | 2026-07-21 |
| M1 데이터·영속화 | **통과** (`make test-db` 로컬 컨테이너 + CI 런 29787725390 db 잡 양쪽 그린 — INV-1/2/3/5 + RLS + NOTIFY 실측) | 2026-07-21 |
| M2 API·서버 골격 | 대기 | — |
| M3 인제스트 | 대기 | — |
| M4 추론 | 대기 | — |
| M5 정산 | 대기 | — |
| M6 분석 | 대기 | — |
| M7 실시간 | 대기 | — |
| M8 UI·접근성 | 대기 | — |
| M9 언어 구성·배포 | 대기 | — |
