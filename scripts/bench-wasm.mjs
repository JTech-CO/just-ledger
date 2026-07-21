// make bench-wasm — M3 DoD 3: 50MB CSV 파싱 3초 이내.
// wasm-pack --target web 산출물을 Node 에서 직접 구동한다 (같은 wasm 바이너리).
// '메인 스레드 롱태스크 0건'은 아키텍처로 보장된다 — 파싱은 항상 Web Worker 에서
// 실행되며(클라이언트 연결 코드), 여기서는 파싱 시간 예산만 계측한다.
//
// 합성 데이터는 kb(국민은행형) 포맷: 따옴표 천단위·프리앰블·한글 상호 포함.
// (계측용 카운터/시간에 Number 를 쓴다 — 금액 값 경로 아님)

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const pkgDir = join(here, '..', 'modules', 'statement-wasm', 'pkg');

const initModule = await import(
  new URL('file://' + join(pkgDir, 'statement_wasm.js').replace(/\\/g, '/')).href
);
const init = initModule.default;
const { parse_statement, parse_statement_count } = initModule;
await init({ module_or_path: readFileSync(join(pkgDir, 'statement_wasm_bg.wasm')) });

// ── 50MB 합성 kb CSV ─────────────────────────────────────────────────────
const TARGET_BYTES = 50 * 1024 * 1024;
const MERCHANTS = ['스타벅스 강남점', '지에스25 서울역점', '쿠팡 주식회사', '넷플릭스서비시스코리아', '김밥천국 역삼점'];
const parts = [
  'KB국민은행 거래내역조회\n계좌번호,123456-78-901234\n조회기간,2026.01.01 ~ 2026.12.31\n',
  '순번,거래일시,적요,보낸분/받는분,출금액(원),입금액(원),잔액(원),거래점\n',
];
let bytes = 0;
let i = 0;
while (bytes < TARGET_BYTES) {
  i += 1;
  const day = String(1 + (i % 28)).padStart(2, '0');
  const mon = String(1 + (i % 12)).padStart(2, '0');
  const hh = String(i % 24).padStart(2, '0');
  const mm = String(i % 60).padStart(2, '0');
  const merchant = MERCHANTS[i % MERCHANTS.length];
  const amt = (1000 + (i % 90000)).toLocaleString('en-US');
  const row = `${i},2026.${mon}.${day} ${hh}:${mm}:00,체크카드,${merchant},"${amt}","0","1,000,000",강남\n`;
  parts.push(row);
  bytes += Buffer.byteLength(row);
}
const csv = Buffer.from(parts.join(''));
console.log(`합성 CSV: ${(csv.length / 1024 / 1024).toFixed(1)}MB, ${i.toLocaleString('en-US')}행`);

// ── 계측 ────────────────────────────────────────────────────────────────
// V8 는 wasm 을 베이스라인(Liftoff)으로 먼저 실행하고 백그라운드에서 최적화
// (TurboFan) 컴파일한다 — 첫 대형 호출은 미최적화 코드로 돌아 수 배 느리다.
// 클라이언트 Web Worker 는 기동 시 소형 예열 호출로 티어업을 끝내 두므로
// (백서 §7 의 Julia/Prolog 예열과 동일 원칙), 게이트는 예열 후(웜) 값이다.
// 콜드 값도 함께 보고해 퇴행을 감시한다.

const tCold = performance.now();
const coldCount = parse_statement_count(csv);
const coldMs = performance.now() - tCold;
console.log(`콜드(티어업 전 포함): ${coldCount.toLocaleString('en-US')}건, ${coldMs.toFixed(0)}ms — 참고용`);

// 분해 계측 (웜): 순수 파싱 vs JSON 직렬화+JS 문자열 경계
const tc0 = performance.now();
const count = parse_statement_count(csv);
const parseOnlyMs = performance.now() - tc0;

const t0 = performance.now();
const resultJson = parse_statement(csv);
const elapsedMs = performance.now() - t0;

const parsed = JSON.parse(resultJson);
console.log(`웜 파싱만: ${count.toLocaleString('en-US')}건, ${parseOnlyMs.toFixed(0)}ms`);
console.log(`웜 파싱+직렬화: ${parsed.records.length.toLocaleString('en-US')}건, ${elapsedMs.toFixed(0)}ms (직렬화·경계 ≈ ${(elapsedMs - parseOnlyMs).toFixed(0)}ms)`);

const BUDGET_MS = 3000;
if (elapsedMs > BUDGET_MS) {
  console.error(`FAIL: 웜 ${elapsedMs.toFixed(0)}ms > 예산 ${BUDGET_MS}ms (M3 DoD 3)`);
  process.exit(1);
}
console.log(`OK: 50MB 파싱 웜 ${elapsedMs.toFixed(0)}ms ≤ ${BUDGET_MS}ms (M3 DoD 3)`);
