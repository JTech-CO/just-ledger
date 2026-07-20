-- 02_bulk_100k — 무작위 100,000 txn 삽입 후 INV-1 위반 0건 (M1 DoD 2)
-- 시드 고정으로 재현 가능. 2단계: draft 로 일괄 삽입·entry 부착 → posted 일괄 전이.
-- 이 데이터는 03_rollup(전수 대조)·05_notify 가 이어서 사용하므로 커밋한다.
--
-- 참고: random() 은 난수 '소스'로만 쓰며, 산출 금액은 생성 즉시 정수다.
-- 금액 값이 부동소수점 표현을 왕복하는 경로는 없다 (INV-4).

\set ON_ERROR_STOP on
\timing on

BEGIN;

SELECT setseed(0.42);

-- ── 픽스처: 소유자 1, 계층 있는 계정 60개 (KRW 50 + USD 10) ───────────────
INSERT INTO app_user (username) VALUES ('bulk_owner');

WITH o AS (SELECT id FROM app_user WHERE username = 'bulk_owner'),
roots AS (
  INSERT INTO account (owner_id, code, name, type, currency)
  SELECT o.id, 'BULK.R' || g, '루트' || g,
         (ARRAY['asset','liability','equity','income','expense'])[1 + (g % 5)]::account_type,
         'KRW'
  FROM o, generate_series(0, 9) g
  RETURNING id, owner_id, type
)
INSERT INTO account (owner_id, code, name, type, currency, parent_id)
SELECT r.owner_id, 'BULK.C' || row_number() OVER (), '하위' || row_number() OVER (),
       r.type, 'KRW', r.id
FROM roots r, generate_series(1, 4) g;

INSERT INTO account (owner_id, code, name, type, currency)
SELECT (SELECT id FROM app_user WHERE username = 'bulk_owner'),
       'BULK.U' || g, '외화' || g,
       (ARRAY['asset','expense'])[1 + (g % 2)]::account_type, 'USD'
FROM generate_series(0, 9) g;

-- ── 1단계: draft txn 100,000 + entry 부착 (집합 연산) ─────────────────────
CREATE TEMP TABLE t_gen ON COMMIT DROP AS
SELECT gen_random_uuid()                                        AS txn_id,
       date '2025-01-01' + (random() * 550)::int                AS occurred_on,
       1 + (random() * 999999)::bigint                          AS amt1,
       1 + (random() * 999999)::bigint                          AS amt2,
       random() < 0.20                                          AS four_leg,
       random() < 0.05                                          AS is_usd,
       (random() * 1e9)::bigint                                 AS pick1,
       (random() * 1e9)::bigint                                 AS pick2
FROM generate_series(1, 100000);

INSERT INTO txn (id, owner_id, occurred_on, status)
SELECT g.txn_id, (SELECT id FROM app_user WHERE username = 'bulk_owner'),
       g.occurred_on, 'draft'
FROM t_gen g;

-- 계정 풀 (통화별 배열)
CREATE TEMP TABLE t_pool ON COMMIT DROP AS
SELECT currency, array_agg(id) AS ids, count(*) AS n
FROM account
WHERE code LIKE 'BULK.%'
GROUP BY currency;

-- 2-leg: debit 1 + credit 1 / 4-leg: debit 2 + credit 2 (쌍별 균형 → 합계 균형)
INSERT INTO entry (txn_id, account_id, direction, amount_minor, currency)
SELECT g.txn_id,
       p.ids[1 + ((g.pick1 + leg.k) % p.n)::int],
       leg.dir::entry_direction,
       CASE WHEN leg.k IN (0, 1) THEN g.amt1 ELSE g.amt2 END,
       p.currency
FROM t_gen g
JOIN t_pool p
  ON p.currency = CASE WHEN g.is_usd THEN 'USD' ELSE 'KRW' END
CROSS JOIN LATERAL (
  VALUES (0, 'debit'), (1, 'credit'), (2, 'debit'), (3, 'credit')
) AS leg(k, dir)
WHERE leg.k < CASE WHEN g.four_leg THEN 4 ELSE 2 END;

COMMIT;   -- draft 커밋 (INV-1 은 draft 에 무관심 — 빠르게 통과해야 정상)

-- ── 2단계: 전량 posted 전이 (커밋 시 deferred INV-1 100,000건 검사) ────────
BEGIN;
UPDATE txn t SET status = 'posted', posted_at = now()
FROM app_user u
WHERE u.username = 'bulk_owner' AND t.owner_id = u.id AND t.status = 'draft';
COMMIT;

-- ── 검증: INV-1 위반 전수 스윕 (트리거와 독립된 재계산) ────────────────────
DO $$
DECLARE
  v_violations bigint;
  v_posted     bigint;
BEGIN
  SELECT count(*) INTO v_posted
  FROM txn t JOIN app_user u ON u.id = t.owner_id
  WHERE u.username = 'bulk_owner' AND t.status IN ('posted', 'settled');
  IF v_posted <> 100000 THEN
    RAISE EXCEPTION 'TEST_FAIL: posted txn 수 % (기대 100000)', v_posted;
  END IF;

  SELECT count(*) INTO v_violations
  FROM (
    SELECT e.txn_id, e.currency
    FROM entry e
    JOIN txn t ON t.id = e.txn_id
    JOIN app_user u ON u.id = t.owner_id
    WHERE u.username = 'bulk_owner' AND t.status IN ('posted', 'settled')
    GROUP BY e.txn_id, e.currency
    HAVING coalesce(sum(e.amount_minor) FILTER (WHERE e.direction = 'debit'), 0)
        <> coalesce(sum(e.amount_minor) FILTER (WHERE e.direction = 'credit'), 0)
  ) bad;
  IF v_violations <> 0 THEN
    RAISE EXCEPTION 'TEST_FAIL: INV-1 위반 %건 (0 이어야 함)', v_violations;
  END IF;

  RAISE NOTICE 'OK: 02_bulk_100k — posted 100,000건, INV-1 위반 0건';
END $$;
