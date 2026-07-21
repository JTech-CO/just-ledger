%% Prolog 추론 서비스 (M4, 백서 §3.3: 상시 HTTP + JSON).
%% 무상태 — DB 를 보지 않고, 요청에 실린 사실만으로 추론해 결과를 반환한다.
%% merchant 등 민감 필드는 응답 즉시 버려진다 — 어떤 저장·로그도 없다 (INV-6).
%%
%% 기동:
%%   swipl services/prolog/service.prolog                 # HTTP :7070
%%   swipl services/prolog/service.prolog -- --stdin      # stdin/stdout JSONL 1회 처리
%%     입력:  {"op":"classify"|"match_transfers"|"recurring", "payload":{...}}
%%     출력:  계약 inference.schema.json 의 해당 응답 1줄

%% src/ 검색 경로는 use_module 이전에 확정해야 한다
:- prolog_load_context(directory, Dir),
   atom_concat(Dir, '/src', Src),
   asserta(user:file_search_path(src, Src)).

:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_json)).
:- use_module(library(json)).

:- use_module(src(classify)).
:- use_module(src(transfer)).
:- use_module(src(recurring)).

:- http_handler(root(health), health_handler, []).
:- http_handler(root(classify), classify_handler, [method(post)]).
:- http_handler(root(match_transfers), transfers_handler, [method(post)]).
:- http_handler(root(recurring), recurring_handler, [method(post)]).

health_handler(_Request) :-
    reply_json_dict(_{status:"ok"}).

classify_handler(Request) :-
    http_read_json_dict(Request, In),
    (   catch(classify_items(In.items, Results), _, fail)
    ->  reply_json_dict(_{results:Results})
    ;   reply_json_dict(_{error:"bad_request"}, [status(400)])
    ).

transfers_handler(Request) :-
    http_read_json_dict(Request, In),
    (   catch(transfer_pairs(In.items, Pairs), _, fail)
    ->  reply_json_dict(_{pairs:Pairs})
    ;   reply_json_dict(_{error:"bad_request"}, [status(400)])
    ).

recurring_handler(Request) :-
    http_read_json_dict(Request, In),
    (   catch(recurring_series(In.items, Series), _, fail)
    ->  reply_json_dict(_{series:Series})
    ;   reply_json_dict(_{error:"bad_request"}, [status(400)])
    ).

%% ── stdin/stdout 단독 실행 (모듈 규칙: stdin/stdout 만으로 실행 가능) ────────
run_stdin :-
    json_read_dict(user_input, Cmd),
    (   Cmd.op == "classify"
    ->  classify_items(Cmd.payload.items, Results),
        json_write_dict(user_output, _{results:Results})
    ;   Cmd.op == "match_transfers"
    ->  transfer_pairs(Cmd.payload.items, Pairs),
        json_write_dict(user_output, _{pairs:Pairs})
    ;   Cmd.op == "recurring"
    ->  recurring_series(Cmd.payload.items, Series),
        json_write_dict(user_output, _{series:Series})
    ;   json_write_dict(user_output, _{error:"unknown_op"})
    ),
    nl(user_output).

main :-
    current_prolog_flag(argv, Argv),
    (   member('--stdin', Argv)
    ->  run_stdin,
        halt(0)
    ;   getenv_default('PROLOG_PORT', '7070', PortA),
        atom_number(PortA, Port),
        http_server(http_dispatch, [port(Port)]),
        format(user_error, "prolog 추론 서비스 기동: :~w~n", [Port]),
        thread_get_message(_)   % 서버 유지
    ).

getenv_default(Name, _, Value) :- getenv(Name, Value), !.
getenv_default(_, Default, Default).

:- initialization(main, main).
