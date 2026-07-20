-- 04_rls — 소유자 격리 (기술 백서 §7). 두 소유자를 만들고 교차 접근이 전부
-- 차단되는지, 서비스 역할에 BYPASSRLS 가 없는지 검증한다.
--
-- 주의: SET ROLE 후에는 RLS 때문에 타인 행(uuid 포함)을 조회할 수 없으므로,
-- 테스트에 필요한 uuid 는 역할 전환 '전에' 세션 GUC 로 심어 둔다.

\set ON_ERROR_STOP on

BEGIN;

-- 픽스처 (마이그레이션 적용 계정으로 실행 — 테이블 소유자라 RLS 미적용)
DO $$
DECLARE
  v_u1 uuid; v_u2 uuid; v_a1 uuid; v_a2 uuid; v_t1 uuid; v_t2 uuid; v_b2 uuid;
BEGIN
  INSERT INTO app_user (username) VALUES ('rls_u1') RETURNING id INTO v_u1;
  INSERT INTO app_user (username) VALUES ('rls_u2') RETURNING id INTO v_u2;
  INSERT INTO account (owner_id, code, name, type, currency)
    VALUES (v_u1, 'RLS.A1', 'u1 현금', 'asset', 'KRW') RETURNING id INTO v_a1;
  INSERT INTO account (owner_id, code, name, type, currency)
    VALUES (v_u2, 'RLS.A2', 'u2 현금', 'asset', 'KRW') RETURNING id INTO v_a2;
  INSERT INTO account (owner_id, code, name, type, currency)
    VALUES (v_u2, 'RLS.B2', 'u2 식비', 'expense', 'KRW') RETURNING id INTO v_b2;
  INSERT INTO txn (owner_id, occurred_on, memo) VALUES (v_u1, '2026-05-01', 'u1 거래') RETURNING id INTO v_t1;
  -- u2 의 균형 잡힌 posted txn 2개 (u1 이 링크 점유를 시도할 대상)
  INSERT INTO txn (owner_id, occurred_on, memo, status, posted_at)
    VALUES (v_u2, '2026-05-01', 'u2 거래', 'draft', NULL) RETURNING id INTO v_t2;
  INSERT INTO entry (txn_id, account_id, direction, amount_minor, currency) VALUES
    (v_t2, v_a2, 'debit', 3000, 'KRW'), (v_t2, v_b2, 'credit', 3000, 'KRW');
  UPDATE txn SET status = 'posted', posted_at = now() WHERE id = v_t2;

  -- 역할 전환 후에도 읽을 수 있도록 세션 GUC 에 심는다 (SET ROLE 은 GUC 를 유지)
  PERFORM set_config('app.user_id', v_u1::text, false);   -- u1 으로 로그인한 상태
  PERFORM set_config('test.u1_id',  v_u1::text, false);
  PERFORM set_config('test.u2_id',  v_u2::text, false);   -- 침해 대상
  PERFORM set_config('test.a2_id',  v_a2::text, false);
  PERFORM set_config('test.t1_id',  v_t1::text, false);   -- u1 자기 draft txn
  PERFORM set_config('test.u2_t2',  v_t2::text, false);   -- u2 posted txn
END $$;

-- ── ledger_app 역할로 u1 세션 시뮬레이션 ─────────────────────────────────
SET ROLE ledger_app;

DO $$
DECLARE
  v_visible bigint;
  v_affected bigint;
BEGIN
  IF current_owner() IS NULL THEN
    RAISE EXCEPTION 'TEST_SETUP: app.user_id 가 비어 있음';
  END IF;

  -- R1/R2: 자기 행만 보인다
  SELECT count(*) INTO v_visible FROM account WHERE code LIKE 'RLS.%';
  IF v_visible <> 1 THEN
    RAISE EXCEPTION 'TEST_FAIL: u1 에게 계정 %개 노출 (기대 1)', v_visible;
  END IF;
  RAISE NOTICE 'PASS R1: 타인 계정 비노출';

  SELECT count(*) INTO v_visible FROM txn WHERE memo LIKE 'u%거래';
  IF v_visible <> 1 THEN
    RAISE EXCEPTION 'TEST_FAIL: u1 에게 txn %건 노출 (기대 1)', v_visible;
  END IF;
  RAISE NOTICE 'PASS R2: 타인 txn 비노출';

  -- R3/R4: 타인 행 UPDATE/DELETE → 0건 (가시성 차단)
  UPDATE account SET name = '탈취' WHERE id = current_setting('test.a2_id')::uuid;
  GET DIAGNOSTICS v_affected = ROW_COUNT;
  IF v_affected <> 0 THEN
    RAISE EXCEPTION 'TEST_FAIL: 타인 계정 UPDATE 가 %건 적용됨', v_affected;
  END IF;
  RAISE NOTICE 'PASS R3: 타인 계정 UPDATE 0건';

  DELETE FROM txn WHERE memo = 'u2 거래';
  GET DIAGNOSTICS v_affected = ROW_COUNT;
  IF v_affected <> 0 THEN
    RAISE EXCEPTION 'TEST_FAIL: 타인 txn DELETE 가 %건 적용됨', v_affected;
  END IF;
  RAISE NOTICE 'PASS R4: 타인 txn DELETE 0건';

  -- R5: 타인 owner_id 로 계정 INSERT → RLS WITH CHECK 위반 (42501)
  BEGIN
    INSERT INTO account (owner_id, code, name, type, currency)
      VALUES (current_setting('test.u2_id')::uuid, 'RLS.X', 'x', 'asset', 'KRW');
    RAISE EXCEPTION 'TEST_FAIL: 타인 소유 계정 INSERT 가 통과됨';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS R5: 타인 소유 계정 INSERT 차단 (42501)';
  END;

  -- R6: 타인 owner_id 로 txn INSERT → 42501
  BEGIN
    INSERT INTO txn (owner_id, occurred_on)
      VALUES (current_setting('test.u2_id')::uuid, '2026-05-02');
    RAISE EXCEPTION 'TEST_FAIL: 타인 소유 txn INSERT 가 통과됨';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS R6: 타인 소유 txn INSERT 차단 (42501)';
  END;

  -- R6b: 잔액 유지 내부 헬퍼 직접 호출 차단 (PUBLIC EXECUTE 회수 확인)
  BEGIN
    PERFORM fn_bal_apply(gen_random_uuid(), 'KRW', 999999);
    RAISE EXCEPTION 'TEST_FAIL: 앱 역할이 fn_bal_apply 를 직접 호출함';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS R6b: fn_bal_apply 직접 호출 차단 (42501)';
  END;

  -- R6b2: INV-1 내부 검사 함수 직접 호출 차단 (DEFINER 오라클 방지)
  BEGIN
    PERFORM fn_inv1_check(current_setting('test.u2_t2')::uuid);
    RAISE EXCEPTION 'TEST_FAIL: 앱 역할이 fn_inv1_check 를 직접 호출함 (오라클)';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS R6b2: fn_inv1_check 직접 호출 차단 (42501)';
  END;

  -- R6c: 자기 txn 에 타 소유자 계정으로 entry INSERT → entry WITH CHECK 위반 (42501)
  -- (FK RI 는 RLS 를 우회하므로 정책이 계정 소유를 함께 검사하지 않으면 뚫린다)
  BEGIN
    INSERT INTO entry (txn_id, account_id, direction, amount_minor, currency)
      VALUES (current_setting('test.t1_id')::uuid,
              current_setting('test.a2_id')::uuid, 'debit', 10000, 'KRW');
    RAISE EXCEPTION 'TEST_FAIL: 타 소유자 계정으로 entry INSERT 가 통과됨';
  EXCEPTION WHEN insufficient_privilege THEN
    RAISE NOTICE 'PASS R6c: 타 소유자 계정 entry INSERT 차단 (42501)';
  END;

  -- R6d: u2 의 txn 두 개를 u1 소유 링크로 점유 시도 → 복합 FK 위반 (23503)
  -- (txn_a, owner_id) 가 txn(id, owner_id) 를 참조하므로 (u2txn, u1) 조합은 없음
  BEGIN
    INSERT INTO transfer_link (owner_id, txn_a, txn_b, confidence, matched_by)
      VALUES (current_setting('test.u1_id')::uuid,
              least(current_setting('test.u2_t2')::uuid, current_setting('test.t1_id')::uuid),
              greatest(current_setting('test.u2_t2')::uuid, current_setting('test.t1_id')::uuid),
              90, 'attack');
    RAISE EXCEPTION 'TEST_FAIL: 타 소유자 txn 을 링크로 점유함';
  EXCEPTION WHEN foreign_key_violation THEN
    RAISE NOTICE 'PASS R6d: 타 소유자 txn 링크 차단 (23503, 복합 FK)';
  END;

  -- R7: 세션 소유자 미설정(fail-closed) — 전부 비노출
  PERFORM set_config('app.user_id', '', true);
  SELECT count(*) INTO v_visible FROM account;
  IF v_visible <> 0 THEN
    RAISE EXCEPTION 'TEST_FAIL: 소유자 미설정인데 계정 %개 노출', v_visible;
  END IF;
  RAISE NOTICE 'PASS R7: 소유자 미설정 시 0행 (fail-closed)';
END $$;

RESET ROLE;

-- ── 서비스 역할에 BYPASSRLS 없음 (§7) ────────────────────────────────────
DO $$
DECLARE
  v_bad bigint;
BEGIN
  SELECT count(*) INTO v_bad
  FROM pg_roles
  WHERE rolname IN ('ledger_app', 'ledger_worker', 'ledger_realtime')
    AND (rolbypassrls OR rolsuper);
  IF v_bad <> 0 THEN
    RAISE EXCEPTION 'TEST_FAIL: 서비스 역할 %개가 BYPASSRLS/SUPERUSER 보유', v_bad;
  END IF;
  RAISE NOTICE 'PASS R8: 서비스 역할 BYPASSRLS 없음';

  RAISE NOTICE 'OK: 04_rls 전체 통과';
END $$;

ROLLBACK;
