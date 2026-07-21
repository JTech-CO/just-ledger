// Fastify 앱 팩토리. 테스트와 운영이 같은 조립을 쓴다.
// 검증(§2.2 3중 검증의 2단): 요청은 계약 ajv 로 검증(위반 400), 응답도 계약으로 검증(위반 500).
// DB 불변식 에러는 의미별 상태코드로 매핑한다 — 스키마 400 과 구분:
//   JL001(INV-1 불균형)   → 422   JL003(INV-3 settled 불변) → 409
//   23505(unique)         → 409   23503(FK)                → 409
//   RLS WITH CHECK(42501) → 403

import Fastify from 'fastify';
import { loadContracts, fastifyCompilers } from './schema/loader.js';
import { createPools, ensureDefaultOwner } from './db.js';
import { createWorkerAdapter } from './adapters/worker.js';
import { createPrologAdapter } from './adapters/prolog.js';
import { createRealtimeAdapter } from './adapters/realtime.js';
import healthRoutes from './routes/health.js';
import accountRoutes from './routes/accounts.js';
import txnRoutes from './routes/txns.js';
import balanceRoutes from './routes/balances.js';

const PG_ERROR_MAP = {
  JL001: { status: 422, error: 'unbalanced', message: 'INV-1: 통화별 차변·대변이 일치해야 합니다' },
  JL003: { status: 409, error: 'settled_immutable', message: 'INV-3: 마감된 거래는 변경할 수 없습니다' },
  JL005: { status: 409, error: 'link_immutable', message: '이체 링크 쌍은 수정할 수 없습니다' },
  23505: { status: 409, error: 'duplicate', message: '유니크 제약 위반' },
  23503: { status: 409, error: 'reference', message: '참조 무결성 위반 (사용 중이거나 대상 없음)' },
  23514: { status: 400, error: 'check_violation', message: '값 제약 위반' },
  42501: { status: 403, error: 'forbidden', message: '소유자 격리 위반' },
};

/**
 * @param {{ databaseUrl: string, ownerUsername?: string, logger?: boolean }} opts
 */
export async function buildApp(opts) {
  const app = Fastify({ logger: opts.logger ?? false });

  const contracts = loadContracts();
  const { validatorCompiler, serializerCompiler } = fastifyCompilers(contracts.ajv, contracts.ajvQuery);
  app.setValidatorCompiler(validatorCompiler);
  app.setSerializerCompiler(serializerCompiler);

  const { appPool, adminPool } = createPools(opts.databaseUrl);
  const ownerId = await ensureDefaultOwner(adminPool, opts.ownerUsername ?? 'local');

  app.decorate('db', appPool);
  app.decorate('adminDb', adminPool);
  app.decorate('ownerId', ownerId);
  app.decorate('contracts', contracts);
  app.decorate('adapters', {
    worker: createWorkerAdapter(),
    prolog: createPrologAdapter(),
    realtime: createRealtimeAdapter(),
  });

  app.setErrorHandler((err, req, reply) => {
    // Fastify 검증 실패 → 400 (계약 위반 요청)
    if (err.validation) {
      return reply.code(400).send({
        error: 'contract_violation',
        message: err.message,
      });
    }
    const mapped = PG_ERROR_MAP[err.code];
    if (mapped) {
      return reply.code(mapped.status).send({ error: mapped.error, message: mapped.message });
    }
    req.log.error(err);
    return reply.code(err.statusCode ?? 500).send({ error: 'internal', message: err.message });
  });

  await app.register(healthRoutes);
  await app.register(accountRoutes);
  await app.register(txnRoutes);
  await app.register(balanceRoutes);

  app.addHook('onClose', async () => {
    await appPool.end();
    await adminPool.end();
  });

  return app;
}
