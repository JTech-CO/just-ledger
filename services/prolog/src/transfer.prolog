%% 이체 페어 매칭 (M4, 백서 §4.3 + INV-8).
%% 조건: 기저통화 환산액 '완전 일치'(부호 반대), 서로 다른 계좌, 일자 차 3일 이내,
%% 양측 모두 미매칭. 근사 금액 매칭은 절대 도입하지 않는다 (INV-8).
%%
%% 다통화 이체: 각 항목은 선택적으로 fx = {num, den}(계약 common.schema.json#ratio,
%% 유리수 쌍)을 실을 수 있다. 의미는 base_minor = amount_minor * num / den.
%% 매칭은 두 항목의 기저환산액이 '정확히' 반대일 때만 성립한다:
%%   AmtA·NumA·DenB  =:=  -(AmtB·NumB·DenA)      (정수 교차곱 — 나눗셈·부동소수점 없음)
%% 은행이 실제 정산 환율로 딱 떨어질 때만 매칭되고, 최소단위 1원이라도 어긋나면
%% 매칭하지 않는다 → 근사 없음. fx 미지정 항목은 num=den=1(동일통화)로, 기존
%% 동일통화 정확 일치(AmtA =:= -AmtB)와 바이트 단위로 동일하게 동작한다.
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
%% Items: [_{txn_id, account_id, amount_minor, occurred_on, linked, [fx:{num,den}]}, ...]
%% Pairs: [_{txn_a, txn_b, confidence, matched_by}, ...] (txn_a @< txn_b 정규화)
transfer_pairs(Items, Pairs) :-
    % 나쁜 항목 1건이 배치 전체를 무효화하지 않도록, 사실화 실패는 조용히 건너뛴다.
    % (0원·비정수 금액·형식이탈 날짜·잘못된 fx·링크된 txn 은 매칭 후보에서 빠질 뿐)
    foldl(collect_fact, Items, [], Facts),
    findall(P, mutual_unique_pair(Facts, P), Pairs0),
    sort(Pairs0, Pairs).

collect_fact(Item, Acc, Acc1) :-
    (   to_fact(Item, Fact)
    ->  Acc1 = [Fact | Acc]
    ;   Acc1 = Acc
    ).

%% 사실: t(Id, Acct, Amount, Days, Num, Den).  Num/Den 은 기저통화 환산 유리수(>0).
to_fact(Item, t(Id, Acct, Amount, Days, Num, Den)) :-
    get_dict(linked, Item, false),     % 링크된 txn 은 후보 제외 (INV-5) — false 아니면 실패=스킵
    get_dict(txn_id, Item, Id),
    get_dict(account_id, Item, Acct),
    get_dict(amount_minor, Item, AmtS),
    to_int(AmtS, Amount),
    Amount =\= 0,
    get_dict(occurred_on, Item, DateS),
    date_to_days(DateS, Days),
    item_fx(Item, Num, Den).

%% fx 미지정 → 1/1(동일통화). 지정 시 유리수 쌍을 정수로 읽고 양수 검증(잘못되면 실패=스킵).
item_fx(Item, Num, Den) :-
    (   get_dict(fx, Item, FX)
    ->  get_dict(num, FX, NumS), to_int(NumS, Num),
        get_dict(den, FX, DenS), to_int(DenS, Den),
        Num > 0, Den > 0
    ;   Num = 1, Den = 1
    ).

%% 계약 경계는 금액을 '문자열'로 준다(INV-4). 테스트 편의로 정수도 받는다.
to_int(X, X)  :- integer(X), !.
to_int(S, I)  :- number_string(I, S), integer(I).

%% 후보: 기저환산액 정확 반대·다른 계좌·3일 이내 (근사 금지 — INV-8)
candidate(Facts,
          t(IdA, AcctA, AmtA, DayA, NumA, DenA),
          t(IdB, AcctB, AmtB, DayB, NumB, DenB)) :-
    member(t(IdA, AcctA, AmtA, DayA, NumA, DenA), Facts),
    member(t(IdB, AcctB, AmtB, DayB, NumB, DenB), Facts),
    IdA \== IdB,
    AcctA \== AcctB,
    AmtA * NumA * DenB =:= -(AmtB * NumB * DenA),   % 정수 교차곱 — 정확 일치
    abs(DayA - DayB) =< 3.

%% 상호 유일: A 의 후보가 B 하나뿐이고, B 의 후보도 A 하나뿐
mutual_unique_pair(Facts,
        _{txn_a:A, txn_b:B, confidence:Conf, matched_by:MB}) :-
    member(t(IdA, _, AmtA, _, _, _), Facts),
    AmtA < 0,                      % 출금 쪽에서 시작 (기저부호 = 금액부호, 쌍 중복 열거 방지)
    findall(IdX, candidate(Facts, t(IdA,_,_,_,_,_), t(IdX,_,_,_,_,_)), [IdB]),
    findall(IdY, candidate(Facts, t(IdB,_,_,_,_,_), t(IdY,_,_,_,_,_)), [IdA]),
    sort_pair(IdA, IdB, A, B),
    confidence(Facts, IdA, IdB, Conf),
    matched_by(Facts, IdA, IdB, MB).

sort_pair(X, Y, X, Y) :- X @< Y, !.
sort_pair(X, Y, Y, X).

%% 신뢰도: 같은 날 100, 1일 차 90, 2일 85, 3일 80
confidence(Facts, IdA, IdB, Conf) :-
    member(t(IdA, _, _, DayA, _, _), Facts),
    member(t(IdB, _, _, DayB, _, _), Facts),
    Diff is abs(DayA - DayB),
    nth0(Diff, [100, 90, 85, 80], Conf).

%% 근거 라벨: 양측 모두 동일통화(1/1)면 exact, 하나라도 fx 환산이면 fx_exact.
matched_by(Facts, IdA, IdB, "transfer_exact_unique") :-
    fact_fx(Facts, IdA, 1, 1),
    fact_fx(Facts, IdB, 1, 1),
    !.
matched_by(_, _, _, "transfer_fx_exact_unique").

fact_fx(Facts, Id, Num, Den) :-
    member(t(Id, _, _, _, Num, Den), Facts).
