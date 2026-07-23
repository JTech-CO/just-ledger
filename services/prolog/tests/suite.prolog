%% M4 검증 스위트 (make test-classify).
%%   DoD 1: 골든 500건 분류 정확도 ≥ 0.90
%%   DoD 2: 이체 페어 매칭 거짓양성 0 (INV-8) — 함정 케이스 전수
%%   DoD 3: 1,000건 분류 1초 이내
%%   DoD 6: 모든 분류 결과에 근거 규칙명 동반

:- prolog_load_context(directory, Dir),
   atom_concat(Dir, '/../src', Src),
   asserta(user:file_search_path(src, Src)),
   atom_concat(Dir, '/../../..', Root),
   asserta(user:file_search_path(repo, Root)).

:- use_module(src(classify)).
:- use_module(src(rules)).
:- use_module(src(transfer)).
:- use_module(src(recurring)).
:- use_module(library(json)).

:- use_module(library(plunit)).

%% ── 골든 로드 ───────────────────────────────────────────────────────────
load_golden(Rows) :-
    absolute_file_name(repo('fixtures/classify/golden.jsonl'), Path, [access(read)]),
    setup_call_cleanup(
        open(Path, read, In, [encoding(utf8)]),
        read_jsonl(In, Rows),
        close(In)).

read_jsonl(In, Rows) :-
    read_line_to_string(In, Line),
    (   Line == end_of_file
    ->  Rows = []
    ;   Line == ""
    ->  read_jsonl(In, Rows)
    ;   open_string(Line, S),
        json_read_dict(S, Row),
        close(S),
        Rows = [Row | Rest],
        read_jsonl(In, Rest)
    ).

%% uuid 모양 문자열 생성 (테스트용 — 형식만)
mk_uuid(N, U) :-
    format(string(U), "00000000-0000-0000-0000-~|~`0t~d~12+", [N]).

:- begin_tests(classify_golden).

%% 람다 안에서는 dict 점 표기가 확장되지 않는다 — 보조 술어로 접근한다.
row_features(Row, M, Amt, Expected) :-
    get_dict(merchant, Row, MS),
    atom_string(M0, MS),
    downcase_atom(M0, M),
    get_dict(amount_minor, Row, AmtS),
    number_string(Amt, AmtS),
    get_dict(expected, Row, Expected).

score_row(Row, Acc0, Acc) :-
    row_features(Row, M, Amt, Expected),
    classify_one(M, Amt, Cat, Rule, _Conf),
    assertion(Rule \== ''),          % DoD 6: 근거 규칙명 항상 존재
    atom_string(Cat, CatS),
    (   CatS == Expected
    ->  Acc is Acc0 + 1
    ;   Acc = Acc0
    ).

test(golden_accuracy_and_rule_names) :-
    load_golden(Rows),
    length(Rows, Total),
    assertion(Total =:= 500),
    foldl(score_row, Rows, 0, Correct),
    Accuracy is Correct * 100 // Total,
    format(user_error, "분류 정확도: ~w/~w (~w%)~n", [Correct, Total, Accuracy]),
    % DoD 1: ≥ 0.90
    assertion(Correct * 10 >= Total * 9).

golden_item(Rows, L, I, item(M, Amt)) :-
    J is ((I - 1) mod L) + 1,
    nth1(J, Rows, Row),
    row_features(Row, M, Amt, _).

test(thousand_items_under_one_second) :-
    load_golden(Rows),
    length(Rows, L),
    findall(Item, ( between(1, 1000, I), golden_item(Rows, L, I, Item) ), Items),
    length(Items, NI),
    assertion(NI =:= 1000),
    get_time(T0),
    forall(member(item(M, Amt), Items),
           classify_one(M, Amt, _, _, _)),
    get_time(T1),
    Elapsed is T1 - T0,
    format(user_error, "1,000건 분류: ~3f초~n", [Elapsed]),
    % DoD 3: 1초 이내
    assertion(Elapsed < 1.0).

%% 소득 키워드는 부호와 결합해야 한다 (적대 검증 발견의 회귀)
test(income_keyword_requires_positive) :-
    % 음수 '이자'(지출)는 interest(소득)가 아니어야 한다
    classify_one('대출이자', -50000, Cat1, _, _),
    assertion(Cat1 \== interest),
    % 양수 '이자'(소득)는 interest
    classify_one('예금이자', 1250, interest, _, _),
    % 음수 '급여'는 salary 가 아니어야 한다
    classify_one('급여가압류', -100000, Cat2, _, _),
    assertion(Cat2 \== salary),
    classify_one('급여', 3200000, salary, _, _).

test(substring_collision_izakaya_is_food) :-
    % '이자카야' 는 '이자' 부분충돌 없이 food (더 긴 키워드 우선 + 음수)
    classify_one('이자카야', -30000, food, _, _).

test(ordering_coupang_variants) :-
    classify_one('쿠팡이츠', -20000, delivery, _, _),
    classify_one('쿠팡와우멤버십', -4990, subscription, _, _),
    classify_one('쿠팡', -35000, groceries, _, _).

:- end_tests(classify_golden).

%% ── 확장 분류 규칙 (신규 브랜드·카테고리) + 예산 그룹 추론 ──────────────────
:- begin_tests(classify_rules).

cat(Merchant, Amount, Cat) :-
    classify_one(Merchant, Amount, C, Rule, _),
    assertion(Rule \== ''),           % DoD 6: 근거 규칙명 항상 존재
    Cat = C.

%% 신규 카테고리 각각을 대표 브랜드로 검증 (분류 + 근거 규칙명 동반)
test(new_category_brands) :-
    cat('스팀', -22000, gaming),
    cat('넥슨결제', -30000, gaming),
    cat('구글플레이', -5500, appstore),
    cat('앱스토어결제', -1200, appstore),
    cat('행복동물병원', -45000, pet),        % '동물병원' 은 medical '병원' 보다 앞
    cat('펫프렌즈', -30000, pet),
    cat('모두의주차장', -3000, parking),
    cat('강남역주차장', -5000, parking),      % 일반 '주차장' 키워드
    cat('다이소 강남점', -12000, household),
    cat('오늘의집', -34000, household),
    cat('짐박스헬스장', -70000, fitness),
    cat('강남필라테스', -180000, fitness),
    cat('유니세프후원', -30000, donation),
    cat('월드비전 정기후원', -10000, donation).

%% 기존 카테고리 확장 브랜드 + 앱마켓/구독 분리
test(expanded_existing_category_brands) :-
    cat('폴바셋 역삼점', -6500, cafe),
    cat('공차 홍대점', -4800, cafe),
    cat('써브웨이 강남점', -8900, food),
    cat('명동왕곱창', -32000, food),          % '곱창' 일반 키워드
    cat('마라탕집', -13000, food),
    cat('노션', -9900, subscription),
    cat('어도비 크리에이티브클라우드', -24000, subscription),
    cat('넷플릭스', -17000, subscription),    % 구독은 appstore 로 새지 않음
    cat('하나투어', -450000, travel),
    cat('제주 오션뷰펜션', -120000, travel),
    cat('메리츠화재 자동차보험', -88000, insurance).

%% 오분류 방지(음성 규칙)·순서 함정·부호 게이트 — 회귀 방지
test(negative_rules_and_order_traps) :-
    % 사람 병원은 그대로 medical (동물병원 규칙에 안 새어감)
    cat('서울대학교병원', -30000, medical),
    % '굿네이버스'(자선) 는 '버스'(transport) 를 포함하지만 최상단 가드로 donation
    classify_one('굿네이버스 정기후원', -10000, GC, GR, _),
    assertion(GC == donation), assertion(GR == guard_goodneighbors),
    % '스타벅스' 가 짧은 키워드에 가로채이지 않고 cafe 로 남음
    cat('스타벅스 강남점', -5600, cafe),
    % 순서 함정: '노브랜드버거'(food) 는 '노브랜드'(groceries) 보다 앞
    cat('노브랜드버거 서면점', -7500, food),
    % 양수 수령만 income — 음수(납입·환수)는 뒤집히지 않음 (원장 부호 의미 보존)
    cat('국민연금공단', 520000, income_other),
    cat('정부재난지원금', 250000, income_other),
    classify_one('국민연금', -100000, C1, _, _), assertion(C1 \== income_other),
    classify_one('정부지원금환수', -200000, C2, _, _), assertion(C2 \== income_other).

test(category_group_totality_and_values) :-
    % 모든 카테고리는 고정 집합의 그룹 하나에 정확히 매핑된다
    forall(category(C),
           ( findall(G, category_group(C, G), Gs),
             assertion(Gs = [_]) )),
    forall(category_group(_, G),
           assertion(memberchk(G, [essential, lifestyle, income, transfer, other]))).

test(category_group_spot_checks) :-
    assertion(category_group(food, essential)),
    assertion(category_group(cafe, lifestyle)),
    assertion(category_group(salary, income)),
    assertion(category_group(atm, transfer)),
    assertion(category_group(unknown, other)),
    % 신규 카테고리도 그룹에 편입됨
    assertion(category_group(gaming, lifestyle)),
    assertion(category_group(parking, essential)),
    assertion(category_group(household, essential)),
    assertion(category_group(fitness, lifestyle)),
    assertion(category_group(donation, lifestyle)),
    assertion(category_group(appstore, lifestyle)).

:- end_tests(classify_rules).

:- begin_tests(transfer_matching).

%% 헬퍼: 아이템 dict
titem(N, Acct, AmtS, Date, Linked, _{txn_id:U, account_id:Acct, amount_minor:AmtS,
                                     occurred_on:Date, linked:Linked}) :-
    mk_uuid(N, U).

test(pure_pair_matched) :-
    titem(1, "acct-a", "-50000", "2026-07-01", false, A),
    titem(2, "acct-b", "50000", "2026-07-02", false, B),
    transfer_pairs([A, B], Pairs),
    assertion(Pairs = [_]),
    Pairs = [P],
    assertion(P.matched_by == "transfer_exact_unique"),
    assertion(P.confidence =:= 90).

%% ── 거짓양성 0 함정 케이스 (INV-8) — 아래 전부 매칭 0 이어야 한다 ──────────
test(no_match_four_days_apart) :-
    titem(1, "acct-a", "-50000", "2026-07-01", false, A),
    titem(2, "acct-b", "50000", "2026-07-05", false, B),
    transfer_pairs([A, B], Pairs),
    assertion(Pairs == []).

test(no_match_same_account) :-
    titem(1, "acct-a", "-50000", "2026-07-01", false, A),
    titem(2, "acct-a", "50000", "2026-07-01", false, B),
    transfer_pairs([A, B], Pairs),
    assertion(Pairs == []).

test(no_match_same_sign) :-
    titem(1, "acct-a", "-50000", "2026-07-01", false, A),
    titem(2, "acct-b", "-50000", "2026-07-01", false, B),
    transfer_pairs([A, B], Pairs),
    assertion(Pairs == []).

test(no_match_amount_differs_by_one) :-
    % 1원 차이 — 근사 매칭 금지 (INV-8)
    titem(1, "acct-a", "-50000", "2026-07-01", false, A),
    titem(2, "acct-b", "49999", "2026-07-01", false, B),
    transfer_pairs([A, B], Pairs),
    assertion(Pairs == []).

test(no_match_already_linked) :-
    titem(1, "acct-a", "-50000", "2026-07-01", true, A),
    titem(2, "acct-b", "50000", "2026-07-01", false, B),
    transfer_pairs([A, B], Pairs),
    assertion(Pairs == []).

test(no_match_ambiguous_two_candidates) :-
    % 출금 1건에 같은 금액 입금 2건 — 모호 → 보수 정책상 매칭 0
    titem(1, "acct-a", "-50000", "2026-07-01", false, A),
    titem(2, "acct-b", "50000", "2026-07-01", false, B),
    titem(3, "acct-c", "50000", "2026-07-02", false, C),
    transfer_pairs([A, B, C], Pairs),
    assertion(Pairs == []).

test(two_disjoint_pairs_both_matched) :-
    % 금액이 달라 서로 간섭하지 않는 두 쌍 — 둘 다 매칭
    titem(1, "acct-a", "-50000", "2026-07-01", false, A1),
    titem(2, "acct-b", "50000", "2026-07-01", false, B1),
    titem(3, "acct-a", "-70000", "2026-07-03", false, A2),
    titem(4, "acct-c", "70000", "2026-07-03", false, B2),
    transfer_pairs([A1, B1, A2, B2], Pairs),
    length(Pairs, N),
    assertion(N =:= 2).

test(pair_normalized_order) :-
    % 응답 쌍은 txn_a @< txn_b (transfer_link 계약 정합)
    titem(9, "acct-a", "-1000", "2026-07-01", false, A),
    titem(1, "acct-b", "1000", "2026-07-01", false, B),
    transfer_pairs([A, B], [P]),
    assertion(P.txn_a @< P.txn_b).

test(date_days_integer) :-
    date_to_days("2026-07-22", D1),
    date_to_days("2026-07-19", D2),
    assertion(D1 - D2 =:= 3),
    date_to_days("2026-03-01", D3),
    date_to_days("2026-02-28", D4),
    assertion(D3 - D4 =:= 1).

%% ── 다통화 이체 (정수 교차곱 정확 매칭 — 근사 절대 없음, INV-8) ─────────────
%% fxitem: fx = {num, den}. 기저환산액 base = amount_minor * num / den.
fxitem(N, Acct, AmtS, Date, Num, Den,
       _{txn_id:U, account_id:Acct, amount_minor:AmtS, occurred_on:Date,
         linked:false, fx:_{num:Num, den:Den}}) :-
    mk_uuid(N, U).

test(fx_pair_exact_rational_matched) :-
    % 유리수 환율(1단위=8.5 기저 → num=17,den=2)로 딱 떨어지는 이체.
    % 외화 -2000 * 17/2 = -17000 기저 ; 기저통화 +17000 → 정확 반대.
    fxitem(1, "acct-fx", "-2000", "2026-07-01", "17", "2", A),
    titem(2, "acct-krw", "17000", "2026-07-02", false, B),
    transfer_pairs([A, B], Pairs),
    assertion(Pairs = [_]),
    Pairs = [P],
    assertion(P.matched_by == "transfer_fx_exact_unique"),
    assertion(P.confidence =:= 90).

test(fx_pair_off_by_one_minor_rejected) :-
    % 기저환산이 1 최소단위 어긋남 — 근사 매칭 금지 → 매칭 0 (INV-8).
    fxitem(1, "acct-fx", "-2000", "2026-07-01", "17", "2", A),
    titem(2, "acct-krw", "17001", "2026-07-02", false, B),
    transfer_pairs([A, B], Pairs),
    assertion(Pairs == []).

test(fx_integer_rate_usd_krw_matched) :-
    % 정수 환율(1센트=13원): USD -100000센트 * 13 = -1,300,000 ; KRW +1,300,000.
    fxitem(1, "acct-usd", "-100000", "2026-07-01", "13", "1", A),
    titem(2, "acct-krw", "1300000", "2026-07-01", false, B),
    transfer_pairs([A, B], Pairs),
    assertion(Pairs = [_]),
    Pairs = [P],
    assertion(P.matched_by == "transfer_fx_exact_unique"),
    assertion(P.confidence =:= 100).

test(fx_pair_ambiguous_rejected) :-
    % 외화 출금 1건에 기저환산이 정확히 맞는 입금 2건 → 모호 → 보수적으로 매칭 0.
    fxitem(1, "acct-usd", "-100000", "2026-07-01", "13", "1", A),
    titem(2, "acct-krw", "1300000", "2026-07-01", false, B),
    titem(3, "acct-krw2", "1300000", "2026-07-02", false, C),
    transfer_pairs([A, B, C], Pairs),
    assertion(Pairs == []).

test(fx_invalid_den_skips_item) :-
    % den 이 0 이면 fx 사실화 실패 → 해당 항목은 후보에서 제외 → 매칭 0.
    fxitem(1, "acct-usd", "-100000", "2026-07-01", "13", "0", A),
    titem(2, "acct-krw", "1300000", "2026-07-01", false, B),
    transfer_pairs([A, B], Pairs),
    assertion(Pairs == []).

test(fx_wrong_rate_no_false_positive) :-
    % 실제 정산 환율과 다른 rate 를 실으면 기저환산이 어긋나 매칭되지 않는다
    % (은행 스프레드로 딱 떨어지지 않는 현실 케이스 — 거짓양성 0 유지).
    fxitem(1, "acct-usd", "-100000", "2026-07-01", "12", "1", A),
    titem(2, "acct-krw", "1300000", "2026-07-01", false, B),
    transfer_pairs([A, B], Pairs),
    assertion(Pairs == []).

test(plain_same_currency_still_exact_label) :-
    % fx 없는 동일통화 쌍은 기존과 동일하게 transfer_exact_unique 로 라벨.
    titem(1, "acct-a", "-50000", "2026-07-01", false, A),
    titem(2, "acct-b", "50000", "2026-07-01", false, B),
    transfer_pairs([A, B], [P]),
    assertion(P.matched_by == "transfer_exact_unique").

:- end_tests(transfer_matching).

:- begin_tests(recurring_detection).

ritem(N, M, AmtS, Date, _{txn_id:U, merchant:M, amount_minor:AmtS, occurred_on:Date}) :-
    mk_uuid(N, U).

test(monthly_series_detected) :-
    % 매월 14일 넷플릭스 17,000원 × 6
    findall(I, between(1, 6, I), Ns),
    maplist([I, Item]>>(
            MM is I,
            format(string(D), "2026-~|~`0t~d~2+-14", [MM]),
            ritem(I, "넷플릭스", "-17000", D, Item)
        ), Ns, Items),
    recurring_series(Items, Series),
    assertion(Series = [_]),
    Series = [S],
    assertion(S.period_days >= 28),
    assertion(S.period_days =< 31),
    assertion(S.rule_name == "recurring_6_stable").

test(amount_deviation_within_20pct_is_variable) :-
    % 여섯 번째 금액이 ~9% 큰 경우 — 간격이 견고하면 '변동액 구독'으로 탐지
    findall(I, between(1, 6, I), Ns),
    maplist([I, Item]>>(
            format(string(D), "2026-~|~`0t~d~2+-14", [I]),
            ( I =:= 6 -> A = "-18700" ; A = "-17000" ),
            ritem(I, "구독서비스", A, D, Item)
        ), Ns, Items),
    recurring_series(Items, Series),
    assertion(Series = [_]),
    Series = [S],
    assertion(S.rule_name == "recurring_var_amount"),
    assertion(S.period_days >= 28), assertion(S.period_days =< 31).

test(amount_deviation_over_20pct_rejected) :-
    % 여섯 번째 금액이 40% 큰 경우 — 변동 허용범위(20%) 초과 → 미탐지
    findall(I, between(1, 6, I), Ns),
    maplist([I, Item]>>(
            format(string(D), "2026-~|~`0t~d~2+-14", [I]),
            ( I =:= 6 -> A = "-24000" ; A = "-17000" ),
            ritem(I, "널뛰기상점", A, D, Item)
        ), Ns, Items),
    recurring_series(Items, Series),
    assertion(Series == []).

test(variable_amount_utility_detected) :-
    % 공과금형: 매월 25일, 금액이 12%까지 흔들리지만 청구일은 견고 → recurring_var_amount
    Amts = ["-42000", "-45000", "-40000", "-44000", "-41000", "-45000"],
    findall(Item, ( nth1(I, Amts, A),
                    format(string(D), "2026-~|~`0t~d~2+-25", [I]),
                    ritem(I, "도시가스공사", A, D, Item) ), Items),
    recurring_series(Items, Series),
    assertion(Series = [_]),
    Series = [S],
    assertion(S.rule_name == "recurring_var_amount").

test(variable_amount_irregular_interval_rejected) :-
    % 금액 변동 + 간격도 불규칙 → 변동액 검출도 거부 (간격 견고성 요구)
    Dates = ["2026-01-01", "2026-01-08", "2026-02-20", "2026-02-27", "2026-04-10", "2026-04-17"],
    Amts  = ["-40000", "-45000", "-41000", "-44000", "-42000", "-46000"],
    findall(Item, ( nth1(I, Dates, D), nth1(I, Amts, A),
                    ritem(I, "들쭉상점", A, D, Item) ), Items),
    recurring_series(Items, Series),
    assertion(Series == []).

test(monthly_dom_anchored_detected) :-
    % 결제일이 1일·5일로 드리프트 → raw 간격 σ>3 이라 strict 는 실패하지만,
    % '매월 같은 날(±3)' 앵커가 있어 recurring_monthly_dom 으로 탐지된다.
    Dates = ["2026-01-01", "2026-02-05", "2026-03-01", "2026-04-05", "2026-05-01", "2026-06-05"],
    findall(Item, ( nth1(I, Dates, D), ritem(I, "수도사업소", "-12000", D, Item) ), Items),
    recurring_series(Items, Series),
    assertion(Series = [_]),
    Series = [S],
    assertion(S.rule_name == "recurring_monthly_dom"),
    assertion(S.period_days >= 27), assertion(S.period_days =< 32).

test(weekly_series_detected) :-
    % 매주(7일) 6회 — 표준 주기(weekly) 로 recurring_6_stable
    Dates = ["2026-03-02", "2026-03-09", "2026-03-16", "2026-03-23", "2026-03-30", "2026-04-06"],
    findall(Item, ( nth1(I, Dates, D), ritem(I, "주간정기", "-3300", D, Item) ), Items),
    recurring_series(Items, Series),
    assertion(Series = [_]),
    Series = [S],
    assertion(S.period_days =:= 7),
    assertion(S.rule_name == "recurring_6_stable").

test(quarterly_series_detected) :-
    % 분기(약 91일) 6회 — 표준 주기(quarterly) 로 탐지, 주기 88..95
    Dates = ["2025-01-15", "2025-04-15", "2025-07-15", "2025-10-15", "2026-01-15", "2026-04-15"],
    findall(Item, ( nth1(I, Dates, D), ritem(I, "분기구독", "-30000", D, Item) ), Items),
    recurring_series(Items, Series),
    assertion(Series = [_]),
    Series = [S],
    assertion(S.period_days >= 88), assertion(S.period_days =< 95).

test(odd_period_stable_rejected) :-
    % 45일 간격으로 매우 안정적이지만 표준 청구 리듬 밖 → 정기 아님 (정밀도 가드)
    Dates = ["2026-01-01", "2026-02-15", "2026-04-01", "2026-05-16", "2026-06-30", "2026-08-14"],
    findall(Item, ( nth1(I, Dates, D), ritem(I, "이상주기상점", "-9000", D, Item) ), Items),
    recurring_series(Items, Series),
    assertion(Series == []).

test(irregular_interval_rejected) :-
    % 간격이 5, 40, 5, 40, 5 일 — 표준편차 초과 → 미탐지
    Dates = ["2026-01-01", "2026-01-06", "2026-02-15", "2026-02-20", "2026-04-01", "2026-04-06"],
    findall(Item, ( nth1(I, Dates, D), ritem(I, "불규칙상점", "-10000", D, Item) ), Items),
    recurring_series(Items, Series),
    assertion(Series == []).

test(five_occurrences_not_enough) :-
    findall(Item, ( between(1, 5, I),
                    format(string(D), "2026-~|~`0t~d~2+-14", [I]),
                    ritem(I, "다섯번상점", "-9900", D, Item) ), Items),
    recurring_series(Items, Series),
    assertion(Series == []).

test(period_class_bands) :-
    % 표준 주기 밴드 매핑 (Inspector·예산 요약용)
    period_class(7, weekly),
    period_class(14, biweekly),
    period_class(30, monthly),
    period_class(91, quarterly),
    period_class(365, annual),
    assertion(\+ period_class(45, _)),      % 표준 밖
    assertion(\+ period_class(100, _)).

test(date_dom_parses_day) :-
    date_dom("2026-07-25", 25),
    date_dom("2026-02-01", 1),
    assertion(\+ date_dom("2026-07-32", _)).   % 32일은 유효 day-of-month 아님

:- end_tests(recurring_detection).
