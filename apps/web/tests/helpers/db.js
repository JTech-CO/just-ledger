// 테스트용 스크래치 DB 헬퍼. 0001 마이그레이션은 \ir 포함이 있어 psql 로 적용한다
// (execFile + argv 배열 — 셸 미경유, 사용자 입력 없음).

import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const run = promisify(execFile);
const REPO_ROOT = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..', '..');

export const ADMIN_URL = process.env.DATABASE_URL ?? 'postgres://ledger:ledger@db:5432/ledger';

/**
 * 스크래치 DB 를 (재)생성하고 마이그레이션을 적용한다.
 * @param {string} dbName
 * @returns {Promise<string>} 스크래치 DB 접속 URL
 */
export async function createScratchDb(dbName) {
  const url = ADMIN_URL.replace(/\/[^/]*$/, '/' + dbName);
  await run('psql', [ADMIN_URL, '-v', 'ON_ERROR_STOP=1', '-qAt',
    '-c', `DROP DATABASE IF EXISTS ${dbName} WITH (FORCE)`,
    '-c', `CREATE DATABASE ${dbName}`]);
  await run('psql', [url, '-v', 'ON_ERROR_STOP=1', '-q',
    '-f', join(REPO_ROOT, 'db', 'migrations', '0001_init.up.pgsql')],
    { cwd: REPO_ROOT });
  return url;
}

/** @param {string} dbName */
export async function dropScratchDb(dbName) {
  await run('psql', [ADMIN_URL, '-v', 'ON_ERROR_STOP=1', '-qAt',
    '-c', `DROP DATABASE IF EXISTS ${dbName} WITH (FORCE)`]);
}
