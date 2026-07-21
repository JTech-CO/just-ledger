%% 이체 페어 매칭 (M4, 백서 §4.3 + INV-8).
%% 조건: 절대금액 '완전 일치', 부호 반대, 서로 다른 계좌, 일자 차 3일 이내,
%% 양측 모두 미매칭. 근사 금액 매칭은 절대 도입하지 않는다 (INV-8).
%%
%% 모호성 보수 정책 (결정 로그 2026-07-22): 후보가 '상호 유일'할 때만 페어로
%% 확정한다 — A 의 후보가 B 뿐이고 B 의 후보도 A 뿐일 때. 후보가 둘 이상이면
%% 어느 쪽을 골라도 거짓양성 위험이 있으므로 매칭하지 않는다. 거짓양성 0 이
%% 재현율보다 우선이다 (거짓양성 1건이 원장 신뢰를 무너뜨린다).
%%
%% 날짜는 정수 율리우스 적일로 비교한다 (float 미사용).

:- module(transfer, [transfer_pairs/2, date_to_days/2]).

%% "YYYY-MM-DD" → 정수 일수 (율리우스 적일, 순수 정수 산술)
date_to_days(DateS, Days) :-
    split_string(DateS, "-", "", [Ys, Ms, Ds]),
    number_string(Y, Ys), number_string(M, Ms), number_string(D, Ds),
    A is (14 - M) // 12,
    Y1 is Y + 4800 - A,
    M1 is M + 12*A - 3,
    Days is D + (153*M1 + 2)//5 + 365*Y1 + Y1//4 - Y1//100 + Y1//400 - 32045.

%% transfer_pairs(+Items, -Pairs)
%% Items: [_{txn_id, account_id, amount_minor, occurred_on, linked}, ...]
%% Pairs: [_{txn_a, txn_b, confidence, matched_by}, ...] (txn_a @< txn_b 정규화)
transfer_pairs(Items, Pairs) :-
    % 나쁜 항목 1건이 배치 전체를 무효화하지 않도록, 사실화 실패는 조용히 건너뛴다.
    % (0원·비정수 금액·형식이탈 날짜·링크된 txn 은 매칭 후보에서 빠질 뿐)
    foldl(collect_fact, Items, [], Facts),
    findall(P, mutual_unique_pair(Facts, P), Pairs0),
    sort(Pairs0, Pairs).

collect_fact(Item, Acc, Acc1) :-
    (   to_fact(Item, Fact)
    ->  Acc1 = [Fact | Acc]
    ;   Acc1 = Acc
    ).

to_fact(Item, t(Id, Acct, Amount, Days)) :-
    get_dict(linked, Item, false),     % 링크된 txn 은 후보 제외 (INV-5) — false 아니면 실패=스킵
    get_dict(txn_id, Item, Id),
    get_dict(account_id, Item, Acct),
    get_dict(amount_minor, Item, AmtS),
    number_string(Amount, AmtS),
    integer(Amount),
    Amount =\= 0,
    get_dict(occurred_on, Item, DateS),
    date_to_days(DateS, Days).

%% 백서 술어: 절대금액 일치·부호 반대·다른 계좌·3일 이내
candidate(Facts, t(IdA, AcctA, AmtA, DayA), t(IdB, AcctB, AmtB, DayB)) :-
    member(t(IdA, AcctA, AmtA, DayA), Facts),
    member(t(IdB, AcctB, AmtB, DayB), Facts),
    IdA \== IdB,
    AcctA \== AcctB,
    AmtB =:= -AmtA,                % 정확 일치 — 근사 금지 (INV-8)
    abs(DayA - DayB) =< 3.

%% 상호 유일: A 의 후보가 B 하나뿐이고, B 의 후보도 A 하나뿐
mutual_unique_pair(Facts, _{txn_a:A, txn_b:B, confidence:Conf, matched_by:"transfer_exact_unique"}) :-
    member(t(IdA, _, AmtA, _), Facts),
    AmtA < 0,                      % 출금 쪽에서 시작 (쌍 중복 열거 방지)
    findall(IdX, candidate(Facts, t(IdA, _, _, _), t(IdX, _, _, _)), [IdB]),
    findall(IdY, candidate(Facts, t(IdB, _, _, _), t(IdY, _, _, _)), [IdA]),
    sort_pair(IdA, IdB, A, B),
    confidence(Facts, IdA, IdB, Conf).

sort_pair(X, Y, X, Y) :- X @< Y, !.
sort_pair(X, Y, Y, X).

%% 신뢰도: 같은 날 100, 1일 차 90, 2일 85, 3일 80
confidence(Facts, IdA, IdB, Conf) :-
    member(t(IdA, _, _, DayA), Facts),
    member(t(IdB, _, _, DayB), Facts),
    Diff is abs(DayA - DayB),
    nth0(Diff, [100, 90, 85, 80], Conf).
