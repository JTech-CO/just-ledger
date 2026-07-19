# PROGRESS — just-ledger

이 파일만 읽으면 이어서 작업할 수 있어야 한다. 세션 종료 시 반드시 갱신한다.

---

## 현재 phase

**M0 — 툴체인 및 스캐폴딩** (진행 중 — 스캐폴딩 완료, DoD 1 만 Docker 데몬 부재로 대기)

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

---

## 다음 할 일

> **선행 블로커**: Docker 데몬 미기동(아래 *멈춤 기록* 참조). DoD 1 은 데몬이 떠야 진행 가능.

1. **(사용자 조치 필요)** Docker Desktop 기동 — `com.docker.service`(Stopped/Manual)를 관리자 권한으로 시작. 세션이 비관리자라 UAC를 충족 불가.
2. 데몬 기동 후: `docker build -f infra/devcontainer/Dockerfile --target dev -t just-ledger-dev:local .` (11개 툴체인, 최초 30~60분 예상)
3. `docker run --rm -v "$PWD":/workspace -w /workspace just-ledger-dev:local make toolchain-check` → 11개 버전 출력·성공 종료 (M0 DoD 1)
4. 실제 설치 버전을 **툴체인 상태** 표에 확정 기록 + 이미지 다이제스트 고정
5. 컨테이너 안에서 `lua5.4 scripts/tests/linguist-gate.test.lua`, `node contracts/check.mjs` 재확인
6. GitHub 원격 연결 시 CI 그린 확인(로컬에서 GitHub Actions 실행 불가) → M0 DoD 4 최종 확인
7. M0 DoD 재점검 후 **M1(PostgreSQL/PLpgSQL)** 진입

---

## 멈춤 기록 (STOP — HARNESS §3.2)

| 항목 | 내용 |
|---|---|
| **증상** | `docker build` 실패: `failed to connect to the docker API at npipe:////./pipe/dockerDesktopLinuxEngine … daemon is running` |
| **재현** | 호스트(Windows 11)에서 `docker build …` 또는 `docker ps` |
| **원인** | Docker CLI(29.6.1)는 설치됨. 그러나 `com.docker.service`(Docker Desktop Service)가 **Stopped/StartType=Manual**, docker 프로세스 없음. 서비스 시작은 **관리자 권한** 필요. 현재 세션은 비관리자(`IsInRole Administrator=False`)라 UAC 승인 불가 → 데몬 기동 불가 |
| **시도한 것** | ① `Start-Process "Docker Desktop.exe"` ×2 (프로세스 미유지) ② 데몬 준비 6분 폴링 → 타임아웃 ③ 서비스/프로세스/WSL 상태 점검(모두 미기동) |
| **가설** | 관리자 권한으로 `com.docker.service` 를 시작하거나 사용자가 Docker Desktop 을 직접 실행하면 해소 |
| **영향 범위** | **M0 DoD 1(툴체인 이미지+toolchain-check)만** 블록. 나머지 M0 스캐폴딩·계약·CI·게이트는 완료·검증됨 |
| **불변식 우회** | 없음 — 게이트를 낮추거나 위장하지 않음. 데몬 결정 대기 |

---

## 미결 질문

| # | 질문 | 상태 |
|---|---|---|
| 0 | **Docker 데몬 기동 방식** — (a) 사용자가 Docker Desktop 수동 실행 (b) 관리자 UAC 승인으로 서비스 시작 (c) 이미지 빌드 보류하고 스캐폴딩만 확정 | **사용자 결정 대기** |
| 1 | Erlang/Elixir 설치를 `hexpm/elixir` COPY vs Erlang Solutions apt | M0 실제 빌드로 판정(데몬 대기) |
| 2 | GnuCOBOL 소스 빌드 vs 배포판 (`COMP-3` 재현성) | 소스 빌드 우선, 골든 픽스처 검증 |
| 3 | 은행 CSV 골든 픽스처 3종 포맷 | M3 착수 전 결정 |
| 4 | R 패키지 CRAN apt vs `renv` | M6 착수 전 결정 |
| 5 | 프로덕션 배포 대상 | M9 전까지 |

---

## 툴체인 상태

`make toolchain-check` 는 **아직 미실행**(Docker 데몬 대기). 아래는 Dockerfile/PROGRESS 초기 핀이며 확정값이 아니다.

| 언어 | 초기 핀 후보 | 확정 버전 | 확인일 |
|---|---|---|---|
| Node.js | 24.16.0 | — | — |
| Go | 1.26.5 | — | — |
| Rust | stable (`rust-toolchain.toml`) | — | — |
| GHC / cabal | recommended / latest (ghcup) | — | — |
| GnuCOBOL (`cobc`) | 3.2 (소스 빌드) | — | — |
| SWI-Prolog | ppa:swi-prolog/stable | — | — |
| R | apt r-base (4.5.x) | — | — |
| Julia | 1.11.5 | — | — |
| Elixir / OTP | 1.18.3 / 27.3.3 | — | — |
| Lua / LuaRocks | 5.4 | — | — |
| PostgreSQL | 18 (client) | — | — |
| github-linguist | 최신 gem | — | — |

**컨테이너 이미지 다이제스트**: (빌드 완료 시 기록) — `COMP-3` 재현성 때문에 반드시 다이제스트로 고정.

> 참고: 백서 §2.1 은 Node 22 LTS / PG 16 을 명시하나, 툴체인 결정(2026-07-20)에서 Node 24 / PG 18 로 상향했다(Dockerfile·CI 반영). 백서 개정은 M0 확정 후 별도 `docs:` 커밋으로.

---

## 계약 변경 로그

| 날짜 | 계약 파일 | 변경 내용 | 영향 모듈 | 갱신 완료 |
|---|---|---|---|---|
| 2026-07-20 | `contracts/{common,account,entry,txn,ingest-batch,notify-event}.schema.json` | M0 골격 신설 (SSOT 최초 정의) | 소비 예정: web(M2), db(M1), statement-wasm(M3), settlement(M5), realtime(M7). 현재 소비자 코드 없음 | 계약만 (소비자는 각 phase) |

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

---

## 게이트 통과 현황

| Phase | 상태 | 통과일 |
|---|---|---|
| M0 툴체인·스캐폴딩 | 진행 중 (스캐폴딩✔ / DoD1 데몬 대기) | — |
| M1 데이터·영속화 | 대기 | — |
| M2 API·서버 골격 | 대기 | — |
| M3 인제스트 | 대기 | — |
| M4 추론 | 대기 | — |
| M5 정산 | 대기 | — |
| M6 분석 | 대기 | — |
| M7 실시간 | 대기 | — |
| M8 UI·접근성 | 대기 | — |
| M9 언어 구성·배포 | 대기 | — |
