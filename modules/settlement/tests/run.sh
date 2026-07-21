#!/bin/bash
# 골든 테스트 — COBOL 출력을 JS 참조가 생성한 기대 파일과 바이트 단위 비교.
# 차이 1바이트 = 실패 (INV-7 정신: 허용 오차 없음).
set -e
cd "$(dirname "$0")/.."
FIX=../../fixtures/settlement
FAIL=0

check() { # name, cmd-bin, in, expected
  local name="$1" bin="$2" in="$3" exp="$4"
  local out
  out=$(mktemp)
  "$bin" < "$in" > "$out"
  if cmp -s "$out" "$exp"; then
    echo "PASS  $name"
  else
    echo "FAIL  $name — first diff:"
    diff "$exp" "$out" | head -10
    FAIL=1
  fi
  rm -f "$out"
}

check settle-boundary bin/settle "$FIX/settle-boundary.in.dat" "$FIX/settle-boundary.expected.dat"
check settle-bulk     bin/settle "$FIX/settle-bulk.in.dat"     "$FIX/settle-bulk.expected.dat"
check amort           bin/amort  "$FIX/amort.in.dat"           "$FIX/amort.expected.dat"

# 성능 게이트: 마감 10,000 entry 2초 이내 (모듈 CLAUDE.md)
START=$(date +%s%N)
bin/settle < "$FIX/settle-bulk.in.dat" > /dev/null
ELAPSED_MS=$(( ($(date +%s%N) - START) / 1000000 ))
if [ "$ELAPSED_MS" -le 2000 ]; then
  echo "PASS  settle-bulk perf ${ELAPSED_MS}ms (<=2000ms)"
else
  echo "FAIL  settle-bulk perf ${ELAPSED_MS}ms (>2000ms)"
  FAIL=1
fi

exit $FAIL
