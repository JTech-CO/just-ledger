// 환율 폴러 테스트 — 유리수 쌍이 그대로 저장·갱신되는지 (float 경유 없음).
package schedule

import (
	"context"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	workerdb "just-ledger/worker/db"
)

type staticSource struct{ rates []Rate }

func (s staticSource) Fetch(_ context.Context) ([]Rate, error) { return s.rates, nil }

func TestPollerUpsertsRationalPair(t *testing.T) {
	admin := os.Getenv("DATABASE_URL")
	if admin == "" {
		t.Skip("DATABASE_URL 미설정")
	}
	dbName := "wk_fx"
	run := func(url string, args ...string) {
		t.Helper()
		full := append([]string{url, "-v", "ON_ERROR_STOP=1", "-qAt"}, args...)
		cmd := exec.Command("psql", full...)
		wd, _ := os.Getwd()
		cmd.Dir = filepath.Clean(filepath.Join(wd, "..", "..", ".."))
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("psql: %v\n%s", err, out)
		}
	}
	run(admin, "-c", "DROP DATABASE IF EXISTS "+dbName+" WITH (FORCE)")
	run(admin, "-c", "CREATE DATABASE "+dbName)
	testURL := admin[:strings.LastIndex(admin, "/")] + "/" + dbName
	run(testURL, "-q", "-f", filepath.Join("db", "migrations", "0001_init.up.pgsql"))
	t.Cleanup(func() { run(admin, "-c", "DROP DATABASE IF EXISTS "+dbName+" WITH (FORCE)") })

	ctx := context.Background()
	pool, err := workerdb.NewWorkerPool(ctx, testURL)
	if err != nil {
		t.Fatal(err)
	}
	defer pool.Close()

	p := &Poller{
		Pool: pool,
		Log:  slog.New(slog.NewTextHandler(os.Stderr, nil)),
		// USD/KRW 1391.25 = 139125/100 — 유리수 쌍, 실수 없음
		Source: staticSource{rates: []Rate{
			{Base: "USD", Quote: "KRW", AsOf: "2026-07-21", Num: 139125, Den: 100},
		}},
	}
	if err := p.PollOnce(ctx); err != nil {
		t.Fatal(err)
	}

	var num, den int64
	if err := pool.QueryRow(ctx,
		`SELECT rate_num, rate_den FROM fx_rate WHERE base='USD' AND quote='KRW' AND as_of='2026-07-21'`,
	).Scan(&num, &den); err != nil {
		t.Fatal(err)
	}
	if num != 139125 || den != 100 {
		t.Fatalf("유리수 쌍 %d/%d (기대 139125/100)", num, den)
	}

	// 같은 날짜 재폴링 → 갱신 (upsert)
	p.Source = staticSource{rates: []Rate{
		{Base: "USD", Quote: "KRW", AsOf: "2026-07-21", Num: 139200, Den: 100},
	}}
	if err := p.PollOnce(ctx); err != nil {
		t.Fatal(err)
	}
	if err := pool.QueryRow(ctx,
		`SELECT rate_num FROM fx_rate WHERE base='USD' AND quote='KRW' AND as_of='2026-07-21'`,
	).Scan(&num); err != nil {
		t.Fatal(err)
	}
	if num != 139200 {
		t.Fatalf("갱신 후 num=%d (기대 139200)", num)
	}
}
