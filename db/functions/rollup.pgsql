-- 잔액 롤업 함수 (M1) — CREATE OR REPLACE 로 반복 적용 가능.
-- 정본 잔액은 account_balance(트리거 증분 유지)이며, 테스트(DoD 5)가
-- 원장 전수 합산과의 전 계정·전 기간 일치를 검증한다.

-- 단일 계정·통화 잔액. 행이 없으면 0.
CREATE OR REPLACE FUNCTION fn_account_balance(p_account uuid, p_currency char(3))
RETURNS bigint
LANGUAGE sql STABLE
AS $$
  SELECT coalesce(
    (SELECT balance_minor FROM account_balance
      WHERE account_id = p_account AND currency = p_currency), 0);
$$;

-- 계층 롤업: p_root 자신 + 모든 하위 계정의 잔액 합 (통화별).
CREATE OR REPLACE FUNCTION fn_subtree_balance(p_root uuid)
RETURNS TABLE (currency char(3), balance_minor bigint)
LANGUAGE sql STABLE
AS $$
  WITH RECURSIVE subtree AS (
    SELECT id FROM account WHERE id = p_root
    UNION ALL
    SELECT a.id FROM account a JOIN subtree s ON a.parent_id = s.id
  )
  SELECT b.currency, sum(b.balance_minor)::bigint
  FROM account_balance b
  JOIN subtree s ON s.id = b.account_id
  GROUP BY b.currency;
$$;

-- 전 계정 잔액 스냅샷 (0 잔액 행 포함) — API 조회·NOTIFY 페이로드 공용.
CREATE OR REPLACE FUNCTION fn_all_balances()
RETURNS TABLE (account_id uuid, currency char(3), balance_minor bigint)
LANGUAGE sql STABLE
AS $$
  SELECT account_id, currency, balance_minor FROM account_balance;
$$;
