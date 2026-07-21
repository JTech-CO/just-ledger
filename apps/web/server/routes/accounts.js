// 계정 CRUD (M2 DoD 2). 요청·응답 모두 contracts/account.schema.json 기준.
// 응답 SELECT 는 계약 필드만 고른다 (owner_id 등 내부 컬럼은 additionalProperties:false 위반).

import { withOwner } from '../db.js';

const ACCOUNT_COLS = 'id, code, name, type, currency, parent_id, is_closed';

/** @param {import('fastify').FastifyInstance} app */
export default async function accountRoutes(app) {
  const { derive, ref } = app.contracts;

  app.post('/api/accounts', {
    schema: {
      body: derive('account.schema.json', { omit: ['id'], require: ['code', 'name', 'type', 'currency'] }),
      response: { 201: ref('account.schema.json') },
    },
  }, async (req, reply) => {
    const { code, name, type, currency, parent_id = null, is_closed = false } = req.body;
    const row = await withOwner(app.db, app.ownerId, async (c) => {
      const r = await c.query(
        `INSERT INTO account (owner_id, code, name, type, currency, parent_id, is_closed)
         VALUES ($1, $2, $3, $4, $5, $6, $7)
         RETURNING ${ACCOUNT_COLS}`,
        [app.ownerId, code, name, type, currency, parent_id, is_closed],
      );
      return r.rows[0];
    });
    reply.code(201);
    return row;
  });

  app.get('/api/accounts', {
    schema: {
      response: { 200: { type: 'array', items: ref('account.schema.json') } },
    },
  }, async () => {
    return withOwner(app.db, app.ownerId, async (c) => {
      const r = await c.query(`SELECT ${ACCOUNT_COLS} FROM account ORDER BY code`);
      return r.rows;
    });
  });

  app.get('/api/accounts/:id', {
    schema: {
      params: { type: 'object', required: ['id'], properties: { id: ref('common.schema.json#/$defs/uuid') } },
      response: { 200: ref('account.schema.json') },
    },
  }, async (req, reply) => {
    const row = await withOwner(app.db, app.ownerId, async (c) => {
      const r = await c.query(`SELECT ${ACCOUNT_COLS} FROM account WHERE id = $1`, [req.params.id]);
      return r.rows[0];
    });
    if (!row) return reply.code(404).send({ error: 'not_found' });
    return row;
  });

  app.patch('/api/accounts/:id', {
    schema: {
      params: { type: 'object', required: ['id'], properties: { id: ref('common.schema.json#/$defs/uuid') } },
      body: derive('account.schema.json', { omit: ['id', 'code', 'type', 'currency'], require: [] }),
      response: { 200: ref('account.schema.json') },
    },
  }, async (req, reply) => {
    const { name, parent_id, is_closed } = req.body;
    // 자기 참조는 즉시 거절 (순환 일반 검사는 DB 트리거 — JL006)
    if (parent_id === req.params.id) {
      return reply.code(400).send({ error: 'self_parent', message: '자기 자신을 상위 계정으로 둘 수 없습니다' });
    }
    const row = await withOwner(app.db, app.ownerId, async (c) => {
      const r = await c.query(
        `UPDATE account SET
           name      = coalesce($2, name),
           parent_id = CASE WHEN $4::boolean THEN $3::uuid ELSE parent_id END,
           is_closed = coalesce($5, is_closed)
         WHERE id = $1
         RETURNING ${ACCOUNT_COLS}`,
        [req.params.id, name ?? null, parent_id ?? null, parent_id !== undefined, is_closed ?? null],
      );
      return r.rows[0];
    });
    if (!row) return reply.code(404).send({ error: 'not_found' });
    return row;
  });

  app.delete('/api/accounts/:id', {
    schema: {
      params: { type: 'object', required: ['id'], properties: { id: ref('common.schema.json#/$defs/uuid') } },
    },
  }, async (req, reply) => {
    const count = await withOwner(app.db, app.ownerId, async (c) => {
      const r = await c.query('DELETE FROM account WHERE id = $1', [req.params.id]);
      return r.rowCount;
    });
    if (count === 0) return reply.code(404).send({ error: 'not_found' });
    return reply.code(204).send();
  });
}
