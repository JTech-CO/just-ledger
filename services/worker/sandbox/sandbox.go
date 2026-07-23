// Lua 사용자 자동화 규칙 샌드박스 (M4, 백서 §4.3).
//
// 격리 정책:
//   - 표준 라이브러리는 base(안전 부분)·string·math·table 만 연다 (백서 §3.2)
//   - io / os / debug / package(require) 는 열지 않고, base 의 탈출 벡터
//     (load/loadstring/loadfile/dofile/collectgarbage/getmetatable/setmetatable/rawset 등)를 제거한다
//   - 무한 루프는 context 로 100ms(기본) 강제 중단한다 (M4 DoD 5)
//
// 노출 API 는 정확히 4개 (백서 §4.3):
//
//	txn          — 읽기 전용 테이블 (쓰기 시도는 에러)
//	tag(name)    — 태그 부여 액션
//	notify(msg)  — 알림 액션
//	set_account(code) — 상대 계정 지정 액션
//
// 부수효과 채널은 위 3개 액션뿐이다. 규칙 실행 직전 prelude.lua 를 로드해 순수 헬퍼
// 전역(money/text/date/rule)을 노출하지만, 이들은 새 능력이 아니라 위 액션 위에서
// 규칙을 간결하게 쓰기 위한 라이브러리다 (금액 문자열 산술·상대처 매칭·날짜/요일·
// 선언적 규칙 조합기). 소스는 prelude.lua, 단위 테스트는 prelude_test.lua.
//
// 금액 주의(INV-4): Lua number 는 float64 다 — 금액(amount_minor)은 반드시
// '문자열'로 노출한다. 스크립트가 산술을 원하면 money.* 의 문자열 정수 연산을 쓴다.
package sandbox

import (
	"context"
	"errors"
	"fmt"
	"time"

	lua "github.com/yuin/gopher-lua"
)

// TxnView 는 스크립트에 노출되는 거래의 읽기 전용 뷰다.
// 민감 필드(적요·상대처)는 클라이언트 복호화 컨텍스트에서만 채워진다 —
// 서버 워커 경로에서는 빈 값이며, 어느 쪽이든 영속되지 않는다 (INV-6).
type TxnView struct {
	TxnID       string
	OccurredOn  string
	AmountMinor string // 부호 있는 최소 단위 정수 '문자열' (INV-4)
	Currency    string
	Merchant    string // 있을 때만 (일시 전달)
	Category    string // 분류 결과 (있을 때만)
}

// Action 은 스크립트가 요청한 부수효과다 — 실행이 아니라 '수집'된다.
// 적용 여부·방법은 호출자(워커 파이프라인)가 결정한다.
type Action struct {
	Kind  string // "tag" | "notify" | "set_account"
	Value string
}

const DefaultTimeout = 100 * time.Millisecond

// 스크립트가 폭주해도 서버가 죽지 않게 액션 수를 상한한다
const maxActions = 64

var ErrTimeout = errors.New("스크립트 실행 시간 초과")

// Run 은 스크립트를 격리 실행하고 수집된 액션을 반환한다.
func Run(script string, txn TxnView, timeout time.Duration) ([]Action, error) {
	if timeout <= 0 {
		timeout = DefaultTimeout
	}

	L := lua.NewState(lua.Options{SkipOpenLibs: true})
	defer L.Close()

	// ── 선택적 표준 라이브러리 (base/string/math/table 만) ──────────────────
	for _, open := range []struct {
		name string
		fn   lua.LGFunction
	}{
		{lua.BaseLibName, lua.OpenBase},
		{lua.StringLibName, lua.OpenString},
		{lua.MathLibName, lua.OpenMath},
		{lua.TabLibName, lua.OpenTable},
	} {
		L.Push(L.NewFunction(open.fn))
		L.Push(lua.LString(open.name))
		L.Call(1, 0)
	}

	// ── base 의 탈출·egress 벡터 제거 (M4 DoD 4 음성 테스트 대상) ────────────
	for _, name := range []string{
		"load", "loadstring", "loadfile", "dofile", "require",
		"collectgarbage", "getmetatable", "setmetatable",
		"rawset", "rawget", "rawequal", "module",
		// print 는 프로세스 stdout(→로그)으로 직접 쓴다 — 노출 API 4개 규약·INV-6 위반
		"print", "_printregs", "getfenv", "setfenv",
		// 열지 않았지만 전역 자체를 nil 로 못박는다 (혹시 모를 잔재 차단)
		"io", "os", "debug", "package", "channel", "coroutine",
	} {
		L.SetGlobal(name, lua.LNil)
	}

	// ── 메모리 폭탄 차단: string.rep 를 총길이 상한 래퍼로 교체 ──────────────
	// string.rep("x", 1e9) 같은 단일 빌트인 호출은 명령어 경계가 없어 100ms
	// 타임아웃이 선점하지 못하고 GB 를 할당해 워커를 OOM/panic 시킨다 (적대 검증).
	if strTbl, ok := L.GetGlobal(lua.StringLibName).(*lua.LTable); ok {
		L.SetField(strTbl, "rep", L.NewFunction(safeStringRep))
		L.SetField(strTbl, "dump", lua.LNil) // 바이트코드 덤프 불필요
	}

	// ── 읽기 전용 txn 테이블 ────────────────────────────────────────────────
	data := L.NewTable()
	L.SetField(data, "txn_id", lua.LString(txn.TxnID))
	L.SetField(data, "occurred_on", lua.LString(txn.OccurredOn))
	L.SetField(data, "amount_minor", lua.LString(txn.AmountMinor)) // 문자열 (INV-4)
	L.SetField(data, "currency", lua.LString(txn.Currency))
	L.SetField(data, "merchant", lua.LString(txn.Merchant))
	L.SetField(data, "category", lua.LString(txn.Category))

	proxy := L.NewTable()
	mt := L.NewTable()
	L.SetField(mt, "__index", data)
	L.SetField(mt, "__newindex", L.NewFunction(func(l *lua.LState) int {
		l.RaiseError("txn 은 읽기 전용입니다")
		return 0
	}))
	L.SetField(mt, "__metatable", lua.LString("protected")) // getmetatable 우회 차단
	L.SetMetatable(proxy, mt)
	L.SetGlobal("txn", proxy)

	// ── 액션 수집 API 3종 ───────────────────────────────────────────────────
	var actions []Action
	collect := func(kind string) lua.LGFunction {
		return func(l *lua.LState) int {
			if len(actions) >= maxActions {
				l.RaiseError("액션 수 상한 초과")
				return 0
			}
			v := l.CheckString(1)
			actions = append(actions, Action{Kind: kind, Value: v})
			return 0
		}
	}
	L.SetGlobal("tag", L.NewFunction(collect("tag")))
	L.SetGlobal("notify", L.NewFunction(collect("notify")))
	L.SetGlobal("set_account", L.NewFunction(collect("set_account")))

	// ── 타임아웃 강제 (DoD 5) ───────────────────────────────────────────────
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	L.SetContext(ctx)

	// 빌트인이 던지는 Go panic(초대형 할당 오버플로 등)이 워커 프로세스를 죽이지
	// 않도록 격리한다 — 스크립트 실패는 에러로만 표면화된다.
	if err := runProtected(L, script); err != nil {
		if ctx.Err() != nil {
			return nil, fmt.Errorf("%w (%v)", ErrTimeout, timeout)
		}
		return nil, fmt.Errorf("스크립트 오류: %w", err)
	}
	return actions, nil
}

func runProtected(L *lua.LState, script string) (err error) {
	defer func() {
		if r := recover(); r != nil {
			err = fmt.Errorf("스크립트 런타임 중단: %v", r)
		}
	}()
	// 규칙 작성 표준 라이브러리(money/text/date/rule)를 먼저 로드한다 — 규칙은 이
	// 전역들 위에서 작성된다. prelude 는 신뢰 코드이므로 로드 실패는 버그로 취급한다.
	if perr := L.DoString(preludeSource); perr != nil {
		return fmt.Errorf("prelude 로드 실패: %w", perr)
	}
	return L.DoString(script)
}

// safeStringRep 는 표준 string.rep 의 결과 총길이를 상한(1MiB)으로 제한한다.
func safeStringRep(l *lua.LState) int {
	const maxLen = 1 << 20 // 1MiB
	s := l.CheckString(1)
	n := l.CheckInt(2)
	if n < 0 {
		n = 0
	}
	if len(s) != 0 && n > maxLen/len(s) {
		l.RaiseError("string.rep 결과가 상한(1MiB)을 초과합니다")
		return 0
	}
	l.Push(lua.LString(strings_Repeat(s, n)))
	return 1
}

func strings_Repeat(s string, n int) string {
	if n <= 0 || s == "" {
		return ""
	}
	var b []byte
	b = make([]byte, 0, len(s)*n)
	for i := 0; i < n; i++ {
		b = append(b, s...)
	}
	return string(b)
}
