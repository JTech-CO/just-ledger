%% 정기 결제 탐지 (M4, 백서 §4.3).
%% 정규화 상점명이 동일한 '최근 6건'에 대해:
%%   - 금액 상대편차 ≤ 5%  → 정수 산술: (Max - Min) * 20 =< Max
%%   - 결제 간격 표준편차 ≤ 3일 → 정수 산술: Σ(N·Iᵢ - ΣI)² ≤ 9·N³
%% 이면 주기 결제로 판정하고 주기(반올림 평균 간격, 일)를 추정한다.
%% 전 과정 정수 — float 미사용 (INV-4 정신).

:- module(recurring, [recurring_series/2]).

:- use_module(transfer, [date_to_days/2]).

%% recurring_series(+Items, -Series)
%% Items: [_{txn_id, merchant, amount_minor, occurred_on}, ...]
%% Series: [_{merchant, txn_ids, period_days, rule_name}, ...]
recurring_series(Items, Series) :-
    maplist(to_rec, Items, Recs),
    % 상점명별 그룹
    findall(M, member(r(_, M, _, _), Recs), Ms0),
    sort(Ms0, Merchants),
    findall(S, ( member(M, Merchants),
                 merchant_series(Recs, M, S) ), Series).

to_rec(Item, r(Id, M, Amount, Days)) :-
    get_dict(txn_id, Item, Id),
    get_dict(merchant, Item, MS),
    atom_string(M, MS),
    get_dict(amount_minor, Item, AmtS),
    number_string(Amount0, AmtS),
    integer(Amount0),
    Amount is abs(Amount0),
    get_dict(occurred_on, Item, DateS),
    date_to_days(DateS, Days).

merchant_series(Recs, M, _{merchant:MS, txn_ids:Ids, period_days:Period, rule_name:"recurring_6_stable"}) :-
    findall(Days-Id-Amt, member(r(Id, M, Amt, Days), Recs), Triples0),
    length(Triples0, N), N >= 6,
    % 최근 6건 (날짜 오름차순 정렬 후 마지막 6개)
    sort(0, @=<, Triples0, Sorted),
    length(Last6, 6),
    append(_, Last6, Sorted),
    findall(A, member(_-_-A, Last6), Amounts),
    max_list(Amounts, Max), min_list(Amounts, Min),
    Max > 0,
    (Max - Min) * 20 =< Max,                    % 상대편차 ≤ 5%
    findall(D, member(D-_-_, Last6), Dates),
    intervals(Dates, Ints),
    stable_intervals(Ints),
    period_of(Ints, Period),
    Period >= 1,
    findall(Id, member(_-Id-_, Last6), Ids),
    atom_string(M, MS).

intervals([_], []).
intervals([A, B | T], [I | Is]) :-
    I is B - A,
    intervals([B | T], Is).

%% 표준편차 ≤ 3일 (정수): Σ(N·Iᵢ - ΣI)² ≤ 9·N³  ⇔  σ² ≤ 9
stable_intervals(Ints) :-
    length(Ints, N), N > 0,
    sum_list(Ints, Sum),
    foldl([I, Acc0, Acc]>>(D is N*I - Sum, Acc is Acc0 + D*D), Ints, 0, SqSum),
    SqSum * 1 =< 9 * N * N * N.

%% 주기 = 평균 간격 반올림 (정수 나눗셈)
period_of(Ints, Period) :-
    length(Ints, N),
    sum_list(Ints, Sum),
    Period is (Sum + N // 2) // N.
