-- 워커 지원 함수 (M3). 반복 적용 가능.
--
-- 워커의 RLS 모델(결정 로그 — 미결질문 #7 (a)안): 워커는 작업 '단위'로
-- set_config('app.user_id', owner) 를 설정한다. 그러나 작업 발견(어느 배치가
-- 미완료인가)은 소유자 컨텍스트 이전 단계라 RLS 아래에선 불가능하다.
-- 이 함수는 SECURITY DEFINER 로 최소 투영(배치 id·소유자·상태)만 반환한다 —
-- filename 등 내용 필드는 반환하지 않는다 (INV-6 표면 최소화).

CREATE OR REPLACE FUNCTION fn_pending_ingest_batches()
RETURNS TABLE (batch_id uuid, owner_id uuid, state ingest_state)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
SET row_security = off
AS $$
  SELECT b.id, b.owner_id, b.state
  FROM ingest_batch b
  WHERE b.state NOT IN ('done', 'failed')
  ORDER BY b.started_at NULLS FIRST, b.id;
$$;

REVOKE ALL ON FUNCTION fn_pending_ingest_batches() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION fn_pending_ingest_batches() TO ledger_worker;
