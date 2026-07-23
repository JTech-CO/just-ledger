-- subscription.lua — 구독·정기결제 자동 태깅.
--
-- 알려진 구독 서비스 상대처의 '지출' 거래를 "구독" 으로 태깅하고 구독료 비용 계정으로
-- 상대 계정을 지정한다. 결제 금액은 통화 인식 포맷으로 알림에 담는다.
--
-- 주의: 정기결제 '주기' 판정(월/연 주기의 반복성)은 Prolog 서비스 소관이다. 이 규칙은
-- 단일 거래의 상대처 힌트만으로 태깅하며, 반복성을 단정하지 않는다.

local SUBSCRIPTIONS = {
  "넷플릭스", "netflix", "왓챠", "watcha", "티빙", "웨이브", "디즈니", "disney+",
  "spotify", "스포티파이", "youtube premium", "유튜브 프리미엄", "유튜브프리미엄",
  "icloud", "아이클라우드", "google one", "구글 원", "notion", "chatgpt", "openai",
  "melon", "멜론", "지니뮤직", "플로", "쿠팡와우", "네이버플러스", "네이버 플러스",
}

rule.evaluate(txn, {
  when = rule.all(rule.is_expense(), rule.merchant_any(SUBSCRIPTIONS)),
  tag = "구독",
  set_account = "5210", -- 구독료(비용)
  notify = function(t)
    return "구독 결제: " .. (t.merchant or "")
      .. " " .. money.format_currency(t.amount_minor, t.currency)
  end,
})
