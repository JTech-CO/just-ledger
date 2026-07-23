%% 분류 규칙 DB (M4). keyword_rule(RuleName, Category, Keyword, Confidence).
%% 절 순서 = 우선순위 (특수 규칙을 일반 규칙보다 앞에). first-match 로 분류한다.
%% merchant 는 클라이언트에서 정규화됨(NFKC·공백축약·접두어 제거·소문자) —
%% 키워드는 그 정규형 기준으로 작성한다. 근거 규칙명은 응답에 반드시 실린다 (DoD 6).

:- module(rules, [keyword_rule/4, income_rule/4, category/1, category_group/2]).

%% 카테고리 체계 (계약 inference.schema.json category 슬러그 — ^[a-z0-9_]{1,32}$)
category(cafe).          category(food).         category(convenience).
category(groceries).     category(delivery).     category(transport).
category(taxi).          category(fuel).         category(telecom).
category(subscription).  category(utilities).    category(medical).
category(pharmacy).      category(education).    category(culture).
category(clothing).      category(beauty).       category(insurance).
category(finance_fee).   category(salary).       category(interest).
category(transfer_out).  category(atm).          category(housing).
category(travel).        category(income_other). category(unknown).
category(parking).       category(gaming).       category(pet).
category(fitness).       category(donation).     category(household).
category(appstore).

%% ── 예산 그룹 추론 (category_group/2) ────────────────────────────────────
%% 카테고리를 예산 백서 4분류(essential/lifestyle/income/transfer)로 접는다.
%% 예산 규칙 DSL(Haskell)·UI 요약이 카테고리별 합계를 그룹 단위로 굴릴 때 쓴다.
%% 각 카테고리는 정확히 하나의 그룹에 속한다 (suite: 전수 유일성 검증).
category_group(food,          essential).
category_group(groceries,     essential).
category_group(convenience,   essential).
category_group(transport,     essential).
category_group(taxi,          essential).
category_group(fuel,          essential).
category_group(parking,       essential).
category_group(telecom,       essential).
category_group(utilities,     essential).
category_group(housing,       essential).
category_group(medical,       essential).
category_group(pharmacy,      essential).
category_group(insurance,     essential).
category_group(education,     essential).
category_group(household,     essential).
category_group(cafe,          lifestyle).
category_group(delivery,      lifestyle).
category_group(subscription,  lifestyle).
category_group(culture,       lifestyle).
category_group(clothing,      lifestyle).
category_group(beauty,        lifestyle).
category_group(travel,        lifestyle).
category_group(gaming,        lifestyle).
category_group(fitness,       lifestyle).
category_group(pet,           lifestyle).
category_group(donation,      lifestyle).
category_group(appstore,      lifestyle).
category_group(salary,        income).
category_group(interest,      income).
category_group(income_other,  income).
category_group(finance_fee,   transfer).
category_group(transfer_out,  transfer).
category_group(atm,           transfer).
category_group(unknown,       other).

%% ── 브랜드 부분충돌 가드 (최우선) ─────────────────────────────────────────
%% 일반 키워드의 부분문자열이 특정 브랜드를 가로채는 오분류를 최상단에서 차단한다.
%% 예: 자선단체 '굿네이버스' 는 '버스'(transport) 를 포함 → 여기서 먼저 donation 확정.
%% 이 방식은 '이자카야'(더 긴 키워드 우선)·소득 부호 게이트와 같은 음성-규칙 전략이다.
keyword_rule(guard_goodneighbors, donation, "굿네이버스", 90).   % '…네이버스' 의 '버스' 충돌 차단

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
keyword_rule(sub_apple_music_kr, subscription, "애플뮤직", 90).
keyword_rule(sub_notion,      subscription, "notion", 85).
keyword_rule(sub_notion_kr,   subscription, "노션", 85).
keyword_rule(sub_adobe,       subscription, "adobe", 90).
keyword_rule(sub_adobe_kr,    subscription, "어도비", 90).
keyword_rule(sub_millie,      subscription, "밀리의서재", 90).

%% ── 앱마켓·인앱결제 (구독과 분리 — 마켓 자체 청구) ──────────────────────────
keyword_rule(app_appstore,    appstore, "앱스토어", 85).
keyword_rule(app_appstore_en, appstore, "app store", 85).
keyword_rule(app_googleplay,  appstore, "구글플레이", 85).
keyword_rule(app_playstore,   appstore, "google play", 85).

%% ── 게임 (콘솔·PC·모바일 퍼블리셔) ────────────────────────────────────────
keyword_rule(game_steam,      gaming, "스팀", 85).
keyword_rule(game_steam_en,   gaming, "steam", 80).
keyword_rule(game_psn,        gaming, "플레이스테이션", 90).
keyword_rule(game_nintendo,   gaming, "닌텐도", 90).
keyword_rule(game_xbox,       gaming, "엑스박스", 90).
keyword_rule(game_nexon,      gaming, "넥슨", 90).
keyword_rule(game_blizzard,   gaming, "블리자드", 90).

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
keyword_rule(cafe_paulbassett, cafe, "폴바셋", 95).
keyword_rule(cafe_angelinus,  cafe, "엔제리너스", 95).
keyword_rule(cafe_gongcha,    cafe, "공차", 90).
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
keyword_rule(del_ddangyo,     delivery, "땡겨요", 90).

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
keyword_rule(food_izakaya,    food, "이자카야", 85).   % '이자'(이자소득) 부분충돌 방지 — 더 긴 키워드가 먼저
keyword_rule(food_pocha,      food, "포차", 80).
keyword_rule(food_hof,        food, "호프", 75).
%% 프랜차이즈·일반 음식 키워드 (골든 미포함 — 지역·개인 상호 커버)
keyword_rule(food_subway,     food, "써브웨이", 90).
keyword_rule(food_nbburger,   food, "노브랜드버거", 90).
keyword_rule(food_hansot,     food, "한솥", 85).
keyword_rule(food_tteok,      food, "떡볶이", 80).
keyword_rule(food_gopchang,   food, "곱창", 80).
keyword_rule(food_jokbal,     food, "족발", 80).
keyword_rule(food_mara,       food, "마라탕", 85).
keyword_rule(food_guksu,      food, "국수", 75).
keyword_rule(food_donkatsu,   food, "돈까스", 80).

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
keyword_rule(mart_nobrand,    groceries, "노브랜드", 80).
keyword_rule(mart_hanaro,     groceries, "하나로마트", 90).
keyword_rule(mart_cheonggwa,  groceries, "청과", 70).       % 늘푸른청과 등 지역 청과상
keyword_rule(mart_naver,      groceries, "네이버페이", 60).
keyword_rule(mart_word,       groceries, "마트", 70).

%% ── 생활용품·잡화 (마트와 분리 — 식료품이 아님) ──────────────────────────
keyword_rule(hh_daiso,        household, "다이소", 90).
keyword_rule(hh_ikea,         household, "이케아", 90).
keyword_rule(hh_ohou,         household, "오늘의집", 85).

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
keyword_rule(tr_toll,         transport, "통행료", 90).
%% ── 주차 (교통과 분리 — 별도 예산 항목으로 자주 추적됨) ────────────────────
keyword_rule(park_modu,       parking, "모두의주차장", 90).
keyword_rule(park_iparking,   parking, "아이파킹", 90).
keyword_rule(park_lot,        parking, "주차장", 90).
keyword_rule(park_word,       parking, "주차", 85).
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
keyword_rule(tel_hello,       telecom, "헬로모바일", 90).
keyword_rule(tel_altteul,     telecom, "알뜰폰", 85).
keyword_rule(tel_word,        telecom, "통신요금", 90).

%% ── 주거·공과금 ─────────────────────────────────────────────────────────
keyword_rule(util_kepco,      utilities, "한국전력", 95).
keyword_rule(util_kepco2,     utilities, "한전", 85).
keyword_rule(util_gas,        utilities, "도시가스", 95).
keyword_rule(util_water,      utilities, "수도요금", 95).
keyword_rule(util_elec,       utilities, "전기요금", 90).
keyword_rule(util_apt,        housing, "관리비", 90).
keyword_rule(housing_rent,    housing, "월세", 90).
keyword_rule(housing_jeonse,  housing, "전세", 80).

%% ── 반려동물 (동물병원은 일반 병원보다 앞 — first-match 로 pet 우선) ────────
keyword_rule(pet_animal_hosp, pet, "동물병원", 90).
keyword_rule(pet_friends,     pet, "펫프렌즈", 90).
keyword_rule(pet_store,       pet, "반려동물", 80).

%% ── 의료·약국 ───────────────────────────────────────────────────────────
keyword_rule(med_hospital,    medical, "병원", 90).
keyword_rule(med_clinic,      medical, "의원", 85).
keyword_rule(med_dental,      medical, "치과", 90).
keyword_rule(med_oriental,    medical, "한의원", 90).
keyword_rule(med_internal,    medical, "내과", 85).
keyword_rule(med_derma,       medical, "피부과", 88).
keyword_rule(pharm_word,      pharmacy, "약국", 95).

%% ── 교육·문화·의류·미용 ──────────────────────────────────────────────────
keyword_rule(edu_academy,     education, "학원", 90).
keyword_rule(edu_taekwondo,   education, "태권도", 85).
keyword_rule(edu_daycare,     education, "어린이집", 85).
keyword_rule(edu_word,        education, "교육", 75).
keyword_rule(cult_cgv,        culture, "cgv", 95).
keyword_rule(cult_lotte,      culture, "롯데시네마", 95).
keyword_rule(cult_megabox,    culture, "메가박스", 95).
keyword_rule(cult_kyobo,      culture, "교보문고", 90).
keyword_rule(cult_yes24,      culture, "예스24", 90).
keyword_rule(cult_aladin,     culture, "알라딘", 85).
keyword_rule(cult_bookstore,  culture, "서점", 75).
keyword_rule(cult_karaoke,    culture, "노래방", 85).
keyword_rule(cloth_uniqlo,    clothing, "유니클로", 95).
keyword_rule(cloth_musinsa,   clothing, "무신사", 95).
keyword_rule(cloth_zara,      clothing, "자라리테일", 90).
keyword_rule(cloth_spao,      clothing, "스파오", 90).
keyword_rule(cloth_nike,      clothing, "나이키", 90).
keyword_rule(cloth_adidas,    clothing, "아디다스", 90).
keyword_rule(beauty_oliveyoung, beauty, "올리브영", 95).
keyword_rule(beauty_innisfree, beauty, "이니스프리", 90).
keyword_rule(beauty_nail,     beauty, "네일", 80).
keyword_rule(beauty_hair,     beauty, "헤어", 80).
keyword_rule(beauty_salon,    beauty, "미용실", 90).

%% ── 운동·피트니스 (문화와 분리 — 정기 회원권 성격) ────────────────────────
keyword_rule(fit_gym,         fitness, "헬스장", 85).
keyword_rule(fit_fitness,     fitness, "피트니스", 85).
keyword_rule(fit_pilates,     fitness, "필라테스", 88).
keyword_rule(fit_yoga,        fitness, "요가원", 85).

%% ── 여행·숙박 ───────────────────────────────────────────────────────────
keyword_rule(travel_yanolja,  travel, "야놀자", 90).
keyword_rule(travel_goodchoice, travel, "여기어때", 90).
keyword_rule(travel_agoda,    travel, "아고다", 90).
keyword_rule(travel_airbnb,   travel, "에어비앤비", 90).
keyword_rule(travel_hotel,    travel, "호텔", 80).
keyword_rule(travel_pension,  travel, "펜션", 80).
keyword_rule(travel_resort,   travel, "리조트", 80).
keyword_rule(travel_koreanair, travel, "대한항공", 90).
keyword_rule(travel_asiana,   travel, "아시아나", 90).
keyword_rule(travel_jeju,     travel, "제주항공", 90).
keyword_rule(travel_hanatour, travel, "하나투어", 88).
keyword_rule(travel_word,     travel, "여행사", 75).

%% ── 보험·금융 ───────────────────────────────────────────────────────────
keyword_rule(ins_samsung,     insurance, "삼성생명", 90).
keyword_rule(ins_samsung_fire, insurance, "삼성화재", 90).
keyword_rule(ins_hyundai,     insurance, "현대해상", 90).
keyword_rule(ins_kb,          insurance, "kb손해보험", 90).
keyword_rule(ins_meritz,      insurance, "메리츠화재", 90).
keyword_rule(ins_hanwha,      insurance, "한화생명", 90).
keyword_rule(ins_word,        insurance, "보험", 80).
keyword_rule(fee_word,        finance_fee, "수수료", 85).
keyword_rule(fee_annual,      finance_fee, "연회비", 85).

%% ── 기부·후원 (지출이지만 별도 그룹으로 추적) ─────────────────────────────
keyword_rule(donate_unicef,   donation, "유니세프", 90).
keyword_rule(donate_worldvision, donation, "월드비전", 90).
keyword_rule(donate_greenumbrella, donation, "초록우산", 90).
keyword_rule(donate_word,     donation, "후원금", 80).

%% ── 현금·이체 ───────────────────────────────────────────────────────────
keyword_rule(atm_word,        atm, "atm", 90).
keyword_rule(atm_cd,          atm, "현금인출", 95).

%% ── 입금(양수) 전용 규칙: income_rule/4 ──────────────────────────────────
%% classify 는 Amount > 0 일 때만 이 규칙을 시도한다. 부호와 결합하지 않으면
%% 음수 '대출이자'(지출)가 interest(소득)로, '급여가압류'가 salary 로 뒤집힌다
%% — 원장 부호 의미를 파괴하는 오분류다 (적대 검증 발견).
%% '이자'/'급여' 는 부분문자열이라, 지출 계열에서 이자카야·이자녹스 등과 충돌하지
%% 않도록 income_rule 은 반드시 Amount>0 게이트 뒤에서만 시도된다.
income_rule(income_salary,   salary,       "급여", 95).
income_rule(income_salary2,  salary,       "월급", 95).
income_rule(income_bonus,    salary,       "상여", 90).
income_rule(income_pay,      salary,       "임금", 85).
income_rule(income_interest, interest,     "이자", 90).
income_rule(income_dividend, income_other, "배당", 85).
income_rule(income_refund,   income_other, "환급", 80).
income_rule(income_return,   income_other, "환불", 75).
income_rule(income_pension,  income_other, "연금", 85).   % 수령(양수)만 — 납입(음수)은 게이트에서 제외
income_rule(income_subsidy,  income_other, "지원금", 80). % 재난지원금·정부지원금 등
income_rule(income_grant,    income_other, "보조금", 80).
