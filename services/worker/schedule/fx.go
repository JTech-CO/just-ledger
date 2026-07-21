// 환율 폴링 (M3 할 일). 환율은 실수가 아니라 유리수 쌍 rate_num/rate_den 으로
// 보관한다 (CLAUDE.md 금액 취급 규칙 — float 경유 금지).
// fx_rate 는 전역 참조 데이터(RLS 없음), 쓰기는 ledger_worker 권한.
//
// 소스는 인터페이스로 주입한다 — 실서비스 HTTP 소스는 외부 API 계약이 확정되는
// 시점(배포 환경)에 붙이고, 미설정이면 폴링은 비활성이다.
package schedule

import (
	"context"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"
)

// Rate 하나 = base/quote 환율의 유리수 표현. 예: USD/KRW 1391.25 → num=139125, den=100.
type Rate struct {
	Base  string // ISO 4217
	Quote string
	AsOf  string // YYYY-MM-DD
	Num   int64  // > 0
	Den   int64  // > 0
}

type Source interface {
	Fetch(ctx context.Context) ([]Rate, error)
}

type Poller struct {
	Pool     *pgxpool.Pool
	Log      *slog.Logger
	Source   Source // nil 이면 비활성
	Interval time.Duration
}

// Run 은 ctx 취소까지 주기 폴링한다. Source 가 nil 이면 즉시 반환한다.
func (p *Poller) Run(ctx context.Context) {
	if p.Source == nil {
		p.Log.Info("환율 소스 미설정 — 폴링 비활성")
		return
	}
	tick := time.NewTicker(p.Interval)
	defer tick.Stop()
	for {
		if err := p.PollOnce(ctx); err != nil {
			p.Log.Error("환율 폴링 실패", "err", err)
		}
		select {
		case <-ctx.Done():
			return
		case <-tick.C:
		}
	}
}

// PollOnce 는 소스에서 받아 upsert 한다.
func (p *Poller) PollOnce(ctx context.Context) error {
	rates, err := p.Source.Fetch(ctx)
	if err != nil {
		return err
	}
	for _, r := range rates {
		if _, err := p.Pool.Exec(ctx,
			`INSERT INTO fx_rate (base, quote, as_of, rate_num, rate_den)
			 VALUES ($1, $2, $3::date, $4, $5)
			 ON CONFLICT (base, quote, as_of)
			 DO UPDATE SET rate_num = EXCLUDED.rate_num, rate_den = EXCLUDED.rate_den`,
			r.Base, r.Quote, r.AsOf, r.Num, r.Den,
		); err != nil {
			return err
		}
	}
	p.Log.Info("환율 갱신", "count", len(rates))
	return nil
}
