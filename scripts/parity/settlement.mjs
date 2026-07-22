// INV-7 대조 하네스 — COBOL 마감 배치와 JS 참조 구현을 같은 입력으로 실행해
// 전 항목을 비교한다. 차이 1원(1바이트)이라도 있으면 실패. 허용 오차 없음.
//
// 실행: node scripts/parity/settlement.mjs --fixtures fixtures/settlement --strict
// (make parity-settlement — 컨테이너 안에서 실행, bin/settle·bin/amort 필요)

import {
  readFileSync, readdirSync, existsSync, writeFileSync,
  openSync, closeSync, unlinkSync, mkdtempSync,
} from 'node:fs';
import { spawnSync } from 'node:child_process';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { settleReference, amortReference, roundHalfEven } from './lib.mjs';
import {
  parseSettleIn, formatSettleIn, formatSettleOut,
  parseAmortIn, formatAmortOut, parseAmortOut,
} from './records.mjs';

const args = process.argv.slice(2);
const fixturesDir = args.includes('--fixtures')
  ? args[args.indexOf('--fixtures') + 1]
  : 'fixtures/settlement';
const binDir = args.includes('--bin')
  ? args[args.indexOf('--bin') + 1]
  : 'modules/settlement/bin';

let failures = 0;
const fail = (msg) => { failures += 1; console.error(`FAIL  ${msg}`); };
const pass = (msg) => console.log(`PASS  ${msg}`);

/**
 * COBOL 배치 실행 — stdin 텍스트 → stdout 라인 배열.
 * GnuCOBOL 의 LINE SEQUENTIAL 은 stdin 이 파이프면 seek 불가로 status 30 이
 * 나므로, 입력을 임시 파일에 쓰고 그 fd 를 stdin 으로 넘긴다.
 */
const workDir = mkdtempSync(join(tmpdir(), 'parity-'));
let seq = 0;
function runCobol(bin, inputText) {
  const inPath = join(workDir, `in-${(seq += 1)}.dat`);
  writeFileSync(inPath, inputText);
  const fd = openSync(inPath, 'r');
  let r;
  try {
    r = spawnSync(join(binDir, bin), [], {
      stdio: [fd, 'pipe', 'pipe'], encoding: 'utf8', maxBuffer: 64 * 1024 * 1024,
    });
  } finally {
    closeSync(fd);
    unlinkSync(inPath);
  }
  if (r.status !== 0) {
    throw new Error(`${bin} 종료코드 ${r.status}: ${r.stderr}`);
  }
  // 성공 경로에서 stderr 는 항상 비어 있어야 한다 — 침묵 무시 금지
  if (r.stderr.length > 0) {
    throw new Error(`${bin} 이 exit 0 인데 stderr 출력: ${r.stderr}`);
  }
  // 빈 줄을 걸러내지 않는다 — 사이사이 빈 줄 회귀도 diff 로 드러나야 한다.
  // 마지막 개행이 만드는 종단 빈 요소 1개만 제거.
  const lines = r.stdout.split('\n');
  if (lines.length > 0 && lines[lines.length - 1] === '') lines.pop();
  return lines;
}

/** 두 라인 배열을 전 항목 비교, 불일치 목록 반환 */
function diffLines(expected, actual) {
  const diffs = [];
  const n = Math.max(expected.length, actual.length);
  for (let i = 0; i < n; i += 1) {
    if (expected[i] !== actual[i]) {
      diffs.push({ line: i + 1, expected: expected[i] ?? '(없음)', actual: actual[i] ?? '(없음)' });
    }
  }
  return diffs;
}

// ── 1) 마감 정산: 픽스처 전체 — JS 참조 vs COBOL, 그리고 저장된 골든 검증 ──
// 픽스처가 사라져도 침묵 통과하지 않도록 최소 개수를 단언한다 (boundary+bulk).
const settleFixtures = readdirSync(fixturesDir).filter((x) => /^settle-.*\.in\.dat$/.test(x)).sort();
if (settleFixtures.length < 2) {
  fail(`settle 픽스처가 ${settleFixtures.length}개 — 최소 2개(boundary·bulk) 필요. 이름 변경/삭제로 대조가 스킵되면 안 된다.`);
}
for (const f of settleFixtures) {
  const name = f.replace(/\.in\.dat$/, '');
  const inputText = readFileSync(join(fixturesDir, f), 'utf8');
  const entries = inputText.split('\n').filter((l) => l.length > 0).map(parseSettleIn);
  const refLines = settleReference(entries).map(formatSettleOut);
  const cobolLines = runCobol('settle', inputText);
  const diffs = diffLines(refLines, cobolLines);
  if (diffs.length > 0) {
    fail(`${name}: JS↔COBOL 불일치 ${diffs.length}건 (전체 ${refLines.length}계정)`);
    for (const d of diffs.slice(0, 5)) {
      console.error(`      L${d.line}\n      ref:   ${d.expected}\n      cobol: ${d.actual}`);
    }
  } else {
    pass(`${name}: ${entries.length} entry → ${refLines.length}계정 전 항목 일치 (차이 0원)`);
  }
  // 저장된 골든이 살아있는 참조와 어긋나면 stale — 즉시 실패
  const goldenPath = join(fixturesDir, `${name}.expected.dat`);
  if (existsSync(goldenPath)) {
    const golden = readFileSync(goldenPath, 'utf8').split('\n').filter((l) => l.length > 0);
    if (diffLines(refLines, golden).length > 0) fail(`${name}: 저장된 골든이 참조와 불일치 (stale)`);
  }
}

// ── 2) 상각: JS 참조 vs COBOL + 마지막 회차 잔액 0 (DoD 2) ─────────────────
{
  const inputText = readFileSync(join(fixturesDir, 'amort.in.dat'), 'utf8');
  const loans = inputText.split('\n').filter((l) => l.length > 0).map(parseAmortIn);
  const refLines = loans.flatMap((a) =>
    amortReference(a.principal, a.rate_num, a.rate_den, a.periods)
      .map((r) => formatAmortOut(a.loan_id, r)));
  const cobolLines = runCobol('amort', inputText);
  const diffs = diffLines(refLines, cobolLines);
  if (diffs.length > 0) {
    fail(`amort: JS↔COBOL 불일치 ${diffs.length}건 (전체 ${refLines.length}행)`);
    for (const d of diffs.slice(0, 5)) {
      console.error(`      L${d.line}\n      ref:   ${d.expected}\n      cobol: ${d.actual}`);
    }
  } else {
    pass(`amort: ${loans.length}개 대출 ${refLines.length}행 전 항목 일치`);
  }
  // 저장된 amort 골든도 살아있는 참조와 대조 (settle 과 동일한 stale 검사)
  const amortGoldenPath = join(fixturesDir, 'amort.expected.dat');
  if (!existsSync(amortGoldenPath)) {
    fail('amort: 저장된 골든(amort.expected.dat)이 없음');
  } else {
    const golden = readFileSync(amortGoldenPath, 'utf8').split('\n').filter((l) => l.length > 0);
    if (diffLines(refLines, golden).length > 0) fail('amort: 저장된 골든이 참조와 불일치 (stale)');
  }
  // 각 대출의 마지막 회차 종료 잔액이 양쪽 모두 정확히 0
  const byLoan = new Map();
  for (const line of cobolLines) {
    const r = parseAmortOut(line);
    byLoan.set(r.loan_id, r);
  }
  for (const [id, last] of byLoan) {
    if (last.balance !== '0') fail(`amort ${id}: 마지막 회차 잔액 ${last.balance} != 0`);
  }
  if ([...byLoan.values()].every((r) => r.balance === '0')) {
    pass(`amort: 전 대출 마지막 회차 잔액 = 0`);
  }
}

// ── 3) 0.5 경계 전수 (DoD 3): q=0..199 × 방향 D/C, rate 1/2 ────────────────
// amount = 2q+1 → 값 q.5. NEAREST-EVEN: q 짝수→q, 홀수→q+1. 폐형식과
// JS 참조, COBOL 세 값이 모두 일치해야 한다.
{
  const entries = [];
  for (let q = 0; q < 200; q += 1) {
    for (const direction of ['D', 'C']) {
      entries.push({
        account_code: `HALF.${direction}.${String(q).padStart(4, '0')}`,
        direction, currency: 'TST',
        amount_minor: String(2 * q + 1), rate_num: '1', rate_den: '2',
      });
    }
  }
  const inputText = entries.map(formatSettleIn).join('\n') + '\n';
  const refRows = settleReference(entries);
  const cobolLines = runCobol('settle', inputText);
  const diffs = diffLines(refRows.map(formatSettleOut), cobolLines);
  let closedFormBad = 0;
  for (const row of refRows) {
    const q = BigInt(row.account_code.slice(7));
    const sign = row.account_code[5] === 'C' ? -1n : 1n;
    const expect = sign * (q % 2n === 0n ? q : q + 1n);
    if (BigInt(row.balance_krw) !== expect) closedFormBad += 1;
    // 교차검증: roundHalfEven 직접 호출도 동일해야 함
    if (roundHalfEven(sign * (2n * q + 1n), 2n) !== expect) closedFormBad += 1;
  }
  if (closedFormBad > 0) fail(`0.5 경계: 참조가 폐형식과 ${closedFormBad}건 불일치`);
  if (diffs.length > 0) {
    fail(`0.5 경계: JS↔COBOL 불일치 ${diffs.length}건`);
    for (const d of diffs.slice(0, 5)) {
      console.error(`      ref:   ${d.expected}\n      cobol: ${d.actual}`);
    }
  }
  if (closedFormBad === 0 && diffs.length === 0) {
    pass(`0.5 경계 전수 ${entries.length}건: 폐형식·JS·COBOL 삼자 일치 (NEAREST-EVEN)`);
  }
}

if (failures > 0) {
  console.error(`\nINV-7 위반: ${failures}건 실패 — 마감을 커밋하지 않는다.`);
  process.exit(1);
}
console.log('\nparity-settlement: 전 검사 통과 (차이 0원)');
