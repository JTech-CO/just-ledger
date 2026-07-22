// Package settlement — COBOL 마감 배치용 고정폭 레코드 생성기.
//
// 레이아웃의 단일 진실원천은 modules/settlement/copybook/*.cpy 다. 이 패키지는
// 그 미러이며, copybook 이 바뀌면 여기와 scripts/parity/records.mjs 를 함께
// 갱신하고 PROGRESS.md 계약 변경 로그에 기재한다.
//
// M5 DoD 4: copybook PIC 폭을 초과하는 필드는 COBOL 실행 **전에** 여기서
// 오류로 거절한다. COBOL 은 초과분을 조용히 절삭하므로 통과시키면 안 된다.
// 금액은 최소 화폐 단위 정수 문자열로만 다룬다 (INV-4 — float 경유 금지).
package settlement

import (
	"fmt"
	"math/big"
	"strconv"
	"strings"
)

// copybook 계약 한계 (settle-io.cpy / amort-io.cpy 주석과 1:1)
const (
	// MaxSettleAccounts 는 settle.cbl ACC-TABLE OCCURS 상한이다.
	MaxSettleAccounts = 5000
	// MaxAmortPeriods 는 AI-PERIODS 도메인 상한이다 (1..360).
	MaxAmortPeriods = 360
)

// maxS18 = S9(18) 절대값 상한 (10^18 - 1)
var maxS18 = new(big.Int).SetInt64(999999999999999999)

// checkKrwRange 는 entry 환산값 |amount·num/den| 이 S9(18) 에 담기는지
// 보수적으로 사전 검증한다. 반올림 정본(NEAREST-EVEN)은 COBOL 에만 있으므로
// 여기서 재구현하지 않고(CLAUDE.md 반올림 규칙), 상계 floor(q)+1 로 판정한다.
// 경계(몫이 정확히 10^18-1 근방)에서 극소수의 유효 값을 과잉 거절할 수 있으나
// 조용한 절삭보다 명시 거절이 우선이다. 계정별 누적 오버플로는 실행 전 정확
// 판정이 불가능해(반올림 재구현 필요) settle.cbl 의 ON SIZE ERROR 가
// ERROR STATUS 8 로 명시 중단한다 — 어느 경로에도 침묵 절삭은 없다.
func checkKrwRange(amount, num, den string) error {
	a, ok1 := new(big.Int).SetString(amount, 10)
	n, ok2 := new(big.Int).SetString(num, 10)
	d, ok3 := new(big.Int).SetString(den, 10)
	if !ok1 || !ok2 || !ok3 || d.Sign() == 0 {
		return fmt.Errorf("환산 범위 검사: 수치 해석 실패")
	}
	q := new(big.Int).Quo(new(big.Int).Mul(a, n), d)
	q.Add(q, big.NewInt(1))
	if q.Cmp(maxS18) > 0 {
		return fmt.Errorf("환산값이 S9(18) 범위 초과: %s×%s/%s", amount, num, den)
	}
	return nil
}

// SettleEntry 는 SETTLE-IN-REC(81바이트) 한 건의 입력이다.
type SettleEntry struct {
	AccountCode string // PIC X(32)
	Direction   string // PIC X(1) — "D" | "C"
	Currency    string // PIC X(3)
	AmountMinor string // PIC 9(15) — 양의 정수 문자열
	RateNum     string // PIC 9(15)
	RateDen     string // PIC 9(15)
}

// AmortLoan 은 AMORT-IN-REC(67바이트) 한 건의 입력이다.
// Payment(월 납입액 A)는 JS 참조 구현이 계산해 공급한다.
type AmortLoan struct {
	LoanID    string // PIC X(16)
	Principal string // PIC 9(15)
	RateNum   string // PIC 9(9)
	RateDen   string // PIC 9(9)
	Periods   string // PIC 9(3) — 1..360
	Payment   string // PIC 9(15)
}

// digits 는 부호 없는 십진 정수 문자열인지 검사한 뒤 zero-fill 한다.
// 폭 초과·비숫자·빈 문자열은 오류 (조용한 절삭 금지).
func digits(v string, width int, field string) (string, error) {
	if v == "" {
		return "", fmt.Errorf("%s: 빈 값", field)
	}
	for _, c := range v {
		if c < '0' || c > '9' {
			return "", fmt.Errorf("%s: 숫자가 아님 %q", field, v)
		}
	}
	if len(v) > width {
		return "", fmt.Errorf("%s: 길이 %d > PIC 폭 %d (%q)", field, len(v), width, v)
	}
	return strings.Repeat("0", width-len(v)) + v, nil
}

// alnum 은 문자 필드를 폭 검사 후 우측 공백 패딩한다.
func alnum(v string, width int, field string) (string, error) {
	if len(v) > width {
		return "", fmt.Errorf("%s: 길이 %d > PIC 폭 %d (%q)", field, len(v), width, v)
	}
	for _, c := range v {
		if c < 0x20 || c > 0x7e {
			return "", fmt.Errorf("%s: 고정폭 레코드에 비ASCII/제어문자 %q", field, v)
		}
	}
	return v + strings.Repeat(" ", width-len(v)), nil
}

// FormatSettleIn 은 entry 를 SETTLE-IN-REC 한 줄로 만든다 (개행 미포함).
func FormatSettleIn(e SettleEntry) (string, error) {
	code, err := alnum(e.AccountCode, 32, "account_code")
	if err != nil {
		return "", err
	}
	if e.Direction != "D" && e.Direction != "C" {
		return "", fmt.Errorf("direction: %q (D|C 만 허용)", e.Direction)
	}
	if len(e.Currency) != 3 {
		return "", fmt.Errorf("currency: %q ([A-Z]{3} 만 허용)", e.Currency)
	}
	for _, c := range e.Currency {
		if c < 'A' || c > 'Z' {
			return "", fmt.Errorf("currency: %q ([A-Z]{3} 만 허용)", e.Currency)
		}
	}
	cur := e.Currency
	amt, err := digits(e.AmountMinor, 15, "amount_minor")
	if err != nil {
		return "", err
	}
	num, err := digits(e.RateNum, 15, "rate_num")
	if err != nil {
		return "", err
	}
	den, err := digits(e.RateDen, 15, "rate_den")
	if err != nil {
		return "", err
	}
	if den == strings.Repeat("0", 15) {
		return "", fmt.Errorf("rate_den: 0 은 허용되지 않음")
	}
	if err := checkKrwRange(e.AmountMinor, e.RateNum, e.RateDen); err != nil {
		return "", err
	}
	return code + e.Direction + cur + amt + num + den, nil
}

// FormatAmortIn 은 대출 1건을 AMORT-IN-REC 한 줄로 만든다 (개행 미포함).
func FormatAmortIn(a AmortLoan) (string, error) {
	id, err := alnum(a.LoanID, 16, "loan_id")
	if err != nil {
		return "", err
	}
	p, err := digits(a.Principal, 15, "principal")
	if err != nil {
		return "", err
	}
	num, err := digits(a.RateNum, 9, "rate_num")
	if err != nil {
		return "", err
	}
	den, err := digits(a.RateDen, 9, "rate_den")
	if err != nil {
		return "", err
	}
	if den == strings.Repeat("0", 9) {
		return "", fmt.Errorf("rate_den: 0 은 허용되지 않음")
	}
	n, err := digits(a.Periods, 3, "periods")
	if err != nil {
		return "", err
	}
	nv, err := strconv.Atoi(n)
	if err != nil || nv < 1 || nv > MaxAmortPeriods {
		return "", fmt.Errorf("periods: %s (1..%d 만 허용)", a.Periods, MaxAmortPeriods)
	}
	pay, err := digits(a.Payment, 15, "payment")
	if err != nil {
		return "", err
	}
	return id + p + num + den + n + pay, nil
}

// BuildSettleInput 은 entries 전체를 검증·직렬화한다. 한 건이라도 폭·범위를
// 넘거나 고유 계정 수가 테이블 상한을 넘으면 전체를 거절한다 — 부분 마감은 없다.
func BuildSettleInput(entries []SettleEntry) (string, error) {
	var b strings.Builder
	accounts := make(map[string]struct{}, 64)
	for i, e := range entries {
		line, err := FormatSettleIn(e)
		if err != nil {
			return "", fmt.Errorf("entry %d: %w", i+1, err)
		}
		accounts[e.AccountCode] = struct{}{}
		if len(accounts) > MaxSettleAccounts {
			return "", fmt.Errorf("entry %d: 고유 계정 %d개 — 상한 %d (settle.cbl ACC-TABLE)",
				i+1, len(accounts), MaxSettleAccounts)
		}
		b.WriteString(line)
		b.WriteByte('\n')
	}
	return b.String(), nil
}
