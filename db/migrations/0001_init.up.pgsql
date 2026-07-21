-- 0001_init.up — just-ledger 도메인 스키마 (M1)
-- 정본: 기술 백서 §2.3 데이터 모델. API 표현은 contracts/*.schema.json.
-- 금액은 예외 없이 BIGINT 최소 화폐 단위. 부호는 direction 이 담당한다.
--
-- 백서 §2.3 에 없는 추가 객체(결정 로그 2026-07-21):
--   app_user / owner_id  — §7 RLS "계정 소유자 격리" 요건의 구현 수단.
--                          API 계약에는 노출되지 않는다(서버 내부 컬럼).
--   account_balance      — 잔액 증분 유지 테이블(트리거 산출). 롤업 함수·NOTIFY 가 읽는다.
--   transfer_link_member — INV-5 를 진짜 유니크 인덱스(PK)로 강제하기 위한 멤버십 테이블.

BEGIN;

-- ── 열거형 ───────────────────────────────────────────────────────────────
CREATE TYPE account_type AS ENUM ('asset', 'liability', 'equity', 'income', 'expense');
-- 정의 순서가 곧 상태 전이 순서. enum 비교(>=)가 이 순서를 따른다.
CREATE TYPE txn_status AS ENUM ('draft', 'classified', 'posted', 'settled');
CREATE TYPE entry_direction AS ENUM ('debit', 'credit');
CREATE TYPE rule_source AS ENUM ('manual', 'prolog', 'lua', 'haskell');
-- contracts/common.schema.json#/$defs/ingestState 와 1:1
CREATE TYPE ingest_state AS ENUM ('received', 'parsing', 'deduping', 'drafting', 'done', 'failed');
CREATE TYPE artifact_kind AS ENUM ('stl', 'anomaly', 'montecarlo', 'settlement');
CREATE TYPE artifact_generator AS ENUM ('r', 'julia', 'cobol');

-- ── 소유자 (RLS 주체) ────────────────────────────────────────────────────
CREATE TABLE app_user (
  id       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  username text NOT NULL UNIQUE CHECK (length(username) BETWEEN 1 AND 64)
);

-- ── 1. account ───────────────────────────────────────────────────────────
CREATE TABLE account (
  id        uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id  uuid NOT NULL REFERENCES app_user(id),
  code      text NOT NULL CHECK (code ~ '^[A-Za-z0-9._-]{1,32}$'),
  name      text NOT NULL CHECK (length(name) BETWEEN 1 AND 128),
  type      account_type NOT NULL,
  currency  char(3) NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  parent_id uuid REFERENCES account(id),
  is_closed boolean NOT NULL DEFAULT false,
  -- code 유니크는 소유자 스코프. 전역 유니크로 두면 타 테넌트가 특정 code 를
  -- 쓰는지 유니크 위반으로 탐지하는 존재 오라클이 생기고, 사용자 간 code 가 충돌한다.
  UNIQUE (owner_id, code),
  -- entry 가 (account_id, currency) 복합 FK 로 "entry 통화 = 계정 통화"를
  -- 선언적으로 강제할 수 있도록 유니크를 둔다.
  UNIQUE (id, currency)
);
CREATE INDEX idx_account_owner  ON account (owner_id);
CREATE INDEX idx_account_parent ON account (parent_id) WHERE parent_id IS NOT NULL;

-- ── 2. txn ───────────────────────────────────────────────────────────────
CREATE TABLE txn (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id    uuid NOT NULL REFERENCES app_user(id),
  occurred_on date NOT NULL,
  memo        text NOT NULL DEFAULT '' CHECK (length(memo) <= 512),
  source_hash bytea,                 -- BLAKE3 32바이트 지문 (인제스트 중복 제거 키)
  batch_id    uuid,                  -- FK 는 ingest_batch 정의 후 추가
  status      txn_status NOT NULL DEFAULT 'draft',
  posted_at   timestamptz,
  CHECK (source_hash IS NULL OR octet_length(source_hash) = 32),
  -- transfer_link 가 (txn, owner) 복합 FK 로 "링크 양단이 같은 소유자"임을
  -- 선언적으로 강제하도록 유니크를 둔다 (크로스 테넌트 링크 원천 차단).
  UNIQUE (id, owner_id)
);
-- 중복 제거는 소유자 스코프. 전역 유니크는 존재 오라클·사용자 간 충돌을 만든다.
CREATE UNIQUE INDEX uq_txn_owner_source ON txn (owner_id, source_hash)
  WHERE source_hash IS NOT NULL;
CREATE INDEX idx_txn_owner_date ON txn (owner_id, occurred_on);
CREATE INDEX idx_txn_status     ON txn (status);
CREATE INDEX idx_txn_batch      ON txn (batch_id) WHERE batch_id IS NOT NULL;

-- ── 3. entry ─────────────────────────────────────────────────────────────
CREATE TABLE entry (
  id           bigserial PRIMARY KEY,
  txn_id       uuid NOT NULL REFERENCES txn(id) ON DELETE CASCADE,
  account_id   uuid NOT NULL,
  direction    entry_direction NOT NULL,
  -- INV-2: > 0. 상한은 계약 positiveMinor(최대 18자리)와 정합 — 잔액/NOTIFY 직렬화가
  -- i64 19자리로 넘쳐 계약 moneyMinor 패턴을 위반하는 값이 애초에 생기지 않게 한다.
  amount_minor bigint NOT NULL CHECK (amount_minor > 0 AND amount_minor < 1000000000000000000),
  currency     char(3) NOT NULL CHECK (currency ~ '^[A-Z]{3}$'),
  -- entry 통화는 계정 통화와 항상 일치한다 (선언적 강제)
  FOREIGN KEY (account_id, currency) REFERENCES account (id, currency)
);
CREATE INDEX idx_entry_txn     ON entry (txn_id);
CREATE INDEX idx_entry_account ON entry (account_id, currency);

-- ── 4. fx_rate — 환율은 유리수 쌍. 실수 컬럼을 두지 않는다 ─────────────────
CREATE TABLE fx_rate (
  base     char(3) NOT NULL CHECK (base ~ '^[A-Z]{3}$'),
  quote    char(3) NOT NULL CHECK (quote ~ '^[A-Z]{3}$'),
  as_of    date NOT NULL,
  rate_num bigint NOT NULL CHECK (rate_num > 0),
  rate_den bigint NOT NULL CHECK (rate_den > 0),
  PRIMARY KEY (base, quote, as_of),
  CHECK (base <> quote)
);

-- ── 5. category_rule ─────────────────────────────────────────────────────
CREATE TABLE category_rule (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id   uuid NOT NULL REFERENCES app_user(id),
  priority   integer NOT NULL DEFAULT 100,
  matcher    jsonb NOT NULL,
  account_id uuid NOT NULL REFERENCES account(id),
  source     rule_source NOT NULL DEFAULT 'manual'
);
CREATE INDEX idx_category_rule_owner ON category_rule (owner_id, priority);

-- ── 6. budget ────────────────────────────────────────────────────────────
CREATE TABLE budget (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id    uuid NOT NULL REFERENCES app_user(id),
  account_id  uuid NOT NULL REFERENCES account(id),
  period_kind text NOT NULL CHECK (period_kind IN ('monthly', 'quarterly', 'yearly')),
  limit_minor bigint NOT NULL CHECK (limit_minor > 0),
  dsl_src     text NOT NULL DEFAULT ''    -- Haskell 규칙 DSL 원문 (M5)
);
CREATE INDEX idx_budget_owner ON budget (owner_id);

-- ── 7. automation_script ─────────────────────────────────────────────────
CREATE TABLE automation_script (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id   uuid NOT NULL REFERENCES app_user(id),
  name       text NOT NULL CHECK (length(name) BETWEEN 1 AND 128),
  lua_src    text NOT NULL,
  enabled    boolean NOT NULL DEFAULT false,
  timeout_ms integer NOT NULL DEFAULT 100 CHECK (timeout_ms BETWEEN 1 AND 10000)
);
CREATE INDEX idx_automation_owner ON automation_script (owner_id);

-- ── 8. ingest_batch ──────────────────────────────────────────────────────
CREATE TABLE ingest_batch (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id    uuid NOT NULL REFERENCES app_user(id),
  filename    text NOT NULL CHECK (length(filename) BETWEEN 1 AND 255),
  row_count   integer CHECK (row_count >= 0),
  state       ingest_state NOT NULL DEFAULT 'received',
  started_at  timestamptz,
  finished_at timestamptz
);
CREATE INDEX idx_ingest_owner ON ingest_batch (owner_id);

ALTER TABLE txn
  ADD CONSTRAINT txn_batch_fk FOREIGN KEY (batch_id) REFERENCES ingest_batch(id);

-- ── 9. settlement_run ────────────────────────────────────────────────────
CREATE TABLE settlement_run (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id    uuid NOT NULL REFERENCES app_user(id),
  period      daterange NOT NULL CHECK (NOT isempty(period)
                AND lower_inc(period) AND NOT upper_inc(period)
                AND lower(period) IS NOT NULL AND upper(period) IS NOT NULL),
  cobol_exit  integer,
  report_path text,
  checksum    bytea
);
CREATE INDEX idx_settlement_owner ON settlement_run (owner_id);

-- ── 10. transfer_link — Prolog 산출 이체 페어 ─────────────────────────────
CREATE TABLE transfer_link (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id   uuid NOT NULL REFERENCES app_user(id),
  txn_a      uuid NOT NULL,
  txn_b      uuid NOT NULL,
  confidence smallint NOT NULL CHECK (confidence BETWEEN 0 AND 100),
  matched_by text NOT NULL,
  CHECK (txn_a < txn_b),              -- 정규화: 쌍의 순서 고정, (B,A) 중복 표현 차단
  -- 복합 FK 로 "링크 양단 txn 이 링크와 같은 소유자"임을 선언적으로 강제한다.
  -- 이것이 없으면 A 가 B 소유 txn 두 개를 링크해 B 의 INV-5 슬롯을 점유할 수 있다.
  FOREIGN KEY (txn_a, owner_id) REFERENCES txn (id, owner_id) ON DELETE CASCADE,
  FOREIGN KEY (txn_b, owner_id) REFERENCES txn (id, owner_id) ON DELETE CASCADE
);

-- INV-5: 한 txn 은 최대 1개 transfer_link 에만 속한다.
-- 두 컬럼(txn_a/txn_b)을 가로지르는 유니크는 단일 부분 인덱스로 표현할 수 없으므로
-- 멤버십 테이블의 PK(유니크 인덱스)로 강제한다. 행은 트리거가 자동 유지한다.
CREATE TABLE transfer_link_member (
  txn_id  uuid PRIMARY KEY REFERENCES txn(id) ON DELETE CASCADE,
  link_id uuid NOT NULL REFERENCES transfer_link(id) ON DELETE CASCADE
);
CREATE INDEX idx_tlm_link ON transfer_link_member (link_id);

-- ── 11. report_artifact ──────────────────────────────────────────────────
CREATE TABLE report_artifact (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id     uuid NOT NULL REFERENCES app_user(id),
  kind         artifact_kind NOT NULL,
  period       daterange NOT NULL,
  path         text NOT NULL,
  generated_by artifact_generator NOT NULL
);
CREATE INDEX idx_artifact_owner ON report_artifact (owner_id, kind);

-- ── 잔액 유지 테이블 (내부) ───────────────────────────────────────────────
-- balance_minor = sum(debit) - sum(credit), posted 이상 상태의 entry 만 반영.
-- 표시 부호(자산/부채 관점)는 상위 계층이 account.type 으로 결정한다.
-- CHECK: 잔액도 계약 moneyMinor(18자리) 표현 범위를 벗어나지 않게 강제한다 —
-- 넘치면 해당 txn 커밋이 거절(fail-closed)되며, NOTIFY/API 직렬화가 계약을 위반하지 않는다.
CREATE TABLE account_balance (
  account_id    uuid NOT NULL,
  currency      char(3) NOT NULL,
  balance_minor bigint NOT NULL DEFAULT 0
    CHECK (balance_minor BETWEEN -999999999999999999 AND 999999999999999999),
  PRIMARY KEY (account_id, currency),
  FOREIGN KEY (account_id, currency) REFERENCES account (id, currency) ON DELETE CASCADE
);

-- ── 기간 집계 뷰 (월 × 계정 × 통화) ──────────────────────────────────────
-- security_invoker: 조회자 권한으로 실행되어 RLS 가 적용된다 (뷰 소유자 우회 방지).
CREATE VIEW v_period_totals WITH (security_invoker = true) AS
SELECT e.account_id,
       e.currency,
       date_trunc('month', t.occurred_on)::date AS period_month,
       coalesce(sum(e.amount_minor) FILTER (WHERE e.direction = 'debit'), 0)  AS debit_minor,
       coalesce(sum(e.amount_minor) FILTER (WHERE e.direction = 'credit'), 0) AS credit_minor,
       coalesce(sum(e.amount_minor) FILTER (WHERE e.direction = 'debit'), 0)
         - coalesce(sum(e.amount_minor) FILTER (WHERE e.direction = 'credit'), 0) AS net_minor
FROM entry e
JOIN txn t ON t.id = e.txn_id
WHERE t.status IN ('posted', 'settled')
GROUP BY e.account_id, e.currency, date_trunc('month', t.occurred_on);

-- ── 함수·트리거·RLS 정책 (별도 파일, 경로는 이 파일 기준 상대) ──────────────
\ir ../functions/rollup.pgsql
\ir ../triggers/inv_triggers.pgsql
\ir ../triggers/balance_notify.pgsql
\ir ../functions/rls.pgsql

-- ── 서비스 역할 및 권한 ──────────────────────────────────────────────────
-- 역할은 클러스터 전역이므로 존재 검사 후 생성한다. BYPASSRLS 를 부여하지 않는다(§7).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ledger_app') THEN
    CREATE ROLE ledger_app NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ledger_worker') THEN
    CREATE ROLE ledger_worker NOLOGIN;
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'ledger_realtime') THEN
    CREATE ROLE ledger_realtime NOLOGIN;
  END IF;
END $$;

GRANT USAGE ON SCHEMA public TO ledger_app, ledger_worker, ledger_realtime;

-- 마이그레이션을 적용한 로그인 롤(= 서비스가 접속하는 롤)이 SET ROLE 로 강등할 수
-- 있도록 멤버십을 부여한다. 수퍼유저 배포에선 무해(이미 가능), 비수퍼유저 배포에서
-- 이것이 없으면 앱 풀의 SET ROLE ledger_app 이 실패해 서비스가 기동하지 못한다.
DO $$
BEGIN
  IF NOT pg_has_role(current_user, 'ledger_app', 'MEMBER') THEN
    EXECUTE format('GRANT ledger_app TO %I', current_user);
  END IF;
END $$;

-- web(app): 도메인 전반 CRUD (RLS 로 소유자 격리)
GRANT SELECT, INSERT, UPDATE, DELETE ON
  account, txn, entry, category_rule, budget, automation_script,
  ingest_batch, transfer_link, report_artifact
  TO ledger_app;
GRANT SELECT ON app_user, fx_rate, settlement_run, account_balance,
                transfer_link_member, v_period_totals TO ledger_app;

-- worker: 인제스트·환율·정산·매칭 산출 기록
GRANT SELECT, INSERT, UPDATE, DELETE ON
  txn, entry, ingest_batch, transfer_link, settlement_run, report_artifact
  TO ledger_worker;
GRANT SELECT, INSERT, UPDATE ON fx_rate TO ledger_worker;
GRANT SELECT ON app_user, account, category_rule, budget, automation_script,
                account_balance, transfer_link_member, v_period_totals TO ledger_worker;

-- realtime: 읽기 전용 (LISTEN 은 권한 불요)
GRANT SELECT ON account, txn, entry, account_balance, v_period_totals TO ledger_realtime;

GRANT USAGE ON SEQUENCE entry_id_seq TO ledger_app, ledger_worker;

-- ── 함수 실행 권한 최소화 ────────────────────────────────────────────────
-- 함수는 기본 PUBLIC EXECUTE 다. 내부·트리거 전용 함수를 열어 두면 문제가 된다:
-- 특히 fn_inv1_check 는 SECURITY DEFINER + row_security=off 라, 앱이 임의 txn_id 로
-- 직접 호출하면 RLS 를 우회해 타인 txn 의 균형 상태를 예외 발생 여부로 탐지하는
-- 오라클이 된다. 모든 fn_* 에서 PUBLIC 을 회수하고 공개 조회 함수만 다시 부여한다.
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT p.oid::regprocedure AS sig
           FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname = 'public' AND p.proname LIKE 'fn\_%'
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', r.sig);
  END LOOP;
END $$;

-- 공개 조회 함수(모두 SECURITY INVOKER — RLS 가 적용되어 소유자 격리 유지)
GRANT EXECUTE ON FUNCTION
  fn_account_balance(uuid, char), fn_subtree_balance(uuid), fn_all_balances()
  TO ledger_app, ledger_worker, ledger_realtime;

COMMIT;
