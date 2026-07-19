# just-ledger — 전역 규칙

셀프호스팅 복식부기 개인 원장. 11개 언어가 각기 다른 계산 도메인을 담당한다.
메인 언어는 **JavaScript(ESM + JSDoc)** 이며, TypeScript를 도입하지 않는다.

---

## 세션 시작 절차

1. `PROGRESS.md` — 현재 phase, 다음 할 일, 미결 질문, 툴체인 상태
2. `docs/HARNESS.md` — 현재 phase 절만
3. 작업할 모듈의 `CLAUDE.md` (`services/*/CLAUDE.md`, `modules/*/CLAUDE.md`)
4. 필요할 때만 `docs/TECH-WHITEPAPER.md` / `docs/DESIGN-WHITEPAPER.md` 의 해당 절

루트 문서를 전부 읽지 않는다. **한 세션에서 한 언어만 다룬다.**

---

## 절대 불변식 (INV)

| ID | 내용 | 강제 위치 |
|---|---|---|
| INV-1 | `posted` 이상 상태의 모든 txn은 통화별 `sum(debit) = sum(credit)` | PLpgSQL deferrable constraint trigger |
| INV-2 | `entry.amount_minor > 0` (부호는 `direction`이 담당) | `CHECK` 제약 |
| INV-3 | `settled` 기간의 txn·entry는 UPDATE/DELETE 불가 | PLpgSQL 트리거 |
| INV-4 | 금액이 부동소수점을 경유하는 경로 0개 | `make check-no-float` |
| INV-5 | 한 txn은 최대 1개 `transfer_link`에만 속함 | 부분 유니크 인덱스 |
| INV-6 | 명세서 원문이 서버 로그·DB·임시 파일에 평문으로 남지 않음 | 인제스트 테스트 |
| INV-7 | COBOL 마감 결과와 JS 참조 구현의 차이는 **0원** | `make parity-settlement` |
| INV-8 | 이체 페어 매칭 거짓양성 0건 | `make test-classify` |

**위반 1건이라도 발견되면 그 자리에서 작업을 중단하고 `PROGRESS.md`에 기록한 뒤 보고한다.**

---

## 금액 취급 규칙 (최우선)

- 금액은 **최소 화폐 단위 정수**로만 표현한다. `BIGINT` / `i64` / `PIC S9(13)V99 COMP-3`.
- JavaScript에서는 `BigInt` 또는 문자열만 사용한다. `Number`, `parseFloat`, `toFixed`, `Math.round` 를 금액에 사용하지 않는다.
- API 경계에서는 **문자열**로 주고받는다 (`BigInt`는 `JSON.stringify` 불가).
- 환율은 실수가 아니라 유리수 쌍 `rate_num / rate_den` 으로 보관한다.
- 반올림은 COBOL의 `ROUNDED MODE IS NEAREST-EVEN` 만을 정본으로 삼는다. 다른 곳에서 자체 반올림을 구현하지 않는다.
- 표시용 포맷팅도 문자열 연산으로 처리한다.

---

## 디렉터리 ↔ 언어 소유권

| 경로 | 언어 | 소유 범위 |
|---|---|---|
| `apps/web/` | JavaScript | Fastify 서버, React UI |
| `services/worker/` | Go | 큐, 스케줄러, subprocess 오케스트레이션 |
| `services/worker/sandbox/` | Lua | 사용자 자동화 규칙 |
| `services/prolog/` | Prolog (`.prolog`) | 분류, 이체 매칭, 정기결제 탐지 |
| `services/realtime/` | Elixir | Phoenix 채널, NOTIFY 브리지 |
| `modules/statement-wasm/` | Rust | 명세서 파싱, 지문, 암호화 |
| `modules/rules-dsl/` | Haskell | 예산 규칙 DSL |
| `modules/settlement/` | COBOL (`.cbl`/`.cpy`) | 마감 정산, 상각 |
| `modules/analytics/` | R | 통계, 이상치, SVG 리포트 |
| `modules/simulation/` | Julia | 몬테카를로, 상환 최적화 |
| `db/` | PLpgSQL (`.pgsql`) | 스키마, 트리거, 집계, RLS |
| `contracts/` | JSON Schema | **언어 간 단일 진실원천** |
| `fixtures/` | 데이터 | 골든 입출력 |
| `infra/` | Docker / Shell / HCL | 빌드·배포 (Linguist 집계 제외) |

**소유 디렉터리 밖의 파일을 수정하지 않는다.** 다른 모듈이 바뀌어야 하면 계약을 먼저 고치고 보고한다.

---

## 언어 경계 규칙

1. `contracts/*.schema.json` 과 `modules/settlement/*.cpy` 가 단일 진실원천이다. 타입을 각 언어에서 손으로 재정의하지 않는다.
2. 계약을 바꾸면 `PROGRESS.md` 의 **계약 변경 로그**에 영향받는 모듈을 전부 기재한다.
3. 모든 모듈은 **stdin/stdout 만으로 단독 실행 가능**해야 한다. `make run-<module> < fixtures/...` 가 동작해야 한다.
4. 모든 모듈은 골든 테스트(고정 입력 → 고정 기대 출력)를 가진다.
5. 모듈 간 직접 import는 금지한다. 통신은 정의된 프로토콜로만 한다.

---

## 금지 사항

- 게이트 수치 하향, 테스트 삭제·약화로 "통과" 위장
- **정합성 허용 오차 도입** (`INV-7`을 "1원 이내 허용"으로 완화하는 행위)
- 이체 페어 매칭에 금액 근사 매칭 도입
- 금액을 부동소수점으로 처리하는 임시 우회
- 사용자 승인 없는 언어 추가·교체, 아키텍처·패키지 경계 변경
- Linguist 비율을 맞추기 위한 주석 패딩·무의미한 코드 생성
- `.env`, `deps/`, `_build/`, `target/`, `dist-newstyle/`, `node_modules/` 커밋
- 디자인 토큰 외 하드코딩 색상 (`styles/tokens.css` 밖의 hex 값)
- 장식용 이모지, 그라데이션, 카드 그림자 (디자인 백서 §5.3)

---

## 자주 쓰는 명령

```
make help                # 전체 타깃
make toolchain-check     # 11개 툴체인 확인
make up / make down      # 스택 기동/종료
make test                # 전체 테스트
make test-<phase>        # db api ingest classify sandbox settlement dsl analytics simulation realtime ui
make parity-settlement   # INV-7 정합성 대조
make check-no-float      # INV-4 정적 검사
make linguist            # 언어 구성 비율 출력
make linguist-gate       # 비율 게이트 (CI와 동일)
```

---

## 커밋 규칙

- 한 커밋은 한 모듈. 여러 언어를 한 커밋에 섞지 않는다.
- 계약 변경은 별도 커밋으로 분리하고, 영향받는 모듈 갱신은 후속 커밋으로 낸다.
- phase 완료 표기는 **해당 phase DoD 전 항목 통과 후**에만 `PROGRESS.md`에 기록한다.
- 커밋 메시지 접두어: `web:`, `worker:`, `prolog:`, `realtime:`, `wasm:`, `dsl:`, `settlement:`, `analytics:`, `simulation:`, `db:`, `contracts:`, `infra:`, `docs:`

---

## 막혔을 때

같은 실패를 서로 다른 방법으로 3회 시도해도 해결되지 않으면 `docs/HARNESS.md` §3 멈춤 규칙을 따른다.
`PROGRESS.md`에 증상 / 재현 방법 / 시도한 것들 / 가설 / 막힌 지점을 기록하고 보고한다.
**결정 전까지 불변식을 깨는 임시 우회를 만들지 않는다.**
