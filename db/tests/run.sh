#!/usr/bin/env bash
# make test-db — M1 검증 오케스트레이터 (HARNESS M1 DoD 1~6)
# 컨테이너(just-ledger-dev) 안에서 compose 의 db 서비스를 대상으로 실행한다.
#   DATABASE_URL 예: postgres://ledger:ledger@db:5432/ledger
# 스크래치 DB(ledger_m1_test)를 만들어 왕복·테스트 후 정리한다.
set -euo pipefail

cd "$(dirname "$0")/../.."   # 레포 루트

DATABASE_URL="${DATABASE_URL:-postgres://ledger:ledger@db:5432/ledger}"
TEST_DB="ledger_m1_test"
TEST_URL="${DATABASE_URL%/*}/${TEST_DB}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PSQL_ADMIN=(psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -qAt)
PSQL_TEST=(psql "$TEST_URL" -v ON_ERROR_STOP=1)

step() { printf '\n== %s ==\n' "$*"; }

step "0. 스크래치 DB 재생성 ($TEST_DB)"
"${PSQL_ADMIN[@]}" -c "DROP DATABASE IF EXISTS ${TEST_DB} WITH (FORCE)"
"${PSQL_ADMIN[@]}" -c "CREATE DATABASE ${TEST_DB}"

# pg_dump 는 서버와 메이저 버전이 같거나 높아야 한다. 러너처럼 여러 버전이 깔린 환경에서는
# PATH 의 pg_dump(구버전)가 서버(18)를 거부하므로, 설치된 것 중 최신 pg_dump 를 고른다.
PG_DUMP="$(ls -1 /usr/lib/postgresql/*/bin/pg_dump 2>/dev/null | sort -V | tail -1)"
PG_DUMP="${PG_DUMP:-pg_dump}"
# pg_dump 18+ 는 덤프마다 무작위 \restrict/\unrestrict 토큰을 넣는다 — diff 전 제거.
dump_schema() { "$PG_DUMP" -s "$TEST_URL" | grep -vE '^\\(un)?restrict '; }

step "1. 마이그레이션 up (1차)"
"${PSQL_TEST[@]}" -q -f db/migrations/0001_init.up.pgsql
dump_schema > "$TMP/schema_1.sql"

step "1. 마이그레이션 down → 잔여 객체 0 확인"
"${PSQL_TEST[@]}" -q -f db/migrations/0001_init.down.pgsql
leftover=$(psql "$TEST_URL" -qAt -c "
  SELECT count(*) FROM pg_class c
  JOIN pg_namespace n ON n.oid = c.relnamespace
  WHERE n.nspname = 'public' AND c.relkind IN ('r','v','m','S')")
if [ "$leftover" != "0" ]; then
  echo "FAIL: down 이후 public 스키마에 객체 ${leftover}개 잔존 (DoD 1)"; exit 1
fi
echo "OK: down 이후 잔여 객체 0"

step "1. 마이그레이션 up (2차) → 스키마 diff 0 확인 (DoD 1)"
"${PSQL_TEST[@]}" -q -f db/migrations/0001_init.up.pgsql
dump_schema > "$TMP/schema_2.sql"
if ! diff -u "$TMP/schema_1.sql" "$TMP/schema_2.sql" > "$TMP/schema.diff"; then
  echo "FAIL: up/down 왕복 후 스키마 diff 발생 (DoD 1)"
  head -50 "$TMP/schema.diff"; exit 1
fi
echo "OK: up→down→up 왕복, 스키마 diff 0"

step "2. 불변식 음성 테스트 (DoD 3·4, INV-2·5)"
"${PSQL_TEST[@]}" -f db/tests/01_negative.pgsql

step "3. INV-1 커밋 시점 거절 (진짜 deferred 경로)"
if psql "$TEST_URL" -v ON_ERROR_STOP=1 -f db/tests/01b_deferred_commit.pgsql \
     > "$TMP/01b.out" 2> "$TMP/01b.err"; then
  echo "FAIL: 불균형 posted 커밋이 통과됨 — INV-1 커밋 게이트 미작동"
  cat "$TMP/01b.out"; exit 1
fi
if ! grep -q "JL001" "$TMP/01b.err"; then
  echo "FAIL: 커밋 거절 사유가 JL001(INV-1) 이 아님:"
  cat "$TMP/01b.err"; exit 1
fi
echo "OK: 불균형 커밋이 JL001 로 거절됨"

step "3b. INV-1 커밋 게이트가 RLS 역할(ledger_app)+GUC 우회에도 견고한지 (회귀)"
if psql "$TEST_URL" -v ON_ERROR_STOP=1 -f db/tests/01c_rls_role_inv.pgsql \
     > "$TMP/01c.out" 2> "$TMP/01c.err"; then
  echo "FAIL: RLS 역할에서 GUC 우회로 불균형 posted 가 커밋됨 — INV-1 무력화"
  cat "$TMP/01c.out"; exit 1
fi
if ! grep -q "JL001" "$TMP/01c.err"; then
  echo "FAIL: 우회 시도의 실패 사유가 JL001 이 아님 (다른 이유로 실패):"
  cat "$TMP/01c.err"; exit 1
fi
echo "OK: RLS 역할 + GUC 우회에도 INV-1 이 JL001 로 강제됨"

step "4. 무작위 100,000 txn 삽입 → INV-1 위반 0 (DoD 2)"
"${PSQL_TEST[@]}" -f db/tests/02_bulk_100k.pgsql

step "5. 잔액 롤업 ↔ 전수 합산 전 계정·전 기간 대조 (DoD 5)"
"${PSQL_TEST[@]}" -f db/tests/03_rollup_parity.pgsql

step "6. RLS 소유자 격리 (§7)"
"${PSQL_TEST[@]}" -f db/tests/04_rls.pgsql

step "7. NOTIFY 페이로드 계약 검증 (DoD 6)"
# ajv 설치 확인 (계약이 단일 진실원천 — 검증기는 contracts/ 를 그대로 사용)
if [ ! -d db/tests/node_modules/ajv ]; then
  (cd db/tests && npm install --no-save --no-package-lock --silent ajv@8 ajv-formats@3)
fi
psql "$TEST_URL" -v ON_ERROR_STOP=1 -f db/tests/05_notify.pgsql > "$TMP/notify.out" 2>&1
sed -nE 's/.*with payload "(.*)" received from.*/\1/p' "$TMP/notify.out" > "$TMP/payloads.jsonl"
echo "수신 페이로드 $(wc -l < "$TMP/payloads.jsonl")건"
node db/tests/validate-notify.mjs < "$TMP/payloads.jsonl"

# 소유자 격리(M7): 봉투 owner_id 가 실제 소유자와 일치해야 한다.
# 실시간 경로에는 RLS 가 없으므로 이 대조가 테넌트 격리의 회귀 방어다.
# psql 테이블 출력이라 선행 공백이 붙는다 — UUID 패턴으로 뽑는다
OWNER1=$(sed -nE 's/.*OWNER1=([0-9a-fA-F-]{36}).*/\1/p' "$TMP/notify.out" | head -1)
OWNER2=$(sed -nE 's/.*OWNER2=([0-9a-fA-F-]{36}).*/\1/p' "$TMP/notify.out" | head -1)
if [ -z "$OWNER1" ] || [ -z "$OWNER2" ]; then
  echo "FAIL: 소유자 id 추출 실패"; exit 1
fi
# UUID 자체로 대조한다 (jsonb::text 의 공백 표기에 의존하지 않는다).
# owner1 은 8건(balance 4·ingest 3·settlement 1), owner2 는 balance 2건을
# 유발한다. 정확 건수를 단언해 owner_id 가 뒤바뀌는 완전 교차까지 잡는다 —
# n>=1 만 보면 owner1↔owner2 가 통째로 뒤집혀도 통과해 버린다.
n1=$(grep -c "$OWNER1" "$TMP/payloads.jsonl" || true)
n2=$(grep -c "$OWNER2" "$TMP/payloads.jsonl" || true)
nother=$(grep -vc "$OWNER1\|$OWNER2" "$TMP/payloads.jsonl" || true)
echo "owner1 $n1건(기대 8) / owner2 $n2건(기대 2) / 그 외 $nother건(기대 0)"
if [ "$n1" -ne 8 ] || [ "$n2" -ne 2 ] || [ "$nother" -ne 0 ]; then
  echo "FAIL: 봉투 owner_id 격리 위반 — 발행 소유자 분포가 기대와 다름"; exit 1
fi
# 교차 확인: owner2 의 balance_changed 두 건이 owner1 로 새지 않았는지
# (owner2 계정 잔액이 owner1 봉투에 실리면 남의 금융 데이터 유출)
o2bal=$(grep "$OWNER2" "$TMP/payloads.jsonl" | grep -c "balance_changed" || true)
if [ "$o2bal" -ne 2 ]; then
  echo "FAIL: owner2 balance_changed 가 $o2bal 건 (기대 2) — 소유자 교차 의심"; exit 1
fi
echo "OK   소유자 격리: 발행 분포 정확(8/2/0), 교차 없음"

step "정리"
"${PSQL_ADMIN[@]}" -c "DROP DATABASE IF EXISTS ${TEST_DB} WITH (FORCE)"
echo
echo "OK: make test-db 전체 통과 (M1 DoD 1~6)"
