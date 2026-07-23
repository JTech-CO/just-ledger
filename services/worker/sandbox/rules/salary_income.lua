-- salary_income.lua — 급여 자동 분류.
--
-- '소득'(금액 부호 > 0) 중 급여 키워드가 있는 거래를 급여 소득 계정으로 분류·태깅한다.
--
-- 부호 결합이 핵심: 급여/이자 같은 키워드는 부분 문자열이라, 부호 없이 매칭하면
-- 음수 '대출이자'(지출)를 소득으로 뒤집는다. rule.is_income() 과 AND 로 결합해
-- 양수(입금)일 때만 적용한다.

local PAYROLL = { "급여", "월급", "상여", "성과급", "임금", "payroll", "salary" }

rule.evaluate(txn, {
  when = rule.all(rule.is_income(), rule.merchant_any(PAYROLL)),
  tag = "급여",
  set_account = "4110", -- 급여 소득
  notify = function(t)
    return "급여 입금 " .. money.format_currency(t.amount_minor, t.currency)
  end,
})
