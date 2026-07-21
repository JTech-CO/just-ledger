# services/worker/sandbox — Lua

Go 워커 안에 gopher-lua 로 임베드된 사용자 자동화 규칙 샌드박스. `*.lua` 규칙과 Go 바인딩.

> 한 세션에서 Go(worker)와 Lua(sandbox)를 동시에 건드리지 않는다. 샌드박스 정책은 Lua 세션에서, 큐/러너는 Go 세션에서.

## 소유 범위
`services/worker/sandbox/` 의 `*.lua` 및 샌드박스 바인딩. 언어 구성 계측에서 Lua 는 이 디렉터리 + `scripts/linguist-gate.lua` 로 확보한다.

## 규율 (음성 테스트가 핵심)
- 표준 라이브러리 중 **`base` / `string` / `math` / `table` 만** 등록한다.
- `os` · `io` · `package` · `debug` · `load` 접근 시도는 **전부 차단**된다 (M4 DoD 4).
- base 의 egress·탈출 함수(`print`·`load`·`getfenv`/`setfenv`·`getmetatable`·`collectgarbage` 등)를 nil 로 못박는다. 특히 `print` 는 stdout(→로그)으로 새므로 반드시 제거 (INV-6).
- `string.rep` 은 결과 총길이 상한(1MiB) 래퍼로 교체한다 — 단일 빌트인 대량 할당은 명령어 경계가 없어 100ms 타임아웃을 우회해 워커를 OOM 시킨다.
- 스크립트 실행은 panic recover 로 감싼다 — 빌트인 panic 이 상주 워커 프로세스를 죽이지 않게.
- 무한 루프 스크립트는 **100ms 내 강제 중단**된다 (M4 DoD 5).
- 노출 API 는 정확히 4개: `txn`(읽기 전용), `tag()`, `notify()`, `set_account()`.
- 금액을 다루면 문자열/정수로만 — `txn.amount_minor` 는 문자열(Lua number=float64 회피, INV-4).

## 명령
```
cd services/worker && go test ./sandbox/...   # make test-sandbox — 탈출 차단 + 타임아웃
```

## 참조
기술 백서 §3.2(gopher-lua), §4.3(Lua 샌드박스), §7 / 담당 phase: M4.
