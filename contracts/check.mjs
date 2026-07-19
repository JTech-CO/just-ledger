// 계약 스키마 검증 유틸 (CI: contracts 잡, 로컬: `node contracts/check.mjs`).
// contracts/*.schema.json 을 ajv strict 로 전부 컴파일하고 교차 파일 $ref 를 해석한다.
// 금액이 정수 문자열이 아닌 경우(부동소수점 표기 등) 거절됨을 표본으로 확인한다 (INV-4).
//
// contracts/ 는 linguist-vendored 이므로 이 파일은 언어 계측에 포함되지 않는다(도구 코드).
import Ajv2020 from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const dir = dirname(fileURLToPath(import.meta.url));
const files = readdirSync(dir).filter((f) => f.endsWith('.schema.json'));

const ajv = new Ajv2020({ strict: true, allErrors: false });
addFormats(ajv);

const schemas = {};
for (const f of files) {
  const s = JSON.parse(readFileSync(join(dir, f), 'utf8'));
  schemas[f] = s;
  ajv.addSchema(s, s.$id);
}

let fail = 0;
for (const f of files) {
  try {
    ajv.compile(schemas[f]);
    console.log(`OK    ${f}`);
  } catch (e) {
    console.log(`FAIL  ${f}: ${e.message}`);
    fail = 1;
  }
}

// 금액 문자열 왕복 표본 (posted txn 은 균형이 맞아야 하지만 균형은 DB 트리거 소관이므로
// 여기서는 스키마 수준 — 금액이 정수 문자열임 — 만 확인한다).
const validTxn = ajv.getSchema('https://just-ledger.dev/contracts/txn.schema.json');
const good = {
  occurred_on: '2026-07-20',
  status: 'posted',
  entries: [
    { account_id: '11111111-1111-1111-1111-111111111111', direction: 'debit', amount_minor: '150000', currency: 'KRW' },
    { account_id: '22222222-2222-2222-2222-222222222222', direction: 'credit', amount_minor: '150000', currency: 'KRW' },
  ],
};
const floaty = structuredClone(good);
floaty.entries[0].amount_minor = '1500.00';

if (validTxn(good) !== true) {
  console.log('FAIL  정상 posted txn 이 거절됨:', validTxn.errors);
  fail = 1;
}
if (validTxn(floaty) !== false) {
  console.log('FAIL  부동소수점 금액 문자열이 통과됨 (INV-4 위반 소지)');
  fail = 1;
}

console.log(fail ? '\nFAIL: 계약 검증 실패' : '\nOK: 계약 검증 통과');
process.exit(fail);
