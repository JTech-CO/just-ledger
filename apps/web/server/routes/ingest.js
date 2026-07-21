// 인제스트 업로드 (M3-C). 클라이언트가 WASM 으로 파싱·암호화한 봉투를 받는다.
// 서버는 봉투의 최소 필드(지문·일자·금액)만 보고, 전체 레코드는 cipher.blob 에만
// 있어 복호화할 수 없다 (INV-6). 배치+페이로드를 원자적으로 저장하고 202 로 즉시
// 응답한 뒤(§2.2: 업로드가 UI 를 잠그지 않는다), 워커에 처리 힌트를 보낸다.
// 힌트가 실패해도 워커 스캔이 배치를 집으므로 유실되지 않는다.

import { withOwner } from '../db.js';

/** @param {import('fastify').FastifyInstance} app */
export default async function ingestRoutes(app) {
  const { ref } = app.contracts;

  app.post('/api/ingest', {
    schema: {
      body: ref('ingest-payload.schema.json'),
      response: {
        202: {
          type: 'object',
          additionalProperties: false,
          required: ['batch_id', 'state', 'record_count'],
          properties: {
            batch_id: ref('common.schema.json#/$defs/uuid'),
            state: ref('common.schema.json#/$defs/ingestState'),
            record_count: { type: 'integer', minimum: 0 },
          },
        },
      },
    },
  }, async (req, reply) => {
    const { account_id, filename, records, cipher } = req.body;

    const batchId = await withOwner(app.db, app.ownerId, async (c) => {
      // account_id 는 자기 소유여야 한다 (RLS 로 타 소유자 계정은 안 보임 → 0행이면 400)
      const acct = await c.query('SELECT 1 FROM account WHERE id = $1', [account_id]);
      if (acct.rowCount === 0) {
        const err = new Error('account_id 가 존재하지 않거나 소유자가 아닙니다');
        err.statusCode = 400;
        throw err;
      }

      const batch = await c.query(
        `INSERT INTO ingest_batch (owner_id, account_id, filename, state, row_count)
         VALUES ($1, $2, $3, 'received', $4)
         RETURNING id`,
        [app.ownerId, account_id, filename, records.length],
      );
      const id = batch.rows[0].id;
      // 봉투 전체를 jsonb 로 보관 (blob 은 서버가 못 여는 암호문 — INV-6)
      await c.query(
        `INSERT INTO ingest_payload (batch_id, payload) VALUES ($1, $2::jsonb)`,
        [id, JSON.stringify({ account_id, filename, records, cipher })],
      );
      return id;
    });

    // 워커에 처리 힌트 (실패는 무시 — 스캔 폴백). 어댑터 미연결(503)도 삼킨다.
    try {
      await app.adapters.worker.enqueueIngestBatch({ ownerId: app.ownerId, batchId });
    } catch {
      req.log?.debug?.('worker nudge 실패 — 스캔이 처리 (무해)');
    }

    reply.code(202);
    return { batch_id: batchId, state: 'received', record_count: records.length };
  });

  // 배치 상태 조회 (진행률 폴백 — 실시간은 M7)
  app.get('/api/ingest/:id', {
    schema: {
      params: { type: 'object', required: ['id'], properties: { id: ref('common.schema.json#/$defs/uuid') } },
      response: { 200: ref('ingest-batch.schema.json') },
    },
  }, async (req, reply) => {
    const row = await withOwner(app.db, app.ownerId, async (c) => {
      const r = await c.query(
        `SELECT jsonb_strip_nulls(jsonb_build_object(
           'id', id, 'account_id', account_id, 'filename', filename,
           'row_count', row_count, 'state', state,
           'started_at', to_char(started_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'),
           'finished_at', to_char(finished_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"')
         )) AS b FROM ingest_batch WHERE id = $1`,
        [req.params.id],
      );
      return r.rows[0]?.b;
    });
    if (!row) return reply.code(404).send({ error: 'not_found' });
    return row;
  });
}
