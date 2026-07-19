# just-ledger 기술 백서 (Technical Whitepaper)

**버전**: 1.0
**작성일**: 2026년 07월 20일
**작성자**: Bryan / JTech-CO
**참고 문서**: 폴리글랏 기획서 v1.0, 디자인 백서 v1.0, `docs/HARNESS.md`, `contracts/*.schema.json`

---

## 1. 프로젝트 개요 (Project Overview)

### 1.1. 프로젝트 명

**just-ledger** — 셀프호스팅 복식부기 개인 원장

### 1.2. 목적 (Purpose)

- 개인 금융 데이터를 **이중분개(double-entry)** 로 기록하고, 금액 연산 전 구간에서 부동소수점 오차를 원천 배제한다.
- 은행 명세서 원문이 **서버에 평문으로 도달하지 않도록** 브라우저 내에서 파싱·정규화·암호화를 완료한다.
- 계산 도메인(정산·추론·통계·시뮬레이션·파싱)을 각각에 최적인 언어로 분리 구현하고, 언어 경계를 **스키마 계약과 골든 테스트로 관리**하는 폴리글랏 아키텍처를 실증한다.
- 부수 목표: 11개 언어가 각각 5% 이상을 차지하되, 모든 언어 선택에 도메인상의 정당화가 존재하는 코드베이스를 만든다.

### 1.3. 핵심 차별점 (Key Differentiators)

1. **금액 정확성 (Exactness)**: 모든 금액을 `BIGINT` 최소 화폐 단위 정수로 보관하고, 마감 정산은 COBOL의 `COMP-3` 고정소수점으로 수행한다. 애플리케이션 계층에 금액을 부동소수점으로 담는 경로가 **0개**임을 CI로 강제한다.
2. **로컬 우선 인제스트 (Local-first Ingest)**: Rust→WASM 모듈이 Web Worker에서 명세서를 파싱하고 BLAKE3 지문 기반 중복 제거 후 Argon2id 유래 키로 암호화한다. 서버는 원문을 복호화할 수 없다.
3. **계약 기반 폴리글랏 (Contract-driven Polyglot)**: 11개 언어가 `contracts/` 의 JSON Schema와 COBOL copybook을 단일 진실원천으로 공유한다. 각 모듈은 stdin/stdout만으로 단독 실행·검증 가능하다.

---

## 2. 상세 기능 요구사항 (Detailed Requirements)

### 2.1. 시스템 환경 및 인터페이스 (System & Interface)

- **뷰 모드 (View Mode)**: **Desktop First**. 원장은 본질적으로 다열 표 데이터이므로 1440px 기준으로 설계하고 768px까지 fluid 축소한다. 768px 미만은 표를 카드 리스트로 전환한다.
- **테마 정책 (Theme Policy)**: CSS Variables 기반. 기본 Light, `prefers-color-scheme: dark` 자동 대응 + 수동 토글(localStorage 저장). 토큰은 디자인 백서 §5와 1:1 대응한다.
- **배포 형태**: 단일 `docker compose` 스택. 상시 프로세스 4개(web / worker / prolog / realtime) + PostgreSQL, 배치 프로세스 4개(cobol / haskell / r / julia)는 worker가 subprocess로 기동.
- **런타임 요구**: Node 22 LTS, PostgreSQL 16, 컨테이너 총 메모리 2GB 이내.

### 2.2. 사용자 상호작용 로직 (Interaction Logic)

- **이벤트 처리 (Event Handling)**:
  - **Input**: 거래 검색어는 Debounce 250ms. 금액 입력은 IME·천단위 구분자·통화기호를 제거하고 최소 단위 정수로 정규화한 뒤 상태에 반영한다(입력 중에도 float 미사용).
  - **Action**: 명세서 파일 드롭 → Web Worker에서 WASM 파싱(진행률 이벤트) → 암호화 페이로드 업로드 → 서버가 batch 생성 후 즉시 202 응답 → 이후 진행률은 Elixir 채널로 스트리밍. 업로드 요청이 응답을 기다리며 UI를 잠그지 않는다.
  - **Undo**: 분류 변경·태그 부여는 낙관적 갱신(Optimistic Update). 서버 거절 시 이전 상태로 롤백하고 사유를 인라인 표시한다.
- **데이터 검증 (Validation)**: 동일 스키마로 **3중 검증**한다.
  1. 클라이언트: `ajv` + `contracts/*.schema.json`
  2. 서버: Fastify 스키마 컴파일 (동일 파일)
  3. DB: PLpgSQL `CHECK`·트리거 불변식
  - 어느 한 단계라도 통과 실패 시 하위 단계로 진행하지 않는다. 스키마 파일은 한 곳에서만 수정한다.

### 2.3. 데이터 모델 (Data Model)

금액은 **예외 없이** `amount_minor BIGINT`(최소 화폐 단위 정수)이며 부호는 컬럼이 아니라 `direction`이 담당한다.

1. **account**: `id(UUID)`, `code(TEXT UNIQUE)`, `name(TEXT)`, `type(ENUM: asset|liability|equity|income|expense)`, `currency(CHAR(3))`, `parent_id(UUID NULL)`, `is_closed(BOOL)`
2. **txn**: `id(UUID)`, `occurred_on(DATE)`, `memo(TEXT)`, `source_hash(BYTEA UNIQUE)`, `batch_id(UUID NULL)`, `status(ENUM: draft|classified|posted|settled)`, `posted_at(TIMESTAMPTZ)`
3. **entry**: `id(BIGSERIAL)`, `txn_id(UUID FK)`, `account_id(UUID FK)`, `direction(ENUM: debit|credit)`, `amount_minor(BIGINT, CHECK > 0)`, `currency(CHAR(3))`
4. **fx_rate**: `base`, `quote`, `as_of(DATE)`, `rate_num(BIGINT)`, `rate_den(BIGINT)` — 환율은 **유리수 쌍**으로 보관한다. 실수 컬럼을 두지 않는다.
5. **category_rule**: `id`, `priority(INT)`, `matcher(JSONB)`, `account_id`, `source(ENUM: manual|prolog|lua|haskell)`
6. **budget**: `id`, `account_id`, `period_kind`, `limit_minor(BIGINT)`, `dsl_src(TEXT)` — `dsl_src`는 Haskell 규칙 DSL 원문
7. **automation_script**: `id`, `name`, `lua_src(TEXT)`, `enabled(BOOL)`, `timeout_ms(INT)`
8. **ingest_batch**: `id`, `filename`, `row_count`, `state(ENUM)`, `started_at`, `finished_at`
9. **settlement_run**: `id`, `period(DATERANGE)`, `cobol_exit(INT)`, `report_path(TEXT)`, `checksum(BYTEA)`
10. **transfer_link**: `txn_a(UUID)`, `txn_b(UUID)`, `confidence(SMALLINT)`, `matched_by(TEXT)` — Prolog 산출
11. **report_artifact**: `id`, `kind(ENUM: stl|anomaly|montecarlo|settlement)`, `period`, `path`, `generated_by(ENUM: r|julia|cobol)`

**불변식 (Invariants)**

| ID | 내용 | 강제 위치 |
|---|---|---|
| INV-1 | `posted` 이상 상태의 모든 txn에 대해 통화별 `sum(debit) = sum(credit)` | PLpgSQL `AFTER` 트리거 (deferrable) |
| INV-2 | `entry.amount_minor > 0` | `CHECK` 제약 |
| INV-3 | `settled` 기간의 txn·entry는 UPDATE/DELETE 불가 | PLpgSQL 트리거 |
| INV-4 | 금액이 JS `Number`·`float`·`double`을 경유하는 경로 0개 | 정적 검사 + 코드 리뷰 게이트 |
| INV-5 | 한 txn은 최대 1개의 `transfer_link`에만 속함 | 부분 유니크 인덱스 |

### 2.4. 출력 및 성능 기준 (Output & Performance)

- **결과물 형식**: JSON API(`application/json`), COBOL 고정폭 마감 리포트(`text/plain`), R 산출 SVG 차트, Julia 산출 시나리오 JSON, WebSocket 이벤트 프레임.
- **품질 기준 (QA Standards)**:

| 항목 | 기준 |
|---|---|
| 초기 로딩(LCP) | 2.5초 이내 |
| 50MB CSV WASM 파싱 | 3초 이내, 메인 스레드 블로킹 0ms |
| 거래 100,000행 가상 스크롤 | 60fps 유지 |
| COBOL 마감 배치 10,000 txn | 2초 이내 |
| Prolog 분류 1,000건 | 1초 이내 |
| DB `NOTIFY` → 브라우저 수신 | p95 300ms 이내 |
| 브라우저 호환성 | Chrome / Edge / Safari 최신 2개 버전 (WASM + Web Worker 필수) |
| 접근성 | WCAG 2.1 AA, 키보드만으로 전체 원장 조작 가능 |

---

## 3. 기술 스택 및 라이브러리 (Tech Stack)

### 3.1. Core

- **Frontend**: React 18 + Vite 6, Zustand, JavaScript(ESM) + JSDoc 타입 주석
- **Backend**: Node 22 + Fastify 5 (JavaScript ESM)
- **Database**: PostgreSQL 16 (PLpgSQL)
- **타입 전략**: TypeScript를 도입하지 않는다. 계약 타입은 `contracts/*.schema.json` → JSDoc `@typedef` 생성으로 확보하며, 이는 언어 중립 계약을 유지하기 위한 결정이다.

### 3.2. Libraries & Tools

1. **ajv** (필수) — 버전 8.x / 용도: 클라이언트·서버 공용 JSON Schema 검증 / 설정: `strict: true`, `allErrors: false`
2. **wasm-bindgen + wasm-pack** (필수) — 용도: Rust 인제스트 모듈의 브라우저 바인딩 / 설정: `--target web`, 산출물은 `linguist-generated`
3. **gopher-lua** (필수) — 용도: Go 워커 내 Lua 샌드박스 임베딩 / 설정: 표준 라이브러리 중 `base/string/math/table`만 등록
4. **megaparsec** (필수) — 용도: 예산 규칙 DSL 파서 콤비네이터
5. **SWI-Prolog `library(http/thread_httpd)`** (필수) — 용도: 분류·매칭 상주 HTTP 서비스
6. **GnuCOBOL 3.x** (필수) — 용도: 마감 정산 배치 컴파일 / 설정: `-std=cobol2014 -O2`, 고정 형식 소스
7. **R: stats(STL), ggplot2, jsonlite** (필수) — 용도: 계절성 분해·이상치 탐지·SVG 리포트
8. **Julia: Distributions.jl, StatsBase.jl, JSON3.jl** (필수) — 용도: 몬테카를로·상환 최적화
9. **Phoenix (Elixir)** (필수) — 용도: WebSocket 채널, `LISTEN/NOTIFY` 브리지
10. **argon2 / age (Rust)** (필수) — 용도: 패스프레이즈 유래 키 파생 및 페이로드 암호화

### 3.3. 폴리글랏 런타임 배치 (Polyglot Runtime Map)

| 언어 | 프로세스 | 통신 | 담당 |
|---|---|---|---|
| JavaScript | `web` (상시) | HTTP | Fastify 서버, React UI, 세션·권한, 어댑터 |
| Go | `worker` (상시) | Unix socket + JSON | 잡 큐, 스케줄러, 환율 폴링, subprocess 오케스트레이션 |
| Lua | `worker` 내부 | in-process | 사용자 정의 자동화 규칙 샌드박스 |
| Prolog | `prolog` (상시) | HTTP + JSON | 카테고리 추론, 이체 페어 매칭, 정기결제 탐지 |
| Elixir | `realtime` (상시) | WebSocket / PG NOTIFY | 실시간 푸시, 예산 임계 감시, 알림 감독 트리 |
| PLpgSQL | `db` | SQL | 불변식 트리거, 잔액 롤업, 집계 함수, RLS, NOTIFY 발행 |
| Rust | 브라우저 WASM | postMessage | 명세서 파싱·중복제거·암호화 |
| COBOL | 배치 | 고정폭 stdin/stdout | 월말 마감 정산, 상각, 은행가 반올림 |
| Haskell | 배치 | JSONL stdin/stdout | 규칙 DSL 파싱·타입검사·평가 |
| R | 배치 | JSONL + SVG 파일 | 통계 분석, 이상치, 리포트 |
| Julia | 배치 | JSONL stdin/stdout | 몬테카를로, 상환 순서 최적화 |

---

## 4. 아키텍처 및 로직 (Architecture & Logic)

### 4.1. 상태 관리 전략 (State Management)

- **Scope**:
  - **Global**: 조회 기간(period), 인증 세션, 실시간 연결 상태, 테마 — Zustand
  - **Domain slice**: 원장 행 윈도우, 선택 집합, 인제스트 진행률 — Zustand 슬라이스 분리
  - **Local**: 폼 입력, 모달 개폐 — `useState`
- **Tool**: Zustand Store + Custom Hooks. 실시간 이벤트는 store에 직접 병합하며 컴포넌트가 채널을 직접 구독하지 않는다.

```javascript
// src/store/ledgerStore.js
import { create } from 'zustand';

/** @typedef {import('../types').LedgerRow} LedgerRow */

export const useLedgerStore = create((set, get) => ({
  period: currentPeriod(),
  /** @type {LedgerRow[]} */ rows: [],
  totalCount: 0,
  selection: new Set(),
  isSettled: false,

  // Elixir 채널 이벤트를 단일 진입점에서 병합한다.
  applyRealtime(evt) {
    if (evt.type === 'balance_changed') {
      set((s) => ({ rows: mergeRow(s.rows, evt.row) }));
    } else if (evt.type === 'settlement_done') {
      set({ isSettled: true });
    }
  },
}));
```

### 4.2. 주요 동작 파이프라인 (Main Workflow)

1. **초기화 (Init)**: 세션 확인 → 계정 트리·현재 기간 잔액 로드 → Elixir 채널 접속 → 마감 상태 조회.
2. **인제스트 (Ingest)**: 파일 드롭 → Worker에서 WASM 파싱·정규화·BLAKE3 지문 산출·중복 제거 → 암호화 후 업로드 → Go 워커가 draft txn 생성 → Prolog 분류 → Lua 규칙 적용 → PLpgSQL 트리거 검증 후 `posted` → `NOTIFY` → Elixir → UI 갱신.
3. **마감 (Settlement)**: 사용자가 기간 마감 실행 → Go 워커가 고정폭 입력 생성 → COBOL 배치 실행 → 결과 대조(§4.3 정합성) → `settled` 전이 및 해당 기간 잠금 → 리포트 산출물 등록.
4. **분석 (Analysis)**: 야간 스케줄 → R(STL·이상치) 및 Julia(시뮬레이션) 실행 → 산출물 저장 → 다음 접속 시 캐시 서빙.
5. **렌더링/갱신 (Update)**: 분류·태그 변경은 Optimistic Update. 마감된 기간은 읽기 전용으로 렌더링한다.

### 4.3. 핵심 알고리즘 (Core Algorithms)

- **중복 제거 지문 (Rust)**: `source_hash = BLAKE3(normalize(date) ‖ amount_minor ‖ normalize(merchant))`. `normalize`는 NFKC 정규화 → 공백 축약 → 카드사 접두어 제거 → 대소문자 폴딩. 동일 명세서 재업로드 시 신규 행 0건이어야 한다.

- **이체 페어 매칭 (Prolog)**: 절대금액 완전 일치, 부호 반대, 서로 다른 계좌, 일자 차 3일 이내, 양측 모두 미매칭. **근사 금액 매칭은 허용하지 않는다** — 거짓양성 1건이 원장 전체의 신뢰를 무너뜨리기 때문이다.

```prolog
transfer_pair(A, B) :-
    txn_net(A, AccA, Amt, DateA),
    txn_net(B, AccB, NegAmt, DateB),
    A @< B, AccA \== AccB,
    NegAmt =:= -Amt,
    days_between(DateA, DateB, D), abs(D) =< 3,
    \+ linked(A, _), \+ linked(_, B).
```

- **정기 결제 탐지 (Prolog)**: 정규화 상점명이 동일한 최근 6건에 대해 금액 상대편차 ≤ 5%, 결제 간격 표준편차 ≤ 3일이면 주기 결제로 판정하고 주기를 추정한다.

- **은행가 반올림 및 상각 (COBOL)**: `COMPUTE ... ROUNDED MODE IS NEAREST-EVEN`. 원리금 균등 상환은 `A = P·i / (1 - (1+i)^-n)` 로 회차 납입액을 구한 뒤, 각 회차마다 이자 = 잔액·i(반올림), 원금 = A − 이자로 분해하고 **마지막 회차에서 잔여를 흡수**한다. 전 과정 `PIC S9(13)V99 COMP-3`.

- **규칙 DSL (Haskell)**: Lexer → megaparsec Parser → 타입 검사(계정 존재·통화 일치·기간 단위 정합) → Core IR → 평가기. 오류는 소스 위치와 함께 구조화 반환한다.

```
budget "식비" per month <= 400000 KRW
  where account in (5210, 5211)
  alert when spent > 0.8 * limit

rule tag "구독"
  when merchant matches /넷플릭스|스포티파이/ and recurring
```

- **이상치 탐지 (R)**: 일별 지출 시계열 → `stl(s.window = "periodic")` → 잔차 → MAD 기반 robust z-score > 3.5 를 이상치로 판정. 월말 예산 초과 확률은 잔여일 지출 분포 부트스트랩 10,000회로 추정.

- **현금흐름 시뮬레이션 (Julia)**: 최근 12개월 카테고리별 지출의 커널 밀도 추정 → 10,000 경로 몬테카를로 → 비상금 소진 확률 및 분위수 산출. 부채 상환 순서 최적화는 (잔액, 이율, 최소상환액) 상태공간 동적계획법.

- **Lua 샌드박스**: `io / os / debug / package / load / dofile` 제거. 명령 수 훅으로 100ms 타임아웃 강제. 노출 API는 `txn`(읽기 전용 테이블), `tag()`, `notify()`, `set_account()` 4개로 한정.

- **정합성 대조 (Parity)**: COBOL 마감 결과는 `decimal.js` 기반 JavaScript 참조 구현과 동일 입력으로 대조한다. **차이 1원이라도 발생하면 마감을 커밋하지 않는다.** 이 게이트가 프로젝트 전체에서 가장 중요한 검증 지점이다.

---

## 5. UI 구현 가이드 (Implementation Guide)

### 5.1. 디자인 토큰 (Design Tokens)

디자인 백서 §5의 값과 1:1 대응한다. 두 문서가 불일치하면 디자인 백서가 우선한다.

```css
:root {
  --bg: #F6F7F8;
  --surface: #FFFFFF;
  --border: #E1E4E8;
  --border-strong: #C9CED4;
  --text: #14181C;
  --text-muted: #626C76;

  --accent: #14506B;
  --positive: #0F5C3F;
  --negative: #8C2F26;
  --warning: #8A5A00;

  --font-sans: 'Pretendard Variable', Pretendard, system-ui, sans-serif;
  --font-mono: 'JetBrains Mono', ui-monospace, monospace;

  --radius: 3px;
  --row-h: 34px;
}
```

- **Typography**: 본문 15px / `line-height: 1.6` / weight 400·500·600 3단계만. 금액·계정코드·기간 라벨은 `--font-mono` + `font-variant-numeric: tabular-nums`.
- **Breakpoints**: Mobile(`< 768px`), Tablet(`768px`), Desktop(`1024px`), Wide(`1440px`)
- **Spacing scale**: `4 / 8 / 12 / 16 / 24 / 32 / 48 / 64` 이외 임의값 금지.

### 5.2. 공통 컴포넌트 (Shared Components)

- **`<Money>`**: props `minor(bigint|string)`, `currency`, `direction`, `showSign`. 내부에서 문자열 연산만 사용하며 `Number` 변환을 하지 않는다. 색상은 direction으로만 결정하고, **색 외에 부호와 정렬을 병행 표기**한다.
- **`<LedgerTable>`**: 가상 스크롤(윈도우 200행). props `rows`, `settled`, `onSelect`. `settled=true`면 편집 컨트롤을 렌더링하지 않는다(비활성화가 아니라 미렌더링).
- **`<Button>`**: variant `primary | secondary | ghost`, size `sm | md`, `disabled`. 그림자 없음, 호버는 배경 1단계 변화만.
- **`<Modal>`**: Portal + `<dialog>` 기반. z-index 레이어 `1000`(모달) / `1100`(토스트). 포커스 트랩과 `Esc` 닫기 필수.
- **`<AccountPicker>`**: 계정 트리 검색. 코드·이름 동시 검색, 키보드 상하 이동 지원.
- **`<FixedWidthReport>`**: COBOL 산출 고정폭 리포트 뷰어. `--font-mono` 고정, 줄바꿈 금지, 가로 스크롤 허용.

---

## 6. 파일 구조 (File Structure)

```text
just-ledger/
├── apps/
│   └── web/                      # JavaScript (메인)
│       ├── server/               # Fastify
│       │   ├── routes/
│       │   ├── adapters/         # worker/prolog/realtime 호출 어댑터
│       │   └── schema/           # contracts 로더
│       └── client/               # React 18 + Vite
│           ├── components/
│           │   ├── common/
│           │   ├── layout/
│           │   └── ledger/
│           ├── hooks/
│           ├── pages/
│           ├── store/
│           └── styles/
├── services/
│   ├── worker/                   # Go
│   │   ├── queue/
│   │   ├── schedule/
│   │   ├── runner/               # subprocess 오케스트레이션
│   │   └── sandbox/              # Lua 런타임 바인딩 + *.lua
│   ├── prolog/                   # Prolog (*.prolog)
│   └── realtime/                 # Elixir (Phoenix)
├── modules/
│   ├── statement-wasm/           # Rust
│   ├── rules-dsl/                # Haskell
│   ├── settlement/               # COBOL (*.cbl, *.cpy)
│   ├── analytics/                # R
│   └── simulation/               # Julia
├── db/                           # PLpgSQL (*.pgsql)
│   ├── migrations/
│   ├── functions/
│   └── triggers/
├── contracts/                    # JSON Schema (집계 제외)
├── fixtures/                     # 골든 입출력 (집계 제외)
├── infra/                        # Dockerfile, Nix, HCL, Shell (집계 제외)
├── docs/                         # 백서·하네스 (Linguist 자동 제외)
├── Makefile
├── PROGRESS.md
├── CLAUDE.md
└── .gitattributes
```

`deps/`, `_build/`, `target/`, `dist-newstyle/`, `node_modules/` 는 반드시 `.gitignore` 한다. 커밋되면 Linguist 통계가 오염된다.

---

## 7. 개발 시 주의사항 (Implementation Notes)

1. **보안 (Security)**
   - 암호화 키는 사용자 패스프레이즈에서 Argon2id로 파생하며 서버에 저장하지 않는다. 서버는 페이로드를 복호화할 수 없다.
   - subprocess는 셸을 경유하지 않고 argv 배열로 직접 실행한다. 파일명·메모 등 사용자 입력이 인자로 들어가는 경로를 만들지 않는다.
   - COBOL 고정폭 입력은 레코드 길이·수치 범위를 Go 측에서 검증한 뒤 전달한다. 길이 초과는 조용히 잘리므로 반드시 사전 차단한다.
   - Lua 스크립트는 §4.3 화이트리스트 외 전역에 접근할 수 없어야 하며, 타임아웃 초과 시 강제 중단한다.
   - PostgreSQL RLS로 계정 소유자 격리. 서비스 계정은 `BYPASSRLS` 를 갖지 않는다.

2. **성능 최적화 (Optimization)**
   - WASM은 반드시 Web Worker에서 실행한다. 메인 스레드 파싱 금지.
   - 원장 표는 가상 스크롤 필수. 100,000행 DOM 렌더링 금지.
   - SWI-Prolog·Julia는 상주 또는 워커 기동 시 warm-up 한다. 요청마다 프로세스를 띄우면 기동 비용이 처리 시간을 압도한다.
   - R·Julia 산출물은 파일로 캐시하고, 입력 해시가 동일하면 재실행하지 않는다.

3. **이슈 대응 (Known Issues)**
   - GnuCOBOL `COMP-3` 부호 니블은 플랫폼·컴파일 옵션에 따라 표현이 달라진다. 컨테이너 이미지와 컴파일 플래그를 고정하고, 골든 픽스처로 바이트 단위 회귀를 잡는다.
   - SWI-Prolog 상주 프로세스는 장시간 구동 시 메모리가 누적된다. 일 1회 재기동 스케줄을 둔다.
   - Julia는 첫 호출에서 JIT 컴파일 지연이 크다. 워커 기동 시 더미 호출로 예열한다.
   - Elixir와 Fastify가 각각 커넥션 풀을 가지므로 PostgreSQL `max_connections` 를 초과하지 않도록 풀 크기를 명시 설정한다.
   - Safari에서 `BigInt` 직렬화는 `JSON.stringify` 로 처리되지 않는다. 금액은 API 경계에서 문자열로 주고받는다.

---

## 8. 폴리글랏 언어 구성 관리 (Language Composition)

### 8.1. 목표 비율

| 언어 | 목표 | 하한 |
|---|---|---|
| JavaScript (메인) | 28% | — (상한 35%) |
| Go | 9% | 5% |
| Rust | 9% | 5% |
| Elixir | 8% | 5% |
| Haskell | 8% | 5% |
| COBOL | 8% | 5% |
| PLpgSQL | 7% | 5% |
| R | 6% | 5% |
| Prolog | 6% | 5% |
| Julia | 6% | 5% |
| Lua | 5% | 5% |

전체 계측 바이트 목표 약 500KB, 총 15,000줄 내외.

### 8.2. `.gitattributes`

```gitattributes
# 언어 오탐 방지
db/**/*.pgsql              linguist-language=PLpgSQL
services/prolog/**         linguist-language=Prolog

# 5% 미달 언어는 집계에서 제외
infra/**                   linguist-vendored=true
contracts/**               linguist-vendored=true
fixtures/**                linguist-vendored=true
Makefile                   linguist-vendored=true
**/Dockerfile              linguist-vendored=true
*.sh                       linguist-vendored=true
*.css                      linguist-detectable=false
*.html                     linguist-detectable=false

# 생성물 제외
modules/statement-wasm/pkg/**  linguist-generated=true
```

Prolog 소스는 `.pl` 대신 **`.prolog`** 확장자를 사용한다(`.pl`은 Perl과 오탐). SQL 소스는 **`.pgsql`** 확장자 + `linguist-language` 명시로 고정한다.

### 8.3. 계측 및 게이트

```bash
gem install github-linguist
github-linguist --breakdown        # 커밋된 파일만 집계됨
```

CI에서 `github-linguist --json` 을 파싱하여 다음 3가지를 검사하고, 위반 시 빌드를 실패시킨다.

1. 메인(JavaScript) 제외 모든 계측 언어가 5.0% 이상
2. 계측 대상 11개 외의 언어가 통계에 등장하지 않음
3. 메인이 35%를 초과하지 않음

검사 스크립트는 Lua로 작성한다. Lua는 목표 비율이 가장 낮아 바이트 여유가 필요하며, 이 스크립트는 매 푸시마다 실제로 실행되는 코드다.

**비율 조정은 기능 추가 또는 골든 테스트 추가로만 한다.** 주석 패딩·무의미한 코드 생성은 금지한다. 이를 하는 순간 프로젝트의 전제가 무너진다.
