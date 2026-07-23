%% 정기 결제 탐지 (M4, 백서 §4.3).
%% 정규화 상점명이 동일한 '최근 6건'에 대해 우선순위대로 검출한다:
%%   1) recurring_6_stable    — 금액 상대편차 ≤ 5%, 간격 σ ≤ 3, 표준 주기
%%   2) recurring_var_amount  — 금액 변동(5%<dev≤20%)이나 간격이 더 견고(σ ≤ 2)한 구독
%%                              (사용량 과금·공과금형 — 금액은 흔들려도 청구일은 규칙적)
%%   3) recurring_monthly_dom — 간격 σ 는 흔들리나 '매월 같은 날(±3일)'에 앵커된 월납
%%                              (영업일 드리프트 등으로 raw 간격 분산이 큰 월 청구)
%% 어느 검출도 '표준 주기(period_class)'에 속하지 않으면 정기로 보지 않는다
%% — 임의의 안정 주기(예: 45일)를 구독으로 오탐하지 않기 위한 정밀도 가드다.
%% 전 과정 정수 — float 미사용 (INV-4 정신).

:- module(recurring, [recurring_series/2, period_class/2, date_dom/2]).

:- use_module(transfer, [date_to_days/2]).

%% recurring_series(+Items, -Series)
%% Items: [_{txn_id, merchant, amount_minor, occurred_on}, ...]
%% Series: [_{merchant, txn_ids, period_days, rule_name}, ...]
recurring_series(Items, Series) :-
    maplist(to_rec, Items, Recs),
    % 상점명별 그룹 — 상점당 최대 1개 계열 (detect/3 이 컷으로 확정)
    findall(M, member(r(_, M, _, _, _), Recs), Ms0),
    sort(Ms0, Merchants),
    findall(S, ( member(M, Merchants),
                 merchant_series(Recs, M, S) ), Series).

%% 사실화: r(Id, Merchant, AbsAmount, JulianDays, DayOfMonth)
to_rec(Item, r(Id, M, Amount, Days, Dom)) :-
    get_dict(txn_id, Item, Id),
    get_dict(merchant, Item, MS),
    atom_string(M, MS),
    get_dict(amount_minor, Item, AmtS),
    number_string(Amount0, AmtS),
    integer(Amount0),
    Amount is abs(Amount0),
    get_dict(occurred_on, Item, DateS),
    date_to_days(DateS, Days),
    date_dom(DateS, Dom).

%% "YYYY-MM-DD" → 일(day-of-month) 정수
date_dom(DateS, Dom) :-
    split_string(DateS, "-", "", [_, _, Ds]),
    number_string(Dom, Ds),
    integer(Dom), Dom >= 1, Dom =< 31.

%% 최근 6건을 뽑아 우선순위 검출에 넘긴다.
merchant_series(Recs, M, Series) :-
    findall(Days-Id-Amt-Dom, member(r(Id, M, Amt, Days, Dom), Recs), Q0),
    length(Q0, N), N >= 6,
    sort(0, @=<, Q0, Sorted),          % 날짜 오름차순 (Days 우선키)
    length(Last6, 6),
    append(_, Last6, Sorted),          % 최근 6건 (유일 분할)
    detect(Last6, M, Series).

%% 우선순위: strict → variable → monthly-dom. 첫 성공에서 컷 (상점당 1계열).
detect(Last6, M, S) :- detect_strict(Last6, M, S),   !.
detect(Last6, M, S) :- detect_variable(Last6, M, S), !.
detect(Last6, M, S) :- detect_dom(Last6, M, S),      !.

%% ── 1) 표준 안정 구독: 금액 ≤5% · 간격 σ ≤ 3 · 표준 주기 ────────────────────
detect_strict(Last6, M,
        _{merchant:MS, txn_ids:Ids, period_days:Period, rule_name:"recurring_6_stable"}) :-
    amounts(Last6, Amounts),
    amount_within(Amounts, 20),        % (Max-Min)*20 =< Max  ⇔  ≤ 5%
    dates(Last6, Dates),
    intervals(Dates, Ints),
    stable_intervals(Ints, 9),         % σ² ≤ 9  ⇔  σ ≤ 3
    period_of(Ints, Period),
    period_class(Period, _),           % 표준 주기여야 함 (정밀도 가드)
    ids(Last6, Ids),
    atom_string(M, MS).

%% ── 2) 변동액 구독: 5% < 금액편차 ≤ 20% 이나 간격이 더 견고(σ ≤ 2) ──────────
%% 금액이 흔들릴수록 청구 리듬은 더 규칙적이어야 오탐을 막는다 (사용량 과금·요금제).
detect_variable(Last6, M,
        _{merchant:MS, txn_ids:Ids, period_days:Period, rule_name:"recurring_var_amount"}) :-
    amounts(Last6, Amounts),
    \+ amount_within(Amounts, 20),     % 5% 초과 (초과분은 strict 가 이미 가져감)
    amount_within(Amounts, 5),         % 20% 이내
    dates(Last6, Dates),
    intervals(Dates, Ints),
    stable_intervals(Ints, 4),         % σ² ≤ 4  ⇔  σ ≤ 2 (더 엄격)
    period_of(Ints, Period),
    period_class(Period, _),
    ids(Last6, Ids),
    atom_string(M, MS).

%% ── 3) 월납(매월 같은 날 ±3): raw 간격 σ 는 커도 day-of-month 가 앵커됨 ───────
%% 금액은 안정(≤5%)을 요구한다 — 타이밍 가드를 푸는 대신 금액 가드는 조인다.
detect_dom(Last6, M,
        _{merchant:MS, txn_ids:Ids, period_days:Period, rule_name:"recurring_monthly_dom"}) :-
    amounts(Last6, Amounts),
    amount_within(Amounts, 20),        % ≤ 5%
    doms(Last6, Doms),
    dom_anchored(Doms, 3),             % 어떤 기준일 A 의 순환거리 ≤ 3 안에 전부
    dates(Last6, Dates),
    intervals(Dates, Ints),
    period_of(Ints, Period),
    period_class(Period, monthly),     % 월 주기(27..32)로 한정
    ids(Last6, Ids),
    atom_string(M, MS).

%% ── 뽑개 ────────────────────────────────────────────────────────────────
amounts(Last6, As) :- findall(A, member(_-_-A-_, Last6), As).
dates(Last6, Ds)   :- findall(D, member(D-_-_-_, Last6), Ds).
ids(Last6, Is)     :- findall(I, member(_-I-_-_, Last6), Is).
doms(Last6, Ds)    :- findall(Dom, member(_-_-_-Dom, Last6), Ds).

%% 금액 상대편차 가드: (Max-Min)*K =< Max  ⇔  편차 ≤ 1/K.  K=20→5%, K=5→20%.
amount_within(Amounts, K) :-
    max_list(Amounts, Max), min_list(Amounts, Min),
    Max > 0,
    (Max - Min) * K =< Max.

intervals([_], []).
intervals([A, B | T], [I | Is]) :-
    I is B - A,
    intervals([B | T], Is).

%% 간격 표준편차 가드 (정수): Σ(N·Iᵢ - ΣI)² ≤ VarBound·N³  ⇔  σ² ≤ VarBound.
stable_intervals(Ints, VarBound) :-
    length(Ints, N), N > 0,
    sum_list(Ints, Sum),
    foldl([I, Acc0, Acc]>>(D is N*I - Sum, Acc is Acc0 + D*D), Ints, 0, SqSum),
    SqSum =< VarBound * N * N * N.

%% 주기 = 평균 간격 반올림 (정수 나눗셈, NEAREST 계열: (Sum + N//2)//N)
period_of(Ints, Period) :-
    length(Ints, N), N > 0,
    sum_list(Ints, Sum),
    Period is (Sum + N // 2) // N.

%% day-of-month 앵커: 기준일 A(1..31)가 존재해 모든 Dom 이 A 로부터 순환거리 ≤ Tol.
%% 순환거리(주기 31 근사)로 월말(30)·월초(1) 인접을 올바로 처리한다.
dom_anchored(Doms, Tol) :-
    between(1, 31, A),
    forall(member(D, Doms), (dom_circular_dist(A, D, Dist), Dist =< Tol)),
    !.

dom_circular_dist(A, B, Dist) :-
    Raw is abs(A - B),
    Wrap is 31 - Raw,
    Dist is min(Raw, Wrap).

%% ── 표준 결제 주기 분류 (Inspector·예산 요약용, 정밀도 가드) ─────────────────
%% 인식되는 청구 리듬만 정기로 취급한다. 밴드 밖(예: 45일)은 정기 아님.
period_class(P, weekly)     :- P >= 6,   P =< 8.
period_class(P, biweekly)   :- P >= 13,  P =< 16.
period_class(P, monthly)    :- P >= 27,  P =< 32.
period_class(P, bimonthly)  :- P >= 58,  P =< 63.
period_class(P, quarterly)  :- P >= 88,  P =< 95.
period_class(P, semiannual) :- P >= 178, P =< 190.
period_class(P, annual)     :- P >= 358, P =< 372.
