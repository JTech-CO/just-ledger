-- 01_negative — 불변식 음성 테스트 (M1 DoD 3·4 + INV-2·5)
-- 위반 시도가 "반드시 실패"해야 통과. 각 케이스는 DO 블록에서 해당 SQLSTATE 를 잡는다.
-- deferrable 트리거는 SET CONSTRAINTS ... IMMEDIATE 로 문장 시점으로 당겨 잡는다
-- (진짜 커밋 시점 경로는 run.sh 의 01b 가 별도 psql 로 검증).

\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
  v_owner uuid;
  v_krw1  uuid;
  v_krw2  uuid;
  v_usd   uuid;
  v_txn   uuid;
  v_t2    uuid;
  v_t3    uuid;
  v_link  uuid;
  v_eid   bigint;
BEGIN
  -- ── 픽스처 ─────────────────────────────────────────────────────────────
  INSERT INTO app_user (username) VALUES ('neg_owner') RETURNING id INTO v_owner;
  INSERT INTO account (owner_id, code, name, type, currency)
    VALUES (v_owner, 'NEG.CASH',  '현금',   'asset',   'KRW') RETURNING id INTO v_krw1;
  INSERT INTO account (owner_id, code, name, type, currency)
    VALUES (v_owner, 'NEG.FOOD',  '식비',   'expense', 'KRW') RETURNING id INTO v_krw2;
  INSERT INTO account (owner_id, code, name, type, currency)
    VALUES (v_owner, 'NEG.USD',   '외화',   'asset',   'USD') RETURNING id INTO v_usd;

  -- ── T1. INV-2: amount_minor <= 0 은 CHECK 위반 (23514) ─────────────────
  INSERT INTO txn (owner_id, occurred_on) VALUES (v_owner, '2026-01-05') RETURNING id INTO v_txn;
  BEGIN
    INSERT INTO entry (txn_id, account_id, direction, amount_minor, currency)
      VALUES (v_txn, v_krw1, 'debit', 0, 'KRW');
    RAISE EXCEPTION 'TEST_FAIL: INV-2 — amount_minor=0 이 통과됨';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS T1a INV-2: amount_minor=0 거절 (23514)';
  END;
  BEGIN
    INSERT INTO entry (txn_id, account_id, direction, amount_minor, currency)
      VALUES (v_txn, v_krw1, 'debit', -100, 'KRW');
    RAISE EXCEPTION 'TEST_FAIL: INV-2 — 음수 금액이 통과됨';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS T1b INV-2: 음수 금액 거절 (23514)';
  END;

  -- ── T2. INV-1: 불균형 posted 커밋 시도 (IMMEDIATE 로 당겨 검증) ─────────
  INSERT INTO entry (txn_id, account_id, direction, amount_minor, currency) VALUES
    (v_txn, v_krw1, 'debit',  150000, 'KRW'),
    (v_txn, v_krw2, 'credit', 149999, 'KRW');   -- 1원 어긋남 — 허용 오차 없음
  BEGIN
    SET CONSTRAINTS trg_inv1_txn, trg_inv1_entry IMMEDIATE;
    UPDATE txn SET status = 'posted', posted_at = now() WHERE id = v_txn;
    RAISE EXCEPTION 'TEST_FAIL: INV-1 — 1원 불균형 posted 가 통과됨';
  EXCEPTION WHEN sqlstate 'JL001' THEN
    RAISE NOTICE 'PASS T2 INV-1: 1원 불균형 posted 거절 (JL001)';
  END;
  SET CONSTRAINTS ALL DEFERRED;

  -- ── T3. INV-1: 다통화 혼합 — 통화별로 각각 균형이어야 함 ────────────────
  INSERT INTO txn (owner_id, occurred_on) VALUES (v_owner, '2026-01-06') RETURNING id INTO v_t2;
  INSERT INTO entry (txn_id, account_id, direction, amount_minor, currency) VALUES
    (v_t2, v_krw1, 'debit',  1300000, 'KRW'),
    (v_t2, v_usd,  'credit', 1000,    'USD');   -- 통화별 상대편 부재 → 양쪽 다 불균형
  BEGIN
    SET CONSTRAINTS trg_inv1_txn, trg_inv1_entry IMMEDIATE;
    UPDATE txn SET status = 'posted', posted_at = now() WHERE id = v_t2;
    RAISE EXCEPTION 'TEST_FAIL: INV-1 — 통화 혼합 불균형이 통과됨';
  EXCEPTION WHEN sqlstate 'JL001' THEN
    RAISE NOTICE 'PASS T3 INV-1: 통화별 불균형 거절 (JL001)';
  END;
  SET CONSTRAINTS ALL DEFERRED;

  -- ── T4. INV-1: entry 없는 posted ───────────────────────────────────────
  INSERT INTO txn (owner_id, occurred_on) VALUES (v_owner, '2026-01-07') RETURNING id INTO v_t3;
  BEGIN
    SET CONSTRAINTS trg_inv1_txn, trg_inv1_entry IMMEDIATE;
    UPDATE txn SET status = 'posted', posted_at = now() WHERE id = v_t3;
    RAISE EXCEPTION 'TEST_FAIL: INV-1 — entry 없는 posted 가 통과됨';
  EXCEPTION WHEN sqlstate 'JL001' THEN
    RAISE NOTICE 'PASS T4 INV-1: entry 없는 posted 거절 (JL001)';
  END;
  SET CONSTRAINTS ALL DEFERRED;

  -- ── T5. INV-3: settled 불변 ────────────────────────────────────────────
  -- v_txn 을 균형 맞춰 posted → settled 로 만든다.
  UPDATE entry SET amount_minor = 150000
    WHERE txn_id = v_txn AND direction = 'credit';
  UPDATE txn SET status = 'posted', posted_at = now() WHERE id = v_txn;
  UPDATE txn SET status = 'settled' WHERE id = v_txn;

  BEGIN
    UPDATE txn SET memo = '수정 시도' WHERE id = v_txn;
    RAISE EXCEPTION 'TEST_FAIL: INV-3 — settled txn UPDATE 통과됨';
  EXCEPTION WHEN sqlstate 'JL003' THEN
    RAISE NOTICE 'PASS T5a INV-3: settled txn UPDATE 거절 (JL003)';
  END;
  BEGIN
    DELETE FROM txn WHERE id = v_txn;
    RAISE EXCEPTION 'TEST_FAIL: INV-3 — settled txn DELETE 통과됨';
  EXCEPTION WHEN sqlstate 'JL003' THEN
    RAISE NOTICE 'PASS T5b INV-3: settled txn DELETE 거절 (JL003)';
  END;
  SELECT id INTO v_eid FROM entry WHERE txn_id = v_txn LIMIT 1;
  BEGIN
    UPDATE entry SET amount_minor = amount_minor + 1 WHERE id = v_eid;
    RAISE EXCEPTION 'TEST_FAIL: INV-3 — settled entry UPDATE 통과됨';
  EXCEPTION WHEN sqlstate 'JL003' THEN
    RAISE NOTICE 'PASS T5c INV-3: settled entry UPDATE 거절 (JL003)';
  END;
  BEGIN
    DELETE FROM entry WHERE id = v_eid;
    RAISE EXCEPTION 'TEST_FAIL: INV-3 — settled entry DELETE 통과됨';
  EXCEPTION WHEN sqlstate 'JL003' THEN
    RAISE NOTICE 'PASS T5d INV-3: settled entry DELETE 거절 (JL003)';
  END;
  BEGIN
    INSERT INTO entry (txn_id, account_id, direction, amount_minor, currency)
      VALUES (v_txn, v_krw1, 'debit', 10, 'KRW');
    RAISE EXCEPTION 'TEST_FAIL: INV-3 — settled txn 에 entry INSERT 통과됨';
  EXCEPTION WHEN sqlstate 'JL003' THEN
    RAISE NOTICE 'PASS T5e INV-3: settled txn 에 entry INSERT 거절 (JL003)';
  END;

  -- ── T6. INV-5: 한 txn 은 최대 1개 링크 ─────────────────────────────────
  -- 균형 잡힌 posted txn 3개 (A, B, C)
  DECLARE
    v_a uuid; v_b uuid; v_c uuid; v_lo uuid; v_hi uuid;
  BEGIN
    SELECT t.id INTO v_a FROM (SELECT gen_random_uuid() AS id) t;
    SELECT t.id INTO v_b FROM (SELECT gen_random_uuid() AS id) t;
    SELECT t.id INTO v_c FROM (SELECT gen_random_uuid() AS id) t;
    INSERT INTO txn (id, owner_id, occurred_on, status, posted_at) VALUES
      (v_a, v_owner, '2026-02-01', 'draft', NULL),
      (v_b, v_owner, '2026-02-01', 'draft', NULL),
      (v_c, v_owner, '2026-02-01', 'draft', NULL);
    INSERT INTO entry (txn_id, account_id, direction, amount_minor, currency)
    SELECT t, acc, dir::entry_direction, 5000, 'KRW'
    FROM (VALUES
      (v_a, v_krw1, 'debit'), (v_a, v_krw2, 'credit'),
      (v_b, v_krw1, 'debit'), (v_b, v_krw2, 'credit'),
      (v_c, v_krw1, 'debit'), (v_c, v_krw2, 'credit')
    ) AS x(t, acc, dir);
    UPDATE txn SET status = 'posted', posted_at = now() WHERE id IN (v_a, v_b, v_c);

    -- 정규화 순서 (txn_a < txn_b)
    v_lo := least(v_a, v_b); v_hi := greatest(v_a, v_b);
    INSERT INTO transfer_link (owner_id, txn_a, txn_b, confidence, matched_by)
      VALUES (v_owner, v_lo, v_hi, 95, 'test') RETURNING id INTO v_link;
    RAISE NOTICE 'PASS T6a INV-5: 첫 링크 생성 성공';

    -- A 를 다른 링크에 다시 넣기 (양쪽 컬럼 위치 모두)
    BEGIN
      INSERT INTO transfer_link (owner_id, txn_a, txn_b, confidence, matched_by)
        VALUES (v_owner, least(v_a, v_c), greatest(v_a, v_c), 90, 'test');
      RAISE EXCEPTION 'TEST_FAIL: INV-5 — 중복 링크(A 재사용)가 통과됨';
    EXCEPTION WHEN unique_violation THEN
      RAISE NOTICE 'PASS T6b INV-5: txn 재사용 링크 거절 (23505)';
    END;
    BEGIN
      INSERT INTO transfer_link (owner_id, txn_a, txn_b, confidence, matched_by)
        VALUES (v_owner, least(v_b, v_c), greatest(v_b, v_c), 90, 'test');
      RAISE EXCEPTION 'TEST_FAIL: INV-5 — 중복 링크(B 재사용)가 통과됨';
    EXCEPTION WHEN unique_violation THEN
      RAISE NOTICE 'PASS T6c INV-5: 반대 컬럼 재사용도 거절 (23505)';
    END;
    -- 링크 쌍 수정 금지
    BEGIN
      UPDATE transfer_link SET txn_a = v_c WHERE id = v_link;
      RAISE EXCEPTION 'TEST_FAIL: 링크 쌍 수정이 통과됨';
    EXCEPTION WHEN sqlstate 'JL005' THEN
      RAISE NOTICE 'PASS T6d: 링크 쌍 수정 거절 (JL005)';
    END;
    -- 잘못된 순서 (txn_a > txn_b) 는 CHECK 위반
    BEGIN
      DELETE FROM transfer_link WHERE id = v_link;
      INSERT INTO transfer_link (owner_id, txn_a, txn_b, confidence, matched_by)
        VALUES (v_owner, greatest(v_a, v_b), least(v_a, v_b), 95, 'test');
      RAISE EXCEPTION 'TEST_FAIL: txn_a > txn_b 가 통과됨';
    EXCEPTION WHEN check_violation THEN
      RAISE NOTICE 'PASS T6e: 비정규 순서 거절 (23514)';
    END;
  END;

  -- ── T7. entry 통화 ≠ 계정 통화 → 복합 FK 위반 ──────────────────────────
  DECLARE
    v_t7 uuid;
  BEGIN
    INSERT INTO txn (owner_id, occurred_on) VALUES (v_owner, '2026-03-01') RETURNING id INTO v_t7;
    BEGIN
      INSERT INTO entry (txn_id, account_id, direction, amount_minor, currency)
        VALUES (v_t7, v_krw1, 'debit', 1000, 'USD');
      RAISE EXCEPTION 'TEST_FAIL: KRW 계정에 USD entry 가 통과됨';
    EXCEPTION WHEN foreign_key_violation THEN
      RAISE NOTICE 'PASS T7: entry 통화 ≠ 계정 통화 거절 (23503)';
    END;
  END;

  -- ── T8. fx_rate 유리수 쌍 양수 강제 ────────────────────────────────────
  BEGIN
    INSERT INTO fx_rate (base, quote, as_of, rate_num, rate_den)
      VALUES ('USD', 'KRW', '2026-01-01', 1300000, 0);
    RAISE EXCEPTION 'TEST_FAIL: rate_den=0 이 통과됨';
  EXCEPTION WHEN check_violation THEN
    RAISE NOTICE 'PASS T8: rate_den=0 거절 (23514)';
  END;

  RAISE NOTICE 'OK: 01_negative 전체 통과';
END $$;

ROLLBACK;
