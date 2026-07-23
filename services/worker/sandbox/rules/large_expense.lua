-- large_expense.lua — 고액 지출 알림.
--
-- 통화별 임계 이상의 '지출' 거래를 "고액" 으로 태깅하고, 포맷된 금액과 임계를 알린다.
-- 임계 비교는 money.magnitude_ge 로 절댓값(문자열 정수)만 비교한다 — float 미경유.
--
-- 임계는 거래 금액과 같은 '최소 화폐 단위'다: KRW 500000 = ₩500,000(소수 0자리),
-- USD 50000 = $500.00(소수 2자리). 통화별 소수 자릿수 차이를 최소단위로 흡수한다.

local THRESHOLD = {
  KRW = "500000", -- ₩500,000
  JPY = "50000",  -- ¥50,000
  USD = "50000",  -- $500.00
  EUR = "50000",  -- €500.00
  GBP = "40000",  -- £400.00
}

local limit = THRESHOLD[txn.currency] or "500000"

rule.evaluate(txn, {
  when = rule.all(rule.is_expense(), rule.amount_abs_at_least(limit)),
  tag = "고액",
  notify = function(t)
    return "고액 지출 " .. money.format_currency(t.amount_minor, t.currency)
      .. " (임계 " .. money.format_currency(limit, t.currency) .. ")"
  end,
})
