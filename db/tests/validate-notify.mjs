// NOTIFY 페이로드를 contracts/notify-event.schema.json 으로 검증한다 (M1 DoD 6).
// stdin: JSONL (한 줄 = 한 페이로드). run.sh 가 psql 출력에서 추출해 넘긴다.
// 계약이 단일 진실원천이므로 여기서 구조를 재정의하지 않는다 — ajv 로 계약만 적용.
import Ajv2020 from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const contractsDir = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'contracts');

const ajv = new Ajv2020({ strict: true, allErrors: false });
addFormats(ajv);
for (const f of readdirSync(contractsDir).filter((x) => x.endsWith('.schema.json'))) {
  const s = JSON.parse(readFileSync(join(contractsDir, f), 'utf8'));
  ajv.addSchema(s, s.$id);
}
const validate = ajv.getSchema('https://just-ledger.dev/contracts/notify-event.schema.json');

let raw = '';
process.stdin.setEncoding('utf8');
for await (const chunk of process.stdin) raw += chunk;

const lines = raw.split('\n').map((l) => l.trim()).filter(Boolean);
if (lines.length === 0) {
  console.error('FAIL: 검증할 페이로드가 없습니다 (NOTIFY 미수신?)');
  process.exit(1);
}

const seenTypes = new Set();
let fail = 0;
for (const [i, line] of lines.entries()) {
  let payload;
  try {
    payload = JSON.parse(line);
  } catch (e) {
    console.error(`FAIL #${i + 1}: JSON 파싱 실패 — ${line}`);
    fail = 1;
    continue;
  }
  if (validate(payload)) {
    seenTypes.add(payload.type);
    console.log(`OK   #${i + 1} ${payload.type}`);
  } else {
    console.error(`FAIL #${i + 1} ${payload.type ?? '?'}: ${JSON.stringify(validate.errors)}`);
    console.error(`     payload: ${line}`);
    fail = 1;
  }
}

const required = ['balance_changed', 'ingest_progress', 'settlement_done'];
for (const t of required) {
  if (!seenTypes.has(t)) {
    console.error(`FAIL: 이벤트 유형 미수신 — ${t}`);
    fail = 1;
  }
}

console.log(fail ? 'FAIL: NOTIFY 계약 검증 실패' : `OK: ${lines.length}건 전부 계약 준수 (유형 ${seenTypes.size}종)`);
process.exit(fail);
