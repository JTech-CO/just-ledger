// DoD 2 (M8): 디자인 토큰 외 하드코딩 색상 0건. styles/tokens.css 만이 색의
// 단일 진실원천이며, 그 밖의 소스에는 hex·rgb()·hsl()·색 키워드가 없어야 한다.
//
// 검사 대상: apps/web/client 의 .css/.jsx/.js (tokens.css 는 제외 — 정의처).
// 허용: var(--...), transparent, currentColor, inherit, none, 그리고 색이 아닌
//       맥락의 hex(주석·데이터 속성)는 실무상 오탐이라 CSS 색 속성/함수만 본다.
//
// 실행: node scripts/check-hardcoded-color.mjs

import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, extname, relative, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
const SCAN_DIR = join(ROOT, 'apps', 'web', 'client');
const TOKENS = join(SCAN_DIR, 'styles', 'tokens.css');

// hex 색: #rgb / #rrggbb / #rrggbbaa (단어 경계). rgb()/hsl()/rgba()/hsla().
const HEX = /#[0-9a-fA-F]{3,8}\b/g;
const FUNC = /\b(?:rgb|rgba|hsl|hsla|hwb|lab|lch|oklab|oklch|color)\s*\(/g;
// CSS 색 키워드(자주 쓰이는 것). transparent/currentColor/inherit 는 허용.
const NAMED = /\b(?:white|black|red|green|blue|gray|grey|silver|navy|teal|orange|purple|yellow|pink|brown|cyan|magenta|gold|maroon|olive|lime|aqua|fuchsia)\b/gi;

function walk(dir) {
  const out = [];
  for (const name of readdirSync(dir)) {
    const p = join(dir, name);
    const st = statSync(p);
    if (st.isDirectory()) out.push(...walk(p));
    else if (['.css', '.jsx', '.js'].includes(extname(p))) out.push(p);
  }
  return out;
}

/** 그 줄이 실제 '색 지정' 맥락인지 — CSS 색 속성 또는 색 함수. 오탐(데이터·주석) 최소화. */
function isColorContext(line) {
  // 주석 줄 제외 (// 또는 /* 로 시작)
  const t = line.trim();
  if (t.startsWith('//') || t.startsWith('*') || t.startsWith('/*')) return false;
  return true;
}

const files = walk(SCAN_DIR).filter((f) => f !== TOKENS);
const violations = [];

for (const f of files) {
  const lines = readFileSync(f, 'utf8').split('\n');
  lines.forEach((line, i) => {
    if (!isColorContext(line)) return;
    for (const re of [HEX, FUNC, NAMED]) {
      re.lastIndex = 0;
      const m = re.exec(line);
      if (m) {
        // NAMED 는 색이 아닌 식별자(className, 변수)에 흔하니, 색 속성 줄로 한정.
        if (re === NAMED && !/(?:color|background|border|fill|stroke|shadow|outline)/i.test(line)) {
          continue;
        }
        violations.push({ file: relative(ROOT, f), line: i + 1, match: m[0], text: line.trim().slice(0, 80) });
      }
    }
  });
}

if (violations.length > 0) {
  console.error(`FAIL: 하드코딩 색상 ${violations.length}건 (tokens.css 밖)`);
  for (const v of violations) {
    console.error(`  ${v.file}:${v.line}  ${v.match}  ${v.text}`);
  }
  process.exit(1);
}
console.log(`OK: 하드코딩 색상 0건 (검사 ${files.length}파일 — tokens.css 만이 색 정의처)`);
