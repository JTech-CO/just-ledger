-- RLS — 계정 소유자 격리 (기술 백서 §7). 반복 적용 가능.
--
-- 현재 사용자는 세션 GUC 'app.user_id' 로 전달된다 (서버가 인증 후 set_config).
-- 미설정이면 current_owner() 가 NULL → 모든 정책이 false → 아무 행도 보이지 않는다
-- (기본 차단, fail-closed). 서비스 역할(ledger_*)은 BYPASSRLS 를 갖지 않는다.

CREATE OR REPLACE FUNCTION current_owner() RETURNS uuid
LANGUAGE plpgsql STABLE
AS $$
BEGIN
  RETURN nullif(current_setting('app.user_id', true), '')::uuid;
EXCEPTION WHEN invalid_text_representation THEN
  RETURN NULL;
END $$;

-- ── owner_id 직접 보유 테이블 ─────────────────────────────────────────────
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'account', 'txn', 'category_rule', 'budget', 'automation_script',
    'ingest_batch', 'settlement_run', 'transfer_link', 'report_artifact'
  ] LOOP
    EXECUTE format('ALTER TABLE %I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('DROP POLICY IF EXISTS p_owner_all ON %I', t);
    EXECUTE format(
      'CREATE POLICY p_owner_all ON %I FOR ALL '
      'USING (owner_id = current_owner()) '
      'WITH CHECK (owner_id = current_owner())', t);
  END LOOP;
END $$;

-- ── entry: 소유권은 부모 txn 을 따르며, 계정도 자기 소유여야 한다 ──────────
-- WITH CHECK 에 account 소유를 함께 검사하지 않으면, FK(RI 트리거는 RLS 우회)를 통해
-- 자기 txn 으로 타 소유자 계정에 entry 를 붙여 그 계정 잔액을 오염시킬 수 있다(적대 검증 발견).
ALTER TABLE entry ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS p_owner_all ON entry;
CREATE POLICY p_owner_all ON entry FOR ALL
  USING (EXISTS (SELECT 1 FROM txn t
                 WHERE t.id = entry.txn_id AND t.owner_id = current_owner()))
  WITH CHECK (EXISTS (SELECT 1 FROM txn t
                      WHERE t.id = entry.txn_id AND t.owner_id = current_owner())
              AND EXISTS (SELECT 1 FROM account a
                          WHERE a.id = entry.account_id AND a.owner_id = current_owner()));

-- ── account_balance: 소유권은 account 를 따른다 ──────────────────────────
ALTER TABLE account_balance ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS p_owner_all ON account_balance;
CREATE POLICY p_owner_all ON account_balance FOR ALL
  USING (EXISTS (SELECT 1 FROM account a
                 WHERE a.id = account_balance.account_id AND a.owner_id = current_owner()))
  WITH CHECK (EXISTS (SELECT 1 FROM account a
                      WHERE a.id = account_balance.account_id AND a.owner_id = current_owner()));

-- ── transfer_link_member: 소유권은 link 를 따른다 ────────────────────────
ALTER TABLE transfer_link_member ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS p_owner_all ON transfer_link_member;
CREATE POLICY p_owner_all ON transfer_link_member FOR ALL
  USING (EXISTS (SELECT 1 FROM transfer_link l
                 WHERE l.id = transfer_link_member.link_id AND l.owner_id = current_owner()))
  WITH CHECK (EXISTS (SELECT 1 FROM transfer_link l
                      WHERE l.id = transfer_link_member.link_id AND l.owner_id = current_owner()));

-- ── ingest_payload: 소유권은 배치를 따른다 ───────────────────────────────
ALTER TABLE ingest_payload ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS p_owner_all ON ingest_payload;
CREATE POLICY p_owner_all ON ingest_payload FOR ALL
  USING (EXISTS (SELECT 1 FROM ingest_batch b
                 WHERE b.id = ingest_payload.batch_id AND b.owner_id = current_owner()))
  WITH CHECK (EXISTS (SELECT 1 FROM ingest_batch b
                      WHERE b.id = ingest_payload.batch_id AND b.owner_id = current_owner()));

-- app_user: 자기 행만 조회 가능 (생성·관리는 M2 인증 경로에서 확정)
ALTER TABLE app_user ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS p_self ON app_user;
CREATE POLICY p_self ON app_user FOR SELECT
  USING (id = current_owner());

-- fx_rate 는 전역 참조 데이터 — RLS 를 켜지 않는다 (쓰기는 worker 권한으로 제한).
