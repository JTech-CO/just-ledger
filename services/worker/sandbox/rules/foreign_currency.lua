-- foreign_currency.lua — 해외 통화 결제 플래그.
--
-- 기준 통화(KRW) 이외의 거래를 "해외" 로 태깅하고 통화·금액을 통화 인식 포맷으로 알린다.
-- 환산은 하지 않는다(환율은 유리수 쌍으로 별도 처리) — 여기선 표기·플래그만 담당한다.

local BASE_CURRENCY = "KRW"

rule.evaluate(txn, {
  when = rule.negate(rule.currency_is(BASE_CURRENCY)),
  tag = "해외",
  notify = function(t)
    return "해외 통화 거래: " .. money.format_currency(t.amount_minor, t.currency)
  end,
})
