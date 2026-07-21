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

test(amount_deviation_over_5pct_rejected) :-
    % 여섯 번째 금액이 10% 큰 경우 — 미탐지
    findall(I, between(1, 6, I), Ns),
    maplist([I, Item]>>(
            format(string(D), "2026-~|~`0t~d~2+-14", [I]),
            ( I =:= 6 -> A = "-18700" ; A = "-17000" ),
            ritem(I, "구독서비스", A, D, Item)
        ), Ns, Items),
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

:- end_tests(recurring_detection).
