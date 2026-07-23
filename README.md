# just-ledger

> **내 서버에서 돌리는 복식부기 개인 원장 — 금액은 1원도 틀리지 않게, 계산 도메인마다 가장 맞는 언어로.**

**[▶ UI 데모 열기](https://jtech-co.github.io/just-ledger/)** — 설치 없이 화면만 바로 볼 수 있습니다. 브라우저 안에서 도는 **모의 데이터**이며 서버·데이터베이스에 연결되어 있지 않습니다(복식부기 강제·마감 정합성·자동 분류는 서버 계층이라 데모에서는 동작하지 않습니다).

## 1. 소개 (Introduction)

**just-ledger**는 개인 가계를 복식부기(double-entry)로 기록·분석하는 **셀프호스팅 웹 애플리케이션**입니다. 가계부 앱에 내 금융 내역을 넘기지 않고 내 인프라에서 직접 운영하면서도, 회계 장부 수준의 정합성과 통계·시뮬레이션 분석을 함께 얻는 것이 목표입니다.

설계의 두 축은 **금액 정확성**과 **도메인별 언어 선택**입니다. 모든 금액은 최소 화폐 단위 정수로만 다루어 부동소수점 오차가 발생할 경로를 아예 두지 않고, 마감·분류·실시간·통계처럼 성격이 다른 계산은 각각 그 일에 가장 맞는 언어가 담당합니다.

**주요 기능**

- **복식부기 원장**: 모든 거래는 차변 합계 = 대변 합계로 균형을 이룹니다. 이 규칙은 애플리케이션이 아니라 **데이터베이스 트리거가 커밋 시점에 강제**하므로, 어떤 경로로 들어와도 불균형 거래가 저장되지 않습니다.
- **오차 없는 금액 처리**: 금액은 전 구간(입력 → 저장 → 계산 → 표시) 정수로만 흐릅니다. 환율은 실수가 아닌 유리수 쌍으로, 반올림은 은행가 반올림(round-half-even) 하나만 정본으로 씁니다.
- **명세서 가져오기**: 카드·은행 명세서를 **브라우저 안에서** 파싱·암호화해 업로드합니다. 명세서 원문이 서버 로그·DB에 평문으로 남지 않습니다.
- **자동 분류와 이체 매칭**: 논리 규칙으로 거래를 분류하고 정기결제를 탐지하며, 계좌 간 이체 쌍을 **정확 매칭**으로만 연결합니다(금액 근사 매칭을 쓰지 않아 거짓 연결이 생기지 않습니다). 분류 결과에는 근거 규칙 이름이 함께 남습니다.
- **월말 마감 정산**: 마감·이자·감가상각을 고정소수점 십진 연산으로 계산하고, 독립 구현과 **차이 0원**으로 대조한 뒤에만 확정합니다. 마감된 기간의 기록은 수정·삭제가 잠깁니다.
- **예산 규칙과 실시간 알림**: 예산 규칙을 전용 DSL로 정의하고, 잔액 변화·예산 초과·마감 완료를 WebSocket으로 즉시 받아 봅니다.
- **분석과 시뮬레이션**: 지출 추세·이상치 탐지와 결정론적 SVG 리포트, 몬테카를로 현금흐름 예측과 부채 상환 순서 최적화를 제공합니다.
- **사용자 자동화 규칙**: 직접 작성한 규칙 스크립트를 **격리된 샌드박스**에서 실행해 태깅·분류·알림을 자동화합니다.
- **대용량 UI**: 10만 행 원장도 일정한 DOM 수로 가상 스크롤하며, 키보드만으로 조작할 수 있고 명암비 AA·다크 모드·모션 최소화를 지원합니다.

## 2. 기술 스택 (Tech Stack)

- **Frontend**: React 18, Vite 6, CSS Modules (디자인 토큰 기반), Zustand
- **Backend**: Node.js + Fastify 5 (ESM + JSDoc, TypeScript 미사용)
- **Database**: PostgreSQL 18 (불변식 트리거·집계·RLS를 PLpgSQL로)
- **Realtime**: Elixir + Phoenix Channels (PostgreSQL `NOTIFY` 브리지)
- **Deployment**: Docker Compose (단일 스택 셀프호스팅), 개발 툴체인은 단일 devcontainer 이미지로 고정

계산 도메인은 11개 언어가 나누어 맡습니다. 언어마다 그 언어를 고른 이유가 있으며, 장식용 다언어 구성이 아닙니다.

| 언어 | 담당 도메인 | 선정 근거 |
|---|---|---|
| **JavaScript** | web 서버·React UI·어댑터 | 브라우저와 서버를 한 언어로 잇고, 계약을 JSON Schema→JSDoc으로 언어 중립으로 유지한다. |
| **Go** | worker: 큐·스케줄러·subprocess 오케스트레이션 | 경량 동시성과 단일 바이너리로 상주 워커와 배치 프로세스 오케스트레이션에 맞는다. |
| **Rust** | 명세서 파싱·지문·암호화(WASM) | 메모리 안전성과 WASM 타깃으로 브라우저에서 대용량 파싱·암호화를 안전·고속으로 수행한다. |
| **Elixir** | 실시간 채널·NOTIFY 브리지 | BEAM의 경량 프로세스와 감독 트리가 다수 동시 연결의 실시간 푸시·복구에 이상적이다. |
| **Haskell** | 예산 규칙 DSL | 대수적 데이터 타입과 파서 콤비네이터로 DSL의 파싱·타입검사·평가를 견고하게 표현한다. |
| **COBOL** | 마감 정산·이자·상각·은행가 반올림 | 고정소수점 십진 연산과 `ROUNDED NEAREST-EVEN`이 금융 마감의 정합성(0원 오차) 정본에 맞는다. |
| **PLpgSQL** | 스키마·불변식 트리거·집계·RLS | 불변식을 데이터에 가장 가깝게, 트랜잭션 커밋 시점에 강제한다(deferrable 트리거). |
| **R** | 통계 분석·이상치·SVG 리포트 | STL 분해·MAD·부트스트랩과 ggplot SVG로 통계와 결정론적 리포트에 적합하다. |
| **Prolog** | 분류·이체 매칭·정기결제 탐지 | 논리 규칙과 백트래킹이 근거 규칙명을 동반한 분류·정확 매칭 추론에 자연스럽다. |
| **Julia** | 몬테카를로·상환 최적화 | 고성능 수치 계산과 DP로 현금흐름 시뮬레이션·상환 순서 최적화를 수행한다. |
| **Lua** | 사용자 자동화 규칙 샌드박스 | 작고 임베드가 쉬워 gopher-lua로 안전한 사용자 규칙 샌드박스를 만든다. |

언어 간 데이터 형식은 `contracts/*.schema.json`(과 COBOL copybook)이 단일 진실원천이며, 각 모듈은 stdin/stdout만으로 단독 실행되고 고정 입력 → 고정 기대 출력의 골든 테스트를 가집니다.

## 3. 설치 및 실행 (Quick Start)

**요구 사항**: Docker (Compose v2 포함). 11개 언어 툴체인은 모두 개발 이미지 안에 있으므로 호스트에 따로 설치할 필요가 없습니다. 단, UI 개발 서버를 호스트에서 직접 띄우려면 Node.js 24+ 와 pnpm 이 필요합니다.

1. **설치 (Install)**

   ```bash
   git clone https://github.com/JTech-CO/just-ledger.git
   cd just-ledger
   docker build -f infra/devcontainer/Dockerfile --target dev -t just-ledger-dev:local .
   ```

2. **환경 변수 (Environment)**

   `.env.example` 파일을 `.env`로 복사하고 값을 채웁니다. `.env`는 커밋하지 않습니다.

   ```bash
   cp .env.example .env
   ```

   ```bash
   # .env 예시
   POSTGRES_PASSWORD=ledger
   DATABASE_URL=postgres://ledger:ledger@localhost:5432/ledger
   # web(서명)과 realtime(검증)이 공유하는 키 — 반드시 직접 생성해 넣습니다.
   SECRET_KEY_BASE=<openssl rand -hex 64 결과>
   ```

3. **실행 (Run)**

   ```bash
   make up      # db·web(API)·worker·prolog·realtime 기동
   make smoke   # 전체 스택 클린 기동 + 원장 동작 검증 (선택)
   make down    # 종료
   ```

   API 서버는 `http://localhost:3000` 에서 응답합니다(`/health`, `/api/...`).

   화면(React UI)은 개발 서버로 띄웁니다. 빌드 산출물의 프로덕션 정적 서빙은 아직 배선하지 않았습니다.

   ```bash
   cd apps/web && pnpm install && pnpm dev:client   # http://localhost:5173 (API 로 프록시)
   ```

   사용 가능한 전체 명령은 `make help` 로 확인합니다.

## 4. 폴더 구조 (Structure)

```text
just-ledger/
├── apps/web/              # JavaScript — Fastify 서버 + React UI
├── services/
│   ├── worker/            # Go — 큐·스케줄러 (Lua 자동화 규칙 샌드박스 포함)
│   ├── prolog/            # Prolog — 분류·이체 매칭·정기결제 탐지
│   └── realtime/          # Elixir — Phoenix 채널·NOTIFY 브리지
├── modules/
│   ├── statement-wasm/    # Rust — 명세서 파싱·지문·암호화 (WASM)
│   ├── rules-dsl/         # Haskell — 예산 규칙 DSL
│   ├── settlement/        # COBOL — 마감 정산·이자·상각
│   ├── analytics/         # R — 통계·이상치·SVG 리포트
│   └── simulation/        # Julia — 몬테카를로·상환 최적화
├── db/                    # PLpgSQL — 스키마·불변식 트리거·집계·RLS
├── contracts/             # JSON Schema — 언어 간 단일 진실원천
├── fixtures/              # 골든 입출력 데이터
├── infra/                 # Docker·Compose·스모크 테스트
└── docs/                  # 기술·디자인 백서
```

## 5. 정보 (Info)

**현재 상태**: 11개 언어 모듈과 원장 핵심 경로(계정·거래 입력 → 불변식 강제 → 잔액 집계 → 실시간 반영)는 동작하며, 각 모듈은 골든 테스트와 CI 게이트로 검증됩니다. 다음 두 가지는 아직 배선 중입니다 — **배치 오케스트레이션**(월말 마감 실행 트리거, 야간 분석·시뮬레이션 스케줄)과 **UI 프로덕션 정적 서빙**.

- **License**: MIT
- **Repository**: https://github.com/JTech-CO/just-ledger
- **문서**: 설계 배경과 의사결정은 `docs/Whitepaper/` 의 기술·디자인 백서에 있습니다.
