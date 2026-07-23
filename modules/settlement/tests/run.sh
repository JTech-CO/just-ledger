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
check interest        bin/interest "$FIX/interest.in.dat"      "$FIX/interest.expected.dat"
check report          bin/report "$FIX/report.in.dat"          "$FIX/report.expected.dat"
check deprec          bin/deprec "$FIX/deprec.in.dat"          "$FIX/deprec.expected.dat"

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

# ── settle 계약 위반 ──────────────────────────────────────────────────────
# direction 'X' — 부호 추정 금지 (settle-io.cpy 계약 1)
printf '%-32sXKRW%015d%015d%015d\n' "BAD.0001" 5 1 1 > "$TMPD/bad-dir.dat"
expect_abort settle-bad-direction bin/settle "$TMPD/bad-dir.dat"
# 고유 계정 5001개 — ACC-TABLE 상한 (settle-io.cpy 계약 2)
awk 'BEGIN{for(i=1;i<=5001;i++)printf "ACC.%-28dDKRW%015d%015d%015d\n",i,1,1,1}' > "$TMPD/too-many.dat"
expect_abort settle-account-cap bin/settle "$TMPD/too-many.dat"

# ── interest 계약 위반 (interest-io.cpy) ──────────────────────────────────
# method 'X' — 'S'/'C' 만 유효, 부호 추정 금지
printf '%-16s%s%015d%09d%09d%05d%05d%03d\n' "IBADM" "X" 100 5 100 1 1 0 \
    > "$TMPD/i-badm.dat"
expect_abort interest-bad-method bin/interest "$TMPD/i-badm.dat"
# rate_den 0 — 0 나눗셈 방지
printf '%-16s%s%015d%09d%09d%05d%05d%03d\n' "IDEN0" "S" 100 5 0 1 365 0 \
    > "$TMPD/i-den0.dat"
expect_abort interest-den-zero bin/interest "$TMPD/i-den0.dat"
# basis 0 (simple) — day-count 0 나눗셈 방지
printf '%-16s%s%015d%09d%09d%05d%05d%03d\n' "IBAS0" "S" 100 5 100 1 0 0 \
    > "$TMPD/i-bas0.dat"
expect_abort interest-basis-zero bin/interest "$TMPD/i-bas0.dat"
# 결과가 9(15) 초과 — ON SIZE ERROR 로 중단 (조용한 절삭 없음)
printf '%-16s%s%015d%09d%09d%05d%05d%03d\n' "IOVF" "S" \
    999999999999999 999999999 1 99999 1 0 > "$TMPD/i-ovf.dat"
expect_abort interest-overflow bin/interest "$TMPD/i-ovf.dat"

# ── report 계약 위반 (report-io.cpy) ──────────────────────────────────────
# 빈 입력 — 헤더 없음
: > "$TMPD/r-empty.dat"
expect_abort report-empty bin/report "$TMPD/r-empty.dat"
# 첫 레코드가 헤더가 아님 ('D' 로 시작)
printf 'D%-32s%-24s+%018d\n' "ACC.1" "Checking" 5 > "$TMPD/r-nohdr.dat"
expect_abort report-no-header bin/report "$TMPD/r-nohdr.dat"
# 알 수 없는 레코드 타입 ('X') — 조용한 스킵 금지
printf 'H%-7s%-40s\nX%-32s%-24s+%018d\n' "2026-06" "T" "ACC.1" "N" 5 \
    > "$TMPD/r-badtype.dat"
expect_abort report-bad-type bin/report "$TMPD/r-badtype.dat"
# 순합계가 S9(18) 초과 — edited move 절삭 대신 중단
printf 'H%-7s%-40s\nD%-32s%-24s+%018d\nD%-32s%-24s+%018d\n' \
    "2026-06" "T" "A1" "N" 999999999999999999 "A2" "N" 999999999999999999 \
    > "$TMPD/r-ovf.dat"
expect_abort report-total-overflow bin/report "$TMPD/r-ovf.dat"

# ── deprec 계약 위반 (deprec-io.cpy) ──────────────────────────────────────
# method 'X' — 'L'/'D' 만 유효
printf '%-16s%s%015d%015d%09d%09d%03d\n' "DBADM" "X" 1000 100 0 1 5 \
    > "$TMPD/d-badm.dat"
expect_abort deprec-bad-method bin/deprec "$TMPD/d-badm.dat"
# salvage > cost — 음수 상각 기준액
printf '%-16s%s%015d%015d%09d%09d%03d\n' "DSALV" "L" 1000 2000 0 1 5 \
    > "$TMPD/d-salv.dat"
expect_abort deprec-salvage-gt-cost bin/deprec "$TMPD/d-salv.dat"
# rate_den 0 (declining) — 0 나눗셈 방지
printf '%-16s%s%015d%015d%09d%09d%03d\n' "DDEN0" "D" 1000 100 25 0 5 \
    > "$TMPD/d-den0.dat"
expect_abort deprec-den-zero bin/deprec "$TMPD/d-den0.dat"

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
