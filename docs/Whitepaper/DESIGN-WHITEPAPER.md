# just-ledger 디자인 백서 (Design Whitepaper)

**버전**: 1.0
**작성일**: 2026년 07월 20일
**작성자**: Bryan / JTech-CO
**참고 문서**: 폴리글랏 기획서 v1.0, 기술 백서 v1.0 §5, `docs/HARNESS.md`

---

## 1. 프로젝트 개요 (Project Overview)

### 1.1. 프로젝트 명

**just-ledger UI/UX Design**

### 1.2. 목적 (Purpose)

- 복식부기라는 **300년 된 표기법**을 학습 부담 없이 쓸 수 있는 화면으로 옮긴다. 차변/대변, 계정 코드, 마감 같은 회계 고유 개념을 감추지 않고, 대신 시각적으로 읽히게 만든다.
- 다열 숫자 표를 하루에도 여러 번 훑는 사용자에게 **밀도와 정확한 정렬**을 제공한다. 스크롤 없이 한 화면에서 한 달을 본다.
- 겉모습은 어디에나 있는 가계부처럼 보여야 한다. **화려한 UI는 이 프로젝트의 서사를 해친다.**

### 1.3. 핵심 차별점 (Key Differentiators)

1. **마감선 (Closing Rule)** — 시그니처. 회계 장부에서 합계 아래에 긋는 이중선을 그대로 UI 문법으로 사용한다. 기간이 마감되면 마지막 행 아래에 이중선이 그어지고 그 위는 편집 컨트롤이 **사라진다**. "잠김"을 회색 처리나 자물쇠 아이콘이 아니라 장부의 관습으로 표현한다.
2. **원장 정렬 (Ledger Alignment)** — 금액은 예외 없이 우측 정렬 + `tabular-nums` + mono. 자릿수가 세로로 맞아떨어지는 것 자체가 이 화면의 정보 전달 방식이다.
3. **고정폭의 목소리 (Fixed-width Voice)** — 계정 코드·기간 라벨·합계·COBOL 산출 리포트가 모두 같은 mono 서체를 쓴다. mono가 단순 숫자용 폰트가 아니라 "장부가 말하는 방식"으로 일관되게 등장한다.

> 이 디자인이 피하는 것: 따뜻한 크림색 배경 + 세리프 헤드라인 + 테라코타 액센트 조합, 카드마다 걸린 그림자, 그라데이션, 장식용 아이콘. 참조 멘탈 모델은 **Stripe Dashboard**와 **Linear**, 그리고 실제 은행 거래명세서 인쇄물이다.

---

## 2. 상세 기능 요구사항 (Detailed Requirements)

### 2.1. 레이아웃 및 인터페이스 (Layout & Interface)

- **뷰 모드 (View Mode)**: Desktop First / 3-Column Shell
  - *데스크톱(≥1024px)*: 좌측 계정 트리 사이드바 `240px` 고정 + 중앙 원장 `fluid` + 우측 상세 패널 `320px`(선택 시에만 등장). 최대 컨테이너 `1440px` 중앙 정렬.
  - *태블릿(768~1023px)*: 사이드바 접힘(오버레이), 상세 패널은 하단 시트.
  - *모바일(<768px)*: 표를 카드 리스트로 전환. 카드당 표시 항목은 일자·상대처·금액·계정 4개로 제한.

```text
┌──────────────────────────────────────────────────────────────┐
│ Topbar   just-ledger   [2026-07 ▾]        검색     사용자    │
├────────────┬─────────────────────────────────┬───────────────┤
│ 계정 트리   │  원장 (LedgerTable)             │ 상세 패널     │
│ 1010 현금  │  일자 │ 적요 │ 계정 │ 차변 │ 대변│ (행 선택 시) │
│ 1020 예금  │  ──────────────────────────────  │               │
│ 5210 식비  │  07-01 …                        │  분류 이력    │
│ 5310 교통  │  07-02 …                        │  Prolog 근거  │
│            │  ══════════  ← 마감선(시그니처) │  Lua 규칙     │
│ [잔액 요약]│  합계    1,240,000   1,240,000  │               │
└────────────┴─────────────────────────────────┴───────────────┘
```

- **테마 정책 (Theme Policy)**: Light 기본 + `prefers-color-scheme` 자동 + 수동 토글(localStorage 저장).
  - *배경색*: Light `#F6F7F8` / Dark `#14181C`
  - *기본 텍스트 색*: Light `#14181C` / Dark `#E4E7EA`
  - 다크 모드는 순수 검정을 쓰지 않는다. 장시간 표를 보는 화면에서 순수 검정 배경 위 고채도 텍스트는 눈이 빨리 피로해진다.

### 2.2. 사용자 상호작용 (Interaction Logic)

- **주요 액션 (Actions)**:
  - **Hover**: 표 행은 배경 1단계 변화(`--surface` → `--row-hover`)만. `transform`·`scale`·그림자 변화 없음. 표에서 행이 움직이면 자릿수 정렬이 깨져 보인다.
  - **Selection**: 선택 행은 좌측 2px `--accent` 인디케이터 + 배경 변화. 테두리 전체를 두르지 않는다(행 높이가 1px 변하면 표 전체가 흔들린다).
  - **Navigation**: 좌측 사이드바 계정 트리. GNB 없음. 상단은 기간 선택기·검색·사용자 메뉴만 둔다.
- **입력 방식 (Input)**:
  - 거래 추가·수정은 **인라인 에디팅**. 모달은 파일 인제스트와 마감 확인처럼 되돌릴 수 없는 동작에만 쓴다.
  - 파일 인제스트는 전역 드롭존. 드래그 진입 시 화면 테두리에 2px `--accent` 인셋만 표시한다(오버레이로 화면을 덮지 않는다).
  - 계정 선택은 코드·이름 동시 검색 콤보박스. 숫자만 입력해도 코드로 매칭된다.
- **키보드**: `j/k` 행 이동, `Enter` 상세, `e` 인라인 편집, `/` 검색, `Esc` 닫기. 마우스 없이 원장 전체를 조작할 수 있어야 한다.

### 2.3. 데이터 구조 및 모듈 (Component Structure)

1. **헤더 (Topbar)**: 높이 `48px`. 로고(텍스트) 좌측, 기간 선택기 중앙 좌측, 검색·테마 토글·사용자 우측. 하단 `1px --border`. sticky, 그림자 없음.
2. **사이드바 (Account Tree)**: 폭 `240px`, 배경 `--bg`(본문보다 한 단계 어둡게), 계정 코드는 mono `--text-muted`, 이름은 sans. 계정 유형별 그룹 헤더는 12px / weight 600 / `letter-spacing: 0.04em` 대문자 라벨.
3. **콘텐츠 (LedgerTable)**: 배경 `--surface`, 행 높이 `34px`, 셀 좌우 패딩 `12px`. 행 구분선은 `1px --border` 대신 **하단 hairline만**. 헤더 행은 sticky, 12px / weight 600 / `--text-muted`.
4. **상세 패널 (Inspector)**: 폭 `320px`, 좌측 `1px --border`. 분류 근거(Prolog 규칙명), 적용된 Lua 스크립트, 원본 명세서 행을 순서대로 표시한다.
5. **푸터**: 없음. 대신 원장 하단에 **합계 행**이 sticky로 고정된다. 합계 행이 이 화면의 푸터다.

### 2.4. 출력 및 결과물 (Output)

- **결과물 형식**: React Component (JSX) + CSS Modules, 디자인 토큰은 `styles/tokens.css` 단일 파일.
- **품질 기준 (QA Standards)**:
  - WCAG 2.1 AA. 본문 대비 4.5:1 이상, 비활성 텍스트도 3:1 이상.
  - 차변/대변, 수입/지출을 **색만으로 구분하지 않는다**. 부호·열 위치·정렬을 병행한다(색각 이상 대응).
  - 가로 스크롤 발생 금지(단, 고정폭 리포트 뷰어는 예외로 허용).
  - `prefers-reduced-motion: reduce` 존중 — 모든 트랜지션 0ms 전환.
  - 키보드 포커스 링은 항상 가시적(`2px --accent`, `outline-offset: 1px`).

---

## 3. 기술 스택 및 라이브러리 (Tech Stack)

### 3.1. Core

- **Frontend Framework**: React 18 + Vite 6 (JavaScript ESM + JSDoc)
- **Styling Engine**: CSS Modules + CSS Variables. Tailwind·CSS-in-JS를 쓰지 않는다. 토큰이 11개 언어 산출물(COBOL 리포트 뷰어, R SVG 차트)에도 적용되어야 하므로, 순수 CSS 변수가 가장 이식성이 높다.

### 3.2. Libraries & Tools

1. **@tanstack/react-virtual**
   - 용도: 원장 표 가상 스크롤
   - 설정: `estimateSize: 34`, `overscan: 12`
2. **lucide-react**
   - 용도: 아이콘 (SVG). 이모지 아이콘 사용 금지.
   - 설정: `size: 16`, `strokeWidth: 1.75` 고정. 장식 목적 아이콘은 두지 않고 기능 있는 컨트롤에만 사용한다.
3. **Pretendard Variable / JetBrains Mono**
   - 용도: 본문 / 숫자·코드·리포트
   - 설정: 로컬 서브셋 호스팅(`font-display: swap`). 외부 폰트 CDN 사용 금지.

---

## 4. 아키텍처 및 로직 (Architecture & Logic)

### 4.1. 시각적 계층 구조 (Visual Hierarchy)

타입 스케일: `12 / 13 / 15 / 17 / 20 / 26`. weight는 400 / 500 / 600 세 단계만 사용한다.

- **Level 1 (Page Title)**: 20px / 600 / `--text` / `line-height: 1.3`
- **Level 2 (Section Title)**: 17px / 600 / `--text`
- **Level 3 (Body Text)**: 15px / 400 / `--text` / `line-height: 1.6`
- **Level 4 (Table Cell)**: 15px / 400. 숫자 셀은 `--font-mono` / `tabular-nums` / 우측 정렬
- **Level 5 (Meta/Caption/Column Label)**: 12px / 500 / `--text-muted` / `letter-spacing: 0.04em`

```css
.amount {
  font-family: var(--font-mono);
  font-variant-numeric: tabular-nums;
  text-align: right;
  font-size: 15px;
}

/* 시그니처: 마감선 */
.ledger-row--period-end {
  border-bottom: 3px double var(--text);
}
```

### 4.2. 반응형 로직 (Responsive Logic)

1. **Desktop (≥1024px, 기본)**: 3열 셸. 표 전체 컬럼(일자·적요·상대처·계정·차변·대변·잔액) 노출.
2. **Transition Point 1 (1024px)**: 상세 패널이 오버레이로 전환. 사이드바 유지.
3. **Transition Point 2 (768px)**: 사이드바 접힘. 표에서 `상대처`·`잔액` 컬럼 숨김.
4. **Mobile (<768px)**: 표 → 카드 리스트. 카드는 1행에 일자·금액, 2행에 적요·계정. 합계는 화면 하단 고정 바.

컬럼을 축소할 때 **금액 컬럼은 절대 숨기거나 축약하지 않는다.** 금액이 잘려 보이는 가계부는 존재 이유가 없다.

### 4.3. 핵심 컴포넌트 로직 (Core Components)

- **`<LedgerTable>`**: 가상 스크롤 기반 원장 표.
  - 행 높이 고정 `34px`. 내용에 따라 높이가 변하면 스크롤 위치 계산이 흔들린다.
  - `settled` 기간의 행은 편집 컨트롤을 **렌더링하지 않는다**(비활성화 스타일을 입히는 게 아니라 DOM에서 제외). 회색 처리된 버튼은 "누를 수 있을 것 같은데 안 되는" 인지 부하를 만든다.
  - 기간 마지막 행 하단에 `3px double` 마감선. 마감 전에는 `1px solid --border-strong` 점선 예고선을 둔다.

- **`<Money>`**: 금액 표시 원자 컴포넌트.
  - 색은 `direction`으로만 결정: 수입/차변 증가 `--positive`, 지출/대변 증가 `--negative`.
  - **색과 함께 부호를 항상 표기**한다. 색각 이상 사용자와 흑백 인쇄에서 동일하게 읽혀야 한다.
  - 통화 기호는 `--text-muted`, 금액 본체는 `--text` 명도로 분리해 숫자가 먼저 읽히게 한다.

- **`<BalanceSummary>`**: 사이드바 하단 잔액 요약.
  - 카드 3개를 나란히 두는 패턴을 쓰지 않는다. 계정 유형별 1행 리스트 + 우측 정렬 금액.
  - 잔액 변화는 Elixir 채널 수신 시 `120ms` 배경 하이라이트 1회. 카운트업 애니메이션 금지.

- **`<IngestProgress>`**: 인제스트 진행 표시.
  - WASM 파싱(로컬) 단계와 서버 처리 단계를 **분리해 표시**한다. 사용자가 "내 파일이 아직 내 컴퓨터에 있다"는 것을 알 수 있어야 한다. 이것이 이 제품의 핵심 약속이다.
  - 진행 바는 1px 두께 선형. shimmer·스켈레톤 금지.

- **`<FixedWidthReport>`**: COBOL 마감 리포트 뷰어.
  - `--font-mono`, `white-space: pre`, 줄바꿈 금지, 가로 스크롤 허용.
  - 배경은 `--surface`, 좌측에 3px `--accent` 인셋으로 "기계가 생성한 산출물"임을 표시한다.

- **`<ReportChart>`**: R 산출 SVG 리포트.
  - ggplot2 테마를 디자인 토큰에 맞춰 커스터마이즈한다(배경 투명, 격자선 `--border`, 텍스트 `--text-muted`, 15px 기준). R이 생성한 차트가 UI와 이질적으로 보이면 안 된다.
  - 다크 모드에서는 SVG를 필터로 반전시키지 않고, R 측에서 다크 테마 산출물을 별도로 생성한다.

---

## 5. UI/UX 디자인 가이드 (Design System)

### 5.1. 색상 팔레트 (Color Palette)

중성색은 **cool gray 1계열**, accent는 **1색**으로 한정한다. 그 외 3색은 상태 표시 전용이며, 없으면 정보 전달이 깨지기 때문에 존재한다.

**Light**

| 역할 | 값 | 변수명 | 용도 |
|---|---|---|---|
| Background | `#F6F7F8` | `--bg` | 페이지·사이드바 배경 |
| Surface | `#FFFFFF` | `--surface` | 표·패널 표면 |
| Row hover | `#F1F3F5` | `--row-hover` | 표 행 호버 |
| Border | `#E1E4E8` | `--border` | 기본 구분선 |
| Border strong | `#C9CED4` | `--border-strong` | 합계선·구획 |
| Text | `#14181C` | `--text` | 본문 |
| Text muted | `#626C76` | `--text-muted` | 라벨·보조 |
| Accent | `#14506B` | `--accent` | CTA, 링크, 포커스 링, 선택 인디케이터 |
| Positive | `#0F5C3F` | `--positive` | 수입 / 차변 증가 |
| Negative | `#8C2F26` | `--negative` | 지출 / 대변 증가 |
| Warning | `#8A5A00` | `--warning` | 예산 초과, 미분류 거래 |

**Dark**

| 변수명 | 값 |
|---|---|
| `--bg` | `#14181C` |
| `--surface` | `#1B2026` |
| `--row-hover` | `#232A31` |
| `--border` | `#2C333A` |
| `--border-strong` | `#3D454D` |
| `--text` | `#E4E7EA` |
| `--text-muted` | `#98A2AC` |
| `--accent` | `#57A8C4` |
| `--positive` | `#4FA37C` |
| `--negative` | `#D97A6E` |
| `--warning` | `#C79A3E` |

**색 사용 규칙**: 새 색을 추가하기 전에 "이 색이 없으면 정보 전달이 깨지는가"를 묻는다. 답이 "아니오"면 추가하지 않는다. 그라데이션은 사용하지 않는다.

### 5.2. 타이포그래피 (Typography)

- **Font Family**:
  - Sans: `'Pretendard Variable', Pretendard, system-ui, sans-serif`
  - Mono: `'JetBrains Mono', ui-monospace, 'SFMono-Regular', monospace`
  - **2개를 초과하지 않는다.**
- **Font Weight**: 400(본문) / 500(라벨·강조) / 600(제목·합계). 300 이하와 700 이상은 사용하지 않는다.
- **Mono 적용 대상**: 금액, 계정 코드, 기간 라벨(`2026-07`), 합계, 해시·ID, COBOL 고정폭 리포트, DSL 편집기. 그 외에는 사용하지 않는다.
- **숫자 설정**: 표 내 모든 숫자에 `font-variant-numeric: tabular-nums`. 자릿수 정렬이 이 제품의 가독성 그 자체다.
- **한글 처리**: `word-break: keep-all`, `line-break: strict`. 적요·계정명이 어절 중간에서 끊기지 않게 한다.

### 5.3. 간격 · 곡률 · 고도 · 모션

- **Spacing scale**: `4 / 8 / 12 / 16 / 24 / 32 / 48 / 64`. 이외 임의값 금지.
- **Radius**: `3px` (버튼·입력·카드), 표 셀은 `0`. 큰 곡률을 쓰지 않는다.
- **Elevation**: 카드에 그림자를 쓰지 않는다. `1px --border` + 배경 명도 차이로 구분한다. 그림자는 실제로 떠 있는 요소(모달·드롭다운·토스트)에만 `0 8px 24px rgba(20,24,28,0.12)` 1종만 사용한다.
- **Motion**: duration `120ms`(색·배경), `160ms`(개폐), easing `ease-out`. 무한 반복 애니메이션 없음. 페이지 진입 stagger 없음. `prefers-reduced-motion: reduce` 시 전부 `0ms`.

---

## 6. 파일 구조 (File Structure)

```text
apps/web/client/
├── styles/
│   ├── tokens.css              # Design Tokens (Light/Dark 변수 전체)
│   ├── reset.css               # Reset & Base
│   └── global.css              # 폰트 로드, 스크롤바, 포커스 링
├── components/
│   ├── layout/
│   │   ├── Topbar/
│   │   ├── Sidebar/            # 계정 트리
│   │   └── Inspector/          # 상세 패널
│   ├── ui/                     # Button, Input, Modal, Combobox, Toast
│   └── ledger/
│       ├── LedgerTable/        # 가상 스크롤 표 + 마감선
│       ├── Money/
│       ├── BalanceSummary/
│       ├── IngestProgress/
│       ├── FixedWidthReport/   # COBOL 산출물 뷰어
│       └── ReportChart/        # R 산출 SVG 뷰어
└── pages/
    ├── Ledger.jsx
    ├── Budgets.jsx             # Haskell DSL 편집기
    ├── Reports.jsx
    └── Automation.jsx          # Lua 스크립트 편집기
```

---

## 7. 개발 시 주의사항 (Implementation Notes)

1. **스타일링 전략 (Styling Strategy)**
   - CSS Modules + 토큰 변수만 사용한다. 컴포넌트 파일에 하드코딩된 hex 값이 있으면 리뷰에서 반려한다.
   - 클래스 명명은 컴포넌트 스코프 내 소문자 케밥(`.row`, `.row--selected`). 전역 클래스는 `tokens.css`·`global.css`에만 존재한다.
   - 표 관련 스타일은 레이아웃 흔들림을 만드는 속성(`padding` 변화, `border` 추가, `transform`)을 호버·선택 상태에 사용하지 않는다.

2. **접근성 가이드 (Accessibility)**
   - 표는 `<table>` 시맨틱을 유지한다. 가상 스크롤 구현이 `div` 그리드를 강제하면 `role="grid"`·`aria-rowindex`·`aria-colindex`를 명시한다.
   - 금액의 의미를 색으로만 전달하지 않는다. 부호 + 컬럼 위치를 병행한다.
   - 모든 인터랙티브 요소는 키보드로 도달 가능하고 포커스 링이 보인다. `outline: none` 단독 사용 금지.
   - 인제스트·마감처럼 시간이 걸리는 동작은 `aria-live="polite"`로 상태 변화를 읽어준다.

3. **예외 처리 (Exception Handling)**
   - **로딩**: 스켈레톤 shimmer를 쓰지 않는다. 표 영역에 행 높이만 유지한 무채색 플레이스홀더를 두고, 200ms 이내 응답 시에는 아무것도 표시하지 않는다.
   - **빈 상태**: "거래가 없습니다"로 끝내지 않는다. 명세서 업로드 또는 수기 입력 중 다음 행동 하나를 제시한다.
   - **오류**: 사과하지 않고 무엇이 왜 실패했고 무엇을 하면 되는지 쓴다. 예 — "3행의 금액 형식을 읽지 못했습니다. 통화 기호를 제거하고 다시 올려 주세요."
   - **정합성 실패**: COBOL 마감 결과와 참조 구현이 불일치하면 마감을 완료 처리하지 않고, 불일치 항목을 표로 보여준다. 이 경우에만 `--negative` 배경 배너를 사용한다(전체 화면에서 유일한 강한 경고 표현).

4. **카피 (Copy)**
   - 사용자가 아는 말로 쓴다. "batch", "ingest", "settlement" 대신 "명세서 불러오기", "기간 마감"으로 표기한다.
   - 동작 이름은 흐름 전체에서 동일하게 유지한다. 버튼이 "기간 마감"이면 완료 토스트도 "기간을 마감했습니다"다.
   - 문장은 능동태·평서형·문장 케이스. 느낌표와 장식용 이모지는 사용하지 않는다.

---
