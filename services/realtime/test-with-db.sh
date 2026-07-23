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
  # 테스트가 실패해도(set -e) 스크래치 DB 를 반드시 정리한다. trap 이 없으면
  # 실패 시 DROP 이 실행되지 않아 다음 실행에 잔재가 남는다.
  trap 'psql "$ADMIN_URL" -qAt -c "DROP DATABASE IF EXISTS ${TEST_DB} WITH (FORCE)" >/dev/null 2>&1 || true' EXIT
  echo "== 스크래치 DB 재생성 ($TEST_DB) =="
  psql "$ADMIN_URL" -v ON_ERROR_STOP=1 -qAt -c "DROP DATABASE IF EXISTS ${TEST_DB} WITH (FORCE)"
  psql "$ADMIN_URL" -v ON_ERROR_STOP=1 -qAt -c "CREATE DATABASE ${TEST_DB}"
  (cd "$REPO" && psql "$TEST_URL" -v ON_ERROR_STOP=1 -q -f db/migrations/0001_init.up.pgsql)
  echo "== 통합 포함 테스트 =="
  # set -e 아래에서 mix test 실패가 스크립트를 즉시 끝내지 않도록 상태를 잡는다
  # (trap 이 정리를 보장하고, 여기서 실제 종료코드를 그대로 전파한다).
  status=0
  DATABASE_URL="$TEST_URL" mix test "$@" || status=$?
  exit $status
else
  echo "== DATABASE_URL 미설정 — 순수 로직만 =="
  mix test "$@"
fi
