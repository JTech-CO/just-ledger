# just-ledger

셀프호스팅 복식부기 개인 원장. 11개 언어가 각기 다른 계산 도메인을 담당하는 폴리글랏 시스템이며, 언어 선택마다 도메인상 정당화가 존재한다(장식용 다언어가 아니다).

메인 언어는 **JavaScript(ESM + JSDoc)**. TypeScript는 도입하지 않는다 — 계약이 11개 언어를 가로지르므로 언어 종속 타입 시스템보다 `contracts/*.schema.json` → JSDoc 생성이 적합하다.

## 빠른 시작

개발 환경은 **단일 devcontainer 이미지**로 11개 툴체인을 고정한다.

```bash
# 1) 개발 이미지 빌드 (11개 툴체인). 컨텍스트는 레포 루트 — devcontainer.json / compose.yaml 와 동일.
docker build -f infra/devcontainer/Dockerfile --target dev -t just-ledger-dev:local .

# 2) 툴체인 확인 (M0 DoD 1)
docker run --rm -v "$PWD":/workspace -w /workspace just-ledger-dev:local make toolchain-check

# 3) 스택 기동
cp .env.example .env
make up          # docker compose 로 db/web/worker/prolog/realtime 기동
```

`make help` 로 전체 타깃을 본다.

## 언어 구성과 선정 근거

각 언어는 그 언어가 가장 잘 맞는 도메인을 담당한다(기술 백서 §3.3).

| 언어 | 담당 | 선정 근거 (M9 DoD 6) |
|---|---|---|
| **JavaScript** | web 서버·React UI·어댑터 | 브라우저와 서버를 한 언어로 잇고, 계약을 JSON Schema→JSDoc으로 언어 중립으로 유지한다. |
| **Go** | worker: 큐·스케줄러·subprocess 오케스트레이션 | 경량 동시성과 단일 바이너리로 상주 워커와 배치 프로세스 오케스트레이션에 맞는다. |
| **Rust** | 명세서 파싱·지문·암호화(WASM) | 메모리 안전성과 WASM 타깃으로 브라우저에서 대용량 파싱·암호화를 안전·고속으로 수행한다. |
| **Elixir** | 실시간 채널·NOTIFY 브리지 | BEAM의 경량 프로세스와 감독 트리가 다수 동시 연결의 실시간 푸시·복구에 이상적이다. |
| **Haskell** | 예산 규칙 DSL | 대수적 데이터 타입과 파서 콤비네이터로 DSL의 파싱·타입검사·평가를 견고하게 표현한다. |
| **COBOL** | 마감 정산·상각·은행가 반올림 | 고정소수점 십진 연산과 `ROUNDED NEAREST-EVEN`이 금융 마감의 정합성(0원 오차) 정본에 맞는다. |
| **PLpgSQL** | 스키마·불변식 트리거·집계·RLS | 불변식을 데이터에 가장 가깝게, 트랜잭션 커밋 시점에 강제한다(deferrable 트리거). |
| **R** | 통계 분석·이상치·SVG 리포트 | STL 분해·MAD·부트스트랩과 ggplot SVG로 통계와 결정론적 리포트에 적합하다. |
| **Prolog** | 분류·이체 매칭·정기결제 탐지 | 논리 규칙과 백트래킹이 근거 규칙명을 동반한 분류·정확 매칭 추론에 자연스럽다. |
| **Julia** | 몬테카를로·상환 최적화 | 고성능 수치 계산과 DP로 현금흐름 시뮬레이션·상환 순서 최적화를 수행한다. |
| **Lua** | 사용자 자동화 규칙 샌드박스·언어 게이트 | 작고 임베드가 쉬워 gopher-lua로 안전한 사용자 규칙 샌드박스를 만든다. |

목표 비율·게이트는 기술 백서 §8, 강제는 `make linguist-gate` / CI `linguist` 잡.

## 절대 불변식

| ID | 내용 |
|---|---|
| INV-1 | `posted` 이상 txn은 통화별 `sum(debit)=sum(credit)` |
| INV-2 | `entry.amount_minor > 0` (부호는 `direction`) |
| INV-3 | `settled` 기간 txn·entry는 UPDATE/DELETE 불가 |
| INV-4 | 금액이 부동소수점을 경유하는 경로 0개 |
| INV-5 | 한 txn은 최대 1개 `transfer_link`에만 속함 |
| INV-6 | 명세서 원문이 서버 로그·DB·임시 파일에 평문으로 남지 않음 |
| INV-7 | COBOL 마감과 JS 참조 구현의 차이 0원 |
| INV-8 | 이체 페어 매칭 거짓양성 0건 |

## 문서

- `PROGRESS.md` — 현재 phase·다음 할 일·툴체인 상태·결정 로그 (세션 인계)
- `docs/Harness/HARNESS.md` — phase별 진입조건·DoD·검증·멈춤 규칙
- `docs/Whitepaper/TECH-WHITEPAPER.md` / `DESIGN-WHITEPAPER.md`
- `CLAUDE.md` (루트 + 각 모듈) — 작업 규율
