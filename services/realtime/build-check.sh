#!/bin/bash
# 로컬 빌드·테스트 편의 스크립트 (컨테이너에서 실행)
cd "$(dirname "$0")"
export MIX_ENV="${MIX_ENV:-test}"
mix local.hex --force --if-missing >/dev/null 2>&1
mix local.rebar --force --if-missing >/dev/null 2>&1
mix deps.get 2>&1 | grep -Ev '^\s*$' | tail -5
mix compile --warnings-as-errors 2>&1 | tail -30
status=${PIPESTATUS[0]}
echo "COMPILE_EXIT=$status"
[ "$status" -ne 0 ] && exit "$status"
mix test 2>&1 | tail -40
