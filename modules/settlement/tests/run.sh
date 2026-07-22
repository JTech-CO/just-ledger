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

# 음성 케이스: 계약 위반 입력은 조용한 절삭 없이 비정상 종료해야 한다
expect_abort() { # name, bin, input-file
  local name="$1" bin="$2" in="$3"
  if "$bin" < "$in" > /dev/null 2>/dev/null; then
    echo "FAIL  $name — 비정상 입력인데 exit 0"
    FAIL=1
  else
    echo "PASS  $name (명시적 거절)"
  fi
}

TMPD=$(mktemp -d)
# direction 'X' — 부호 추정 금지 (settle-io.cpy 계약 1)
printf '%-32sXKRW%015d%015d%015d\n' "BAD.0001" 5 1 1 > "$TMPD/bad-dir.dat"
expect_abort settle-bad-direction bin/settle "$TMPD/bad-dir.dat"
# 고유 계정 5001개 — ACC-TABLE 상한 (settle-io.cpy 계약 2)
awk 'BEGIN{for(i=1;i<=5001;i++)printf "ACC.%-28dDKRW%015d%015d%015d\n",i,1,1,1}' > "$TMPD/too-many.dat"
expect_abort settle-account-cap bin/settle "$TMPD/too-many.dat"
rm -rf "$TMPD"

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
