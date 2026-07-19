# db — PLpgSQL (`.pgsql`)

스키마, 불변식 트리거, 잔액 롤업, 기간 집계, RLS, `NOTIFY` 발행.

> 확장자는 `.pgsql` + `.gitattributes` 의 `linguist-language=PLpgSQL` (`.sql` 은 SQL/TSQL 로 오탐).

## 소유 범위
`db/` (`migrations/`, `functions/`, `triggers/`, `tests/`). 데이터 모델은 기술 백서 §2.3 을 정본으로 하되, API 표현은 `contracts/` 를 따른다.

## 명령
```
psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f db/tests/run.pgsql   # make test-db
```

## 불변식 (강제 위치)
- **INV-1**: `posted` 이상 txn 은 통화별 `sum(debit)=sum(credit)`. **`AFTER` deferrable constraint trigger** 로 커밋 시점 검사(`BEFORE` 로 두면 다중 entry 중간 상태 오탐).
- **INV-2**: `entry.amount_minor > 0` — `CHECK` 제약. 부호는 `direction`.
- **INV-3**: `settled` 기간 txn·entry 는 UPDATE/DELETE 불가 — 트리거.
- **INV-5**: 한 txn 은 최대 1개 `transfer_link` — 부분 유니크 인덱스.

## 규율
- 마이그레이션 up/down 왕복 성공, 스키마 diff 0.
- 무작위 100,000 txn 삽입 후 INV-1 위반 0. 불균형 txn 삽입은 **반드시 실패**.
- 잔액 롤업 함수 = 원장 전수 합산과 전 계정·전 기간 일치.
- `NOTIFY` 페이로드는 `contracts/notify-event.schema.json` 준수.
- RLS 로 계정 소유자 격리. 서비스 계정은 `BYPASSRLS` 없음.

## 참조
기술 백서 §2.3, §4.1 / 담당 phase: M1.
