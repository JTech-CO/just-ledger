// @vitest-environment happy-dom
// make a11y — M8 접근성 게이트 (DoD 3·4·6·7).
//   · 대비비 WCAG 2.1 AA (본문 4.5:1, 비활성 3:1, 그래픽 3:1) — 라이트·다크
//   · 색각: 차변/대변이 색만이 아니라 부호로도 구분됨 (Money)
//   · reduced-motion: 트랜지션 0ms 규약 (tokens 확인)
//   · settled 기간: 편집 컨트롤이 DOM 에 없음 (렌더링 제외)

import { describe, it, expect, afterEach } from 'vitest';
import { render, screen, within, cleanup } from '@testing-library/react';
import { loadTokens, contrastRatio } from './helpers/contrast.mjs';
import Money from '../client/components/common/Money.jsx';
import { Row } from '../client/components/ledger/LedgerTable.jsx';

afterEach(cleanup);

const { light, dark } = loadTokens();

describe('대비비 WCAG 2.1 AA (DoD 4)', () => {
  for (const [name, tok] of [['light', light], ['dark', dark]]) {
    describe(name, () => {
      it('토큰이 온전히 로드된다', () => {
        for (const k of ['bg', 'surface', 'text', 'text-muted', 'accent', 'positive', 'negative', 'border']) {
          expect(tok[k], `${name}.${k}`).toMatch(/^#[0-9a-fA-F]{6}$/);
        }
      });

      it('본문 텍스트 ≥ 4.5:1 (bg·surface 양쪽)', () => {
        for (const base of ['bg', 'surface']) {
          expect(contrastRatio(tok.text, tok[base])).toBeGreaterThanOrEqual(4.5);
        }
      });

      it('비활성 텍스트 ≥ 3:1 (백서 §2.4 — 비활성도 3:1)', () => {
        for (const base of ['bg', 'surface']) {
          expect(contrastRatio(tok['text-muted'], tok[base])).toBeGreaterThanOrEqual(3);
        }
      });

      it('금액 색(positive·negative) ≥ 4.5:1 — 숫자는 본문이다', () => {
        for (const role of ['positive', 'negative']) {
          expect(contrastRatio(tok[role], tok.surface)).toBeGreaterThanOrEqual(4.5);
        }
      });

      it('accent(포커스 링·인디케이터) ≥ 3:1 비텍스트', () => {
        expect(contrastRatio(tok.accent, tok.surface)).toBeGreaterThanOrEqual(3);
        // 포커스 링은 배경(bg)과도 3:1 (§2.4 — 포커스는 항상 가시)
        expect(contrastRatio(tok.accent, tok.bg)).toBeGreaterThanOrEqual(3);
      });

      it('warning 텍스트(예산 경고·offline) ≥ 4.5:1', () => {
        expect(contrastRatio(tok.warning, tok.surface)).toBeGreaterThanOrEqual(4.5);
      });

      it('primary 버튼: accent 배경 위 surface 텍스트 ≥ 4.5:1 (button.primary)', () => {
        // global.css button.primary { background: accent; color: surface }
        expect(contrastRatio(tok.surface, tok.accent)).toBeGreaterThanOrEqual(4.5);
      });
    });
  }
});

describe('색각: 차변/대변을 색만으로 구분하지 않는다 (DoD 4, §4.3)', () => {
  it('음수는 색과 무관하게 부호(−)를 표기한다', () => {
    render(<Money minor="-1234" tone="credit" />);
    // 색(className)이 아니라 문자로 방향이 읽혀야 한다
    expect(screen.getByText('−')).toBeTruthy();
  });

  it('signed 양수는 + 부호를 표기한다', () => {
    render(<Money minor="1234" signed />);
    expect(screen.getByText('+')).toBeTruthy();
  });

  it('차변/대변 tone 이 달라도 부호로 구분된다 (흑백에서도 읽힘)', () => {
    const { container } = render(
      <>
        <Money minor="-500" tone="credit" />
        <Money minor="500" tone="debit" signed />
      </>,
    );
    const text = container.textContent;
    expect(text).toContain('−');
    expect(text).toContain('+');
  });
});

describe('settled 기간 편집 컨트롤 DOM 제외 (DoD 7)', () => {
  const accountName = new Map([['a1', '1010 현금'], ['a2', '5210 식비']]);
  const mkTxn = (id, status) => ({
    id,
    occurred_on: '2026-05-10',
    memo: 't',
    status,
    entries: [
      { id: `${id}-d`, account_id: 'a2', direction: 'debit', amount_minor: '1000', currency: 'KRW' },
      { id: `${id}-c`, account_id: 'a1', direction: 'credit', amount_minor: '1000', currency: 'KRW' },
    ],
  });

  it('posted 행에는 편집 버튼이 있다', () => {
    const { container } = render(
      <Row txn={mkTxn('t1', 'posted')} rowIndex={0} accountName={accountName}
        translateY={0} active={false} periodEnd={false} settled={false} onSelect={() => {}} onEdit={() => {}} />,
    );
    expect(within(container).queryByRole('button', { name: /편집/ })).toBeTruthy();
  });

  it('settled 행에는 편집 버튼이 DOM 에 없다(비활성 스타일이 아니라 미렌더)', () => {
    const { container } = render(
      <Row txn={mkTxn('t2', 'settled')} rowIndex={0} accountName={accountName}
        translateY={0} active={false} periodEnd settled onSelect={() => {}} onEdit={() => {}} />,
    );
    expect(within(container).queryByRole('button', { name: /편집/ })).toBeNull();
  });
});

describe('reduced-motion 규약 (DoD 6)', () => {
  it('tokens.css 의 --dur-* 가 reduce 미디어에서 0 으로 정의된다', async () => {
    const { readFileSync } = await import('node:fs');
    const { dirname, join } = await import('node:path');
    const { fileURLToPath } = await import('node:url');
    const css = readFileSync(
      join(dirname(fileURLToPath(import.meta.url)), '..', 'client', 'styles', 'tokens.css'),
      'utf8',
    );
    const reduceBlock = css.slice(css.indexOf('prefers-reduced-motion'));
    expect(reduceBlock).toMatch(/--dur-color:\s*0ms/);
    expect(reduceBlock).toMatch(/--dur-toggle:\s*0ms/);
  });
});
