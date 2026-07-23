#!/usr/bin/env lua5.4
-- prelude_test.lua — prelude.lua 순수 함수 골든 단위 테스트.
--
-- 실행 (컨테이너):
--   lua5.4 services/worker/sandbox/prelude_test.lua
--
-- 고정 입력 → 고정 기대 출력. 서브프로세스 없음(컨테이너 seccomp 회피).
-- money.* 는 float 를 경유하지 않으므로 2^53 초과 금액도 정확히 처리해야 한다 (INV-4).

-- prelude.lua 를 스크립트와 같은 디렉터리에서 로드한다.
local here = string.match(arg[0], "^(.*)[/\\]") or "."
local P = assert(dofile(here .. "/prelude.lua"), "prelude.lua 로드 실패")
local money, text, date, rule = P.money, P.text, P.date, P.rule

-- ── 미니 테스트 하네스 ──────────────────────────────────────────────────────
local pass, fail = 0, 0
local function eq(got, want, msg)
  if got == want then
    pass = pass + 1
  else
    fail = fail + 1
    io.write(string.format("  FAIL %s: got %s, want %s\n",
      msg or "", tostring(got), tostring(want)))
  end
end
local function ok(cond, msg) eq(cond and true or false, true, msg) end
local function raises(fn, msg)
  local good = pcall(fn)
  eq(good, false, (msg or "") .. " (에러가 발생해야 함)")
end

-- ===========================================================================
-- money
-- ===========================================================================

-- 유효성
ok(money.is_valid("0"), "is_valid 0")
ok(money.is_valid("123"), "is_valid 123")
ok(money.is_valid("-45"), "is_valid -45")
ok(money.is_valid("+7"), "is_valid +7")
ok(money.is_valid("007"), "is_valid 007")
ok(not money.is_valid(""), "is_valid empty")
ok(not money.is_valid("1.5"), "is_valid float rejected")
ok(not money.is_valid("abc"), "is_valid abc")
ok(not money.is_valid("1-2"), "is_valid 1-2")
ok(not money.is_valid("-"), "is_valid lone sign")
ok(not money.is_valid(nil), "is_valid nil")

-- 정규화
eq(money.normalize("007"), "7", "normalize 007")
eq(money.normalize("-0"), "0", "normalize -0")
eq(money.normalize("+123"), "123", "normalize +123")
eq(money.normalize("-000045"), "-45", "normalize -000045")
eq(money.normalize("0"), "0", "normalize 0")
raises(function() money.normalize("x") end, "normalize invalid")

-- 부호
eq(money.sign("0"), 0, "sign 0")
eq(money.sign("-0"), 0, "sign -0")
eq(money.sign("5"), 1, "sign 5")
eq(money.sign("-5"), -1, "sign -5")
ok(money.is_negative("-17000"), "is_negative")
ok(money.is_positive("17000"), "is_positive")
ok(money.is_zero("-0"), "is_zero")

-- abs / negate
eq(money.abs("-45"), "45", "abs -45")
eq(money.abs("45"), "45", "abs 45")
eq(money.abs("-0"), "0", "abs -0")
eq(money.negate("45"), "-45", "negate 45")
eq(money.negate("-45"), "45", "negate -45")
eq(money.negate("0"), "0", "negate 0")

-- 비교
eq(money.compare("-5", "3"), -1, "compare -5 3")
eq(money.compare("10", "9"), 1, "compare 10 9")
eq(money.compare("100", "99"), 1, "compare 100 99")
eq(money.compare("-100", "-99"), -1, "compare -100 -99")
eq(money.compare("0", "-1"), 1, "compare 0 -1")
eq(money.compare("7", "7"), 0, "compare 7 7")
eq(money.compare("-0", "0"), 0, "compare -0 0")
ok(money.lt("-5", "3"), "lt")
ok(money.ge("3", "3"), "ge")
ok(money.gt("100", "99"), "gt")

-- 덧셈/뺄셈 (부호 조합)
eq(money.add("999", "1"), "1000", "add carry")
eq(money.add("-5", "3"), "-2", "add mixed 1")
eq(money.add("5", "-5"), "0", "add to zero")
eq(money.add("-5", "-3"), "-8", "add both neg")
eq(money.add("100", "-40"), "60", "add mixed 2")
eq(money.add("-40", "100"), "60", "add mixed 3")
eq(money.sub("60", "100"), "-40", "sub to neg")
eq(money.sub("5", "5"), "0", "sub to zero")

-- 큰 수 — float64(2^53) 정밀도 밖에서도 정확 (INV-4 핵심)
eq(money.add("9999999999999999999", "1"), "10000000000000000000", "add big carry")
eq(money.sub("10000000000000000000", "1"), "9999999999999999999", "sub big borrow")
eq(money.add("123456789012345678", "876543210987654322"), "1000000000000000000", "add 18-digit")

-- 절댓값 비교 / 임계
ok(money.magnitude_ge("-17000", "10000"), "magnitude_ge over")
ok(not money.magnitude_ge("5000", "10000"), "magnitude_ge under")
ok(money.magnitude_ge("10000", "10000"), "magnitude_ge equal")
ok(money.magnitude_gt("10001", "10000"), "magnitude_gt")

-- 포맷 (문자열 연산만)
eq(money.format("-1234567", { frac_digits = 2, group = "," }), "-12,345.67", "format neg")
eq(money.format("50", { frac_digits = 2 }), "0.50", "format small")
eq(money.format("-7", { frac_digits = 2 }), "-0.07", "format tiny neg")
eq(money.format("1234", { frac_digits = 0, group = "," }), "1,234", "format frac0 group")
eq(money.format("0", { frac_digits = 2 }), "0.00", "format zero")
eq(money.format("1000000", { frac_digits = 2, group = "," }), "10,000.00", "format group")
eq(money.format("100", { frac_digits = 2, plus = true }), "+1.00", "format plus")

-- 통화 인식 포맷
eq(money.currency_frac("KRW"), 0, "frac KRW")
eq(money.currency_frac("USD"), 2, "frac USD")
eq(money.currency_frac("BHD"), 3, "frac BHD")
eq(money.currency_frac("ZZZ"), 2, "frac default")
eq(money.format_currency("-17000", "KRW"), "-17,000 KRW", "format_currency KRW")
eq(money.format_currency("1050", "USD"), "10.50 USD", "format_currency USD")

-- ===========================================================================
-- text
-- ===========================================================================

ok(text.contains("넷플릭스 정기결제", "넷플릭스"), "contains ko")
ok(text.contains("HELLO", "hello", true), "contains ci")
ok(not text.contains("HELLO", "hello"), "contains cs")
ok(not text.contains("x", ""), "contains empty needle")
eq(text.find_keyword("스타벅스 강남", { "이디야", "스타벅스" }), "스타벅스", "find_keyword")
ok(text.contains_any("kb카드 이체", { "이체", "송금" }), "contains_any")
ok(text.contains_all("card payment", { "card", "payment" }), "contains_all")
ok(not text.contains_all("card only", { "card", "payment" }), "contains_all miss")
eq(text.keyword_score("전기 가스 수도", { "전기", "가스", "통신" }), 2, "keyword_score")
ok(text.starts_with("AMAZON US", "AMAZON"), "starts_with")
ok(text.ends_with("card ****1234", "1234"), "ends_with")
eq(text.trim("  hi  "), "hi", "trim")
eq(text.squish("a   b\tc"), "a b c", "squish")
eq(text.digits_only("****-1234"), "1234", "digits_only")
eq(text.mask("1234567890", 4), "******7890", "mask")
eq(text.mask("12", 4), "12", "mask short")

-- glob
ok(text.matches_glob("AMAZON MARKET", "AMAZON*"), "glob star")
ok(text.matches_glob("STARBUCKS", "STAR?UCKS"), "glob question")
ok(text.matches_glob("STARBUCKS", "star*", true), "glob ci")
ok(text.matches_glob("A.B", "A.B"), "glob literal dot match")
ok(not text.matches_glob("AXB", "A.B"), "glob literal dot no wildcard")
ok(not text.matches_glob("net", "netflix*"), "glob no match")

-- ===========================================================================
-- date
-- ===========================================================================

ok(date.is_leap_year(2024), "leap 2024")
ok(not date.is_leap_year(2100), "leap 2100")
ok(date.is_leap_year(2000), "leap 2000")
ok(not date.is_leap_year(2026), "leap 2026")

eq(date.days_in_month(2026, 2), 28, "dim feb")
eq(date.days_in_month(2024, 2), 29, "dim feb leap")
eq(date.days_in_month(2026, 4), 30, "dim apr")
eq(date.days_in_month(2026, 12), 31, "dim dec")

do
  local y, m, d = date.parse("2026-07-22")
  eq(y, 2026, "parse y"); eq(m, 7, "parse m"); eq(d, 22, "parse d")
end
ok(not date.is_valid("2026-13-01"), "invalid month")
ok(not date.is_valid("2026-02-29"), "invalid feb day")
ok(date.is_valid("2024-02-29"), "valid feb leap")
ok(not date.is_valid("2026-7-2"), "invalid format")
ok(not date.is_valid("2026-00-10"), "invalid month 0")

-- 요일 (0=일 .. 6=토). 확실한 앵커 날짜로 검증.
eq(date.weekday("1970-01-01"), 4, "weekday 1970 Thu")
eq(date.weekday("2000-01-01"), 6, "weekday 2000 Sat")
eq(date.weekday("2023-01-01"), 0, "weekday 2023 Sun")
eq(date.weekday("2024-01-01"), 1, "weekday 2024 Mon")
ok(date.is_weekend("2023-01-01"), "is_weekend Sun")
ok(not date.is_weekend("2024-01-01"), "not weekend Mon")

ok(date.is_month_end("2026-02-28"), "month_end feb")
ok(not date.is_month_end("2024-02-28"), "not month_end feb leap")
ok(date.is_month_end("2026-07-31"), "month_end jul")
ok(not date.is_month_end("2026-07-30"), "not month_end")

eq(date.day_of_year("2026-01-01"), 1, "doy jan1")
eq(date.day_of_year("2026-12-31"), 365, "doy dec31")
eq(date.day_of_year("2024-12-31"), 366, "doy dec31 leap")

eq(date.to_ordinal("1970-01-01"), 0, "ordinal epoch")
eq(date.to_ordinal("1970-01-02"), 1, "ordinal +1")
eq(date.to_ordinal("1969-12-31"), -1, "ordinal -1")
eq(date.to_ordinal("2000-01-01"), 10957, "ordinal 2000")
do
  local y, m, d = date.from_ordinal(0)
  eq(date.format(y, m, d), "1970-01-01", "from_ordinal epoch")
end
-- 왕복
for _, s in ipairs({ "2026-07-22", "2024-02-29", "1999-12-31", "2100-03-01" }) do
  local y, m, d = date.from_ordinal(date.to_ordinal(s))
  eq(date.format(y, m, d), s, "roundtrip " .. s)
end
eq(date.add_days("2026-07-30", 3), "2026-08-02", "add_days month cross")
eq(date.add_days("2026-12-31", 1), "2027-01-01", "add_days year cross")
eq(date.add_days("2024-02-28", 1), "2024-02-29", "add_days leap")
eq(date.add_days("2026-02-28", 1), "2026-03-01", "add_days non-leap")
eq(date.diff_days("2026-07-25", "2026-07-22"), 3, "diff_days")
eq(date.compare("2026-07-22", "2026-07-23"), -1, "date compare")
ok(date.in_range("2026-07-22", "2026-07-01", "2026-07-31"), "in_range")
ok(not date.in_range("2026-08-01", "2026-07-01", "2026-07-31"), "not in_range")

-- ===========================================================================
-- rule (술어 + evaluate)
-- ===========================================================================

local expense = { txn_id = "t1", occurred_on = "2023-01-01", amount_minor = "-17000",
  currency = "KRW", merchant = "넷플릭스 정기결제", category = "subscription" }
local income = { txn_id = "t2", occurred_on = "2024-01-01", amount_minor = "3200000",
  currency = "KRW", merchant = "주식회사 급여이체", category = "" }

ok(rule.is_expense()(expense), "is_expense true")
ok(not rule.is_expense()(income), "is_expense false")
ok(rule.is_income()(income), "is_income")
ok(rule.amount_abs_at_least("10000")(expense), "amount_abs_at_least")
ok(not rule.amount_abs_at_least("100000")(expense), "amount_abs_at_least under")
ok(rule.merchant_any({ "넷플릭스", "왓챠" })(expense), "merchant_any")
ok(rule.merchant_glob("*급여*")(income), "merchant_glob")
ok(rule.category_is("subscription")(expense), "category_is")
ok(rule.currency_is("KRW")(expense), "currency_is")
ok(rule.on_weekend()(expense), "on_weekend (Sun)")
ok(not rule.on_weekend()(income), "on_weekday (Mon)")
ok(rule.all(rule.is_expense(), rule.amount_abs_at_least("10000"))(expense), "rule.all")
ok(not rule.all(rule.is_expense(), rule.is_income())(expense), "rule.all mixed")
ok(rule.any(rule.is_income(), rule.merchant_any({ "넷플릭스" }))(expense), "rule.any")
ok(rule.negate(rule.is_income())(expense), "rule.negate")

-- evaluate: 전역 tag/notify/set_account 스텁으로 방출을 검증한다.
local emitted
function tag(v) emitted[#emitted + 1] = { "tag", v } end
function notify(v) emitted[#emitted + 1] = { "notify", v } end
function set_account(v) emitted[#emitted + 1] = { "set_account", v } end

emitted = {}
local applied = rule.evaluate(expense, {
  when = rule.is_expense(),
  set_account = "5210",
  tag = "구독",
  notify = function(t) return "구독 결제 " .. t.merchant end,
})
ok(applied, "evaluate applied")
eq(#emitted, 3, "evaluate emitted 3")
eq(emitted[1][1], "set_account", "emit order 1")
eq(emitted[1][2], "5210", "emit set_account val")
eq(emitted[2][1], "tag", "emit order 2")
eq(emitted[2][2], "구독", "emit tag val")
eq(emitted[3][1], "notify", "emit order 3")
eq(emitted[3][2], "구독 결제 넷플릭스 정기결제", "emit dynamic notify")

emitted = {}
ok(not rule.evaluate(income, { when = rule.is_expense(), tag = "구독" }), "evaluate not applied")
eq(#emitted, 0, "no emit when predicate false")

emitted = {}
local n = rule.run(expense, {
  { when = rule.is_expense(), tag = "지출" },
  { when = rule.is_income(), tag = "소득" },
  { when = rule.on_weekend(), tag = "주말" },
})
eq(n, 2, "rule.run applied count")
eq(#emitted, 2, "rule.run emitted count")

-- ── 요약 ────────────────────────────────────────────────────────────────────
io.write(string.format("prelude_test: %d passed, %d failed\n", pass, fail))
if fail > 0 then os.exit(1) end
