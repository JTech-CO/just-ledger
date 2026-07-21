// PostgreSQL 연결 계층.
//   - appPool: 모든 요청 쿼리. 접속 즉시 SET ROLE ledger_app → RLS 활성 (BYPASSRLS 없음).
//   - adminPool: 서버 수명주기 작업만 (기본 소유자 부트스트랩). 요청 경로에서 사용 금지.
//   - withOwner: 요청 단위 트랜잭션 — set_config('app.user_id', owner, true) 로 RLS 주체 설정.
// 금액 주의: pg 는 BIGINT(int8)를 기본으로 '문자열'로 반환한다. 절대 int8 파서를
// Number 로 재정의하지 않는다 (INV-4, scripts/check-no-float.mjs 가 정적 차단).

import pg from 'pg';

/** @typedef {import('pg').PoolClient} PoolClient */

export function createPools(databaseUrl) {
  const appPool = new pg.Pool({
    connectionString: databaseUrl,
    max: 10,
    // 풀에 편입되는 커넥션은 항상 RLS 대상 역할로 강등된다.
    // onConnect 는 pg-pool 이 promise 를 await 하고, 실패 시 해당 커넥션을 파기하며
    // connect() 호출자에게 에러를 전파한다 — SET ROLE 실패가 조용히 넘어가
    // 소유자 롤(RLS 우회)로 쿼리가 나가는 fail-open 경로를 차단한다.
    onConnect: (client) => client.query('SET ROLE ledger_app'),
  });

  const adminPool = new pg.Pool({ connectionString: databaseUrl, max: 2 });

  return { appPool, adminPool };
}

/**
 * 소유자 컨텍스트 트랜잭션. RLS 정책의 current_owner() 가 이 GUC 를 읽는다.
 * @template T
 * @param {pg.Pool} pool
 * @param {string} ownerId  app_user.id (uuid)
 * @param {(client: PoolClient) => Promise<T>} fn
 * @returns {Promise<T>}
 */
export async function withOwner(pool, ownerId, fn) {
  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SELECT set_config('app.user_id', $1, true)", [ownerId]);
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    throw err;
  } finally {
    client.release();
  }
}

/**
 * 개발 단일 사용자 부트스트랩 (M2). 인증·다중 사용자는 이후 phase 에서 확정한다.
 * app_user 쓰기 권한은 앱 역할에 없으므로 admin 풀로만 수행한다.
 * @param {pg.Pool} adminPool
 * @returns {Promise<string>} 기본 소유자 uuid
 */
export async function ensureDefaultOwner(adminPool, username = 'local') {
  const found = await adminPool.query('SELECT id FROM app_user WHERE username = $1', [username]);
  if (found.rowCount > 0) return found.rows[0].id;
  const made = await adminPool.query(
    'INSERT INTO app_user (username) VALUES ($1) ON CONFLICT (username) DO UPDATE SET username = EXCLUDED.username RETURNING id',
    [username],
  );
  return made.rows[0].id;
}
