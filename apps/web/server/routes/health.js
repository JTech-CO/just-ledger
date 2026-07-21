// 활성 프로브 (M2 DoD 1 — 기동 후 3초 이내 200). DB 는 건드리지 않는 순수 liveness.

/** @param {import('fastify').FastifyInstance} app */
export default async function healthRoutes(app) {
  app.get('/health', {
    schema: {
      response: {
        200: {
          type: 'object',
          additionalProperties: false,
          required: ['status'],
          properties: { status: { const: 'ok' } },
        },
      },
    },
  }, async () => ({ status: 'ok' }));
}
