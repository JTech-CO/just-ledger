-- 불변식 트리거 (M1). 반복 적용 가능(DROP IF EXISTS + CREATE).
--
-- 커스텀 SQLSTATE:
--   JL001 — INV-1 위반 (posted 이상 txn 의 통화별 차대 불균형 / entry 없음)
--   JL003 — INV-3 위반 (settled txn·entry 변경 시도)
--   JL005 — transfer_link 불변성 위반 (링크 쌍은 수정 불가, 삭제 후 재생성)
--
-- INV-1 은 반드시 deferrable constraint trigger 로 커밋 시점에 검사한다.
-- BEFORE 트리거로 두면 다중 entry 삽입의 중간 상태에서 오탐한다 (HARNESS M1 주의).

-- ── INV-1: 통화별 sum(debit) = sum(credit) ───────────────────────────────
-- SECURITY DEFINER + row_security=off: 불변식 검사는 세션 소유자·app.user_id GUC 와
-- 무관하게 원장 전체를 봐야 한다. INVOKER 로 두면 커밋 직전 GUC 를 비워 RLS 로 txn 을
-- 안 보이게 만들어 검사를 통째로 스킵시키는 우회가 가능하다(적대 검증 발견).
CREATE OR REPLACE FUNCTION fn_inv1_check(p_txn uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp SET row_security = off
AS $$
DECLARE
  v_status txn_status;
  v_cnt    bigint;
  v_bad    bigint;
BEGIN
  -- 커밋 시점의 현재 상태를 다시 읽는다 (큐잉 시점 값이 아니라).
  SELECT status INTO v_status FROM txn WHERE id = p_txn;
  IF NOT FOUND OR v_status NOT IN ('posted', 'settled') THEN
    RETURN;
  END IF;

  SELECT count(*) INTO v_cnt FROM entry WHERE txn_id = p_txn;
  IF v_cnt = 0 THEN
    RAISE EXCEPTION USING
      ERRCODE = 'JL001',
      MESSAGE = format('INV-1: posted 이상 txn %s 에 entry 가 없습니다', p_txn);
  END IF;

  SELECT count(*) INTO v_bad FROM (
    SELECT currency
    FROM entry
    WHERE txn_id = p_txn
    GROUP BY currency
    HAVING coalesce(sum(amount_minor) FILTER (WHERE direction = 'debit'), 0)
        <> coalesce(sum(amount_minor) FILTER (WHERE direction = 'credit'), 0)
  ) unbalanced;
  IF v_bad > 0 THEN
    RAISE EXCEPTION USING
      ERRCODE = 'JL001',
      MESSAGE = format('INV-1: txn %s 이 %s개 통화에서 차변·대변 불일치', p_txn, v_bad);
  END IF;
END $$;

-- 트리거 함수는 데이터 계층 로직 — 세션 사용자 권한과 무관하게 실행되어야 하고,
-- 회수된 내부 헬퍼(fn_inv1_check 등)를 정의자 권한으로 호출해야 한다. 전부 DEFINER.
CREATE OR REPLACE FUNCTION fn_inv1_trg_txn() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM fn_inv1_check(NEW.id);
  RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION fn_inv1_trg_entry() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    PERFORM fn_inv1_check(NEW.txn_id);
  END IF;
  IF TG_OP IN ('DELETE', 'UPDATE') THEN
    IF TG_OP = 'DELETE' OR OLD.txn_id IS DISTINCT FROM NEW.txn_id THEN
      PERFORM fn_inv1_check(OLD.txn_id);
    END IF;
  END IF;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS trg_inv1_txn ON txn;
CREATE CONSTRAINT TRIGGER trg_inv1_txn
  AFTER INSERT OR UPDATE ON txn
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION fn_inv1_trg_txn();

DROP TRIGGER IF EXISTS trg_inv1_entry ON entry;
CREATE CONSTRAINT TRIGGER trg_inv1_entry
  AFTER INSERT OR UPDATE OR DELETE ON entry
  DEFERRABLE INITIALLY DEFERRED
  FOR EACH ROW EXECUTE FUNCTION fn_inv1_trg_entry();

-- ── INV-3: settled txn·entry 는 UPDATE/DELETE 불가 ───────────────────────
-- BEFORE 트리거 이름은 알파벳 순으로 실행되므로 trg_10_* 으로 잔액 유지(trg_20_*)보다
-- 먼저 실행되게 한다. settled 진입(posted → settled)은 허용, 이탈·변경은 전부 거절.
CREATE OR REPLACE FUNCTION fn_inv3_txn() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
  IF OLD.status = 'settled' THEN
    RAISE EXCEPTION USING
      ERRCODE = 'JL003',
      MESSAGE = format('INV-3: settled txn %s 은 %s 불가', OLD.id, TG_OP);
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END $$;

-- DEFINER + row_security off: 부모 txn 상태 조회가 RLS·GUC 에 좌우되면 안 된다.
-- FOR SHARE: 부모 txn 의 상태 전이(fn_bal_txn 의 FOR NO KEY UPDATE)와 직렬화한다.
CREATE OR REPLACE FUNCTION fn_inv3_entry() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp SET row_security = off
AS $$
DECLARE
  v_status txn_status;
  v_txn    uuid;
BEGIN
  v_txn := CASE WHEN TG_OP = 'INSERT' THEN NEW.txn_id ELSE OLD.txn_id END;
  SELECT status INTO v_status FROM txn WHERE id = v_txn FOR SHARE;
  -- 부모 txn 이 이미 삭제된 경우(FK CASCADE 진행 중)는 부모 검사를 통과한 것이다.
  IF FOUND AND v_status = 'settled' THEN
    RAISE EXCEPTION USING
      ERRCODE = 'JL003',
      MESSAGE = format('INV-3: settled txn %s 의 entry 는 %s 불가', v_txn, TG_OP);
  END IF;
  -- UPDATE 로 entry 를 다른 txn 으로 옮기는 경우 대상 txn 도 검사
  IF TG_OP = 'UPDATE' AND NEW.txn_id IS DISTINCT FROM OLD.txn_id THEN
    SELECT status INTO v_status FROM txn WHERE id = NEW.txn_id FOR SHARE;
    IF FOUND AND v_status = 'settled' THEN
      RAISE EXCEPTION USING
        ERRCODE = 'JL003',
        MESSAGE = format('INV-3: settled txn %s 으로 entry 이동 불가', NEW.txn_id);
    END IF;
  END IF;
  IF TG_OP = 'DELETE' THEN RETURN OLD; END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_10_inv3_txn ON txn;
CREATE TRIGGER trg_10_inv3_txn
  BEFORE UPDATE OR DELETE ON txn
  FOR EACH ROW EXECUTE FUNCTION fn_inv3_txn();

DROP TRIGGER IF EXISTS trg_10_inv3_entry ON entry;
CREATE TRIGGER trg_10_inv3_entry
  BEFORE INSERT OR UPDATE OR DELETE ON entry
  FOR EACH ROW EXECUTE FUNCTION fn_inv3_entry();

-- ── 계정 계층 순환 방지 (JL006) ──────────────────────────────────────────
-- parent_id 로 자기 자신에 도달하는 순환이 생기면 재귀 CTE(fn_subtree_balance 등)가
-- 무한 순회한다. 부모 체인을 거슬러 올라가며 순환·과도한 깊이를 커밋 전에 거절한다.
CREATE OR REPLACE FUNCTION fn_account_no_cycle() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_cur   uuid;
  v_depth int := 0;
BEGIN
  IF NEW.parent_id IS NULL THEN RETURN NEW; END IF;
  IF NEW.parent_id = NEW.id THEN
    RAISE EXCEPTION USING ERRCODE = 'JL006',
      MESSAGE = format('계정 %s 은 자기 자신을 상위로 둘 수 없습니다', NEW.id);
  END IF;
  v_cur := NEW.parent_id;
  WHILE v_cur IS NOT NULL LOOP
    v_depth := v_depth + 1;
    IF v_cur = NEW.id THEN
      RAISE EXCEPTION USING ERRCODE = 'JL006',
        MESSAGE = format('계정 계층 순환 감지: %s', NEW.id);
    END IF;
    IF v_depth > 64 THEN
      RAISE EXCEPTION USING ERRCODE = 'JL006',
        MESSAGE = '계정 계층 깊이 제한(64) 초과';
    END IF;
    SELECT parent_id INTO v_cur FROM account WHERE id = v_cur;
  END LOOP;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_10_account_no_cycle ON account;
CREATE TRIGGER trg_10_account_no_cycle
  BEFORE INSERT OR UPDATE OF parent_id ON account
  FOR EACH ROW EXECUTE FUNCTION fn_account_no_cycle();

-- ── INV-5: 멤버십 행 자동 유지 ───────────────────────────────────────────
-- transfer_link_member.txn_id PK 가 "한 txn 최대 1개 링크"를 유니크 인덱스로 강제.
-- 이미 링크된 txn 을 다시 링크하면 23505(unique_violation)로 실패한다.
-- SECURITY DEFINER: 멤버십 테이블은 트리거만 쓴다(앱 역할에 쓰기 권한 없음).
CREATE OR REPLACE FUNCTION fn_tlink_member() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
  INSERT INTO transfer_link_member (txn_id, link_id)
  VALUES (NEW.txn_a, NEW.id), (NEW.txn_b, NEW.id);
  RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION fn_tlink_immutable() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
  IF NEW.txn_a IS DISTINCT FROM OLD.txn_a OR NEW.txn_b IS DISTINCT FROM OLD.txn_b THEN
    RAISE EXCEPTION USING
      ERRCODE = 'JL005',
      MESSAGE = format('transfer_link %s 의 쌍은 수정 불가 — 삭제 후 재생성하세요', OLD.id);
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_tlink_member ON transfer_link;
CREATE TRIGGER trg_tlink_member
  AFTER INSERT ON transfer_link
  FOR EACH ROW EXECUTE FUNCTION fn_tlink_member();

DROP TRIGGER IF EXISTS trg_tlink_immutable ON transfer_link;
CREATE TRIGGER trg_tlink_immutable
  BEFORE UPDATE ON transfer_link
  FOR EACH ROW EXECUTE FUNCTION fn_tlink_immutable();
