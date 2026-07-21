// make bench-wasm — M3 DoD 3: 50MB CSV 파싱 3초 이내.
// wasm-pack --target web 산출물을 Node 에서 직접 구동한다 (같은 wasm 바이너리).
// '메인 스레드 롱태스크 0건'은 아키텍처로 보장된다 — 파싱은 항상 Web Worker 에서
// 실행된다(클라이언트 연결 코드). 여기서는 파싱 시간 예산만 계측한다.
//
// 두 경로를 모두 계측한다:
//   - UTF-8 합성(토스형): 제로카피 디코드 경로
//   - CP949 실픽스처 증식(국민형): EUC-KR 디코드 변환 경로 + 따옴표 천단위 필드
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

const PASS = 'bench-passphrase';
const BUDGET_MS = 3000;
const TARGET_BYTES = 50 * 1024 * 1024;

// ── UTF-8 합성 (토스형: 부호 단일 금액 컬럼) ─────────────────────────────
function synthUtf8() {
  const merchants = ['스타벅스 강남점', '지에스25 서울역점', '쿠팡 주식회사', '넷플릭스', '김밥천국'];
  const parts = ['﻿거래 일시,적요,거래 유형,거래 금액,거래 후 잔액,메모\n'];
  let bytes = Buffer.byteLength(parts[0]);
  let i = 0;
  while (bytes < TARGET_BYTES) {
    i += 1;
    const day = String(1 + (i % 28)).padStart(2, '0');
    const mon = String(1 + (i % 12)).padStart(2, '0');
    const row = `2026-${mon}-${day} 08:12:45,${merchants[i % merchants.length]},체크카드,-${1000 + (i % 90000)},150800,\n`;
    parts.push(row);
    bytes += Buffer.byteLength(row);
  }
  return { buf: Buffer.from(parts.join('')), rows: i };
}

// ── CP949 실픽스처 증식 (국민형: CP949 디코드 + 따옴표 천단위) ───────────
// kb.csv 의 프리앰블+헤더는 1회, 데이터 행 바이트를 반복해 50MB 를 만든다.
// CP949 바이트를 그대로 복제하므로 Node 에 인코더가 없어도 실디코드 경로를 탄다.
function synthCp949() {
  const kb = readFileSync(join(here, '..', 'fixtures', 'ingest', 'kb.csv'));
  const nl = 0x0a;
  // 앞 4줄(프리앰블 3 + 헤더 1)의 끝 오프셋을 찾는다
  let count = 0;
  let headerEnd = 0;
  for (let k = 0; k < kb.length; k += 1) {
    if (kb[k] === nl) {
      count += 1;
      if (count === 4) { headerEnd = k + 1; break; }
    }
  }
  const head = kb.subarray(0, headerEnd);
  const dataRow = kb.subarray(headerEnd, kb.indexOf(nl, headerEnd) + 1); // 데이터 1행
  const chunks = [head];
  let bytes = head.length;
  let rows = 0;
  while (bytes < TARGET_BYTES) {
    chunks.push(dataRow);
    bytes += dataRow.length;
    rows += 1;
  }
  return { buf: Buffer.concat(chunks), rows };
}

function measure(label, buf) {
  // V8 티어업(Liftoff → TurboFan) 전 콜드는 수 배 느리다. 클라이언트 Worker 는 기동 시
  // 예열하므로(PROGRESS '다음 할 일' 추적) 게이트는 웜 값이다. 콜드는 참고로 함께 보고.
  const cold0 = performance.now();
  parse_statement_count(buf, PASS);
  const coldMs = performance.now() - cold0;

  const pc0 = performance.now();
  const count = parse_statement_count(buf, PASS);
  const parseMs = performance.now() - pc0;

  const t0 = performance.now();
  const json = parse_statement(buf, PASS);
  const totalMs = performance.now() - t0;
  const records = JSON.parse(json).records.length;

  console.log(`[${label}] ${(buf.length / 1048576).toFixed(1)}MB, ${count.toLocaleString('en-US')}건 ` +
    `| 콜드 ${coldMs.toFixed(0)}ms | 웜 파싱 ${parseMs.toFixed(0)}ms | 웜 파싱+직렬화 ${totalMs.toFixed(0)}ms`);
  return { totalMs, records };
}

const utf8 = synthUtf8();
const cp949 = synthCp949();
console.log(`합성: UTF-8 ${utf8.rows.toLocaleString('en-US')}행, CP949 ${cp949.rows.toLocaleString('en-US')}행`);

const r1 = measure('UTF-8 ', utf8.buf);
const r2 = measure('CP949 ', cp949.buf);

const worst = Math.max(r1.totalMs, r2.totalMs);
if (worst > BUDGET_MS) {
  console.error(`FAIL: 웜 최댓값 ${worst.toFixed(0)}ms > 예산 ${BUDGET_MS}ms (M3 DoD 3)`);
  process.exit(1);
}
console.log(`OK: 50MB 파싱 웜 최댓값 ${worst.toFixed(0)}ms ≤ ${BUDGET_MS}ms (UTF-8·CP949 양 경로, M3 DoD 3)`);
