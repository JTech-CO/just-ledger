# contracts — 언어 간 단일 진실원천

11개 언어가 공유하는 데이터 계약. `modules/settlement/*.cpy`(copybook)와 함께 **유일한 타입 정본**이다. 어느 언어에서도 타입을 손으로 재정의하지 않는다.

## 파일
| 파일 | 대상 |
|---|---|
| `common.schema.json` | 공통 원시 타입(uuid/currency/date/금액 문자열/유리수 쌍/enum). 나머지가 `$ref` 로 참조. |
| `account.schema.json` | 계정 (§2.3-1) |
| `entry.schema.json` | 분개 행 (§2.3-3) |
| `txn.schema.json` | 거래 + entries (§2.3-2) |
| `ingest-batch.schema.json` | 인제스트 배치 (§2.3-8) |
| `notify-event.schema.json` | PG NOTIFY → Elixir → 브라우저 실시간 프레임 |

## 규칙
- **금액은 예외 없이 최소 화폐 단위 정수를 '문자열'로.** 부동소수점 표현(`number` 타입, 소수점)을 스키마에 두지 않는다 (INV-4). `common.schema.json#/$defs/moneyMinor`(부호 有)·`positiveMinor`(entry 전용, INV-2) 사용.
- 환율은 실수가 아니라 유리수 쌍 `ratio { num, den }`.
- 드래프트: **JSON Schema 2020-12**. ajv `strict: true` 로 컴파일된다.
- 교차 파일 `$ref` 는 `$id` (`https://just-ledger.dev/contracts/<name>.schema.json`) 기준 상대 파일명으로 해석된다. 로더는 모든 스키마를 `addSchema` 로 등록한 뒤 컴파일한다(`check.mjs` 참조).

## 검증
```
node contracts/check.mjs        # ajv strict 컴파일 + 금액 문자열 표본 (CI: contracts 잡)
```

## 계약 변경 절차
계약을 바꾸면 **먼저 스키마를 고치고**, `PROGRESS.md` 의 *계약 변경 로그* 에 영향받는 모듈을 전부 기재한 뒤 각 모듈을 갱신한다. 계약 변경은 별도 커밋(`contracts:`)으로 분리한다.

> `check.mjs` 는 도구 코드다. `contracts/**` 는 `linguist-vendored` 라 언어 구성 계측에 포함되지 않는다.
