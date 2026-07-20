-- 03_rollup_parity — 잔액 롤업 = 원장 전수 합산, 전 계정·전 기간 일치 (M1 DoD 5)
-- 02_bulk_100k 가 만든 데이터(10만 posted txn)를 대상으로 세 방향에서 대조한다.
--   A. 계정 잔액: account_balance(증분 유지) ↔ entry 전수 재집계
--   B. 계층 롤업: fn_subtree_balance ↔ 재귀 전수 재집계
--   C. 기간 집계: v_period_totals ↔ 월별 전수 재집계

\set ON_ERROR_STOP on
\timing on

DO $$
DECLARE
  v_bad bigint;
  v_cnt bigint;
BEGIN
  -- ── A. 계정 잔액 전수 대조 (0 잔액 포함 완전 외부 조인) ──────────────────
  SELECT count(*) INTO v_bad
  FROM (
    SELECT coalesce(b.account_id, f.account_id) AS account_id,
           coalesce(b.currency, f.currency)     AS currency
    FROM account_balance b
    FULL JOIN (
      SELECT e.account_id, e.currency,
             sum(CASE WHEN e.direction = 'debit' THEN e.amount_minor
                      ELSE -e.amount_minor END) AS bal
      FROM entry e
      JOIN txn t ON t.id = e.txn_id
      WHERE t.status IN ('posted', 'settled')
      GROUP BY e.account_id, e.currency
    ) f ON f.account_id = b.account_id AND f.currency = b.currency
    WHERE coalesce(b.balance_minor, 0) <> coalesce(f.bal, 0)
  ) diff;
  IF v_bad <> 0 THEN
    RAISE EXCEPTION 'TEST_FAIL: 잔액 롤업 ↔ 전수 합산 불일치 %건', v_bad;
  END IF;
  RAISE NOTICE 'PASS A: 계정 잔액 전수 대조 일치';

  -- fn_account_balance 표본 일치 (전 계정 × 통화)
  SELECT count(*) INTO v_bad
  FROM account a
  JOIN account_balance b ON b.account_id = a.id
  WHERE fn_account_balance(a.id, b.currency) <> b.balance_minor;
  IF v_bad <> 0 THEN
    RAISE EXCEPTION 'TEST_FAIL: fn_account_balance 불일치 %건', v_bad;
  END IF;
  RAISE NOTICE 'PASS A2: fn_account_balance 일치';

  -- ── B. 계층 롤업 대조 (BULK 루트 10개 전부, 양방향) ──────────────────────
  SELECT count(*) INTO v_bad
  FROM account root
  CROSS JOIN LATERAL (
    WITH RECURSIVE sub AS (
      SELECT root.id AS aid
      UNION ALL
      SELECT a.id FROM account a JOIN sub ON a.parent_id = sub.aid
    ),
    full_scan AS (
      SELECT e.currency,
             sum(CASE WHEN e.direction = 'debit' THEN e.amount_minor
                      ELSE -e.amount_minor END) AS bal
      FROM entry e
      JOIN txn t ON t.id = e.txn_id
      JOIN sub st ON st.aid = e.account_id
      WHERE t.status IN ('posted', 'settled')
      GROUP BY e.currency
    ),
    rollup AS (
      SELECT s.currency, s.balance_minor AS bal FROM fn_subtree_balance(root.id) s
    )
    SELECT count(*) AS mismatches
    FROM ((SELECT * FROM rollup EXCEPT SELECT * FROM full_scan)
          UNION ALL
          (SELECT * FROM full_scan EXCEPT SELECT * FROM rollup)) d
  ) chk
  WHERE root.code LIKE 'BULK.R%' AND chk.mismatches <> 0;
  IF v_bad <> 0 THEN
    RAISE EXCEPTION 'TEST_FAIL: 계층 롤업 불일치 루트 %개', v_bad;
  END IF;
  RAISE NOTICE 'PASS B: 계층 롤업 (루트 10개, 양방향) 일치';

  -- ── C. 기간 집계 뷰 대조 (양방향 EXCEPT) ────────────────────────────────
  SELECT count(*) INTO v_bad FROM (
    (SELECT account_id, currency, period_month, debit_minor, credit_minor, net_minor
     FROM v_period_totals
     EXCEPT
     SELECT e.account_id, e.currency, date_trunc('month', t.occurred_on)::date,
            coalesce(sum(e.amount_minor) FILTER (WHERE e.direction = 'debit'), 0),
            coalesce(sum(e.amount_minor) FILTER (WHERE e.direction = 'credit'), 0),
            coalesce(sum(e.amount_minor) FILTER (WHERE e.direction = 'debit'), 0)
              - coalesce(sum(e.amount_minor) FILTER (WHERE e.direction = 'credit'), 0)
     FROM entry e JOIN txn t ON t.id = e.txn_id
     WHERE t.status IN ('posted', 'settled')
     GROUP BY e.account_id, e.currency, date_trunc('month', t.occurred_on))
    UNION ALL
    (SELECT e.account_id, e.currency, date_trunc('month', t.occurred_on)::date,
            coalesce(sum(e.amount_minor) FILTER (WHERE e.direction = 'debit'), 0),
            coalesce(sum(e.amount_minor) FILTER (WHERE e.direction = 'credit'), 0),
            coalesce(sum(e.amount_minor) FILTER (WHERE e.direction = 'debit'), 0)
              - coalesce(sum(e.amount_minor) FILTER (WHERE e.direction = 'credit'), 0)
     FROM entry e JOIN txn t ON t.id = e.txn_id
     WHERE t.status IN ('posted', 'settled')
     GROUP BY e.account_id, e.currency, date_trunc('month', t.occurred_on)
     EXCEPT
     SELECT account_id, currency, period_month, debit_minor, credit_minor, net_minor
     FROM v_period_totals)
  ) d;
  IF v_bad <> 0 THEN
    RAISE EXCEPTION 'TEST_FAIL: 기간 집계 뷰 불일치 %행', v_bad;
  END IF;
  RAISE NOTICE 'PASS C: 기간 집계 뷰 (전 기간) 일치';

  -- ── 변경 후 재대조: posted 일부를 draft 로 되돌려 잔액 회수 검증 ─────────
  UPDATE txn t SET status = 'draft'
  FROM app_user u
  WHERE u.username = 'bulk_owner' AND t.owner_id = u.id
    AND t.id IN (
      SELECT t2.id FROM txn t2
      JOIN app_user u2 ON u2.id = t2.owner_id
      WHERE u2.username = 'bulk_owner' AND t2.status = 'posted'
      LIMIT 500);

  SELECT count(*) INTO v_bad
  FROM (
    SELECT coalesce(b.account_id, f.account_id), coalesce(b.currency, f.currency)
    FROM account_balance b
    FULL JOIN (
      SELECT e.account_id, e.currency,
             sum(CASE WHEN e.direction = 'debit' THEN e.amount_minor
                      ELSE -e.amount_minor END) AS bal
      FROM entry e JOIN txn t ON t.id = e.txn_id
      WHERE t.status IN ('posted', 'settled')
      GROUP BY e.account_id, e.currency
    ) f ON f.account_id = b.account_id AND f.currency = b.currency
    WHERE coalesce(b.balance_minor, 0) <> coalesce(f.bal, 0)
  ) diff;
  IF v_bad <> 0 THEN
    RAISE EXCEPTION 'TEST_FAIL: posted→draft 회수 후 불일치 %건', v_bad;
  END IF;
  RAISE NOTICE 'PASS D: posted→draft 500건 회수 후에도 일치';

  RAISE NOTICE 'OK: 03_rollup_parity 전체 통과';
END $$;
