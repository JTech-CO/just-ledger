// 서버 엔트리. M2 DoD 1: 기동 후 3초 이내 /health 200.
import { buildApp } from './app.js';

const started = process.hrtime.bigint();

const app = await buildApp({
  databaseUrl: process.env.DATABASE_URL ?? 'postgres://ledger:ledger@localhost:5432/ledger',
  logger: true,
});

const port = Number.parseInt(process.env.PORT ?? '3000', 10);   // no-float-ok: 포트 번호 (금액 아님)
await app.listen({ host: '0.0.0.0', port });

const bootMs = (process.hrtime.bigint() - started) / 1000000n;
app.log.info(`just-ledger web 기동 완료: ${bootMs}ms (기준 3000ms 이내)`);
