// 큐·스캐너 — 진실원천은 DB 의 ingest_batch 상태 기계다.
// 소켓 nudge(즉시 처리 힌트)가 없어도 주기 스캔이 미완료 배치를 집어 처리하므로,
// 워커 강제 종료 후 재시작 시 자동 재개된다 (M3 DoD 5).
//
// 작업 발견은 fn_pending_ingest_batches() (SECURITY DEFINER, 최소 투영) —
// 처리 자체는 배치 소유자 컨텍스트(RLS)로 수행한다.
package queue

import (
	"context"
	"log/slog"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"just-ledger/worker/ingest"
)

type Scanner struct {
	Pool     *pgxpool.Pool
	Log      *slog.Logger
	Interval time.Duration
	// nudge 채널: 소켓이 (owner, batch) 를 밀어넣으면 즉시 처리
	Nudge chan Job
}

type Job struct {
	OwnerID string
	BatchID string
}

func NewScanner(pool *pgxpool.Pool, log *slog.Logger, interval time.Duration) *Scanner {
	return &Scanner{
		Pool:     pool,
		Log:      log,
		Interval: interval,
		Nudge:    make(chan Job, 64),
	}
}

// Run 은 ctx 취소까지 스캔 루프를 돈다.
func (s *Scanner) Run(ctx context.Context) {
	// 기동 직후 1회 즉시 스캔 — 재시작 시 미완료 배치를 지체 없이 재개 (DoD 5)
	s.ScanOnce(ctx)

	tick := time.NewTicker(s.Interval)
	defer tick.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case job := <-s.Nudge:
			s.process(ctx, job)
		case <-tick.C:
			s.ScanOnce(ctx)
		}
	}
}

// ScanOnce 는 미완료 배치를 전부 집어 처리한다.
func (s *Scanner) ScanOnce(ctx context.Context) {
	rows, err := s.Pool.Query(ctx, `SELECT batch_id, owner_id FROM fn_pending_ingest_batches()`)
	if err != nil {
		s.Log.Error("미완료 배치 조회 실패", "err", err)
		return
	}
	var jobs []Job
	for rows.Next() {
		var j Job
		if err := rows.Scan(&j.BatchID, &j.OwnerID); err != nil {
			s.Log.Error("배치 행 스캔 실패", "err", err)
			rows.Close()
			return
		}
		jobs = append(jobs, j)
	}
	rows.Close()
	if err := rows.Err(); err != nil {
		s.Log.Error("배치 조회 순회 실패", "err", err)
		return
	}

	for _, j := range jobs {
		s.process(ctx, j)
	}
}

func (s *Scanner) process(ctx context.Context, j Job) {
	if _, err := ingest.ProcessBatch(ctx, s.Pool, s.Log, j.OwnerID, j.BatchID); err != nil {
		// ProcessBatch 가 이미 실패 상태 반영·로그를 끝냈다 — 스캐너는 계속 진행
		return
	}
}
