// make test-api — M2 DoD 1·2·3·4(서버 측)·불변식 매핑 왕복 테스트.
// 실제 PostgreSQL(스크래치 DB) 위에서 fastify.inject 로 전체 검증 체인을 통과한다.

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import Fastify from 'fastify';
import { buildApp } from '../server/app.js';
import { loadContracts, fastifyCompilers } from '../server/schema/loader.js';
import { createScratchDb, dropScratchDb } from './helpers/db.js';

const DB = 'ledger_api_test';
/** @type {import('fastify').FastifyInstance} */
let app;
let bootMs = 0;

// 18자리 최대 금액 — 문자열 왕복 무손실의 극한 케이스 (Number 였다면 정밀도 파괴)
const MAX18 = '999999999999999999';

beforeAll(async () => {
  const url = await createScratchDb(DB);
  const t0 = performance.now();
  app = await buildApp({ databaseUrl: url, ownerUsername: 'api_test' });
  await app.ready();
  bootMs = performance.now() - t0;
});

afterAll(async () => {
  await app?.close();
  await dropScratchDb(DB);
});

async function makeAccount(code, type = 'asset', currency = 'KRW') {
  const r = await app.inject({
    method: 'POST',
    url: '/api/accounts',
    payload: { code, name: `테스트 ${code}`, type, currency },
  });
  expect(r.statusCode).toBe(201);
  return r.json();
}

describe('M2 DoD 1 — health', () => {
  it('GET /health 200, 기동 3초 이내', async () => {
    const r = await app.inject({ method: 'GET', url: '/health' });
    expect(r.statusCode).toBe(200);
    expect(r.json()).toEqual({ status: 'ok' });
    expect(bootMs).toBeLessThan(3000);
  });
});

describe('M2 DoD 2 — 계정 CRUD 왕복', () => {
  it('생성 → 조회 → 수정 → 삭제', async () => {
    const made = await makeAccount('CRUD.1');
    expect(made.code).toBe('CRUD.1');
    expect(made.is_closed).toBe(false);

    const got = await app.inject({ url: `/api/accounts/${made.id}` });
    expect(got.statusCode).toBe(200);
    expect(got.json()).toEqual(made);

    const patched = await app.inject({
      method: 'PATCH',
      url: `/api/accounts/${made.id}`,
      payload: { name: '이름 변경' },
    });
    expect(patched.statusCode).toBe(200);
    expect(patched.json().name).toBe('이름 변경');

    const del = await app.inject({ method: 'DELETE', url: `/api/accounts/${made.id}` });
    expect(del.statusCode).toBe(204);
    const gone = await app.inject({ url: `/api/accounts/${made.id}` });
    expect(gone.statusCode).toBe(404);
  });

  it('중복 code → 409', async () => {
    await makeAccount('DUP.1');
    const dup = await app.inject({
      method: 'POST',
      url: '/api/accounts',
      payload: { code: 'DUP.1', name: 'x', type: 'asset', currency: 'KRW' },
    });
    expect(dup.statusCode).toBe(409);
  });
});

describe('M2 DoD 3 — 계약 검증 (위반 400)', () => {
  it('통화 소문자 → 400', async () => {
    const r = await app.inject({
      method: 'POST',
      url: '/api/accounts',
      payload: { code: 'BAD.1', name: 'x', type: 'asset', currency: 'krw' },
    });
    expect(r.statusCode).toBe(400);
    expect(r.json().error).toBe('contract_violation');
  });

  it('금액 소수점 문자열 → 400 (positiveMinor 패턴)', async () => {
    const a = await makeAccount('V.A');
    const b = await makeAccount('V.B', 'expense');
    const r = await app.inject({
      method: 'POST',
      url: '/api/txns',
      payload: {
        occurred_on: '2026-07-01',
        status: 'posted',
        entries: [
          { account_id: b.id, direction: 'debit', amount_minor: '1500.00', currency: 'KRW' },
          { account_id: a.id, direction: 'credit', amount_minor: '150000', currency: 'KRW' },
        ],
      },
    });
    expect(r.statusCode).toBe(400);
  });

  it('금액 0 → 400 (INV-2 는 스키마 단계에서 이미 거절)', async () => {
    const a = await makeAccount('V.C');
    const b = await makeAccount('V.D', 'expense');
    const r = await app.inject({
      method: 'POST',
      url: '/api/txns',
      payload: {
        occurred_on: '2026-07-01',
        status: 'posted',
        entries: [
          { account_id: b.id, direction: 'debit', amount_minor: '0', currency: 'KRW' },
          { account_id: a.id, direction: 'credit', amount_minor: '0', currency: 'KRW' },
        ],
      },
    });
    expect(r.statusCode).toBe(400);
    // 스키마 단계(contract_violation)에서 잘렸는지 확인 — DB CHECK(23514→400)와 구분
    expect(r.json().error).toBe('contract_violation');
  });

  it('쿼리스트링 위반 → 400 (별도 ajvQuery 경로)', async () => {
    const badDate = await app.inject({ url: '/api/txns?from=2026-13-99x' });
    expect(badDate.statusCode).toBe(400);
    expect(badDate.json().error).toBe('contract_violation');

    const badLimit = await app.inject({ url: '/api/txns?limit=0' });
    expect(badLimit.statusCode).toBe(400);

    const overLimit = await app.inject({ url: '/api/txns?limit=501' });
    expect(overLimit.statusCode).toBe(400);
  });

  it('params 위반 (uuid 아님) → 400', async () => {
    const r = await app.inject({ url: '/api/accounts/not-a-uuid' });
    expect(r.statusCode).toBe(400);
    expect(r.json().error).toBe('contract_violation');
  });

  it('limit 이 실제로 적용된다 (default 주입 + 명시값)', async () => {
    const a = await makeAccount('L.A');
    const b = await makeAccount('L.B', 'expense');
    for (let i = 0; i < 3; i += 1) {
      const r = await app.inject({
        method: 'POST',
        url: '/api/txns',
        payload: {
          occurred_on: '2026-06-01',
          memo: `limit 검증 ${i}`,
          status: 'draft',
          entries: [
            { account_id: b.id, direction: 'debit', amount_minor: '100', currency: 'KRW' },
            { account_id: a.id, direction: 'credit', amount_minor: '100', currency: 'KRW' },
          ],
        },
      });
      expect(r.statusCode).toBe(201);
    }
    const limited = await app.inject({ url: '/api/txns?from=2026-06-01&to=2026-06-01&limit=2' });
    expect(limited.json().length).toBe(2);
  });

  it('응답 계약 검증이 실제로 강제된다 (위반 응답 → 500)', async () => {
    // buildApp 과 동일한 컴파일러로 조립한 미니 앱 — 계약과 다른 형태를 반환하는
    // 라우트가 500 으로 잡혀야 serializerCompiler 가 '검증'을 하고 있는 것이다.
    const contracts = loadContracts();
    const { validatorCompiler, serializerCompiler } = fastifyCompilers(contracts.ajv, contracts.ajvQuery);
    const mini = Fastify();
    mini.setValidatorCompiler(validatorCompiler);
    mini.setSerializerCompiler(serializerCompiler);
    mini.get('/bad', {
      schema: { response: { 200: contracts.ref('account.schema.json') } },
    }, async () => ({ garbage: true }));
    const r = await mini.inject({ url: '/bad' });
    expect(r.statusCode).toBe(500);
    await mini.close();
  });

  it('entries 1건 → 400 (minItems 2)', async () => {
    const a = await makeAccount('V.E');
    const r = await app.inject({
      method: 'POST',
      url: '/api/txns',
      payload: {
        occurred_on: '2026-07-01',
        status: 'draft',
        entries: [{ account_id: a.id, direction: 'debit', amount_minor: '1000', currency: 'KRW' }],
      },
    });
    expect(r.statusCode).toBe(400);
  });

  it('status=settled 생성 시도 → 400 (정산 전용)', async () => {
    const a = await makeAccount('V.F');
    const b = await makeAccount('V.G', 'expense');
    const r = await app.inject({
      method: 'POST',
      url: '/api/txns',
      payload: {
        occurred_on: '2026-07-01',
        status: 'settled',
        entries: [
          { account_id: b.id, direction: 'debit', amount_minor: '1000', currency: 'KRW' },
          { account_id: a.id, direction: 'credit', amount_minor: '1000', currency: 'KRW' },
        ],
      },
    });
    expect(r.statusCode).toBe(400);
  });
});

describe('M2 DoD 4(서버) — 금액 문자열 왕복 무손실', () => {
  it('18자리 최대 금액이 생성→단건→목록→기간잔액 전 경로에서 동일 문자열', async () => {
    const cash = await makeAccount('RT.CASH');
    const exp = await makeAccount('RT.EXP', 'expense');

    const created = await app.inject({
      method: 'POST',
      url: '/api/txns',
      payload: {
        occurred_on: '2026-07-15',
        memo: '왕복 무손실',
        status: 'posted',
        entries: [
          { account_id: exp.id, direction: 'debit', amount_minor: MAX18, currency: 'KRW' },
          { account_id: cash.id, direction: 'credit', amount_minor: MAX18, currency: 'KRW' },
        ],
      },
    });
    expect(created.statusCode).toBe(201);
    const txn = created.json();
    expect(txn.entries.map((e) => e.amount_minor)).toEqual([MAX18, MAX18]);
    expect(txn.posted_at).toBeTruthy();

    const single = await app.inject({ url: `/api/txns/${txn.id}` });
    expect(single.json().entries.map((e) => e.amount_minor)).toEqual([MAX18, MAX18]);

    const list = await app.inject({ url: '/api/txns?from=2026-07-15&to=2026-07-15' });
    const found = list.json().find((t) => t.id === txn.id);
    expect(found.entries.map((e) => e.amount_minor)).toEqual([MAX18, MAX18]);

    // 잔액·기간 집계도 문자열 그대로 (BigInt 재계산과 일치)
    const balances = await app.inject({ url: '/api/balances' });
    const expBal = balances.json().find((b) => b.account_id === exp.id);
    expect(expBal.balance_minor).toBe(MAX18);
    const cashBal = balances.json().find((b) => b.account_id === cash.id);
    expect(cashBal.balance_minor).toBe('-' + MAX18);

    const period = await app.inject({ url: '/api/balances/period?from=2026-07-01&to=2026-07-31' });
    const row = period.json().find((r) => r.account_id === exp.id);
    expect(row.period_month).toBe('2026-07-01');
    expect(row.debit_minor).toBe(MAX18);
    expect(row.net_minor).toBe(MAX18);
  });
});

describe('불변식 → 상태코드 매핑', () => {
  it('불균형 posted → 422 (INV-1, 커밋 시점 거절)', async () => {
    const a = await makeAccount('U.A');
    const b = await makeAccount('U.B', 'expense');
    const r = await app.inject({
      method: 'POST',
      url: '/api/txns',
      payload: {
        occurred_on: '2026-07-02',
        status: 'posted',
        entries: [
          { account_id: b.id, direction: 'debit', amount_minor: '150000', currency: 'KRW' },
          { account_id: a.id, direction: 'credit', amount_minor: '149999', currency: 'KRW' },
        ],
      },
    });
    expect(r.statusCode).toBe(422);
    expect(r.json().error).toBe('unbalanced');
  });

  it('불균형이어도 draft 는 저장된다 (분류 전 단계)', async () => {
    const a = await makeAccount('U.C');
    const b = await makeAccount('U.D', 'expense');
    const r = await app.inject({
      method: 'POST',
      url: '/api/txns',
      payload: {
        occurred_on: '2026-07-02',
        status: 'draft',
        entries: [
          { account_id: b.id, direction: 'debit', amount_minor: '5000', currency: 'KRW' },
          { account_id: a.id, direction: 'credit', amount_minor: '4000', currency: 'KRW' },
        ],
      },
    });
    expect(r.statusCode).toBe(201);
  });

  it('entry 통화 ≠ 계정 통화 → 409 (복합 FK)', async () => {
    const a = await makeAccount('U.E');
    const b = await makeAccount('U.F', 'expense');
    const r = await app.inject({
      method: 'POST',
      url: '/api/txns',
      payload: {
        occurred_on: '2026-07-02',
        status: 'draft',
        entries: [
          { account_id: b.id, direction: 'debit', amount_minor: '1000', currency: 'USD' },
          { account_id: a.id, direction: 'credit', amount_minor: '1000', currency: 'KRW' },
        ],
      },
    });
    expect(r.statusCode).toBe(409);
  });
});
