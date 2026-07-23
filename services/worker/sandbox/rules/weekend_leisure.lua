-- weekend_leisure.lua — 주말 여가 지출 태깅.
--
-- 주말(토·일)에 발생한 외식/여가 카테고리 '지출' 거래를 "주말여가" 로 태깅한다.
-- 요일 판정은 date.is_weekend (Sakamoto 알고리즘, occurred_on 의 ISO 날짜) 로 한다.

local LEISURE = { "dining", "restaurant", "cafe", "entertainment", "bar", "leisure", "travel" }

rule.evaluate(txn, {
  when = rule.all(rule.is_expense(), rule.on_weekend(), rule.category_any(LEISURE)),
  tag = "주말여가",
})
