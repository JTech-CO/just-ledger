// just-ledger 워커 엔트리 (백서 §3.3: 상시 프로세스, Unix socket + JSON).
// 큐 스캐너(진실원천 = DB 상태 기계) + 소켓 nudge + 환율 스케줄러.
package main

import (
	"context"
	"log/slog"
	"os"
	"os/signal"
	"syscall"
	"time"

	workerdb "just-ledger/worker/db"
	"just-ledger/worker/queue"
	"just-ledger/worker/schedule"
)

func env(key, def string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return def
}

func main() {
	log := slog.New(slog.NewTextHandler(os.Stdout, nil))

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	pool, err := workerdb.NewWorkerPool(ctx,
		env("DATABASE_URL", "postgres://ledger:ledger@localhost:5432/ledger"))
	if err != nil {
		log.Error("DB 연결 실패", "err", err)
		os.Exit(1)
	}
	defer pool.Close()

	scanner := queue.NewScanner(pool, log, 5*time.Second)

	fx := &schedule.Poller{
		Pool:     pool,
		Log:      log,
		Source:   nil, // 외부 환율 API 는 배포 환경에서 주입 (.env FX_API_URL)
		Interval: 6 * time.Hour,
	}

	sock := &queue.SocketServer{
		Path:    env("WORKER_SOCKET", "/tmp/just-ledger-worker.sock"),
		Log:     log,
		Scanner: scanner,
		PollFx: func(ctx context.Context) error {
			if fx.Source == nil {
				return context.Canceled // 미설정 신호
			}
			return fx.PollOnce(ctx)
		},
	}

	go fx.Run(ctx)
	go func() {
		if err := sock.Run(ctx); err != nil {
			log.Error("소켓 서버 종료", "err", err)
		}
	}()

	log.Info("worker 기동", "socket", sock.Path)
	scanner.Run(ctx) // 블로킹 — 시그널로 종료
	log.Info("worker 종료")
}
