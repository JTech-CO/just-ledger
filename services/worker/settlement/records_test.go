package settlement

import (
	"bufio"
	"os"
	"strconv"
	"strings"
	"testing"
)

// 골든 교차검증: JS(gen.mjs)가 생성한 boundary 픽스처와 Go 포매터의 출력이
// 바이트 단위로 같아야 한다. 레이아웃 미러가 어긋나면 여기서 잡힌다.
func TestFormatSettleInMatchesGolden(t *testing.T) {
	entries := []SettleEntry{
		{"BND.0001", "D", "USD", "5", "1", "2"},
		{"BND.0001", "D", "USD", "15", "1", "2"},
		{"BND.0002", "D", "USD", "25", "1", "2"},
		{"BND.0002", "C", "USD", "35", "1", "2"},
		{"BND.0003", "D", "JPY", "3", "5", "2"},
	}
	f, err := os.Open("../../../fixtures/settlement/settle-boundary.in.dat")
	if err != nil {
		t.Fatalf("골든 픽스처 열기 실패: %v", err)
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	for i, e := range entries {
		if !sc.Scan() {
			t.Fatalf("골든 라인 부족: %d", i)
		}
		got, err := FormatSettleIn(e)
		if err != nil {
			t.Fatalf("entry %d: %v", i, err)
		}
		if got != sc.Text() {
			t.Errorf("entry %d 불일치\n golden: %q\n go:     %q", i, sc.Text(), got)
		}
		if len(got) != 81 {
			t.Errorf("entry %d 길이 %d != 81", i, len(got))
		}
	}
}

func TestFormatAmortInMatchesGolden(t *testing.T) {
	// gen.mjs LOANS[0] — payment 는 JS 참조(levelPayment)가 계산한 값
	loan := AmortLoan{
		LoanID: "LN0001", Principal: "1000000",
		RateNum: "5", RateDen: "1000", Periods: "12", Payment: "86066",
	}
	f, err := os.Open("../../../fixtures/settlement/amort.in.dat")
	if err != nil {
		t.Fatalf("골든 픽스처 열기 실패: %v", err)
	}
	defer f.Close()
	sc := bufio.NewScanner(f)
	if !sc.Scan() {
		t.Fatal("골든 비어 있음")
	}
	got, err := FormatAmortIn(loan)
	if err != nil {
		t.Fatal(err)
	}
	if got != sc.Text() {
		t.Errorf("불일치\n golden: %q\n go:     %q", sc.Text(), got)
	}
	if len(got) != 67 {
		t.Errorf("길이 %d != 67", len(got))
	}
}

// M5 DoD 4: copybook PIC 폭 초과는 COBOL 실행 전에 거절된다.
// COBOL 은 초과분을 조용히 절삭하므로 어떤 초과도 통과해선 안 된다.
func TestOverflowRejectedBeforeCobol(t *testing.T) {
	valid := SettleEntry{"ACC.0001", "D", "KRW", "1000", "1", "1"}
	cases := []struct {
		name   string
		mutate func(SettleEntry) SettleEntry
	}{
		{"account_code 33자", func(e SettleEntry) SettleEntry {
			e.AccountCode = strings.Repeat("A", 33)
			return e
		}},
		{"amount 16자리", func(e SettleEntry) SettleEntry {
			e.AmountMinor = strings.Repeat("9", 16)
			return e
		}},
		{"rate_num 16자리", func(e SettleEntry) SettleEntry {
			e.RateNum = strings.Repeat("9", 16)
			return e
		}},
		{"rate_den 16자리", func(e SettleEntry) SettleEntry {
			e.RateDen = strings.Repeat("9", 16)
			return e
		}},
		{"currency 4자", func(e SettleEntry) SettleEntry {
			e.Currency = "KRWX"
			return e
		}},
		{"direction 불량", func(e SettleEntry) SettleEntry {
			e.Direction = "X"
			return e
		}},
		{"금액 음수 문자열", func(e SettleEntry) SettleEntry {
			e.AmountMinor = "-5"
			return e
		}},
		{"금액 소수점", func(e SettleEntry) SettleEntry {
			e.AmountMinor = "10.5"
			return e
		}},
		{"금액 빈 값", func(e SettleEntry) SettleEntry {
			e.AmountMinor = ""
			return e
		}},
		{"rate_den 0", func(e SettleEntry) SettleEntry {
			e.RateDen = "0"
			return e
		}},
		{"코드 비ASCII", func(e SettleEntry) SettleEntry {
			e.AccountCode = "계정.0001"
			return e
		}},
		{"코드 개행 주입", func(e SettleEntry) SettleEntry {
			e.AccountCode = "A\nB"
			return e
		}},
	}
	if _, err := FormatSettleIn(valid); err != nil {
		t.Fatalf("유효 entry 가 거절됨: %v", err)
	}
	for _, c := range cases {
		if _, err := FormatSettleIn(c.mutate(valid)); err == nil {
			t.Errorf("%s: 거절되어야 하는데 통과함", c.name)
		}
	}
}

func TestAmortOverflowRejected(t *testing.T) {
	valid := AmortLoan{"LN0001", "1000000", "5", "1000", "12", "86066"}
	cases := []struct {
		name   string
		mutate func(AmortLoan) AmortLoan
	}{
		{"loan_id 17자", func(a AmortLoan) AmortLoan { a.LoanID = strings.Repeat("L", 17); return a }},
		{"principal 16자리", func(a AmortLoan) AmortLoan { a.Principal = strings.Repeat("9", 16); return a }},
		{"rate_num 10자리", func(a AmortLoan) AmortLoan { a.RateNum = strings.Repeat("9", 10); return a }},
		{"periods 4자리", func(a AmortLoan) AmortLoan { a.Periods = "1000"; return a }},
		{"periods 0", func(a AmortLoan) AmortLoan { a.Periods = "0"; return a }},
		{"rate_den 0", func(a AmortLoan) AmortLoan { a.RateDen = "0"; return a }},
		{"payment 16자리", func(a AmortLoan) AmortLoan { a.Payment = strings.Repeat("9", 16); return a }},
	}
	if _, err := FormatAmortIn(valid); err != nil {
		t.Fatalf("유효 대출이 거절됨: %v", err)
	}
	for _, c := range cases {
		if _, err := FormatAmortIn(c.mutate(valid)); err == nil {
			t.Errorf("%s: 거절되어야 하는데 통과함", c.name)
		}
	}
}

// 환산값 S9(18) 초과는 COBOL 실행 전에 거절 — 조용한 절삭 경로 차단 (INV-7)
func TestKrwRangeRejectedBeforeCobol(t *testing.T) {
	// 999999999999999 × 999999999999999 / 1 ≈ 1e30 — 계약 폭 이내지만 범위 초과
	over := SettleEntry{"ACC.0001", "D", "KRW",
		strings.Repeat("9", 15), strings.Repeat("9", 15), "1"}
	if _, err := FormatSettleIn(over); err == nil {
		t.Fatal("S9(18) 초과 환산이 통과함 — COBOL 이 조용히 절삭했을 값")
	}
	// 상한 바로 안쪽은 통과해야 함: 9e17 × 1 / 1
	within := SettleEntry{"ACC.0001", "D", "KRW", "900000000000000", "1000", "1"}
	if _, err := FormatSettleIn(within); err != nil {
		t.Fatalf("범위 내 환산이 거절됨: %v", err)
	}
}

// 고유 계정 수 > 5000 이면 실행 전 거절 (settle.cbl ACC-TABLE 상한)
func TestAccountCapRejectedBeforeCobol(t *testing.T) {
	mk := func(n int) []SettleEntry {
		es := make([]SettleEntry, n)
		for i := range es {
			es[i] = SettleEntry{
				AccountCode: "ACC." + strings.Repeat("0", 5-len(strconv.Itoa(i))) + strconv.Itoa(i),
				Direction:   "D", Currency: "KRW",
				AmountMinor: "1", RateNum: "1", RateDen: "1",
			}
		}
		return es
	}
	if _, err := BuildSettleInput(mk(MaxSettleAccounts)); err != nil {
		t.Fatalf("5000계정 배치가 거절됨: %v", err)
	}
	if _, err := BuildSettleInput(mk(MaxSettleAccounts + 1)); err == nil {
		t.Fatal("5001계정 배치가 통과함 — COBOL 테이블 상한 초과")
	}
}

// 상각 회차 계약 상한 1..360 강제
func TestAmortPeriodsCapRejected(t *testing.T) {
	valid := AmortLoan{"LN0001", "1000000", "5", "1000", "360", "86066"}
	if _, err := FormatAmortIn(valid); err != nil {
		t.Fatalf("periods=360 이 거절됨: %v", err)
	}
	for _, p := range []string{"361", "999"} {
		bad := valid
		bad.Periods = p
		if _, err := FormatAmortIn(bad); err == nil {
			t.Errorf("periods=%s 가 통과함 (상한 360)", p)
		}
	}
}

// 통화는 [A-Z]{3} 정확히 — 소문자·2자·공백 포함 거절 (JS 미러와 대칭)
func TestCurrencyFormatRejected(t *testing.T) {
	valid := SettleEntry{"ACC.0001", "D", "KRW", "1000", "1", "1"}
	for _, cur := range []string{"kr1", "KR", "K W", "krw"} {
		bad := valid
		bad.Currency = cur
		if _, err := FormatSettleIn(bad); err == nil {
			t.Errorf("currency=%q 가 통과함", cur)
		}
	}
}

// 한 건이라도 불량이면 배치 전체 거절 — 부분 마감 금지
func TestBuildSettleInputAllOrNothing(t *testing.T) {
	good := SettleEntry{"ACC.0001", "D", "KRW", "1000", "1", "1"}
	bad := SettleEntry{strings.Repeat("A", 33), "D", "KRW", "1000", "1", "1"}
	if _, err := BuildSettleInput([]SettleEntry{good, bad, good}); err == nil {
		t.Fatal("불량 포함 배치가 통과함")
	}
	out, err := BuildSettleInput([]SettleEntry{good, good})
	if err != nil {
		t.Fatal(err)
	}
	lines := strings.Split(strings.TrimRight(out, "\n"), "\n")
	if len(lines) != 2 || len(lines[0]) != 81 {
		t.Fatalf("직렬화 형상 이상: %d줄, 폭 %d", len(lines), len(lines[0]))
	}
}
