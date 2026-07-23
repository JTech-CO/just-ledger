-- month_end_fee.lua — 월말 수수료·이자 태깅.
--
-- 월의 마지막 날(date.is_month_end)에 발생한 '지출' 중 수수료/이자 표기를 "월말수수료"
-- 로 태깅한다. 은행 계좌유지 수수료·이자 정산이 월말에 몰리는 패턴을 표면화한다.
--
-- '이자' 키워드는 소득('이자 수입')과 지출('대출이자') 양쪽에 쓰이므로 rule.is_expense()
-- 와 AND 로 결합해 지출만 잡는다.

rule.evaluate(txn, {
  when = rule.all(
    rule.is_expense(),
    rule.is_month_end(),
    rule.merchant_any({ "수수료", "이자", "fee", "interest" })
  ),
  tag = "월말수수료",
})
