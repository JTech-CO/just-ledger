// WCAG 2.1 대비비 계산 (a11y 테스트용). tokens.css 를 파싱해 라이트·다크
// 두 팔레트를 뽑고 역할별 대비를 검증한다. R 쪽(modules/analytics/R/tokens.R)의
// contrast_ratio 와 같은 공식 — 언어는 달라도 계산은 동일해야 한다.

import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const TOKENS = join(
  dirname(fileURLToPath(import.meta.url)),
  '..', '..', 'client', 'styles', 'tokens.css',
);

/** #RRGGBB → 상대 휘도 (WCAG) */
export function relativeLuminance(hex) {
  const n = hex.replace('#', '');
  const rgb = [0, 2, 4].map((i) => parseInt(n.slice(i, i + 2), 16) / 255);
  const lin = rgb.map((c) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4));
  return 0.2126 * lin[0] + 0.7152 * lin[1] + 0.0722 * lin[2];
}

/** 대비비 (항상 ≥ 1) */
export function contrastRatio(a, b) {
  const la = relativeLuminance(a);
  const lb = relativeLuminance(b);
  return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
}

/**
 * tokens.css → { light: {name: hex}, dark: {name: hex} }.
 * 라이트 = 첫 :root(수동 토글 블록 우선), 다크 = data-theme='dark' 또는 media.
 */
export function loadTokens() {
  const css = readFileSync(TOKENS, 'utf8').replace(/\/\*[\s\S]*?\*\//g, '');

  const block = (selectorRe) => {
    const m = css.match(selectorRe);
    if (!m) return {};
    const start = css.indexOf('{', m.index);
    const end = css.indexOf('}', start);
    const body = css.slice(start + 1, end);
    const out = {};
    for (const decl of body.split(';')) {
      const d = decl.match(/--([a-z0-9-]+)\s*:\s*(#[0-9a-fA-F]{6})/);
      if (d) out[d[1]] = d[2];
    }
    return out;
  };

  const light = { ...block(/:root\s*\{/), ...block(/:root\[data-theme=['"]light['"]\]/) };
  const dark = { ...block(/prefers-color-scheme\s*:\s*dark[^}]*:root/), ...block(/:root\[data-theme=['"]dark['"]\]/) };
  return { light, dark };
}
