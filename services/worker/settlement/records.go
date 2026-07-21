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
	"strings"
)

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
	cur, err := alnum(e.Currency, 3, "currency")
	if err != nil {
		return "", err
	}
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
	if n == "000" {
		return "", fmt.Errorf("periods: 1 이상이어야 함")
	}
	pay, err := digits(a.Payment, 15, "payment")
	if err != nil {
		return "", err
	}
	return id + p + num + den + n + pay, nil
}

// BuildSettleInput 은 entries 전체를 검증·직렬화한다. 한 건이라도 폭을
// 넘으면 전체를 거절한다 — 부분 마감은 없다.
func BuildSettleInput(entries []SettleEntry) (string, error) {
	var b strings.Builder
	for i, e := range entries {
		line, err := FormatSettleIn(e)
		if err != nil {
			return "", fmt.Errorf("entry %d: %w", i+1, err)
		}
		b.WriteString(line)
		b.WriteByte('\n')
	}
	return b.String(), nil
}
