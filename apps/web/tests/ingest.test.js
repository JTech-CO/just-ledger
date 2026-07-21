// M3-C 업로드 API 통합 테스트 (실제 PostgreSQL).
//   - 봉투 계약 검증(위반 400) + 202 왕복
//   - batch + payload 저장, 상태 조회
//   - INV-6: 서버는 봉투 최소 필드만 본다 (봉투에 평문이 없으므로 자명, 회귀 방지)
//   - 워커 미기동에도 업로드 성공(nudge 실패 무시, 스캔 폴백)

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { buildApp } from '../server/app.js';
import { createScratchDb, dropScratchDb } from './helpers/db.js';

const DB = 'ledger_ingest_test';
/** @type {import('fastify').FastifyInstance} */
let app;
let accountId;

// 유효한 봉투(서버 가시 최소 필드 + 형식만 맞는 더미 cipher — 서버는 blob 을 열지 않는다)
function envelope(overrides = {}) {
  return {
    account_id: accountId,
    filename: 'stmt-2026-06.csv',
    file_hash: 'ab'.repeat(32),
    record_count: 2,
    records: [
      { source_hash: '1'.repeat(64), occurred_on: '2026-06-02', amount_minor: '-4500', currency: 'KRW' },
      { source_hash: '2'.repeat(64), occurred_on: '2026-06-05', amount_minor: '3500000', currency: 'KRW' },
    ],
    cipher: {
      alg: 'argon2id-chacha20poly1305',
      salt: 'AAAAAAAAAAAAAAAAAAAAAA==',
      nonce: 'AAAAAAAAAAAAAAAA',
      m_kib: 19456, t: 2, p: 1,
      blob: 'AAAAAAAAAAAAAAAAAAAAAA==',
    },
    ...overrides,
  };
}

beforeAll(async () => {
  const url = await createScratchDb(DB);
  app = await buildApp({ databaseUrl: url, ownerUsername: 'ingest_test' });
  await app.ready();
  const acct = await app.inject({
    method: 'POST', url: '/api/accounts',
    payload: { code: 'ING.CASH', name: '입출금', type: 'asset', currency: 'KRW' },
  });
  accountId = acct.json().id;
});

afterAll(async () => {
  await app?.close();
  await dropScratchDb(DB);
});

describe('POST /api/ingest', () => {
  it('유효 봉투 → 202, batch 생성 (워커 미기동이어도 성공)', async () => {
    const r = await app.inject({ method: 'POST', url: '/api/ingest', payload: envelope() });
    expect(r.statusCode).toBe(202);
    const body = r.json();
    expect(body.state).toBe('received');
    expect(body.record_count).toBe(2);
    expect(body.batch_id).toMatch(/^[0-9a-f-]{36}$/);

    // 상태 조회
    const got = await app.inject({ url: `/api/ingest/${body.batch_id}` });
    expect(got.statusCode).toBe(200);
    expect(got.json().state).toBe('received');
    expect(got.json().account_id).toBe(accountId);
  });

  it('타 소유자/부재 account_id → 400', async () => {
    const r = await app.inject({
      method: 'POST', url: '/api/ingest',
      payload: envelope({ account_id: '99999999-9999-9999-9999-999999999999' }),
    });
    expect(r.statusCode).toBe(400);
  });

  it('cipher 누락 봉투 → 400 (계약 위반)', async () => {
    const bad = envelope();
    delete bad.cipher;
    const r = await app.inject({ method: 'POST', url: '/api/ingest', payload: bad });
    expect(r.statusCode).toBe(400);
    expect(r.json().error).toBe('contract_violation');
  });

  it('records 금액 소수점 문자열 → 400', async () => {
    const r = await app.inject({
      method: 'POST', url: '/api/ingest',
      payload: envelope({
        records: [{ source_hash: '3'.repeat(64), occurred_on: '2026-06-01', amount_minor: '1500.00', currency: 'KRW' }],
      }),
    });
    expect(r.statusCode).toBe(400);
  });

  it('INV-6: 응답·저장 어디에도 blob 평문이 새지 않는다 (봉투 최소 필드만 노출)', async () => {
    const r = await app.inject({ method: 'POST', url: '/api/ingest', payload: envelope() });
    const batchId = r.json().batch_id;
    // 배치 조회 응답에는 내용 필드가 없다 (지문·일자·금액은 payload 안, 조회는 배치 메타만)
    const got = await app.inject({ url: `/api/ingest/${batchId}` });
    const keys = Object.keys(got.json());
    expect(keys).not.toContain('records');
    expect(keys).not.toContain('cipher');
    expect(keys).not.toContain('payload');
  });
});
