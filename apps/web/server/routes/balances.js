// 잔액·기간 집계 조회 (M2 DoD 2 — "기간 잔액").
// 잔액 정본은 DB account_balance(트리거 유지)이며 fn_all_balances() 로 읽는다 (RLS 적용).
// 기간 집계는 v_period_totals (security_invoker 뷰). 금액은 전부 ::text.

import { withOwner } from '../db.js';

/** @param {import('fastify').FastifyInstance} app */
export default async function balanceRoutes(app) {
  const { ref } = app.contracts;

  app.get('/api/balances', {
    schema: {
      response: { 200: { type: 'array', items: ref('balance.schema.json') } },
    },
  }, async () => {
    return withOwner(app.db, app.ownerId, async (c) => {
      const r = await c.query(
        `SELECT account_id, currency, balance_minor::text AS balance_minor
         FROM fn_all_balances() ORDER BY account_id, currency`,
      );
      return r.rows;
    });
  });

  // 기간(월) × 계정 × 통화 집계. 응답 스키마는 공통 원시 타입($defs)으로 조립한다.
  app.get('/api/balances/period', {
    schema: {
      querystring: {
        type: 'object',
        properties: {
          from: ref('common.schema.json#/$defs/date'),
          to: ref('common.schema.json#/$defs/date'),
        },
      },
      response: {
        200: {
          type: 'array',
          items: {
            type: 'object',
            additionalProperties: false,
            required: ['account_id', 'currency', 'period_month', 'debit_minor', 'credit_minor', 'net_minor'],
            properties: {
              account_id: ref('common.schema.json#/$defs/uuid'),
              currency: ref('common.schema.json#/$defs/currency'),
              period_month: ref('common.schema.json#/$defs/date'),
              debit_minor: ref('common.schema.json#/$defs/moneyMinor'),
              credit_minor: ref('common.schema.json#/$defs/moneyMinor'),
              net_minor: ref('common.schema.json#/$defs/moneyMinor'),
            },
          },
        },
      },
    },
  }, async (req) => {
    const { from, to } = req.query;
    return withOwner(app.db, app.ownerId, async (c) => {
      const r = await c.query(
        `SELECT account_id, currency,
                to_char(period_month, 'YYYY-MM-DD') AS period_month,
                debit_minor::text  AS debit_minor,
                credit_minor::text AS credit_minor,
                net_minor::text    AS net_minor
         FROM v_period_totals
         WHERE ($1::date IS NULL OR period_month >= date_trunc('month', $1::date))
           AND ($2::date IS NULL OR period_month <= $2)
         ORDER BY period_month, account_id, currency`,
        [from ?? null, to ?? null],
      );
      return r.rows;
    });
  });
}
