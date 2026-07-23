-- installment.lua — 할부 결제 태깅.
--
-- 상대처/적요에 할부 표기가 있는 '지출' 거래를 "할부" 로 태깅한다.
-- (할부 개월수 파싱·잔여 회차 계산은 상각 모듈(COBOL) 소관 — 여기선 태깅만.)

rule.evaluate(txn, {
  when = rule.all(rule.is_expense(), rule.merchant_any({ "할부", "installment", "개월" })),
  tag = "할부",
})
