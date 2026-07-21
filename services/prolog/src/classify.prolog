%% 분류 엔진 (M4). first-match: rules.prolog 절 순서가 우선순위다.
%% 모든 결과에 근거 규칙명(rule_name)이 실린다 (DoD 6 — Inspector 표시용).
%% 금액은 문자열로 받아 정수로만 다룬다 (INV-4 — float 경유 없음).

:- module(classify, [classify_one/5, classify_items/2]).

:- use_module(rules).

%% classify_one(+MerchantAtom, +AmountMinorInt, -Category, -RuleName, -Confidence)
classify_one(Merchant, Amount, Category, RuleName, Conf) :-
    (   keyword_rule(RuleName0, Cat0, Keyword, Conf0),
        sub_atom(Merchant, _, _, _, Keyword)
    ->  Category = Cat0, RuleName = RuleName0, Conf = Conf0
    ;   Amount > 0
    ->  Category = income_other, RuleName = positive_amount_fallback, Conf = 40
    ;   Category = unknown, RuleName = no_match, Conf = 0
    ).

%% classify_items(+Items, -Results)
%% Items: [_{txn_id:Id, merchant:M, amount_minor:AmtStr}, ...] (계약 classifyRequest)
classify_items(Items, Results) :-
    maplist(classify_item, Items, Results).

classify_item(Item, _{txn_id:Id, category:CatS, rule_name:RuleS, confidence:Conf}) :-
    get_dict(txn_id, Item, Id),
    get_dict(merchant, Item, MerchantS),
    atom_string(Merchant0, MerchantS),
    downcase_atom(Merchant0, Merchant),   % 방어적 소문자화 (클라이언트 정규화의 재보장)
    get_dict(amount_minor, Item, AmtS),
    number_string(Amount, AmtS),
    integer(Amount),                       % 소수점 금액은 여기서 실패 → 호출자가 400
    classify_one(Merchant, Amount, Cat, Rule, Conf),
    atom_string(Cat, CatS),
    atom_string(Rule, RuleS).
