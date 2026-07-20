-- 잔액 증분 유지 + NOTIFY 발행 (M1). 반복 적용 가능.
--
-- 잔액 규약: balance_minor = sum(debit) - sum(credit), status IN (posted, settled) 만 반영.
-- NOTIFY 채널: 'ledger_events' 단일. 페이로드는 contracts/notify-event.schema.json 준수.
--   금액(balance_minor)은 문자열로 직렬화한다 (moneyMinor — INV-4, BigInt 직렬화 문제).
--
-- 발행은 문장 단위(statement-level, transition table)로 묶어 대량 변경 시
-- (계정, 통화) 쌍당 1건만 내보낸다. row-level 로 두면 10만 건 삽입에서 수십만 건이 발행된다.

-- ── 잔액 upsert 헬퍼 ─────────────────────────────────────────────────────
-- 권한 모델: account_balance 는 내부 유지 테이블 — 앱 역할에 쓰기 권한이 없다.
-- 쓰기는 SECURITY DEFINER 트리거 함수(fn_bal_txn/fn_bal_entry — trigger 반환형이라
-- SQL 로 직접 호출 불가)를 통해서만 일어나고, 이 헬퍼는 PUBLIC 실행을 회수해
-- 앱 역할이 직접 호출해 잔액을 오염시키는 경로를 차단한다.
CREATE OR REPLACE FUNCTION fn_bal_apply(p_account uuid, p_currency char(3), p_delta bigint)
RETURNS void
LANGUAGE sql
AS $$
  INSERT INTO account_balance (account_id, currency, balance_minor)
  VALUES (p_account, p_currency, p_delta)
  ON CONFLICT (account_id, currency)
  DO UPDATE SET balance_minor = account_balance.balance_minor + EXCLUDED.balance_minor;
$$;

-- txn 전체 entry 를 잔액에 일괄 반영/회수 (p_sign = +1 반영, -1 회수)
CREATE OR REPLACE FUNCTION fn_bal_apply_txn(p_txn uuid, p_sign int)
RETURNS void
LANGUAGE sql
AS $$
  INSERT INTO account_balance (account_id, currency, balance_minor)
  SELECT e.account_id, e.currency,
         p_sign * sum(CASE WHEN e.direction = 'debit' THEN e.amount_minor
                           ELSE -e.amount_minor END)
  FROM entry e
  WHERE e.txn_id = p_txn
  GROUP BY e.account_id, e.currency
  ON CONFLICT (account_id, currency)
  DO UPDATE SET balance_minor = account_balance.balance_minor + EXCLUDED.balance_minor;
$$;

-- ── txn 상태 전이에 따른 잔액 유지 (row-level) ────────────────────────────
-- SECURITY DEFINER: trigger 반환형이라 SQL 로 직접 호출 불가 — 트리거 경유로만 실행.
-- account_balance 쓰기 권한을 앱 역할에 주지 않기 위한 권한 경계다.
CREATE OR REPLACE FUNCTION fn_bal_txn() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_old_in boolean;
  v_new_in boolean;
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- entry 는 txn FK 때문에 txn 보다 먼저 존재할 수 없다. 따라서 txn INSERT 시점의
    -- entry 는 항상 0개(또는 같은 wCTE 문장 내 — 이 경우 entry 트리거가 반영)다.
    -- 여기서 잔액을 반영하면 entry 트리거와 이중 반영된다. 반영은 전적으로 entry 트리거 담당.
    RETURN NULL;
  END IF;

  IF TG_OP = 'DELETE' THEN
    -- INV-3 트리거(trg_10_*)가 settled 를 이미 차단했다. posted 삭제는 잔액 회수.
    IF OLD.status IN ('posted', 'settled') THEN
      PERFORM fn_bal_apply_txn(OLD.id, -1);
    END IF;
    RETURN OLD;
  END IF;

  -- UPDATE: posted 경계 통과 시에만 잔액 이동
  v_old_in := OLD.status IN ('posted', 'settled');
  v_new_in := NEW.status IN ('posted', 'settled');
  IF v_old_in <> v_new_in THEN
    PERFORM fn_bal_apply_txn(NEW.id, CASE WHEN v_new_in THEN 1 ELSE -1 END);
  END IF;
  RETURN NULL;
END $$;

-- 삭제 시 잔액 회수는 entry 가 CASCADE 로 사라지기 전에 해야 하므로 BEFORE.
DROP TRIGGER IF EXISTS trg_20_bal_txn_del ON txn;
CREATE TRIGGER trg_20_bal_txn_del
  BEFORE DELETE ON txn
  FOR EACH ROW EXECUTE FUNCTION fn_bal_txn();

DROP TRIGGER IF EXISTS trg_20_bal_txn ON txn;
CREATE TRIGGER trg_20_bal_txn
  AFTER INSERT OR UPDATE ON txn
  FOR EACH ROW EXECUTE FUNCTION fn_bal_txn();

-- ── entry 변경에 따른 잔액 유지 (row-level) ──────────────────────────────
CREATE OR REPLACE FUNCTION fn_bal_entry() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_status txn_status;
BEGIN
  -- FOR SHARE: 부모 txn 의 상태 전이(fn_bal_txn 의 UPDATE = FOR NO KEY UPDATE)와
  -- 직렬화해, 동시 실행 시 entry 가 잔액에서 누락/이중되는 경합을 막는다(적대 검증 발견).
  IF TG_OP IN ('DELETE', 'UPDATE') THEN
    SELECT status INTO v_status FROM txn WHERE id = OLD.txn_id FOR SHARE;
    -- 부모가 이미 삭제된 경우(CASCADE): txn BEFORE DELETE 가 전체를 회수했으므로 건너뛴다.
    IF FOUND AND v_status IN ('posted', 'settled') THEN
      PERFORM fn_bal_apply(OLD.account_id, OLD.currency,
        CASE WHEN OLD.direction = 'debit' THEN -OLD.amount_minor ELSE OLD.amount_minor END);
    END IF;
  END IF;
  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    SELECT status INTO v_status FROM txn WHERE id = NEW.txn_id FOR SHARE;
    IF FOUND AND v_status IN ('posted', 'settled') THEN
      PERFORM fn_bal_apply(NEW.account_id, NEW.currency,
        CASE WHEN NEW.direction = 'debit' THEN NEW.amount_minor ELSE -NEW.amount_minor END);
    END IF;
  END IF;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_20_bal_entry ON entry;
CREATE TRIGGER trg_20_bal_entry
  AFTER INSERT OR UPDATE OR DELETE ON entry
  FOR EACH ROW EXECUTE FUNCTION fn_bal_entry();

-- 내부 헬퍼는 SQL 직접 호출 금지 (SECURITY DEFINER 트리거 함수만 호출한다)
REVOKE ALL ON FUNCTION fn_bal_apply(uuid, char, bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION fn_bal_apply_txn(uuid, int) FROM PUBLIC;

-- ── NOTIFY: balance_changed ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_notify_balance(p_account uuid, p_currency char(3))
RETURNS void
LANGUAGE sql
AS $$
  SELECT pg_notify('ledger_events', jsonb_build_object(
    'type', 'balance_changed',
    'row', jsonb_build_object(
      'account_id', p_account,
      'currency', p_currency::text,
      'balance_minor', fn_account_balance(p_account, p_currency)::text
    ))::text);
$$;

-- txn 상태 변경 문장 이후: posted 경계를 넘은 txn 들의 (계정, 통화) 쌍만 발행
-- notify 트리거 함수도 DEFINER: 회수된 fn_notify_balance 를 정의자 권한으로 호출한다.
CREATE OR REPLACE FUNCTION fn_notify_txn_stmt() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM fn_notify_balance(p.account_id, p.currency)
  FROM (
    SELECT DISTINCT e.account_id, e.currency
    FROM new_txns n
    JOIN old_txns o ON o.id = n.id
    JOIN entry e ON e.txn_id = n.id
    WHERE (o.status IN ('posted', 'settled')) <> (n.status IN ('posted', 'settled'))
  ) p;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_30_notify_txn ON txn;
CREATE TRIGGER trg_30_notify_txn
  AFTER UPDATE ON txn
  REFERENCING OLD TABLE AS old_txns NEW TABLE AS new_txns
  FOR EACH STATEMENT EXECUTE FUNCTION fn_notify_txn_stmt();

-- entry 변경 문장 이후: 영향받은 (계정, 통화) 쌍 발행.
-- DELETE 에서 부모 txn 이 함께 사라진 경우 상태를 알 수 없으므로 발행한다
-- (잔액이 안 변했어도 최신 잔액 재전송은 무해 — 클라이언트 병합은 멱등).
CREATE OR REPLACE FUNCTION fn_notify_entry_ins() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM fn_notify_balance(p.account_id, p.currency)
  FROM (
    SELECT DISTINCT r.account_id, r.currency
    FROM new_rows r
    JOIN txn t ON t.id = r.txn_id
    WHERE t.status IN ('posted', 'settled')
  ) p;
  RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION fn_notify_entry_upd() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM fn_notify_balance(p.account_id, p.currency)
  FROM (
    SELECT r.account_id, r.currency
    FROM new_rows r JOIN txn t ON t.id = r.txn_id
    WHERE t.status IN ('posted', 'settled')
    UNION
    SELECT r.account_id, r.currency
    FROM old_rows r JOIN txn t ON t.id = r.txn_id
    WHERE t.status IN ('posted', 'settled')
  ) p;
  RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION fn_notify_entry_del() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM fn_notify_balance(p.account_id, p.currency)
  FROM (
    SELECT DISTINCT r.account_id, r.currency
    FROM old_rows r
    LEFT JOIN txn t ON t.id = r.txn_id
    WHERE t.id IS NULL OR t.status IN ('posted', 'settled')
  ) p;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_30_notify_entry_ins ON entry;
CREATE TRIGGER trg_30_notify_entry_ins
  AFTER INSERT ON entry
  REFERENCING NEW TABLE AS new_rows
  FOR EACH STATEMENT EXECUTE FUNCTION fn_notify_entry_ins();

DROP TRIGGER IF EXISTS trg_30_notify_entry_upd ON entry;
CREATE TRIGGER trg_30_notify_entry_upd
  AFTER UPDATE ON entry
  REFERENCING OLD TABLE AS old_rows NEW TABLE AS new_rows
  FOR EACH STATEMENT EXECUTE FUNCTION fn_notify_entry_upd();

DROP TRIGGER IF EXISTS trg_30_notify_entry_del ON entry;
CREATE TRIGGER trg_30_notify_entry_del
  AFTER DELETE ON entry
  REFERENCING OLD TABLE AS old_rows
  FOR EACH STATEMENT EXECUTE FUNCTION fn_notify_entry_del();

-- ── NOTIFY: ingest_progress ──────────────────────────────────────────────
-- 계약 필수 필드는 type/batch_id/state. processed/total 은 M3 워커가 채운다.
CREATE OR REPLACE FUNCTION fn_notify_ingest() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP = 'INSERT' OR OLD.state IS DISTINCT FROM NEW.state THEN
    PERFORM pg_notify('ledger_events', jsonb_build_object(
      'type', 'ingest_progress',
      'batch_id', NEW.id,
      'state', NEW.state)::text);
  END IF;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_30_notify_ingest ON ingest_batch;
CREATE TRIGGER trg_30_notify_ingest
  AFTER INSERT OR UPDATE ON ingest_batch
  FOR EACH ROW EXECUTE FUNCTION fn_notify_ingest();

-- ── NOTIFY: settlement_done ──────────────────────────────────────────────
-- 기간은 [start, end) 로 저장되며 계약 페이로드의 end 는 포함 종료일(upper - 1일).
CREATE OR REPLACE FUNCTION fn_notify_settlement() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.cobol_exit = 0 AND (TG_OP = 'INSERT' OR OLD.cobol_exit IS DISTINCT FROM NEW.cobol_exit) THEN
    PERFORM pg_notify('ledger_events', jsonb_build_object(
      'type', 'settlement_done',
      'period', jsonb_build_object(
        'start', to_char(lower(NEW.period), 'YYYY-MM-DD'),
        'end',   to_char(upper(NEW.period) - 1, 'YYYY-MM-DD')))::text);
  END IF;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_30_notify_settlement ON settlement_run;
CREATE TRIGGER trg_30_notify_settlement
  AFTER INSERT OR UPDATE ON settlement_run
  FOR EACH ROW EXECUTE FUNCTION fn_notify_settlement();
