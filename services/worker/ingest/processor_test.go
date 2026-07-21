// M3 인제스트 통합 테스트 (실제 PostgreSQL + 워커 롤/RLS 경로).
//
//	DoD 2: 동일 파일 재업로드 시 신규 txn 0건
//	DoD 5: 미완료 배치 자동 재개 (멱등 재처리)
//	INV-6: 서버(DB·로그)에 평문 적요·상대처 부재
package ingest

import (
	"context"
	"strings"
	"testing"
)

// kb 골든과 같은 형태의 서버 가시 최소 레코드 3건 (지문은 64-hex 형식만 맞으면 됨)
const recs3 = `[
  {"source_hash":"` + h1 + `","occurred_on":"2026-06-02","amount_minor":"-4500","currency":"KRW"},
  {"source_hash":"` + h2 + `","occurred_on":"2026-06-05","amount_minor":"3500000","currency":"KRW"},
  {"source_hash":"` + h3 + `","occurred_on":"2026-06-15","amount_minor":"-200000","currency":"KRW"}
]`

const (
	h1 = "1111111111111111111111111111111111111111111111111111111111111111"
	h2 = "2222222222222222222222222222222222222222222222222222222222222222"
	h3 = "3333333333333333333333333333333333333333333333333333333333333333"
)

func TestProcessBatchCreatesDrafts(t *testing.T) {
	pool, admin, _ := createScratch(t, "wk_drafts")
	f := makeFixture(t, admin, "drafts")
	batch := makeBatch(t, admin, f, recs3)
	log, _ := testLogger()

	res, err := ProcessBatch(context.Background(), pool, log, f.OwnerID, batch)
	if err != nil {
		t.Fatal(err)
	}
	if res.Inserted != 3 || res.Skipped != 0 {
		t.Fatalf("inserted=%d skipped=%d (기대 3/0)", res.Inserted, res.Skipped)
	}
	if s := batchState(t, admin, batch); s != "done" {
		t.Fatalf("배치 상태 %s (기대 done)", s)
	}
	if n := countTxns(t, admin, f.OwnerID); n != 3 {
		t.Fatalf("txn %d건 (기대 3)", n)
	}
	// 각 draft 는 은행 계정 다리 1개: 출금 → credit, 입금 → debit
	nCredit := withOwnerQuery(t, pool, f.OwnerID,
		`SELECT count(*) FROM entry e JOIN txn tx ON tx.id = e.txn_id
		 WHERE e.direction = 'credit' AND e.account_id = $1`, f.AccountID)
	if nCredit != 2 {
		t.Fatalf("credit 다리 %d (기대 2 — 출금 2건)", nCredit)
	}
}

// M3 DoD 2 — 동일 파일 재업로드(같은 지문 집합) 시 신규 txn 0건
func TestReuploadCreatesZeroNewTxns(t *testing.T) {
	pool, admin, _ := createScratch(t, "wk_dedup")
	f := makeFixture(t, admin, "dedup")
	log, _ := testLogger()

	b1 := makeBatch(t, admin, f, recs3)
	if _, err := ProcessBatch(context.Background(), pool, log, f.OwnerID, b1); err != nil {
		t.Fatal(err)
	}
	before := countTxns(t, admin, f.OwnerID)

	b2 := makeBatch(t, admin, f, recs3) // 재업로드 = 새 배치, 같은 지문
	res, err := ProcessBatch(context.Background(), pool, log, f.OwnerID, b2)
	if err != nil {
		t.Fatal(err)
	}
	if res.Inserted != 0 || res.Skipped != 3 {
		t.Fatalf("재업로드 inserted=%d skipped=%d (기대 0/3)", res.Inserted, res.Skipped)
	}
	if after := countTxns(t, admin, f.OwnerID); after != before {
		t.Fatalf("재업로드 후 txn %d → %d — 신규 생성됨 (DoD 2 위반)", before, after)
	}
	if s := batchState(t, admin, b2); s != "done" {
		t.Fatalf("재업로드 배치 상태 %s (기대 done)", s)
	}
}

// M3 DoD 5 — 미완료(비종결) 상태로 남은 배치가 재처리로 완결되고, 부분 진행분과
// 중복되지 않는다 (강제 종료 후 재시작 시나리오의 서버측 등가물)
func TestResumeIncompleteBatch(t *testing.T) {
	pool, admin, _ := createScratch(t, "wk_resume")
	f := makeFixture(t, admin, "resume")
	log, _ := testLogger()

	batch := makeBatch(t, admin, f, recs3)
	ctx := context.Background()

	// 크래시 시뮬레이션: 첫 레코드만 수동 반영하고 상태를 drafting 에 남겨 둔다
	if _, err := admin.Exec(ctx,
		`UPDATE ingest_batch SET state = 'drafting', started_at = now() WHERE id = $1`, batch); err != nil {
		t.Fatal(err)
	}
	if _, err := admin.Exec(ctx,
		`INSERT INTO txn (owner_id, occurred_on, status, source_hash, batch_id)
		 VALUES ($1, '2026-06-02', 'draft', decode($2, 'hex'), $3)`,
		f.OwnerID, h1, batch); err != nil {
		t.Fatal(err)
	}

	// 재시작한 워커가 배치를 다시 집는다 (fn_pending_ingest_batches 경유 확인)
	rows, err := pool.Query(ctx, `SELECT batch_id::text FROM fn_pending_ingest_batches()`)
	if err != nil {
		t.Fatal(err)
	}
	found := false
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			t.Fatal(err)
		}
		if id == batch {
			found = true
		}
	}
	rows.Close()
	if !found {
		t.Fatal("미완료 배치가 pending 조회에 나타나지 않음 (DoD 5 전제 붕괴)")
	}

	if _, err := ProcessBatch(ctx, pool, log, f.OwnerID, batch); err != nil {
		t.Fatal(err)
	}
	if s := batchState(t, admin, batch); s != "done" {
		t.Fatalf("재개 후 상태 %s (기대 done)", s)
	}
	// 부분 진행분(h1) + 나머지 2건 = 3건 정확히 (중복 없음)
	if n := countTxns(t, admin, f.OwnerID); n != 3 {
		t.Fatalf("재개 후 txn %d건 (기대 3 — 멱등 위반)", n)
	}
}

func TestZeroAmountSkippedAndBadRecordFails(t *testing.T) {
	pool, admin, _ := createScratch(t, "wk_edge")
	f := makeFixture(t, admin, "edge")
	log, _ := testLogger()
	ctx := context.Background()

	// 0원 레코드는 건너뛴다 (INV-2: entry 는 양수만)
	zero := `[{"source_hash":"` + h1 + `","occurred_on":"2026-06-01","amount_minor":"0","currency":"KRW"}]`
	b1 := makeBatch(t, admin, f, zero)
	res, err := ProcessBatch(ctx, pool, log, f.OwnerID, b1)
	if err != nil {
		t.Fatal(err)
	}
	if res.Inserted != 0 || res.Skipped != 1 {
		t.Fatalf("0원 레코드 inserted=%d skipped=%d (기대 0/1)", res.Inserted, res.Skipped)
	}

	// 금액 형식 위반(소수점) → 배치 failed (조용한 절삭 금지)
	bad := `[{"source_hash":"` + h2 + `","occurred_on":"2026-06-01","amount_minor":"1500.00","currency":"KRW"}]`
	b2 := makeBatch(t, admin, f, bad)
	if _, err := ProcessBatch(ctx, pool, log, f.OwnerID, b2); err == nil {
		t.Fatal("형식 위반 레코드가 통과됨")
	}
	if s := batchState(t, admin, b2); s != "failed" {
		t.Fatalf("형식 위반 배치 상태 %s (기대 failed)", s)
	}

	// 통화 불일치(USD 레코드, KRW 계정) → 복합 FK 거절 → failed
	usd := `[{"source_hash":"` + h3 + `","occurred_on":"2026-06-01","amount_minor":"-1000","currency":"USD"}]`
	b3 := makeBatch(t, admin, f, usd)
	if _, err := ProcessBatch(ctx, pool, log, f.OwnerID, b3); err == nil {
		t.Fatal("통화 불일치가 통과됨")
	}
	if s := batchState(t, admin, b3); s != "failed" {
		t.Fatalf("통화 불일치 배치 상태 %s (기대 failed)", s)
	}
}

// INV-6 서버측 — 처리 후 DB 어디에도, 워커 로그 어디에도 평문 적요·상대처가 없다.
// (페이로드에 애초에 없고, 워커는 내용 필드를 읽지도 로그하지도 않는다)
func TestNoPlaintextOnServer(t *testing.T) {
	pool, admin, testURL := createScratch(t, "wk_inv6")
	f := makeFixture(t, admin, "inv6")
	log, logBuf := testLogger()
	ctx := context.Background()

	batch := makeBatch(t, admin, f, recs3)
	if _, err := ProcessBatch(ctx, pool, log, f.OwnerID, batch); err != nil {
		t.Fatal(err)
	}

	// DB 전 텍스트 표면 검사: 민감 단어가 어떤 행에도 없어야 한다
	// (실제 명세서라면 '스타벅스' 같은 상대처가 여기 있었을 것 — 봉투 설계가 막는다)
	for _, probe := range []string{"스타벅스", "적요", "상대처테스트"} {
		var n int
		if err := admin.QueryRow(ctx, `
			SELECT (SELECT count(*) FROM ingest_payload WHERE payload::text LIKE '%'||$1||'%')
			     + (SELECT count(*) FROM ingest_batch  WHERE filename LIKE '%'||$1||'%')
			     + (SELECT count(*) FROM txn           WHERE memo LIKE '%'||$1||'%')`,
			probe).Scan(&n); err != nil {
			t.Fatal(err)
		}
		if n != 0 {
			t.Fatalf("INV-6 위반: %q 이 서버 저장소에 존재", probe)
		}
	}

	// 워커 로그 표면: id·건수·상태만 있어야 한다
	logs := logBuf.String()
	for _, probe := range []string{"amount_minor", "source_hash", "-4500", "3500000"} {
		if strings.Contains(logs, probe) {
			t.Fatalf("워커 로그에 레코드 내용 노출: %q\n%s", probe, logs)
		}
	}
	_ = testURL
}
