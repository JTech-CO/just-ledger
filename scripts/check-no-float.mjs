// INV-4 정적 검사 — 금액이 부동소수점(Number)을 경유하는 코드 경로 0개.
// 사용: node scripts/check-no-float.mjs apps/web services/worker
//
// 검출 규칙:
//   1) parseFloat / toFixed 는 대상 디렉터리 전체에서 전면 금지 (금액 여부 불문 — 정당한 용도 없음)
//   2) 금액 식별자(amount|balance|minor|debit|credit|rate_num|rate_den|limit)가 있는 줄에서
//      Number( / parseInt / Math.round|floor|ceil|trunc / +단항 변환(`+ x` 아님, `Number(`만) 금지
//   3) pg 의 int8 파서 재정의(setTypeParser(20, ...)) 금지 — BIGINT 는 문자열로 받아야 한다
//   4) JSON Schema/계약에서 금액을 number 타입으로 선언하는 것은 contracts/check.mjs 소관
//
// 탈출구: 검토를 거친 예외 줄은 `// no-float-ok: <사유>` 를 붙인다 (감사 가능하게 사유 필수).

import { readdirSync, readFileSync, statSync, existsSync } from 'node:fs';
import { join, extname } from 'node:path';

const EXTS = new Set(['.js', '.mjs', '.cjs', '.jsx']);
const SKIP_DIRS = new Set(['node_modules', 'dist', 'pkg', '.vite', 'coverage', 'bin']);

const MONEY_IDENT = /(amount|balance|minor|debit|credit|rate_num|rate_den|limit_minor)/i;
const GLOBAL_BAN = /\b(parseFloat|toFixed)\s*\(/;
const MONEY_BAN = /\b(Number|parseInt)\s*\(|\bMath\.(round|floor|ceil|trunc)\s*\(|Intl\.NumberFormat/;
// pg 드라이버 설정으로 BIGINT/NUMERIC 이 Number 로 파싱되는 모든 경로를 차단한다.
// setTypeParser 는 인자 불문 전면 금지(정당한 용도가 이 코드베이스에 없음).
const PG_INT8_BAN = /setTypeParser\s*\(|parseInt8|builtins\s*\.\s*(INT8|NUMERIC|MONEY|FLOAT)/;
// 금액 프로퍼티에 산술 연산자를 직접 붙이는 암묵 Number 강제변환
// (예: a.amount_minor - b.amount_minor 정렬 콜백 — 2^53 초과 시 조용히 틀어짐).
// '+' 는 문자열 결합과 겹쳐 제외 — Number( 없는 '+x' 단항은 별도 패턴으로.
const MONEY_ARITH = /\.\s*(amount_minor|balance_minor|debit_minor|credit_minor|net_minor|limit_minor|rate_num|rate_den)\s*[-*/%]|[-*/%]\s*[\w.]*\.\s*(amount_minor|balance_minor|debit_minor|credit_minor|net_minor|limit_minor|rate_num|rate_den)\b|\(\s*\+\s*[\w.]*(amount|minor|balance)/;
const ALLOW = /\/\/\s*no-float-ok:\s*\S/;

const roots = process.argv.slice(2);
if (roots.length === 0) {
  console.error('사용법: node scripts/check-no-float.mjs <dir> [dir...]');
  process.exit(2);
}

/** @returns {string[]} */
function walk(dir) {
  const out = [];
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    const st = statSync(p);
    if (st.isDirectory()) {
      if (!SKIP_DIRS.has(name)) out.push(...walk(p));
    } else if (EXTS.has(extname(name))) {
      out.push(p);
    }
  }
  return out;
}

const violations = [];
let scanned = 0;

for (const root of roots) {
  if (!existsSync(root)) continue;   // 아직 착수 전 모듈 (예: services/worker @ M2)
  for (const file of walk(root)) {
    scanned += 1;
    const lines = readFileSync(file, 'utf8').split('\n');
    lines.forEach((line, i) => {
      if (ALLOW.test(line)) return;
      // 주석 전용 줄은 실행 코드가 아니다 (JSDoc 설명의 '합 = credit 합' 류 오탐 방지)
      const t = line.trimStart();
      if (t.startsWith('*') || t.startsWith('//') || t.startsWith('/*')) return;
      const loc = `${file}:${i + 1}`;
      if (GLOBAL_BAN.test(line)) {
        violations.push(`${loc}  전면 금지 API 사용: ${line.trim()}`);
      } else if (PG_INT8_BAN.test(line)) {
        violations.push(`${loc}  pg 숫자 파서 재정의 금지 (BIGINT/NUMERIC 은 문자열 유지): ${line.trim()}`);
      } else if (MONEY_ARITH.test(line)) {
        violations.push(`${loc}  금액 프로퍼티 직접 산술 (BigInt 경유 필수): ${line.trim()}`);
      } else if (MONEY_IDENT.test(line) && MONEY_BAN.test(line)) {
        violations.push(`${loc}  금액 경로에 Number 계열 사용: ${line.trim()}`);
      }
    });
  }
}

if (violations.length > 0) {
  console.error(`FAIL: INV-4 위반 ${violations.length}건 (검사 파일 ${scanned}개)`);
  for (const v of violations) console.error('  ' + v);
  process.exit(1);
}
console.log(`OK: INV-4 위반 0건 (검사 파일 ${scanned}개 — ${roots.join(', ')})`);
