// 거래 생성·조회 (M2 DoD 2·3·4).
// 금액은 전 경로 문자열 — DB 의 BIGINT 는 SQL 에서 ::text 로 직렬화해 JSON number 를
// 거치지 않는다 (INV-4). 균형(INV-1)은 DB deferred 트리거가 커밋 시점에 강제하며,
// 위반은 JL001 → 422 로 매핑된다 (스키마 위반 400 과 구분).

import { withOwner } from '../db.js';

// entries 를 계약 형태의 jsonb 로 만드는 SQL 조각 (amount_minor::text 필수)
const ENTRIES_JSON = `
  (SELECT coalesce(jsonb_agg(jsonb_build_object(
      'id', e.id::text,
      'txn_id', e.txn_id,
      'account_id', e.account_id,
      'direction', e.direction,
      'amount_minor', e.amount_minor::text,
      'currency', e.currency
    ) ORDER BY e.id), '[]'::jsonb)
   FROM entry e WHERE e.txn_id = t.id)`;

const TXN_JSON = `
  jsonb_strip_nulls(jsonb_build_object(
    'id', t.id,
    'occurred_on', to_char(t.occurred_on, 'YYYY-MM-DD'),
    'memo', t.memo,
    'source_hash', encode(t.source_hash, 'hex'),
    'batch_id', t.batch_id,
    'status', t.status,
    'posted_at', to_char(t.posted_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
  )) || jsonb_build_object('entries', ${ENTRIES_JSON})`;

/** @param {import('fastify').FastifyInstance} app */
export default async function txnRoutes(app) {
  const { derive, ref } = app.contracts;

  // 생성 요청: 계약에서 파생 — id/posted_at/batch_id/source_hash 는 서버·워커 소관.
  // settled 는 정산(M5)만 만들 수 있으므로 제한한다.
  const entryCreate = derive('entry.schema.json', { omit: ['id', 'txn_id'] });
  const txnCreate = derive('txn.schema.json', {
    omit: ['id', 'posted_at', 'batch_id', 'source_hash'],
    restrictEnum: { status: ['draft', 'classified', 'posted'] },
  });
  txnCreate.properties.entries = { type: 'array', minItems: 2, items: entryCreate };

  app.post('/api/txns', {
    schema: {
      body: txnCreate,
      response: { 201: ref('txn.schema.json') },
    },
  }, async (req, reply) => {
    const { occurred_on, memo = '', status, entries } = req.body;
    const row = await withOwner(app.db, app.ownerId, async (c) => {
      const t = await c.query(
        `INSERT INTO txn (owner_id, occurred_on, memo, status, posted_at)
         VALUES ($1, $2, $3, $4::txn_status,
                 CASE WHEN $4::txn_status = 'posted' THEN now() ELSE NULL END)
         RETURNING id`,
        [app.ownerId, occurred_on, memo, status],
      );
      const txnId = t.rows[0].id;
      for (const e of entries) {
        await c.query(
          `INSERT INTO entry (txn_id, account_id, direction, amount_minor, currency)
           VALUES ($1, $2, $3, $4::bigint, $5)`,
          [txnId, e.account_id, e.direction, e.amount_minor, e.currency],
        );
      }
      const out = await c.query(`SELECT ${TXN_JSON} AS txn FROM txn t WHERE t.id = $1`, [txnId]);
      return out.rows[0].txn;
    });
    reply.code(201);
    return row;
  });

  app.get('/api/txns', {
    schema: {
      querystring: {
        type: 'object',
        properties: {
          from: ref('common.schema.json#/$defs/date'),
          to: ref('common.schema.json#/$defs/date'),
          status: ref('common.schema.json#/$defs/txnStatus'),
          limit: { type: 'integer', minimum: 1, maximum: 500, default: 100 },
        },
      },
      response: { 200: { type: 'array', items: ref('txn.schema.json') } },
    },
  }, async (req) => {
    // limit 폴백은 이중 방어 — ajvQuery useDefaults 가 꺼져도 LIMIT NULL(무제한)로 새지 않게
    const { from, to, status, limit = 100 } = req.query;
    return withOwner(app.db, app.ownerId, async (c) => {
      const r = await c.query(
        `SELECT ${TXN_JSON} AS txn
         FROM txn t
         WHERE ($1::date IS NULL OR t.occurred_on >= $1)
           AND ($2::date IS NULL OR t.occurred_on <= $2)
           AND ($3::txn_status IS NULL OR t.status = $3)
         ORDER BY t.occurred_on DESC, t.id
         LIMIT $4`,
        [from ?? null, to ?? null, status ?? null, limit],
      );
      return r.rows.map((x) => x.txn);
    });
  });

  app.get('/api/txns/:id', {
    schema: {
      params: { type: 'object', required: ['id'], properties: { id: ref('common.schema.json#/$defs/uuid') } },
      response: { 200: ref('txn.schema.json') },
    },
  }, async (req, reply) => {
    const row = await withOwner(app.db, app.ownerId, async (c) => {
      const r = await c.query(`SELECT ${TXN_JSON} AS txn FROM txn t WHERE t.id = $1`, [req.params.id]);
      return r.rows[0]?.txn;
    });
    if (!row) return reply.code(404).send({ error: 'not_found' });
    return row;
  });
}
