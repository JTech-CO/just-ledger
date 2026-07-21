// Lua 샌드박스 테스트 (M4 DoD 4·5, make test-sandbox).
package sandbox

import (
	"strings"
	"testing"
	"time"
)

var sampleTxn = TxnView{
	TxnID:       "00000000-0000-0000-0000-000000000001",
	OccurredOn:  "2026-07-22",
	AmountMinor: "-17000",
	Currency:    "KRW",
	Merchant:    "넷플릭스",
	Category:    "subscription",
}

func TestHappyPathActions(t *testing.T) {
	script := `
		if txn.category == "subscription" then
			tag("구독")
			notify("구독 결제: " .. txn.merchant)
		end
		if string.find(txn.amount_minor, "^%-") then
			set_account("5210")
		end
	`
	actions, err := Run(script, sampleTxn, 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(actions) != 3 {
		t.Fatalf("액션 %d개 (기대 3): %+v", len(actions), actions)
	}
	want := map[string]string{"tag": "구독", "notify": "구독 결제: 넷플릭스", "set_account": "5210"}
	for _, a := range actions {
		if want[a.Kind] != a.Value {
			t.Fatalf("%s = %q (기대 %q)", a.Kind, a.Value, want[a.Kind])
		}
	}
}

// M4 DoD 4 — os/io/package/debug/load 접근 시도가 전부 차단된다 (음성 5종)
func TestEscapeVectorsBlocked(t *testing.T) {
	cases := []struct {
		name   string
		script string
	}{
		{"os", `os.execute("echo hi")`},
		{"io", `io.open("/etc/passwd", "r")`},
		{"package", `require("os")`},
		{"debug", `debug.getinfo(1)`},
		{"load", `local f = load("return 1"); f()`},
		{"loadstring", `loadstring("return 1")()`},
		{"dofile", `dofile("/etc/passwd")`},
		{"getmetatable_escape", `getmetatable(txn).__index`},
		{"collectgarbage", `collectgarbage("collect")`},
		{"print", `print("leak: " .. txn.merchant)`}, // stdout egress (INV-6)
		{"getfenv", `getfenv(1)`},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			_, err := Run(c.script, sampleTxn, 0)
			if err == nil {
				t.Fatalf("%s 접근이 차단되지 않음", c.name)
			}
			// 타임아웃이 아니라 '에러(nil 참조 등)'로 막혀야 한다
			if strings.Contains(err.Error(), "시간 초과") {
				t.Fatalf("%s 가 타임아웃으로 막힘 (기대: 접근 에러)", c.name)
			}
		})
	}
}

// M4 DoD 5 — 무한 루프가 100ms 내에 강제 중단된다
func TestInfiniteLoopTimeout(t *testing.T) {
	start := time.Now()
	_, err := Run(`while true do end`, sampleTxn, 100*time.Millisecond)
	elapsed := time.Since(start)
	if err == nil {
		t.Fatal("무한 루프가 중단되지 않음")
	}
	if !strings.Contains(err.Error(), "시간 초과") {
		t.Fatalf("무한 루프가 타임아웃 아닌 사유로 종료: %v", err)
	}
	if elapsed > 500*time.Millisecond {
		t.Fatalf("중단까지 %v (100ms 강제인데 과도)", elapsed)
	}
}

// 무한 재귀(스택)도 안전하게 잡힌다
func TestInfiniteRecursion(t *testing.T) {
	_, err := Run(`local function f() return f() end f()`, sampleTxn, 100*time.Millisecond)
	if err == nil {
		t.Fatal("무한 재귀가 잡히지 않음")
	}
}

func TestTxnReadOnly(t *testing.T) {
	_, err := Run(`txn.amount_minor = "999"`, sampleTxn, 0)
	if err == nil {
		t.Fatal("txn 쓰기가 허용됨 (읽기 전용이어야 함)")
	}
	if !strings.Contains(err.Error(), "읽기 전용") {
		t.Fatalf("예상과 다른 에러: %v", err)
	}
}

// INV-4 — 금액은 문자열로 노출된다 (Lua number=float64 경유 금지)
func TestAmountIsString(t *testing.T) {
	// 큰 금액이 float 정밀도로 깨지지 않는지 — 18자리 문자열 그대로 보존
	txn := sampleTxn
	txn.AmountMinor = "900719925474099301" // 2^53 초과
	actions, err := Run(`notify(txn.amount_minor)`, txn, 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(actions) != 1 || actions[0].Value != "900719925474099301" {
		t.Fatalf("금액 문자열 왕복 손실: %+v", actions)
	}
	// type 이 string 인지 스크립트 내에서 확인
	_, err = Run(`if type(txn.amount_minor) ~= "string" then error("not string") end`, txn, 0)
	if err != nil {
		t.Fatalf("amount_minor 가 문자열이 아님: %v", err)
	}
}

// 메모리 폭탄이 워커를 죽이지 않고 에러로 잡힌다 (타임아웃 우회 방지)
func TestMemoryBombContained(t *testing.T) {
	cases := []string{
		`local s = string.rep("x", 2000000000)`,                  // 2GB 단일 할당 시도
		`local s = string.rep(string.rep("y", 1000000), 100000)`, // 중첩 폭탄
	}
	for i, script := range cases {
		start := time.Now()
		_, err := Run(script, sampleTxn, 100*time.Millisecond)
		if err == nil {
			t.Fatalf("케이스 %d: 메모리 폭탄이 차단되지 않음", i)
		}
		if time.Since(start) > 2*time.Second {
			t.Fatalf("케이스 %d: 차단까지 과도한 시간 %v", i, time.Since(start))
		}
	}
	// 정상 범위의 string.rep 은 동작해야 한다
	actions, err := Run(`notify(string.rep("ab", 3))`, sampleTxn, 0)
	if err != nil || len(actions) != 1 || actions[0].Value != "ababab" {
		t.Fatalf("정상 string.rep 오동작: %+v, %v", actions, err)
	}
}

func TestActionCountCapped(t *testing.T) {
	_, err := Run(`for i=1,1000 do tag("x") end`, sampleTxn, 500*time.Millisecond)
	if err == nil {
		t.Fatal("액션 폭주가 상한에 걸리지 않음")
	}
}

func TestSafeStdlibAvailable(t *testing.T) {
	// string/math/table 은 정상 동작해야 한다
	script := `
		local up = string.upper("abc")
		local mx = math.max(1, 2, 3)
		local t = {3, 1, 2}
		table.sort(t)
		notify(up .. tostring(mx) .. tostring(t[1]))
	`
	actions, err := Run(script, sampleTxn, 0)
	if err != nil {
		t.Fatal(err)
	}
	if len(actions) != 1 || actions[0].Value != "ABC31" {
		t.Fatalf("표준 라이브러리 오동작: %+v", actions)
	}
}
