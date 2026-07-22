#!/bin/bash
# make test-realtime — 실시간 계층 검증 (컨테이너에서 실행).
#
# DATABASE_URL 이 있으면 전용 스크래치 DB 를 만들어 마이그레이션을 적용하고
# 통합 테스트(@tag :db — 전파 지연·동시 연결·복구)까지 돌린다.
# 없으면 순수 로직(봉투 파싱·라우팅·임계 판정·채널 격리)만 돈다.
set -euo pipefail
cd "$(dirname "$0")"
REPO="$(cd ../.. && pwd)"

export MIX_ENV=test
mix local.hex --force --if-missing >/dev/null 2>&1
mix local.rebar --force --if-missing >/dev/null 2>&1
mix deps.get >/dev/null

if [ -n "${DATABASE_URL:-}" ]; then
  TEST_DB="ledger_m7_test"
  ADMIN_URL="$DATABASE_URL"
  TEST_URL="${DATABASE_URL%/*}/${TEST_DB}"
  echo "== 스크래치 DB 재생성 ($TEST_DB) =="
  psql "$ADMIN_URL" -v ON_ERROR_STOP=1 -qAt -c "DROP DATABASE IF EXISTS ${TEST_DB} WITH (FORCE)"
  psql "$ADMIN_URL" -v ON_ERROR_STOP=1 -qAt -c "CREATE DATABASE ${TEST_DB}"
  (cd "$REPO" && psql "$TEST_URL" -v ON_ERROR_STOP=1 -q -f db/migrations/0001_init.up.pgsql)
  echo "== 통합 포함 테스트 =="
  DATABASE_URL="$TEST_URL" mix test "$@"
  status=$?
  psql "$ADMIN_URL" -qAt -c "DROP DATABASE IF EXISTS ${TEST_DB} WITH (FORCE)" >/dev/null
  exit $status
else
  echo "== DATABASE_URL 미설정 — 순수 로직만 =="
  mix test "$@"
fi
