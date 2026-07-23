-- 0001_init.down — 0001 이 만든 프로젝트 객체를 전부 제거한다.
-- 역할(ledger_*)은 클러스터 전역 공유 자원이므로 남긴다 (up 은 존재 검사 후 생성).

BEGIN;

DROP VIEW IF EXISTS v_period_totals;

-- 테이블 (트리거·정책·인덱스는 테이블과 함께 제거된다)
DROP TABLE IF EXISTS
  transfer_link_member,
  transfer_link,
  report_artifact,
  settlement_run,
  account_balance,
  entry,
  txn,
  ingest_payload,
  ingest_batch,
  category_rule,
  budget_alert_log,
  budget,
  automation_script,
  account,
  fx_rate,
  app_user
CASCADE;

-- 함수
DROP FUNCTION IF EXISTS
  fn_account_balance(uuid, char),
  fn_subtree_balance(uuid),
  fn_all_balances(),
  fn_inv1_check(uuid),
  fn_inv1_trg_txn(),
  fn_inv1_trg_entry(),
  fn_inv3_txn(),
  fn_inv3_entry(),
  fn_account_no_cycle(),
  fn_tlink_member(),
  fn_tlink_immutable(),
  fn_bal_apply(uuid, char, bigint),
  fn_bal_apply_txn(uuid, int),
  fn_bal_txn(),
  fn_bal_entry(),
  fn_notify_balance(uuid, char),
  fn_notify_txn_stmt(),
  fn_notify_entry_ins(),
  fn_notify_entry_upd(),
  fn_notify_entry_del(),
  fn_notify_ingest(),
  fn_notify_settlement(),
  fn_pending_ingest_batches(),
  current_owner()
CASCADE;

-- 열거형
DROP TYPE IF EXISTS
  account_type, txn_status, entry_direction, rule_source,
  ingest_state, artifact_kind, artifact_generator
CASCADE;

COMMIT;
