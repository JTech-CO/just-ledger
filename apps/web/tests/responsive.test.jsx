// @vitest-environment happy-dom
// make a11y (M8) — 반응형·가로 스크롤(DoD 5) 규약을 CSS 소스로 검증한다.
// happy-dom 은 레이아웃을 계산하지 않으므로 실제 픽셀 폭 대신 CSS 모듈 규칙에
// 반응형 브레이크포인트·overflow 정책이 있는지, 그리고 금액 컬럼이 어떤
// 브레이크포인트에서도 숨김(display:none)되지 않는지를 소스 단위로 확인한다.

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const clientDir = join(dirname(fileURLToPath(import.meta.url)), '..', 'client');
const read = (p) => readFileSync(join(clientDir, p), 'utf8');

describe('가로 스크롤 정책 (DoD 5)', () => {
  it('셸 본문은 가로 오버플로를 만들지 않는다 (min-width:0 로 축소 허용)', () => {
    const css = read('components/layout/AppShell.module.css');
    expect(css).toMatch(/min-width:\s*0/);
  });

  it('표 스크롤 영역은 세로만, 가로 오버플로는 hidden', () => {
    const css = read('components/ledger/LedgerTable.module.css');
    expect(css).toMatch(/overflow-x:\s*hidden/);
    expect(css).toMatch(/overflow-y:\s*auto/);
  });

  it('고정폭 리포트 뷰어만 가로 스크롤을 허용한다(유일한 예외)', () => {
    const css = read('components/report/FixedWidthReport.module.css');
    expect(css).toMatch(/overflow-x:\s*auto/);
  });
});

describe('반응형 브레이크포인트 (§4.2)', () => {
  it('표는 컨테이너 쿼리로 반응한다 — 뷰포트가 아닌 표 폭 기준(상세 패널 열림 대응)', () => {
    const css = read('components/ledger/LedgerTable.module.css');
    // 뷰포트 media 가 아니라 @container 여야 상세 패널로 표가 좁아질 때도 반응한다
    expect(css).toMatch(/container-type:\s*inline-size/);
    expect(css).toMatch(/@container ledger \(max-width:/);
    // 상대처→계정 순 축소 + 카드 전환 3구간
    expect((css.match(/@container ledger \(max-width:/g) || []).length).toBeGreaterThanOrEqual(3);
  });

  // 회귀: container-type:inline-size 는 인라인 축 컨테인먼트라 콘텐츠가 폭에
  // 기여하지 못한다. .wrap 은 row 방향 flex 컨테이너(.tableArea)의 항목이므로
  // flex 를 명시하지 않으면 기본값 0 1 auto(콘텐츠 기반)로 **폭이 0 이 되어 표
  // 전체가 사라진다**. 실제 브라우저에서만 재현되고 happy-dom 은 레이아웃을
  // 계산하지 않으므로, 소스 수준에서 이 조합을 못 박아 둔다.
  it('표 래퍼는 컨테이너 쿼리와 함께 flex 크기를 명시한다 — 폭 0 붕괴 방지', () => {
    const css = read('components/ledger/LedgerTable.module.css');
    const wrapRule = css.match(/\.wrap\s*\{[^}]*\}/);
    expect(wrapRule).toBeTruthy();
    expect(wrapRule[0]).toMatch(/container-type:\s*inline-size/);
    expect(wrapRule[0]).toMatch(/flex:\s*\d/);
  });

  // 회귀: 모든 셀이 <span> 이라 :last-of-type/:nth-of-type 로는 금액 칸을 못 고른다
  // (마지막 span 은 편집칸). 그러면 차변·대변이 같은 그리드 컬럼에 겹쳐 세로로 포개진다.
  // 전용 클래스(debitCol/creditCol)로 서로 다른 컬럼에 못 박는다.
  it('차변·대변은 전용 클래스로 서로 다른 컬럼에 놓인다 — 금액 겹침 방지', () => {
    const css = read('components/ledger/LedgerTable.module.css');
    expect(css).toMatch(/\.debitCol\s*\{[^}]*grid-column:\s*debit/);
    expect(css).toMatch(/\.creditCol\s*\{[^}]*grid-column:\s*credit/);
    // type 기반 선택자로 금액 컬럼을 배치하면 안 된다(재발 방지)
    expect(css).not.toMatch(/\.colAmount:(?:last-of-type|nth-of-type)/);
  });

  it('금액 컬럼은 어떤 브레이크포인트에서도 숨기지 않는다 (§4.2)', () => {
    const css = read('components/ledger/LedgerTable.module.css');
    // colAmount 에 display:none 이 붙는 규칙이 없어야 한다
    const amountHidden = /\.colAmount[^{]*\{[^}]*display:\s*none/.test(css);
    expect(amountHidden).toBe(false);
    // 반대로 상대처(colCounter)는 좁은 폭에서 숨겨진다(금액과 대비)
    expect(css).toMatch(/\.colCounter\s*\{\s*display:\s*none/);
  });
});

describe('모션 정책 (DoD 6)', () => {
  it('행 hover 는 배경만 — transform/scale 트랜지션 없음 (§2.2)', () => {
    const css = read('components/ledger/LedgerTable.module.css');
    // .row 단독 규칙(position:absolute 포함)의 transition 이 background-color 만인지
    const m = css.match(/\.row\s*\{[^}]*position:\s*absolute[^}]*\}/);
    expect(m).toBeTruthy();
    // 주석을 제거하고 실제 선언만 본다 ("transform" 이 주석에 있어도 오탐 없게)
    const rowRule = m[0].replace(/\/\*[\s\S]*?\*\//g, '');
    expect(rowRule).toMatch(/transition:\s*background-color/);
    expect(rowRule).not.toMatch(/transform\s*:/);
    expect(rowRule).not.toMatch(/scale\s*\(/);
  });
});
