// 테스트 인프라 — 스크래치 DB 를 만들고 0001 마이그레이션을 psql 로 적용한다
// (\ir 포함이 있어 psql 필수; exec 는 argv 배열 — 셸 미경유).
package ingest

import (
	"context"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	workerdb "just-ledger/worker/db"
)

func adminURL(t *testing.T) string {
	t.Helper()
	u := os.Getenv("DATABASE_URL")
	if u == "" {
		t.Skip("DATABASE_URL 미설정 — DB 통합 테스트 건너뜀 (CI/컨테이너에서 실행)")
	}
	return u
}

func repoRoot(t *testing.T) string {
	t.Helper()
	wd, err := os.Getwd()
	if err != nil {
		t.Fatal(err)
	}
	// 패키지 테스트 wd = services/worker/<pkg> → repo root 는 3단계 위
	return filepath.Clean(filepath.Join(wd, "..", "..", ".."))
}

func psql(t *testing.T, url string, args ...string) {
	t.Helper()
	full := append([]string{url, "-v", "ON_ERROR_STOP=1", "-qAt"}, args...)
	cmd := exec.Command("psql", full...)
	cmd.Dir = repoRoot(t)
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("psql %v: %v\n%s", args, err, out)
	}
}

// createScratch 는 스크래치 DB + 마이그레이션 + 워커 롤 풀을 준비한다.
func createScratch(t *testing.T, dbName string) (*pgxpool.Pool, *pgxpool.Pool, string) {
	t.Helper()
	admin := adminURL(t)
	psql(t, admin, "-c", "DROP DATABASE IF EXISTS "+dbName+" WITH (FORCE)")
	psql(t, admin, "-c", "CREATE DATABASE "+dbName)

	testURL := admin[:strings.LastIndex(admin, "/")] + "/" + dbName
	psql(t, testURL, "-q", "-f", filepath.Join("db", "migrations", "0001_init.up.pgsql"))

	ctx := context.Background()
	workerPool, err := workerdb.NewWorkerPool(ctx, testURL)
	if err != nil {
		t.Fatal(err)
	}
	adminPool, err := pgxpool.New(ctx, testURL) // 픽스처 생성용 (RLS 미적용 소유자)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		workerPool.Close()
		adminPool.Close()
		psql(t, admin, "-c", "DROP DATABASE IF EXISTS "+dbName+" WITH (FORCE)")
	})
	return workerPool, adminPool, testURL
}

type fixture struct {
	OwnerID   string
	AccountID string
}

func makeFixture(t *testing.T, adminPool *pgxpool.Pool, tag string) fixture {
	t.Helper()
	ctx := context.Background()
	var f fixture
	if err := adminPool.QueryRow(ctx,
		`INSERT INTO app_user (username) VALUES ($1) RETURNING id::text`, "wk_"+tag,
	).Scan(&f.OwnerID); err != nil {
		t.Fatal(err)
	}
	if err := adminPool.QueryRow(ctx,
		`INSERT INTO account (owner_id, code, name, type, currency)
		 VALUES ($1, $2, '입출금', 'asset', 'KRW') RETURNING id::text`,
		f.OwnerID, "WK."+tag,
	).Scan(&f.AccountID); err != nil {
		t.Fatal(err)
	}
	return f
}

// makeBatch 는 배치 + 페이로드(서버 가시 최소 필드 + 더미 cipher)를 만든다.
// cipher.blob 은 실제 암호문이 아니어도 워커는 열지 않는다(열 수 없어야 정상 — INV-6).
func makeBatch(t *testing.T, adminPool *pgxpool.Pool, f fixture, records string) string {
	t.Helper()
	ctx := context.Background()
	var batchID string
	if err := adminPool.QueryRow(ctx,
		`INSERT INTO ingest_batch (owner_id, account_id, filename, state)
		 VALUES ($1, $2, 'stmt.csv', 'received') RETURNING id::text`,
		f.OwnerID, f.AccountID,
	).Scan(&batchID); err != nil {
		t.Fatal(err)
	}
	payload := fmt.Sprintf(`{
	  "account_id": %q, "filename": "stmt.csv",
	  "file_hash": "%s", "record_count": 0,
	  "records": %s,
	  "cipher": {"alg":"argon2id-chacha20poly1305","salt":"AAAAAAAAAAAAAAAAAAAAAA==",
	             "nonce":"AAAAAAAAAAAAAAAA","m_kib":19456,"t":2,"p":1,"blob":"AAAA"}
	}`, f.AccountID, strings.Repeat("ab", 32), records)
	if _, err := adminPool.Exec(ctx,
		`INSERT INTO ingest_payload (batch_id, payload) VALUES ($1, $2::jsonb)`,
		batchID, payload,
	); err != nil {
		t.Fatal(err)
	}
	return batchID
}

func testLogger() (*slog.Logger, *strings.Builder) {
	var buf strings.Builder
	return slog.New(slog.NewTextHandler(&buf, nil)), &buf
}

func countTxns(t *testing.T, adminPool *pgxpool.Pool, ownerID string) int {
	t.Helper()
	var n int
	if err := adminPool.QueryRow(context.Background(),
		`SELECT count(*) FROM txn WHERE owner_id = $1`, ownerID).Scan(&n); err != nil {
		t.Fatal(err)
	}
	return n
}

func batchState(t *testing.T, adminPool *pgxpool.Pool, batchID string) string {
	t.Helper()
	var s string
	if err := adminPool.QueryRow(context.Background(),
		`SELECT state::text FROM ingest_batch WHERE id = $1`, batchID).Scan(&s); err != nil {
		t.Fatal(err)
	}
	return s
}

// 워커 롤로 소유자 컨텍스트 쿼리를 실행하는 헬퍼 (검증용)
func withOwnerQuery(t *testing.T, pool *pgxpool.Pool, ownerID, sql string, args ...any) int {
	t.Helper()
	var n int
	err := workerdb.WithOwner(context.Background(), pool, ownerID, func(tx pgx.Tx) error {
		return tx.QueryRow(context.Background(), sql, args...).Scan(&n)
	})
	if err != nil {
		t.Fatal(err)
	}
	return n
}
