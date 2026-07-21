%% 분류 규칙 DB (M4). keyword_rule(RuleName, Category, Keyword, Confidence).
%% 절 순서 = 우선순위 (특수 규칙을 일반 규칙보다 앞에). first-match 로 분류한다.
%% merchant 는 클라이언트에서 정규화됨(NFKC·공백축약·접두어 제거·소문자) —
%% 키워드는 그 정규형 기준으로 작성한다. 근거 규칙명은 응답에 반드시 실린다 (DoD 6).

:- module(rules, [keyword_rule/4, category/1]).

%% 카테고리 체계 (계약 inference.schema.json category 슬러그)
category(cafe).          category(food).         category(convenience).
category(groceries).     category(delivery).     category(transport).
category(taxi).          category(fuel).         category(telecom).
category(subscription).  category(utilities).    category(medical).
category(pharmacy).      category(education).    category(culture).
category(clothing).      category(beauty).       category(insurance).
category(finance_fee).   category(salary).       category(interest).
category(transfer_out).  category(atm).          category(housing).
category(travel).        category(income_other). category(unknown).

%% ── 구독 (통신·OTT 보다 앞 — '유튜브 프리미엄' 류가 문화로 새지 않게) ──────
keyword_rule(sub_netflix,     subscription, "넷플릭스", 95).
keyword_rule(sub_netflix_en,  subscription, "netflix", 95).
keyword_rule(sub_youtube,     subscription, "유튜브", 90).
keyword_rule(sub_youtube_en,  subscription, "youtube", 90).
keyword_rule(sub_spotify,     subscription, "스포티파이", 95).
keyword_rule(sub_spotify_en,  subscription, "spotify", 95).
keyword_rule(sub_melon,       subscription, "멜론", 85).
keyword_rule(sub_coupang_wow, subscription, "쿠팡와우", 90).
keyword_rule(sub_watcha,      subscription, "왓챠", 95).
keyword_rule(sub_wavve,       subscription, "웨이브", 85).
keyword_rule(sub_tving,       subscription, "티빙", 90).
keyword_rule(sub_disney,      subscription, "디즈니", 90).
keyword_rule(sub_chatgpt,     subscription, "openai", 90).
keyword_rule(sub_icloud,      subscription, "icloud", 90).
keyword_rule(sub_google_one,  subscription, "google one", 90).

%% ── 카페·간식 ───────────────────────────────────────────────────────────
keyword_rule(cafe_starbucks,  cafe, "스타벅스", 95).
keyword_rule(cafe_starbucks_en, cafe, "starbucks", 95).
keyword_rule(cafe_twosome,    cafe, "투썸", 95).
keyword_rule(cafe_ediya,      cafe, "이디야", 95).
keyword_rule(cafe_mega,       cafe, "메가엠지씨", 95).
keyword_rule(cafe_megacoffee, cafe, "메가커피", 95).
keyword_rule(cafe_compose,    cafe, "컴포즈", 95).
keyword_rule(cafe_paik,       cafe, "빽다방", 95).
keyword_rule(cafe_hollys,     cafe, "할리스", 95).
keyword_rule(cafe_generic,    cafe, "커피", 70).
keyword_rule(cafe_word,       cafe, "카페", 65).
keyword_rule(dessert_baskin,  cafe, "배스킨", 90).
keyword_rule(dessert_paris,   cafe, "파리바게뜨", 85).
keyword_rule(dessert_tous,    cafe, "뚜레쥬르", 85).

%% ── 배달 (음식점보다 앞) ────────────────────────────────────────────────
keyword_rule(del_baemin,      delivery, "배달의민족", 95).
keyword_rule(del_baemin2,     delivery, "우아한형제", 90).
keyword_rule(del_yogiyo,      delivery, "요기요", 95).
keyword_rule(del_coupang_eats, delivery, "쿠팡이츠", 95).

%% ── 식비 (음식점) ────────────────────────────────────────────────────────
keyword_rule(food_mcdonald,   food, "맥도날드", 95).
keyword_rule(food_burgerking, food, "버거킹", 95).
keyword_rule(food_lotteria,   food, "롯데리아", 95).
keyword_rule(food_kfc,        food, "kfc", 95).
keyword_rule(food_momstouch,  food, "맘스터치", 95).
keyword_rule(food_kimbap,     food, "김밥", 90).
keyword_rule(food_kyochon,    food, "교촌", 90).
keyword_rule(food_bbq,        food, "비비큐", 90).
keyword_rule(food_bhc,        food, "비에이치씨", 90).
keyword_rule(food_sushi,      food, "초밥", 85).
keyword_rule(food_gukbap,     food, "국밥", 85).
keyword_rule(food_chicken,    food, "치킨", 80).
keyword_rule(food_pizza,      food, "피자", 80).
keyword_rule(food_restaurant, food, "식당", 75).
keyword_rule(food_gogi,       food, "고기", 70).
keyword_rule(food_bunsik,     food, "분식", 80).

%% ── 편의점 ───────────────────────────────────────────────────────────────
keyword_rule(cvs_gs25,        convenience, "gs25", 95).
keyword_rule(cvs_cu,          convenience, "cu ", 90).
keyword_rule(cvs_seven,       convenience, "세븐일레븐", 95).
keyword_rule(cvs_seven_en,    convenience, "7-eleven", 90).
keyword_rule(cvs_emart24,     convenience, "이마트24", 95).
keyword_rule(cvs_ministop,    convenience, "미니스톱", 95).

%% ── 마트·장보기 ─────────────────────────────────────────────────────────
keyword_rule(mart_emart,      groceries, "이마트", 90).
keyword_rule(mart_homeplus,   groceries, "홈플러스", 95).
keyword_rule(mart_lotte,      groceries, "롯데마트", 95).
keyword_rule(mart_costco,     groceries, "코스트코", 95).
keyword_rule(mart_market_kurly, groceries, "마켓컬리", 95).
keyword_rule(mart_kurly,      groceries, "컬리", 85).
keyword_rule(mart_coupang,    groceries, "쿠팡", 75).
keyword_rule(mart_naver,      groceries, "네이버페이", 60).
keyword_rule(mart_word,       groceries, "마트", 70).

%% ── 교통 ────────────────────────────────────────────────────────────────
keyword_rule(taxi_kakao,      taxi, "카카오티", 90).
keyword_rule(taxi_kakao2,     taxi, "카카오 티", 90).
keyword_rule(taxi_word,       taxi, "택시", 90).
keyword_rule(tr_subway,       transport, "지하철", 95).
keyword_rule(tr_korail,       transport, "코레일", 95).
keyword_rule(tr_srt,          transport, "에스알", 85).
keyword_rule(tr_ktx,          transport, "ktx", 90).
keyword_rule(tr_bus,          transport, "버스", 85).
keyword_rule(tr_tmoney,       transport, "티머니", 90).
keyword_rule(tr_hipass,       transport, "하이패스", 90).
keyword_rule(fuel_sk,         fuel, "sk에너지", 90).
keyword_rule(fuel_gs,         fuel, "gs칼텍스", 90).
keyword_rule(fuel_soil,       fuel, "에쓰오일", 90).
keyword_rule(fuel_hyundai,    fuel, "현대오일", 90).
keyword_rule(fuel_word,       fuel, "주유소", 90).

%% ── 통신 ────────────────────────────────────────────────────────────────
keyword_rule(tel_skt,         telecom, "에스케이텔레콤", 95).
keyword_rule(tel_skt2,        telecom, "skt", 90).
keyword_rule(tel_kt,          telecom, "케이티 ", 85).
keyword_rule(tel_lgu,         telecom, "엘지유플러스", 95).
keyword_rule(tel_lgu2,        telecom, "lg u+", 90).
keyword_rule(tel_word,        telecom, "통신요금", 90).

%% ── 주거·공과금 ─────────────────────────────────────────────────────────
keyword_rule(util_kepco,      utilities, "한국전력", 95).
keyword_rule(util_kepco2,     utilities, "한전", 85).
keyword_rule(util_gas,        utilities, "도시가스", 95).
keyword_rule(util_water,      utilities, "수도요금", 95).
keyword_rule(util_apt,        housing, "관리비", 90).
keyword_rule(housing_rent,    housing, "월세", 90).

%% ── 의료·약국 ───────────────────────────────────────────────────────────
keyword_rule(med_hospital,    medical, "병원", 90).
keyword_rule(med_clinic,      medical, "의원", 85).
keyword_rule(med_dental,      medical, "치과", 90).
keyword_rule(med_oriental,    medical, "한의원", 90).
keyword_rule(pharm_word,      pharmacy, "약국", 95).

%% ── 교육·문화·의류·미용 ──────────────────────────────────────────────────
keyword_rule(edu_academy,     education, "학원", 90).
keyword_rule(edu_word,        education, "교육", 75).
keyword_rule(cult_cgv,        culture, "cgv", 95).
keyword_rule(cult_lotte,      culture, "롯데시네마", 95).
keyword_rule(cult_megabox,    culture, "메가박스", 95).
keyword_rule(cult_kyobo,      culture, "교보문고", 90).
keyword_rule(cult_yes24,      culture, "예스24", 90).
keyword_rule(cult_aladin,     culture, "알라딘", 85).
keyword_rule(cloth_uniqlo,    clothing, "유니클로", 95).
keyword_rule(cloth_musinsa,   clothing, "무신사", 95).
keyword_rule(cloth_zara,      clothing, "자라리테일", 90).
keyword_rule(cloth_spao,      clothing, "스파오", 90).
keyword_rule(beauty_oliveyoung, beauty, "올리브영", 95).
keyword_rule(beauty_hair,     beauty, "헤어", 80).
keyword_rule(beauty_salon,    beauty, "미용실", 90).

%% ── 여행·숙박 ───────────────────────────────────────────────────────────
keyword_rule(travel_yanolja,  travel, "야놀자", 90).
keyword_rule(travel_goodchoice, travel, "여기어때", 90).
keyword_rule(travel_agoda,    travel, "아고다", 90).
keyword_rule(travel_airbnb,   travel, "에어비앤비", 90).
keyword_rule(travel_hotel,    travel, "호텔", 80).
keyword_rule(travel_koreanair, travel, "대한항공", 90).
keyword_rule(travel_asiana,   travel, "아시아나", 90).
keyword_rule(travel_jeju,     travel, "제주항공", 90).

%% ── 보험·금융 ───────────────────────────────────────────────────────────
keyword_rule(ins_samsung,     insurance, "삼성생명", 90).
keyword_rule(ins_samsung_fire, insurance, "삼성화재", 90).
keyword_rule(ins_hyundai,     insurance, "현대해상", 90).
keyword_rule(ins_kb,          insurance, "kb손해보험", 90).
keyword_rule(ins_word,        insurance, "보험", 80).
keyword_rule(fee_word,        finance_fee, "수수료", 85).

%% ── 입금 계열 (양수 금액 전용 규칙은 classify 에서 부호 검사와 결합) ─────────
keyword_rule(income_salary,   salary, "급여", 95).
keyword_rule(income_salary2,  salary, "월급", 95).
keyword_rule(income_interest, interest, "이자", 90).

%% ── 현금·이체 ───────────────────────────────────────────────────────────
keyword_rule(atm_word,        atm, "atm", 90).
keyword_rule(atm_cd,          atm, "현금인출", 95).
