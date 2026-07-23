-- prelude.lua — 사용자 자동화 규칙 표준 라이브러리 (just-ledger, 백서 §4.3)
--
-- 이 파일은 Go 샌드박스(sandbox.go)가 **모든 규칙 실행 직전** DoString 으로 로드한다.
-- 규칙은 여기서 정의한 전역 테이블 `money` / `text` / `date` / `rule` 을 그대로 쓴다.
--
-- 실행 환경 제약 (두 곳 모두에서 동작해야 한다):
--   1) Go 워커 샌드박스 = gopher-lua (Lua 5.1 의미론, number 는 float64)
--   2) 단위 테스트 = lua5.4 (`lua5.4 prelude_test.lua`)
-- 따라서 5.3+ 전용 문법(정수 나눗셈 //, 비트 연산, math.tointeger 등)을 쓰지 않고,
-- 정수 나눗셈이 필요하면 math.floor 로 처리한다.
--
-- 금액 규칙 (INV-4 — 최우선):
--   금액(amount_minor)은 '최소 화폐 단위 정수'를 담은 **문자열**이다.
--   number(float64)로 변환하면 2^53 초과에서 정밀도가 깨지므로, money.* 는 금액을
--   number 로 바꾸지 않고 '문자열 자릿수' 위에서 직접 부호·비교·가감을 수행한다.
--   날짜 성분(연·월·일)은 금액이 아니므로 number 로 다뤄도 안전하다.
--
-- 샌드박스에서 setmetatable/getmetatable/rawset 등은 제거돼 있으므로, 이 라이브러리는
-- 메타테이블을 쓰지 않는 순수 테이블·클로저로만 구성한다.

local money = {}
local text = {}
local date = {}
local rule = {}

-- ===========================================================================
-- money — 최소 화폐 단위 정수(문자열) 산술. float 미경유 (INV-4).
-- ===========================================================================

-- 선행 0 제거 → 정규 자릿수 문자열. 전부 0 이면 "0".
local function strip(d)
  local i, n = 1, #d
  while i < n and string.byte(d, i) == 48 do i = i + 1 end
  return string.sub(d, i)
end

-- 부호 없는 자릿수 문자열 두 개의 크기 비교. -1 / 0 / 1.
local function ucompare(a, b)
  if #a ~= #b then
    if #a < #b then return -1 else return 1 end
  end
  if a == b then return 0 end
  if a < b then return -1 else return 1 end
end

-- 부호 없는 덧셈 (필산). 정규 자릿수 문자열 반환.
local function uadd(a, b)
  local i, j = #a, #b
  local carry, k = 0, 0
  local out = {}
  while i > 0 or j > 0 or carry > 0 do
    local da = (i > 0) and (string.byte(a, i) - 48) or 0
    local db = (j > 0) and (string.byte(b, j) - 48) or 0
    local sum = da + db + carry
    if sum >= 10 then sum = sum - 10; carry = 1 else carry = 0 end
    k = k + 1
    out[k] = string.char(sum + 48)
    i, j = i - 1, j - 1
  end
  local rev = {}
  for x = k, 1, -1 do rev[k - x + 1] = out[x] end
  return strip(table.concat(rev))
end

-- 부호 없는 뺄셈 (a >= b 가정). 정규 자릿수 문자열 반환.
local function usub(a, b)
  local i, j = #a, #b
  local borrow, k = 0, 0
  local out = {}
  while i > 0 do
    local da = string.byte(a, i) - 48
    local db = (j > 0) and (string.byte(b, j) - 48) or 0
    local diff = da - db - borrow
    if diff < 0 then diff = diff + 10; borrow = 1 else borrow = 0 end
    k = k + 1
    out[k] = string.char(diff + 48)
    i, j = i - 1, j - 1
  end
  local rev = {}
  for x = k, 1, -1 do rev[k - x + 1] = out[x] end
  return strip(table.concat(rev))
end

-- 금액 문자열 파싱. 반환: sign(-1|1), digits(정규 자릿수). 실패 시 nil.
-- 정규 0 은 sign=1, digits="0" 으로 통일한다.
function money._parse(s)
  if type(s) ~= "string" then return nil end
  local sign, digits = string.match(s, "^([+-]?)(%d+)$")
  if not digits then return nil end
  digits = strip(digits)
  local sgn = (sign == "-") and -1 or 1
  if digits == "0" then sgn = 1 end
  return sgn, digits
end

local function must(s)
  local sgn, d = money._parse(s)
  assert(d, "money: 유효하지 않은 금액 문자열: " .. tostring(s))
  return sgn, d
end

-- 유효한 최소 단위 정수 문자열인가?
function money.is_valid(s)
  return (money._parse(s)) ~= nil
end

-- 정규형 문자열 ("0", "123", "-45").
function money.normalize(s)
  local sgn, d = must(s)
  if d == "0" then return "0" end
  return (sgn < 0 and "-" or "") .. d
end

-- 부호. -1 / 0 / 1.
function money.sign(s)
  local sgn, d = must(s)
  if d == "0" then return 0 end
  return sgn
end

function money.is_zero(s) return money.sign(s) == 0 end
function money.is_negative(s) return money.sign(s) < 0 end
function money.is_positive(s) return money.sign(s) > 0 end

-- 절댓값 문자열 (항상 부호 없음).
function money.abs(s)
  local _, d = must(s)
  return d
end

-- 부호 반전.
function money.negate(s)
  local sgn, d = must(s)
  if d == "0" then return "0" end
  return (sgn > 0 and "-" or "") .. d
end

-- 부호 있는 비교. a<b → -1, a==b → 0, a>b → 1. (음수 < 0 < 양수)
function money.compare(a, b)
  local sa, da = must(a)
  local sb, db = must(b)
  local za, zb = (da == "0"), (db == "0")
  local sga = za and 0 or sa
  local sgb = zb and 0 or sb
  if sga ~= sgb then
    if sga < sgb then return -1 else return 1 end
  end
  if sga == 0 then return 0 end
  local u = ucompare(da, db)
  if sga > 0 then return u else return -u end
end

function money.eq(a, b) return money.compare(a, b) == 0 end
function money.lt(a, b) return money.compare(a, b) < 0 end
function money.le(a, b) return money.compare(a, b) <= 0 end
function money.gt(a, b) return money.compare(a, b) > 0 end
function money.ge(a, b) return money.compare(a, b) >= 0 end

-- 부호 있는 덧셈. 문자열 반환.
function money.add(a, b)
  local sa, da = must(a)
  local sb, db = must(b)
  local mag, sgn
  if sa == sb then
    mag, sgn = uadd(da, db), sa
  else
    local c = ucompare(da, db)
    if c == 0 then
      return "0"
    elseif c > 0 then
      mag, sgn = usub(da, db), sa
    else
      mag, sgn = usub(db, da), sb
    end
  end
  if mag == "0" then return "0" end
  return (sgn < 0 and "-" or "") .. mag
end

-- 부호 있는 뺄셈. a - b.
function money.sub(a, b)
  return money.add(a, money.negate(b))
end

-- 절댓값 크기 비교. |a| ? |b| → -1 / 0 / 1.
function money.abs_compare(a, b)
  local _, da = must(a)
  local _, db = must(b)
  return ucompare(da, db)
end

-- |a| >= |threshold| ?  (고액 판정 등에 사용)
function money.magnitude_ge(a, threshold)
  return money.abs_compare(a, threshold) >= 0
end

-- |a| > |threshold| ?
function money.magnitude_gt(a, threshold)
  return money.abs_compare(a, threshold) > 0
end

-- 세 자리 그룹 구분자 삽입 (정수 자릿수 문자열 대상).
local function group3(digits, sep)
  if sep == "" or #digits <= 3 then return digits end
  local parts = {}
  local i = #digits
  while i > 3 do
    parts[#parts + 1] = string.sub(digits, i - 2, i)
    i = i - 3
  end
  parts[#parts + 1] = string.sub(digits, 1, i)
  -- parts 는 뒤에서부터 담겼으니 뒤집어 sep 로 잇는다
  local rev = {}
  for x = #parts, 1, -1 do rev[#rev + 1] = parts[x] end
  return table.concat(rev, sep)
end

-- 표시용 포맷팅 (문자열 연산만 — 표시 경로도 float 미경유).
--   opts.frac_digits (기본 2)   : 소수 자릿수
--   opts.group       (기본 "")  : 천 단위 구분자 (예 ",")
--   opts.point       (기본 ".") : 소수점
--   opts.plus        (기본 nil) : 양수에 '+' 표기
--   opts.prefix / opts.suffix   : 통화 기호 등
function money.format(a, opts)
  opts = opts or {}
  local frac = opts.frac_digits
  if frac == nil then frac = 2 end
  assert(frac >= 0, "money.format: frac_digits 는 0 이상이어야 합니다")
  local sep = opts.group or ""
  local point = opts.point or "."
  local sgn, d = must(a)
  local neg = (sgn < 0 and d ~= "0")
  -- frac+1 자리 이상이 되도록 좌측 0 패딩
  while #d < frac + 1 do d = "0" .. d end
  local intpart, fracpart
  if frac == 0 then
    intpart, fracpart = d, ""
  else
    intpart = string.sub(d, 1, #d - frac)
    fracpart = string.sub(d, #d - frac + 1)
  end
  intpart = group3(intpart, sep)
  local sign_str = neg and "-" or (opts.plus and "+" or "")
  local body = intpart
  if frac > 0 then body = body .. point .. fracpart end
  return sign_str .. (opts.prefix or "") .. body .. (opts.suffix or "")
end

-- ISO 4217 통화별 최소 단위 지수 (minor unit). 목록에 없으면 2.
money.frac_digits = {
  KRW = 0, JPY = 0, VND = 0, CLP = 0, ISK = 0, KMF = 0, XAF = 0, XOF = 0,
  PYG = 0, RWF = 0, UGX = 0, VUV = 0, XPF = 0, GNF = 0, BIF = 0, DJF = 0,
  USD = 2, EUR = 2, GBP = 2, CNY = 2, CAD = 2, AUD = 2, HKD = 2, SGD = 2,
  CHF = 2, INR = 2, THB = 2, TWD = 2, PHP = 2, MYR = 2, IDR = 2, BRL = 2,
  BHD = 3, KWD = 3, OMR = 3, JOD = 3, TND = 3, IQD = 3, LYD = 3,
}

-- 통화의 최소 단위 지수. 미등록 통화는 2 로 가정.
function money.currency_frac(cur)
  local f = money.frac_digits[cur]
  if f == nil then return 2 end
  return f
end

-- 통화 인식 포맷 — 통화별 소수 자릿수와 천 단위 구분자를 적용한다.
function money.format_currency(a, cur, opts)
  opts = opts or {}
  local o = {
    frac_digits = money.currency_frac(cur),
    group = opts.group or ",",
    point = opts.point or ".",
    plus = opts.plus,
    prefix = opts.prefix,
    suffix = opts.suffix or (" " .. cur),
  }
  return money.format(a, o)
end

-- ===========================================================================
-- text — 상대처/카테고리 문자열 매칭. UTF-8 바이트 안전 (부분 문자열은 바이트 일치).
-- ===========================================================================

-- ASCII 소문자화 (한글 등 멀티바이트는 그대로 — 부분 문자열 매칭에 영향 없음).
function text.lower(s)
  return string.lower(s or "")
end

-- h 안에 부분 문자열 n 이 있는가. ci=true 면 대소문자 무시(ASCII).
function text.contains(h, n, ci)
  if h == nil or n == nil or n == "" then return false end
  if ci then h = string.lower(h); n = string.lower(n) end
  return string.find(h, n, 1, true) ~= nil
end

-- 대소문자 무시 contains.
function text.icontains(h, n)
  return text.contains(h, n, true)
end

-- 키워드 목록 중 h 에 처음 등장하는 것을 반환 (없으면 nil).
function text.find_keyword(h, list, ci)
  for _, k in ipairs(list) do
    if text.contains(h, k, ci) then return k end
  end
  return nil
end

-- 목록 중 하나라도 포함되는가.
function text.contains_any(h, list, ci)
  return text.find_keyword(h, list, ci) ~= nil
end

-- 목록 전부가 포함되는가.
function text.contains_all(h, list, ci)
  for _, k in ipairs(list) do
    if not text.contains(h, k, ci) then return false end
  end
  return true
end

-- 포함된 키워드 개수 (신뢰도 점수용).
function text.keyword_score(h, list, ci)
  local n = 0
  for _, k in ipairs(list) do
    if text.contains(h, k, ci) then n = n + 1 end
  end
  return n
end

function text.starts_with(s, p)
  if s == nil or p == nil then return false end
  return string.sub(s, 1, #p) == p
end

function text.ends_with(s, p)
  if s == nil or p == nil then return false end
  if p == "" then return true end
  return string.sub(s, #s - #p + 1) == p
end

-- 앞뒤 공백 제거.
function text.trim(s)
  return (string.gsub(s or "", "^%s*(.-)%s*$", "%1"))
end

-- 앞뒤 공백 제거 + 내부 연속 공백을 하나로.
function text.squish(s)
  return (string.gsub(text.trim(s), "%s+", " "))
end

-- 숫자만 남긴다 (카드 뒷자리 추출 등).
function text.digits_only(s)
  return (string.gsub(s or "", "%D", ""))
end

-- 뒤 keep 자만 남기고 나머지를 '*' 로 가린다 (표시 시 민감 조각 축약).
function text.mask(s, keep)
  s = s or ""
  keep = keep or 0
  local n = #s
  if n <= keep then return s end
  return string.rep("*", n - keep) .. string.sub(s, n - keep + 1)
end

-- glob(부분 정규식) 매칭. `*` = 임의 길이, `?` = 한 글자. 나머지는 리터럴.
-- 상대처 패턴("AMAZON*", "STARBUCKS ????") 매칭에 쓴다. ASCII 지향.
local GLOB_MAGIC = "^$()%.[]*+-?"
function text.matches_glob(s, glob, ci)
  if s == nil or glob == nil then return false end
  if ci then s = string.lower(s); glob = string.lower(glob) end
  local pat = { "^" }
  for i = 1, #glob do
    local c = string.sub(glob, i, i)
    if c == "*" then
      pat[#pat + 1] = ".*"
    elseif c == "?" then
      pat[#pat + 1] = "."
    elseif string.find(GLOB_MAGIC, c, 1, true) then
      pat[#pat + 1] = "%" .. c
    else
      pat[#pat + 1] = c
    end
  end
  pat[#pat + 1] = "$"
  return string.find(s, table.concat(pat)) ~= nil
end

-- ===========================================================================
-- date — "YYYY-MM-DD" ISO 날짜. 성분은 number(정수값)로 다룬다 (금액 아님).
-- ===========================================================================

local MONTH_DAYS = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 }

function date.is_leap_year(y)
  return (y % 4 == 0 and y % 100 ~= 0) or (y % 400 == 0)
end

function date.days_in_month(y, m)
  assert(m >= 1 and m <= 12, "date: 월 범위 오류")
  if m == 2 and date.is_leap_year(y) then return 29 end
  return MONTH_DAYS[m]
end

-- 파싱 + 검증. 반환: y, m, d (number). 형식/범위 오류면 nil.
function date.parse(s)
  if type(s) ~= "string" then return nil end
  local ys, ms, ds = string.match(s, "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
  if not ys then return nil end
  local y, m, d = tonumber(ys), tonumber(ms), tonumber(ds)
  if m < 1 or m > 12 then return nil end
  if d < 1 or d > date.days_in_month(y, m) then return nil end
  return y, m, d
end

function date.is_valid(s)
  return (date.parse(s)) ~= nil
end

local function parse_must(s)
  local y, m, d = date.parse(s)
  assert(y, "date: 유효하지 않은 날짜: " .. tostring(s))
  return y, m, d
end

function date.year(s) local y = parse_must(s); return y end
function date.month(s) local _, m = parse_must(s); return m end
function date.day(s) local _, _, d = parse_must(s); return d end

-- 요일. Sakamoto 알고리즘. 0=일 .. 6=토.
local SAKAMOTO = { 0, 3, 2, 5, 0, 3, 5, 1, 4, 6, 2, 4 }
function date.weekday(s)
  local y, m, d = parse_must(s)
  if m < 3 then y = y - 1 end
  local w = (y + math.floor(y / 4) - math.floor(y / 100) + math.floor(y / 400)
    + SAKAMOTO[m] + d) % 7
  return w
end

function date.is_weekend(s)
  local w = date.weekday(s)
  return w == 0 or w == 6
end

function date.is_weekday(s)
  return not date.is_weekend(s)
end

function date.is_month_end(s)
  local y, m, d = parse_must(s)
  return d == date.days_in_month(y, m)
end

function date.day_of_year(s)
  local y, m, d = parse_must(s)
  local total = d
  for mm = 1, m - 1 do total = total + date.days_in_month(y, mm) end
  return total
end

-- 유닉스 에폭(1970-01-01) 기준 일련일수. Howard Hinnant days_from_civil.
function date.to_ordinal(s)
  local y, m, d = parse_must(s)
  local yy = (m <= 2) and (y - 1) or y
  local era = math.floor((yy >= 0 and yy or (yy - 399)) / 400)
  local yoe = yy - era * 400
  local mp = (m > 2) and (m - 3) or (m + 9)
  local doy = math.floor((153 * mp + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
end

-- 일련일수 → y, m, d. to_ordinal 의 역변환.
function date.from_ordinal(z)
  z = z + 719468
  local era = math.floor((z >= 0 and z or (z - 146096)) / 146097)
  local doe = z - era * 146097
  local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524)
    - math.floor(doe / 146096)) / 365)
  local y = yoe + era * 400
  local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
  local mp = math.floor((5 * doy + 2) / 153)
  local d = doy - math.floor((153 * mp + 2) / 5) + 1
  local m = (mp < 10) and (mp + 3) or (mp - 9)
  if m <= 2 then y = y + 1 end
  return y, m, d
end

function date.format(y, m, d)
  return string.format("%04d-%02d-%02d", y, m, d)
end

-- s 에서 n 일 이동한 ISO 날짜 문자열.
function date.add_days(s, n)
  local y, m, d = date.from_ordinal(date.to_ordinal(s) + n)
  return date.format(y, m, d)
end

-- a - b 의 일수 차 (a, b: ISO 문자열).
function date.diff_days(a, b)
  return date.to_ordinal(a) - date.to_ordinal(b)
end

-- a<b → -1, a==b → 0, a>b → 1.
function date.compare(a, b)
  local diff = date.diff_days(a, b)
  if diff < 0 then return -1 elseif diff > 0 then return 1 else return 0 end
end

function date.before(a, b) return date.compare(a, b) < 0 end
function date.after(a, b) return date.compare(a, b) > 0 end

-- lo <= s <= hi (경계 포함).
function date.in_range(s, lo, hi)
  return date.compare(s, lo) >= 0 and date.compare(s, hi) <= 0
end

-- ===========================================================================
-- rule — 선언적 규칙 조합기. 술어(predicate)는 function(txn) -> bool.
--        txn 은 read-only 테이블(txn_id/occurred_on/amount_minor/currency/
--        merchant/category). 액션은 전역 tag/notify/set_account 로 방출한다.
-- ===========================================================================

-- 술어 AND 결합.
function rule.all(...)
  local preds = { ... }
  return function(txn)
    for i = 1, #preds do
      if not preds[i](txn) then return false end
    end
    return true
  end
end

-- 술어 OR 결합.
function rule.any(...)
  local preds = { ... }
  return function(txn)
    for i = 1, #preds do
      if preds[i](txn) then return true end
    end
    return false
  end
end

-- 술어 부정.
function rule.negate(p)
  return function(txn) return not p(txn) end
end

-- ── 술어 팩토리 ────────────────────────────────────────────────────────────

-- 상대처가 키워드 중 하나를 포함.
function rule.merchant_any(keywords, ci)
  if ci == nil then ci = true end
  return function(txn) return text.contains_any(txn.merchant or "", keywords, ci) end
end

-- 상대처가 glob 패턴에 일치.
function rule.merchant_glob(glob, ci)
  if ci == nil then ci = true end
  return function(txn) return text.matches_glob(txn.merchant or "", glob, ci) end
end

function rule.category_is(cat)
  return function(txn) return txn.category == cat end
end

function rule.category_any(list)
  return function(txn)
    for _, c in ipairs(list) do
      if txn.category == c then return true end
    end
    return false
  end
end

function rule.currency_is(cur)
  return function(txn) return txn.currency == cur end
end

-- 지출 (금액 부호 < 0).
function rule.is_expense()
  return function(txn) return money.sign(txn.amount_minor) < 0 end
end

-- 소득 (금액 부호 > 0).
function rule.is_income()
  return function(txn) return money.sign(txn.amount_minor) > 0 end
end

-- |금액| >= threshold (threshold: 최소 단위 정수 문자열).
function rule.amount_abs_at_least(threshold)
  return function(txn) return money.magnitude_ge(txn.amount_minor, threshold) end
end

-- |금액| < threshold.
function rule.amount_abs_below(threshold)
  return function(txn) return not money.magnitude_ge(txn.amount_minor, threshold) end
end

function rule.on_weekend()
  return function(txn) return date.is_weekend(txn.occurred_on) end
end

function rule.on_weekday()
  return function(txn) return date.is_weekday(txn.occurred_on) end
end

function rule.day_of_month_is(d)
  return function(txn) return date.day(txn.occurred_on) == d end
end

function rule.day_of_month_between(lo, hi)
  return function(txn)
    local dd = date.day(txn.occurred_on)
    return dd >= lo and dd <= hi
  end
end

function rule.month_is(m)
  return function(txn) return date.month(txn.occurred_on) == m end
end

function rule.is_month_end()
  return function(txn) return date.is_month_end(txn.occurred_on) end
end

function rule.date_in_range(lo, hi)
  return function(txn) return date.in_range(txn.occurred_on, lo, hi) end
end

-- ── 실행 ───────────────────────────────────────────────────────────────────

-- spec = { when=pred, tag=v, set_account=v, notify=v }
--   각 액션 값은 문자열이거나 function(txn)->문자열(동적 메시지) 이다.
--   when 이 참이면 액션을 전역 tag/notify/set_account 로 방출하고 true 를 반환한다.
function rule.evaluate(txn, spec)
  if spec.when and not spec.when(txn) then return false end
  local function emit(name, v)
    if v == nil then return end
    if type(v) == "function" then v = v(txn) end
    local f = _G[name]
    assert(type(f) == "function", "rule: 액션 '" .. name .. "' 을 사용할 수 없습니다")
    f(v)
  end
  emit("set_account", spec.set_account)
  emit("tag", spec.tag)
  emit("notify", spec.notify)
  return true
end

rule.apply = rule.evaluate

-- 여러 spec 을 순서대로 평가. 적용된 spec 수를 반환한다.
function rule.run(txn, specs)
  local applied = 0
  for _, spec in ipairs(specs) do
    if rule.evaluate(txn, spec) then applied = applied + 1 end
  end
  return applied
end

-- ── 전역 노출 (샌드박스 규칙이 직접 사용) + 모듈 반환 (단위 테스트용) ─────────
-- 샌드박스는 이 청크를 DoString 으로 로드하며 반환값을 버린다 → 전역으로 노출한다.
-- 단위 테스트(lua5.4)는 dofile 반환값(모듈 테이블)로도 접근할 수 있다.
_G.money = money
_G.text = text
_G.date = date
_G.rule = rule

return { money = money, text = text, date = date, rule = rule }
