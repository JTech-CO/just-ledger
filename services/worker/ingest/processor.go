// 인제스트 배치 처리 — 업로드된 봉투(ingest_payload)의 서버 가시 최소 필드로
// draft txn 을 만든다 (백서 §4.2-2: Go 워커가 draft txn 생성).
//
// 상태 기계: received → drafting → done | failed.
// (parsing/deduping 은 클라이언트 WASM 단계 — 서버는 그 상태를 만들지 않는다.
//
//	M8 에서 클라이언트 진행률 보고용으로 쓰일 수 있어 enum 에는 남아 있다.)
//
// 재개(DoD 5): 상태가 비종결인 배치는 스캐너가 다시 집어 처리한다. draft 생성이
// (owner, source_hash) ON CONFLICT DO NOTHING 으로 멱등이라 몇 번을 재실행해도
// 결과가 같다 — 강제 종료 후 재시작 시 미완료 배치가 자동으로 완결된다.
//
// 중복 제거(DoD 2): 동일 파일 재업로드는 같은 지문 집합을 가지므로 신규 txn 0건.
//
// INV-6: 이 패키지는 명세서 내용 필드(적요·상대처)를 아예 읽지 않는다 — 서버 가시
// 필드는 지문·일자·금액·통화뿐이고, 로그에는 id·건수·상태만 남긴다.
package ingest

import (
	"context"
	"errors"
	"fmt"
	"log/slog"
	"regexp"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"

	workerdb "just-ledger/worker/db"
)

// 계약 common.schema.json#/$defs/moneyMinor 와 동일 (최대 18자리)
var moneyRe = regexp.MustCompile(`^(0|-?[1-9][0-9]{0,17})$`)
var hashRe = regexp.MustCompile(`^[0-9a-f]{64}$`)
var dateRe = regexp.MustCompile(`^[0-9]{4}-[0-9]{2}-[0-9]{2}$`)

// 서버 가시 최소 레코드 (contracts/ingest-payload.schema.json records[])
type minimalRecord struct {
	SourceHash  string `json:"source_hash"`
	OccurredOn  string `json:"occurred_on"`
	AmountMinor string `json:"amount_minor"`
	Currency    string `json:"currency"`
}

type Result struct {
	Total    int
	Inserted int
	Skipped  int // 중복(지문 충돌 아님 — 이미 존재) + 0원 레코드
}

// ProcessBatch 는 한 배치를 종결 상태까지 진행한다.
func ProcessBatch(ctx context.Context, pool *pgxpool.Pool, log *slog.Logger, ownerID, batchID string) (Result, error) {
	var res Result

	err := workerdb.WithOwner(ctx, pool, ownerID, func(tx pgx.Tx) error {
		// 배치·페이로드 로드 (RLS 아래 — 소유자 불일치면 0행)
		var state string
		var accountID *string
		if err := tx.QueryRow(ctx,
			`SELECT state, account_id::text FROM ingest_batch WHERE id = $1`, batchID,
		).Scan(&state, &accountID); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return fmt.Errorf("배치 없음 또는 소유자 불일치: %s", batchID)
			}
			return err
		}
		if state == "done" || state == "failed" {
			return nil // 이미 종결 — 멱등
		}
		if accountID == nil {
			return failBatch(ctx, tx, batchID, "배치에 account_id 없음")
		}

		var records []minimalRecord
		if err := tx.QueryRow(ctx,
			`SELECT coalesce(payload->'records', '[]'::jsonb) FROM ingest_payload WHERE batch_id = $1`,
			batchID,
		).Scan(&records); err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				return failBatch(ctx, tx, batchID, "페이로드 없음")
			}
			return err
		}
		res.Total = len(records)

		if _, err := tx.Exec(ctx,
			`UPDATE ingest_batch SET state = 'drafting', started_at = coalesce(started_at, now())
			 WHERE id = $1`, batchID); err != nil {
			return err
		}

		for i, r := range records {
			if !hashRe.MatchString(r.SourceHash) || !dateRe.MatchString(r.OccurredOn) ||
				!moneyRe.MatchString(r.AmountMinor) {
				// 내용은 로그에 남기지 않는다 (INV-6) — 위치만
				return failBatch(ctx, tx, batchID, fmt.Sprintf("레코드 %d 형식 위반", i))
			}
			if r.AmountMinor == "0" {
				res.Skipped++ // 0원 레코드는 분개 불가(INV-2) — 건너뜀
				continue
			}

			// draft txn (중복이면 스킵 — DoD 2). 금액·지문은 텍스트로 넘겨 SQL 에서 캐스팅.
			var txnID *string
			err := tx.QueryRow(ctx,
				`INSERT INTO txn (owner_id, occurred_on, status, source_hash, batch_id)
				 VALUES ($1, $2::date, 'draft', decode($3, 'hex'), $4)
				 ON CONFLICT (owner_id, source_hash) WHERE source_hash IS NOT NULL DO NOTHING
				 RETURNING id::text`,
				ownerID, r.OccurredOn, r.SourceHash, batchID,
			).Scan(&txnID)
			if errors.Is(err, pgx.ErrNoRows) {
				res.Skipped++ // 이미 존재 (재업로드)
				continue
			}
			if err != nil {
				return err
			}

			// 은행 계정 다리 한 개: 입금(+) = 차변, 출금(-) = 대변. 상대 다리는 분류(M4).
			direction := "debit"
			amount := r.AmountMinor
			if amount[0] == '-' {
				direction = "credit"
				amount = amount[1:]
			}
			if _, err := tx.Exec(ctx,
				`INSERT INTO entry (txn_id, account_id, direction, amount_minor, currency)
				 VALUES ($1, $2, $3, $4::bigint, $5)`,
				*txnID, *accountID, direction, amount, r.Currency,
			); err != nil {
				return err
			}
			res.Inserted++
		}

		_, err := tx.Exec(ctx,
			`UPDATE ingest_batch SET state = 'done', finished_at = now(), row_count = $2
			 WHERE id = $1`, batchID, res.Total)
		return err
	})
	if err != nil {
		// 실패를 배치 상태에 반영 (별도 트랜잭션 — 본 트랜잭션은 롤백됐다)
		if markErr := markFailed(ctx, pool, ownerID, batchID); markErr != nil {
			log.Error("배치 실패 표기 불가", "batch", batchID, "err", markErr)
		}
		log.Error("배치 처리 실패", "batch", batchID, "err", err)
		return res, err
	}

	log.Info("배치 처리 완료",
		"batch", batchID, "total", res.Total, "inserted", res.Inserted, "skipped", res.Skipped)
	return res, nil
}

// failBatch 는 검증 실패를 종결 상태로 만들고, 처리 함수를 정상 종료시킨다
// (재시도해도 같은 입력이면 같은 실패 — 무한 재개 루프 방지).
func failBatch(ctx context.Context, tx pgx.Tx, batchID, reason string) error {
	if _, err := tx.Exec(ctx,
		`UPDATE ingest_batch SET state = 'failed', finished_at = now() WHERE id = $1`, batchID); err != nil {
		return err
	}
	// reason 은 내용 없는 위치 정보만 담는다 (INV-6)
	return fmt.Errorf("배치 %s 실패: %s", batchID, reason)
}

func markFailed(ctx context.Context, pool *pgxpool.Pool, ownerID, batchID string) error {
	return workerdb.WithOwner(ctx, pool, ownerID, func(tx pgx.Tx) error {
		_, err := tx.Exec(ctx,
			`UPDATE ingest_batch SET state = 'failed', finished_at = now()
			 WHERE id = $1 AND state NOT IN ('done', 'failed')`, batchID)
		return err
	})
}
