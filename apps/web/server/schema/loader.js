// contracts/*.schema.json 로더 — 서버 검증의 단일 진실원천 (기술 백서 §2.2 3중 검증의 2단).
// Fastify 기본 ajv 는 draft-07 이므로, 2020-12 계약은 전용 Ajv2020 인스턴스로 컴파일하고
// validator/serializer 컴파일러를 직접 제공한다. 응답도 계약으로 '검증'한다
// (fast-json-stringify 의 강제 변환이 아니라 — 계약 위반 응답은 500 으로 드러나야 한다).

import Ajv2020 from 'ajv/dist/2020.js';
import addFormats from 'ajv-formats';
import { readdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const CONTRACTS_DIR = join(dirname(fileURLToPath(import.meta.url)), '..', '..', '..', '..', 'contracts');
export const CONTRACT_BASE = 'https://just-ledger.dev/contracts/';

export function loadContracts() {
  const ajv = new Ajv2020({ strict: true, allErrors: false, coerceTypes: false });
  addFormats(ajv);
  // querystring 전용: HTTP 쿼리는 항상 문자열로 도착하므로 타입 강제변환을 허용한다.
  // 금액 필드는 계약상 type:string 이라 강제변환 대상이 아예 아니다 (INV-4 안전).
  // useDefaults: 스키마의 default(예: limit=100)를 실제로 주입한다 — 없으면 장식이 된다.
  const ajvQuery = new Ajv2020({ strict: true, allErrors: false, coerceTypes: true, useDefaults: true });
  addFormats(ajvQuery);

  /** @type {Record<string, object>} 파일명 → 스키마 */
  const byFile = {};
  for (const f of readdirSync(CONTRACTS_DIR).filter((x) => x.endsWith('.schema.json'))) {
    const s = JSON.parse(readFileSync(join(CONTRACTS_DIR, f), 'utf8'));
    byFile[f] = s;
    ajv.addSchema(s, s.$id);
    ajvQuery.addSchema(s, s.$id);
  }

  /** 클론 내부의 상대 $ref 를 절대 URI 로 재기저 — $id 제거 후에도 해석 가능해야 한다 */
  function absolutizeRefs(node) {
    if (Array.isArray(node)) {
      for (const x of node) absolutizeRefs(x);
    } else if (node && typeof node === 'object') {
      if (typeof node.$ref === 'string' && !node.$ref.startsWith('http') && !node.$ref.startsWith('#')) {
        node.$ref = CONTRACT_BASE + node.$ref;
      }
      for (const v of Object.values(node)) absolutizeRefs(v);
    }
  }

  /**
   * 계약에서 파생 스키마를 기계적으로 만든다 (손 재정의 금지 원칙 —
   * 원본을 구조적으로 변형만 한다: 필드 생략, required 축소, enum 제한).
   * @param {string} file 계약 파일명
   * @param {{omit?: string[], require?: string[], restrictEnum?: Record<string, string[]>}} opts
   */
  function derive(file, opts = {}) {
    const src = byFile[file];
    const clone = structuredClone(src);
    delete clone.$id;   // 파생본은 재등록하지 않는다 (인라인 사용)
    delete clone.$schema;
    absolutizeRefs(clone);
    if (opts.omit) {
      for (const k of opts.omit) delete clone.properties[k];
      clone.required = (clone.required || []).filter((k) => !opts.omit.includes(k));
    }
    if (opts.require) clone.required = opts.require;
    if (opts.restrictEnum) {
      for (const [k, allowed] of Object.entries(opts.restrictEnum)) {
        // $ref 로 enum 을 가리키는 필드는 인라인 enum 으로 좁힌다 (원본 값의 부분집합만 허용)
        clone.properties[k] = { type: 'string', enum: allowed };
      }
    }
    return clone;
  }

  /** $ref 인라인 헬퍼 — 라우트 스키마에서 계약 URI 참조 */
  const ref = (name) => ({ $ref: CONTRACT_BASE + name });

  return { ajv, ajvQuery, byFile, derive, ref };
}

/** Fastify 옵션: 계약 ajv 로 요청 검증 + 응답 '검증 후' 직렬화 */
export function fastifyCompilers(ajv, ajvQuery) {
  return {
    validatorCompiler({ schema, httpPart }) {
      // 쿼리만 강제변환 인스턴스 — body/params 는 엄격 (금액 문자열 보존)
      return (httpPart === 'querystring' ? ajvQuery : ajv).compile(schema);
    },
    serializerCompiler({ schema }) {
      if (!schema) return (data) => JSON.stringify(data);
      const validate = ajv.compile(schema);
      return (data) => {
        if (!validate(data)) {
          const err = new Error(
            '응답이 계약 스키마를 위반: ' + JSON.stringify(validate.errors?.[0] ?? null),
          );
          err.statusCode = 500;
          throw err;
        }
        return JSON.stringify(data);
      };
    },
  };
}
