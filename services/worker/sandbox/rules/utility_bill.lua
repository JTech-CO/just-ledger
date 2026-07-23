-- utility_bill.lua — 공과금 자동 분류.
--
-- 전기·가스·수도·통신 공급자 상대처의 '지출' 거래를 공과금 계정으로 분류·태깅한다.
--
-- 상대처 키워드는 오탐이 적은 표기만 담는다. 2~3자 라틴 약어(kt·skt 등)는 다른
-- 단어에 부분 문자열로 걸릴 수 있어 제외했다 — 정확 분류는 Prolog 규칙이 담당한다.

local UTILITIES = {
  "한국전력", "한전", "kepco", "전기요금",
  "도시가스", "가스공사", "가스요금",
  "상수도", "수도사업", "수도요금",
  "통신요금", "sk텔레콤", "lg유플러스", "kt요금",
}

rule.evaluate(txn, {
  when = rule.all(rule.is_expense(), rule.merchant_any(UTILITIES)),
  tag = "공과금",
  set_account = "5310", -- 공과금(비용)
})
