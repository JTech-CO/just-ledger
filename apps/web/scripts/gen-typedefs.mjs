// contracts/*.schema.json → JSDoc @typedef 생성 (기술 백서 §3.1 타입 전략).
// 타입을 손으로 재정의하지 않는다 — 이 스크립트가 계약에서 기계적으로 파생한다.
// 출력: apps/web/types/contracts.gen.js (커밋 대상, linguist-generated)

import { readdirSync, readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const contractsDir = join(here, '..', '..', '..', 'contracts');
const outFile = join(here, '..', 'types', 'contracts.gen.js');

const schemas = {};
for (const f of readdirSync(contractsDir).filter((x) => x.endsWith('.schema.json'))) {
  const s = JSON.parse(readFileSync(join(contractsDir, f), 'utf8'));
  schemas[f] = s;
}

/** snake/kebab → PascalCase */
const pascal = (s) => s.replace(/[_-](\w)/g, (_, c) => c.toUpperCase()).replace(/^\w/, (c) => c.toUpperCase());

/** $ref "common.schema.json#/$defs/x" → JSDoc 타입명 */
function refType(ref) {
  const m = ref.match(/^([\w.-]+\.schema\.json)(?:#\/\$defs\/(\w+))?$/);
  if (!m) return 'any';
  if (m[2]) return pascal(m[2]);
  const target = schemas[m[1]];
  return pascal((target && target.title) || m[1].replace('.schema.json', ''));
}

/** JSON Schema 노드 → JSDoc 타입 문자열 */
function jsType(node) {
  if (!node) return 'any';
  if (node.$ref) return refType(node.$ref);
  if (node.const !== undefined) return JSON.stringify(node.const);
  if (node.enum) return node.enum.map((v) => JSON.stringify(v)).join('|');
  if (node.oneOf) return node.oneOf.map(jsType).join('|');
  switch (node.type) {
    case 'string': return 'string';
    case 'integer':
    case 'number': return 'number';   // 계약상 금액은 항상 문자열 — number 는 카운트류뿐
    case 'boolean': return 'boolean';
    case 'null': return 'null';
    case 'array': return `Array<${jsType(node.items)}>`;
    case 'object': {
      if (!node.properties) return 'Object';
      const req = new Set(node.required || []);
      const fields = Object.entries(node.properties)
        .map(([k, v]) => `${k}${req.has(k) ? '' : '?'}: ${jsType(v)}`)
        .join(', ');
      return `{${fields}}`;
    }
    default: return 'any';
  }
}

let out = `// AUTO-GENERATED from contracts/*.schema.json — 수정 금지. pnpm gen:types 로 재생성.
// 금액(MoneyMinor/PositiveMinor)은 최소 화폐 단위 정수 '문자열'이다 (INV-4).
`;

// 1) common.schema.json $defs → 원시 타입 별칭
const common = schemas['common.schema.json'];
for (const [name, def] of Object.entries(common.$defs)) {
  out += `\n/** @typedef {${jsType(def)}} ${pascal(name)} ${def.description ? '— ' + def.description.split('\n')[0] : ''} */\n`;
}

// 2) 엔티티 스키마 → @typedef {Object}
for (const [file, s] of Object.entries(schemas)) {
  if (file === 'common.schema.json') continue;
  const name = pascal(s.title || file.replace('.schema.json', ''));
  if (s.oneOf) {
    out += `\n/** @typedef {${s.oneOf.map(jsType).join('|')}} ${name} — ${(s.description || '').split('\n')[0]} */\n`;
    continue;
  }
  const req = new Set(s.required || []);
  out += `\n/**\n * @typedef {Object} ${name} — ${(s.description || '').split('\n')[0]}\n`;
  for (const [k, v] of Object.entries(s.properties || {})) {
    out += ` * @property {${jsType(v)}} ${req.has(k) ? k : `[${k}]`}\n`;
  }
  out += ` */\n`;
}

out += `\nexport {};\n`;

mkdirSync(dirname(outFile), { recursive: true });
writeFileSync(outFile, out);
console.log(`generated: ${outFile}`);
