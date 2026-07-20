-- 01c_rls_role_inv — 실제 운영 역할(ledger_app) + RLS 활성 환경에서 불변식이
-- 여전히 강제되는지 검증한다. 적대 검증이 찾은 blocker 의 회귀 테스트:
-- "쓰기 후 app.user_id GUC 변경 → COMMIT" 으로 INV-1 검사를 우회하려는 시도가
-- 반드시 실패해야 한다. run.sh 가 별도 psql 로 실행하며 비정상 종료(JL001)해야 통과.

\set ON_ERROR_STOP on
\set VERBOSITY verbose

-- 픽스처는 테이블 소유자 권한으로 준비하고, 우회 시도는 ledger_app 으로 수행한다.
DO $$
DECLARE
  v_u uuid; v_a uuid; v_b uuid;
BEGIN
  INSERT INTO app_user (username) VALUES ('rls_inv_owner') RETURNING id INTO v_u;
  INSERT INTO account (owner_id, code, name, type, currency)
    VALUES (v_u, 'RIV.A', 'A', 'asset', 'KRW') RETURNING id INTO v_a;
  INSERT INTO account (owner_id, code, name, type, currency)
    VALUES (v_u, 'RIV.B', 'B', 'expense', 'KRW') RETURNING id INTO v_b;
  PERFORM set_config('test.owner', v_u::text, false);
  PERFORM set_config('test.a', v_a::text, false);
  PERFORM set_config('test.b', v_b::text, false);
END $$;

-- 앞서 심은 uuid 를 세션 GUC 로 넘긴다 (SET ROLE 후에도 유지)
SET ROLE ledger_app;

BEGIN;
  SELECT set_config('app.user_id', current_setting('test.owner'), false);

  -- 불균형(대변 없는 단일 레그) posted txn 을 만든다
  INSERT INTO txn (id, owner_id, occurred_on, status)
    VALUES (gen_random_uuid(), current_setting('test.owner')::uuid, '2026-07-10', 'draft');

  -- 방금 만든 txn 을 찾아 entry 1건(불균형)만 붙이고 posted 로 전이
  DO $$
  DECLARE v_t uuid;
  BEGIN
    SELECT id INTO v_t FROM txn
      WHERE owner_id = current_setting('test.owner')::uuid AND occurred_on = '2026-07-10'
      ORDER BY id DESC LIMIT 1;
    INSERT INTO entry (txn_id, account_id, direction, amount_minor, currency)
      VALUES (v_t, current_setting('test.a')::uuid, 'debit', 500000, 'KRW');
    UPDATE txn SET status = 'posted', posted_at = now() WHERE id = v_t;
  END $$;

  -- ★ 우회 시도: 커밋 직전에 소유자 GUC 를 비운다.
  -- INVOKER 검사였다면 이 시점 txn 이 RLS 로 안 보여 INV-1 이 스킵됐다.
  SELECT set_config('app.user_id', '', false);

COMMIT;   -- ← SECURITY DEFINER 검사라면 여기서 JL001 로 반드시 실패해야 한다

\echo TEST_FAIL: RLS 역할에서 GUC 우회로 불균형 posted 커밋이 통과됨 (INV-1 무력화)
