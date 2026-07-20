-- 05_notify — NOTIFY 페이로드 계약 준수 (M1 DoD 6)
-- 같은 세션에서 LISTEN 한 뒤 세 종류 이벤트를 발생시킨다. psql 이 stdout 에 찍는
-- "Asynchronous notification ... with payload ..." 행을 run.sh 가 추출해
-- contracts/notify-event.schema.json 으로 검증한다 (ajv — 계약이 단일 진실원천).

\set ON_ERROR_STOP on

LISTEN ledger_events;

-- ── balance_changed: draft → posted 전이 ─────────────────────────────────
DO $$
DECLARE
  v_owner uuid; v_a uuid; v_b uuid; v_t uuid;
BEGIN
  INSERT INTO app_user (username) VALUES ('notify_owner') RETURNING id INTO v_owner;
  INSERT INTO account (owner_id, code, name, type, currency)
    VALUES (v_owner, 'NTF.A', '알림A', 'asset', 'KRW') RETURNING id INTO v_a;
  INSERT INTO account (owner_id, code, name, type, currency)
    VALUES (v_owner, 'NTF.B', '알림B', 'expense', 'KRW') RETURNING id INTO v_b;
  INSERT INTO txn (owner_id, occurred_on) VALUES (v_owner, '2026-06-01') RETURNING id INTO v_t;
  INSERT INTO entry (txn_id, account_id, direction, amount_minor, currency) VALUES
    (v_t, v_b, 'debit',  42000, 'KRW'),
    (v_t, v_a, 'credit', 42000, 'KRW');
  UPDATE txn SET status = 'posted', posted_at = now() WHERE id = v_t;
END $$;

SELECT 1 AS flush_1;   -- 알림 수신 플러시

-- ── balance_changed: posted txn 에 entry 추가 (음수 잔액 경로 포함) ────────
DO $$
DECLARE
  v_t uuid; v_a uuid; v_b uuid;
BEGIN
  SELECT a.id INTO v_a FROM account a WHERE a.code = 'NTF.A';
  SELECT a.id INTO v_b FROM account a WHERE a.code = 'NTF.B';
  SELECT t.id INTO v_t FROM txn t JOIN app_user u ON u.id = t.owner_id
    WHERE u.username = 'notify_owner' LIMIT 1;
  INSERT INTO entry (txn_id, account_id, direction, amount_minor, currency) VALUES
    (v_t, v_b, 'debit',  8000, 'KRW'),
    (v_t, v_a, 'credit', 8000, 'KRW');
END $$;

SELECT 1 AS flush_2;

-- ── ingest_progress: 배치 생성 + 상태 전이 ────────────────────────────────
DO $$
DECLARE
  v_owner uuid; v_batch uuid;
BEGIN
  SELECT id INTO v_owner FROM app_user WHERE username = 'notify_owner';
  INSERT INTO ingest_batch (owner_id, filename, state)
    VALUES (v_owner, 'stmt-2026-06.csv', 'received') RETURNING id INTO v_batch;
  UPDATE ingest_batch SET state = 'parsing', started_at = now() WHERE id = v_batch;
  UPDATE ingest_batch SET state = 'done', finished_at = now(), row_count = 120 WHERE id = v_batch;
END $$;

SELECT 1 AS flush_3;

-- ── settlement_done ──────────────────────────────────────────────────────
DO $$
DECLARE
  v_owner uuid;
BEGIN
  SELECT id INTO v_owner FROM app_user WHERE username = 'notify_owner';
  INSERT INTO settlement_run (owner_id, period, cobol_exit, report_path)
    VALUES (v_owner, daterange('2026-05-01', '2026-06-01', '[)'), 0, '/reports/2026-05.txt');
END $$;

SELECT pg_sleep(0.2);
SELECT 1 AS flush_final;
