-- 01b_deferred_commit — INV-1 의 '진짜' 커밋 시점 거절 경로 검증.
-- 이 파일은 run.sh 가 별도 psql 로 실행하며, "반드시 비정상 종료(JL001)" 해야 통과다.
-- (01_negative 는 SET CONSTRAINTS IMMEDIATE 로 당겨 잡는 경로만 검증한다.)

\set ON_ERROR_STOP on
\set VERBOSITY verbose

BEGIN;

DO $$
DECLARE
  v_owner uuid;
  v_a uuid;
  v_b uuid;
  v_t uuid;
BEGIN
  INSERT INTO app_user (username) VALUES ('deferred_neg_owner') RETURNING id INTO v_owner;
  INSERT INTO account (owner_id, code, name, type, currency)
    VALUES (v_owner, 'DEF.A', 'A', 'asset', 'KRW') RETURNING id INTO v_a;
  INSERT INTO account (owner_id, code, name, type, currency)
    VALUES (v_owner, 'DEF.B', 'B', 'expense', 'KRW') RETURNING id INTO v_b;

  INSERT INTO txn (owner_id, occurred_on) VALUES (v_owner, '2026-04-01') RETURNING id INTO v_t;
  INSERT INTO entry (txn_id, account_id, direction, amount_minor, currency) VALUES
    (v_t, v_a, 'debit',  777777, 'KRW'),
    (v_t, v_b, 'credit', 777776, 'KRW');   -- 1원 불균형
  UPDATE txn SET status = 'posted', posted_at = now() WHERE id = v_t;
  -- 여기서는 아무 에러도 나지 않아야 한다 (deferred). 거절은 COMMIT 에서.
END $$;

COMMIT;   -- ← 이 COMMIT 이 JL001 로 실패해야 한다

-- 여기 도달하면 INV-1 커밋 게이트가 뚫린 것이다.
\echo TEST_FAIL: deferred INV-1 check did not fire at COMMIT
