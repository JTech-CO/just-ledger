// 내장 자동화 규칙 골든 테스트 (make test-sandbox).
//
// rules/*.lua 각 규칙을 '실제' gopher-lua 샌드박스(prelude 로드 포함)에서 고정 입력
// txn 으로 실행하고, 수집된 액션(tag/notify/set_account)이 고정 기대와 일치하는지
// 검증한다. 부호 결합 가드(급여/이자/환불 키워드 오탐 방지)와 임계·요일·월말 경계를
// 음성 케이스로 포함한다.
package sandbox

import (
	"embed"
	"testing"
)

//go:embed rules/*.lua
var rulesFS embed.FS

func mustRule(t *testing.T, name string) string {
	t.Helper()
	b, err := rulesFS.ReadFile("rules/" + name)
	if err != nil {
		t.Fatalf("규칙 파일 로드 실패 %s: %v", name, err)
	}
	return string(b)
}

type goldenCase struct {
	desc string
	rule string
	txn  TxnView
	want []Action
}

func TestRuleGolden(t *testing.T) {
	cases := []goldenCase{
		// ── subscription.lua ────────────────────────────────────────────────
		{
			desc: "subscription/구독 상대처 지출 → 태깅·계정·알림",
			rule: "subscription.lua",
			txn:  TxnView{OccurredOn: "2026-07-10", AmountMinor: "-13500", Currency: "KRW", Merchant: "넷플릭스 정기결제", Category: "subscription"},
			want: []Action{
				{Kind: "set_account", Value: "5210"},
				{Kind: "tag", Value: "구독"},
				{Kind: "notify", Value: "구독 결제: 넷플릭스 정기결제 -13,500 KRW"},
			},
		},
		{
			desc: "subscription/구독 아닌 상대처 → 무동작",
			rule: "subscription.lua",
			txn:  TxnView{OccurredOn: "2026-07-10", AmountMinor: "-4500", Currency: "KRW", Merchant: "스타벅스 강남", Category: "cafe"},
			want: nil,
		},
		{
			desc: "subscription/구독 상대처지만 입금(부호 가드) → 무동작",
			rule: "subscription.lua",
			txn:  TxnView{OccurredOn: "2026-07-10", AmountMinor: "13500", Currency: "KRW", Merchant: "넷플릭스 환불", Category: ""},
			want: nil,
		},

		// ── large_expense.lua ───────────────────────────────────────────────
		{
			desc: "large_expense/KRW 임계 초과 → 고액 태깅·알림",
			rule: "large_expense.lua",
			txn:  TxnView{OccurredOn: "2026-07-11", AmountMinor: "-700000", Currency: "KRW", Merchant: "가전 매장"},
			want: []Action{
				{Kind: "tag", Value: "고액"},
				{Kind: "notify", Value: "고액 지출 -700,000 KRW (임계 500,000 KRW)"},
			},
		},
		{
			desc: "large_expense/USD 임계 초과(최소단위 환산) → 고액",
			rule: "large_expense.lua",
			txn:  TxnView{OccurredOn: "2026-07-11", AmountMinor: "-60000", Currency: "USD", Merchant: "DELTA AIR"},
			want: []Action{
				{Kind: "tag", Value: "고액"},
				{Kind: "notify", Value: "고액 지출 -600.00 USD (임계 500.00 USD)"},
			},
		},
		{
			desc: "large_expense/임계 미만 → 무동작",
			rule: "large_expense.lua",
			txn:  TxnView{OccurredOn: "2026-07-11", AmountMinor: "-300000", Currency: "KRW", Merchant: "마트"},
			want: nil,
		},

		// ── salary_income.lua ───────────────────────────────────────────────
		{
			desc: "salary/급여 입금 → 분류·태깅·알림",
			rule: "salary_income.lua",
			txn:  TxnView{OccurredOn: "2026-07-25", AmountMinor: "3200000", Currency: "KRW", Merchant: "주식회사 클로드 급여"},
			want: []Action{
				{Kind: "set_account", Value: "4110"},
				{Kind: "tag", Value: "급여"},
				{Kind: "notify", Value: "급여 입금 3,200,000 KRW"},
			},
		},
		{
			desc: "salary/급여 키워드지만 출금(부호 가드) → 무동작",
			rule: "salary_income.lua",
			txn:  TxnView{OccurredOn: "2026-07-25", AmountMinor: "-100000", Currency: "KRW", Merchant: "급여가불 상환"},
			want: nil,
		},

		// ── foreign_currency.lua ────────────────────────────────────────────
		{
			desc: "foreign/비KRW 통화 → 해외 태깅·알림",
			rule: "foreign_currency.lua",
			txn:  TxnView{OccurredOn: "2026-07-12", AmountMinor: "-1200", Currency: "USD", Merchant: "APP STORE"},
			want: []Action{
				{Kind: "tag", Value: "해외"},
				{Kind: "notify", Value: "해외 통화 거래: -12.00 USD"},
			},
		},
		{
			desc: "foreign/KRW → 무동작",
			rule: "foreign_currency.lua",
			txn:  TxnView{OccurredOn: "2026-07-12", AmountMinor: "-1200", Currency: "KRW", Merchant: "편의점"},
			want: nil,
		},

		// ── weekend_leisure.lua ─────────────────────────────────────────────
		{
			desc: "weekend/주말 외식 지출 → 태깅",
			rule: "weekend_leisure.lua",
			txn:  TxnView{OccurredOn: "2023-01-01", AmountMinor: "-25000", Currency: "KRW", Merchant: "이자카야", Category: "dining"},
			want: []Action{{Kind: "tag", Value: "주말여가"}},
		},
		{
			desc: "weekend/평일 외식(월요일) → 무동작",
			rule: "weekend_leisure.lua",
			txn:  TxnView{OccurredOn: "2024-01-01", AmountMinor: "-25000", Currency: "KRW", Merchant: "이자카야", Category: "dining"},
			want: nil,
		},
		{
			desc: "weekend/주말이나 여가 카테고리 아님 → 무동작",
			rule: "weekend_leisure.lua",
			txn:  TxnView{OccurredOn: "2023-01-01", AmountMinor: "-25000", Currency: "KRW", Merchant: "마트", Category: "grocery"},
			want: nil,
		},

		// ── utility_bill.lua ────────────────────────────────────────────────
		{
			desc: "utility/전기요금 → 공과금 분류·태깅",
			rule: "utility_bill.lua",
			txn:  TxnView{OccurredOn: "2026-07-15", AmountMinor: "-45000", Currency: "KRW", Merchant: "한국전력공사 전기요금"},
			want: []Action{
				{Kind: "set_account", Value: "5310"},
				{Kind: "tag", Value: "공과금"},
			},
		},
		{
			desc: "utility/일반 상점 → 무동작",
			rule: "utility_bill.lua",
			txn:  TxnView{OccurredOn: "2026-07-15", AmountMinor: "-45000", Currency: "KRW", Merchant: "쿠팡"},
			want: nil,
		},

		// ── installment.lua ─────────────────────────────────────────────────
		{
			desc: "installment/할부 표기 → 태깅",
			rule: "installment.lua",
			txn:  TxnView{OccurredOn: "2026-07-16", AmountMinor: "-300000", Currency: "KRW", Merchant: "신세계백화점 3개월 할부"},
			want: []Action{{Kind: "tag", Value: "할부"}},
		},
		{
			desc: "installment/일시불 → 무동작",
			rule: "installment.lua",
			txn:  TxnView{OccurredOn: "2026-07-16", AmountMinor: "-300000", Currency: "KRW", Merchant: "편의점 일시불"},
			want: nil,
		},

		// ── transfer_hint.lua ───────────────────────────────────────────────
		{
			desc: "transfer/계좌이체 표기 → 힌트 태깅",
			rule: "transfer_hint.lua",
			txn:  TxnView{OccurredOn: "2026-07-17", AmountMinor: "-500000", Currency: "KRW", Merchant: "토스뱅크 계좌이체"},
			want: []Action{{Kind: "tag", Value: "이체"}},
		},
		{
			desc: "transfer/이체 아님 → 무동작",
			rule: "transfer_hint.lua",
			txn:  TxnView{OccurredOn: "2026-07-17", AmountMinor: "-4500", Currency: "KRW", Merchant: "스타벅스"},
			want: nil,
		},

		// ── month_end_fee.lua ───────────────────────────────────────────────
		{
			desc: "month_end/월말 수수료 지출 → 태깅",
			rule: "month_end_fee.lua",
			txn:  TxnView{OccurredOn: "2026-02-28", AmountMinor: "-1000", Currency: "KRW", Merchant: "계좌유지수수료"},
			want: []Action{{Kind: "tag", Value: "월말수수료"}},
		},
		{
			desc: "month_end/월말 아님 → 무동작",
			rule: "month_end_fee.lua",
			txn:  TxnView{OccurredOn: "2026-02-27", AmountMinor: "-1000", Currency: "KRW", Merchant: "이체 수수료"},
			want: nil,
		},
		{
			desc: "month_end/월말 이자지만 입금(부호 가드) → 무동작",
			rule: "month_end_fee.lua",
			txn:  TxnView{OccurredOn: "2026-02-28", AmountMinor: "5000", Currency: "KRW", Merchant: "예금이자"},
			want: nil,
		},

		// ── refund.lua ──────────────────────────────────────────────────────
		{
			desc: "refund/환불 입금 → 태깅",
			rule: "refund.lua",
			txn:  TxnView{OccurredOn: "2026-07-18", AmountMinor: "23000", Currency: "KRW", Merchant: "쿠팡 주문취소 환불"},
			want: []Action{{Kind: "tag", Value: "환불"}},
		},
		{
			desc: "refund/환불 키워드지만 출금(부호 가드) → 무동작",
			rule: "refund.lua",
			txn:  TxnView{OccurredOn: "2026-07-18", AmountMinor: "-23000", Currency: "KRW", Merchant: "쿠팡 환불"},
			want: nil,
		},
	}

	for _, c := range cases {
		t.Run(c.desc, func(t *testing.T) {
			src := mustRule(t, c.rule)
			got, err := Run(src, c.txn, 0)
			if err != nil {
				t.Fatalf("규칙 실행 오류: %v", err)
			}
			if !actionsEqual(got, c.want) {
				t.Fatalf("액션 불일치\n  got:  %+v\n  want: %+v", got, c.want)
			}
		})
	}
}

func actionsEqual(a, b []Action) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}

// prelude 가 실제 샌드박스(gopher-lua)에서 로드되어 헬퍼 전역이 노출되는지 확인한다.
// (prelude_test.lua 는 lua5.4 순수 함수 검증, 이 테스트는 gopher-lua 로딩 검증.)
func TestPreludeLoadsInSandbox(t *testing.T) {
	checks := []struct {
		desc   string
		script string
		want   Action
	}{
		{"money.format_currency", `notify(money.format_currency(txn.amount_minor, txn.currency))`, Action{"notify", "-1,234,567 KRW"}},
		{"money.add 큰수(float 미경유)", `notify(money.add("9999999999999999999","1"))`, Action{"notify", "10000000000000000000"}},
		{"money.magnitude_ge", `if money.magnitude_ge(txn.amount_minor, "1000000") then tag("big") end`, Action{"tag", "big"}},
		{"text.matches_glob", `if text.matches_glob(txn.merchant, "AMAZON*", true) then tag("m") end`, Action{"tag", "m"}},
		{"date.is_weekend", `if date.is_weekend("2023-01-01") then tag("wk") end`, Action{"tag", "wk"}},
		{"date.add_days", `notify(date.add_days("2026-12-31", 1))`, Action{"notify", "2027-01-01"}},
		{"rule.evaluate", `rule.evaluate(txn, { when = rule.is_expense(), tag = "exp" })`, Action{"tag", "exp"}},
	}
	txn := TxnView{OccurredOn: "2026-07-22", AmountMinor: "-1234567", Currency: "KRW", Merchant: "amazon market"}
	for _, c := range checks {
		t.Run(c.desc, func(t *testing.T) {
			got, err := Run(c.script, txn, 0)
			if err != nil {
				t.Fatalf("실행 오류: %v", err)
			}
			if len(got) != 1 || got[0] != c.want {
				t.Fatalf("prelude 헬퍼 결과 불일치: got %+v, want [%+v]", got, c.want)
			}
		})
	}
}
