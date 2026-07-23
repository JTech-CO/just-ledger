-- refund.lua — 환불 태깅.
--
-- '소득'(금액 부호 > 0, 즉 입금) 중 환불/취소 표기가 있는 거래를 "환불" 로 태깅한다.
-- 부호 결합으로 원결제(지출)와 환불(입금)을 구분한다 — 같은 상대처라도 부호가 다르다.

rule.evaluate(txn, {
  when = rule.all(rule.is_income(), rule.merchant_any({ "환불", "취소", "refund", "reversal" })),
  tag = "환불",
})
