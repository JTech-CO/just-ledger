// DB 연결 계층 — 워커는 접속 즉시 SET ROLE ledger_worker 로 강등된다 (RLS 활성,
// BYPASSRLS 없음 — §7). 소유자 컨텍스트는 '작업 단위'로 트랜잭션 GUC 에 설정한다
// (결정 로그: 미결질문 #7 (a)안).
//
// 금액 주의(INV-4): 금액은 SQL 경계에서 text ↔ bigint 캐스팅으로만 다루고,
// Go 쪽에서는 string 그대로 나른다. float 타입을 금액에 쓰지 않는다.
package db

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

// NewWorkerPool 은 ledger_worker 역할로 강등되는 풀을 만든다.
// SET ROLE 실패는 커넥션 획득 실패로 전파된다 (fail-closed — RLS 미적용 커넥션 대여 금지).
func NewWorkerPool(ctx context.Context, databaseURL string) (*pgxpool.Pool, error) {
	cfg, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		return nil, fmt.Errorf("DATABASE_URL 파싱: %w", err)
	}
	cfg.AfterConnect = func(ctx context.Context, conn *pgx.Conn) error {
		_, err := conn.Exec(ctx, "SET ROLE ledger_worker")
		return err
	}
	return pgxpool.NewWithConfig(ctx, cfg)
}

// WithOwner 는 소유자 컨텍스트 트랜잭션을 연다. RLS 의 current_owner() 가
// 이 GUC 를 읽는다. fn 이 에러를 반환하면 롤백한다.
func WithOwner(ctx context.Context, pool *pgxpool.Pool, ownerID string, fn func(pgx.Tx) error) error {
	tx, err := pool.Begin(ctx)
	if err != nil {
		return err
	}
	defer tx.Rollback(ctx) //nolint:errcheck // 커밋 후 롤백은 no-op

	if _, err := tx.Exec(ctx, "SELECT set_config('app.user_id', $1, true)", ownerID); err != nil {
		return fmt.Errorf("소유자 컨텍스트 설정: %w", err)
	}
	if err := fn(tx); err != nil {
		return err
	}
	return tx.Commit(ctx)
}
