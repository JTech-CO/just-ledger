// @vitest-environment happy-dom
// make test-ui (M8) — 가상 스크롤·마감선·선택. DoD 1(60fps)의 정본은 실제
// 브라우저 프로파일이며(PROGRESS.md 첨부), CI 는 브라우저 프레임을 못 잰다.
// 여기서는 (a) 가상화가 실제로 렌더 노드를 데이터 크기에 비례시키지 않고,
// (b) 행 렌더 로직(마감선·settled·선택)이 정확함을 단위로 단언한다.
//
// happy-dom 은 레이아웃을 계산하지 않아 react-virtual 의 뷰포트 측정이
// 불안정하므로, 행 로직은 Row 를 직접 렌더해 검증한다.

import { describe, it, expect, afterEach } from 'vitest';
import { render, cleanup, fireEvent } from '@testing-library/react';
import LedgerTable, { Row } from '../client/components/ledger/LedgerTable.jsx';

afterEach(cleanup);

const accountName = new Map([['a1', '1010 현금'], ['a2', '5210 식비']]);

const mkTxn = (id, occurred_on, status = 'posted') => ({
  id,
  occurred_on,
  memo: `거래 ${id}`,
  status,
  entries: [
    { id: `${id}-d`, account_id: 'a2', direction: 'debit', amount_minor: '1000', currency: 'KRW' },
    { id: `${id}-c`, account_id: 'a1', direction: 'credit', amount_minor: '1000', currency: 'KRW' },
  ],
});

function makeRows(n) {
  return Array.from({ length: n }, (_, i) =>
    mkTxn(`t${i}`, `2026-05-${String((i % 28) + 1).padStart(2, '0')}`),
  );
}

describe('가상화: 렌더 노드가 데이터 크기에 비례하지 않는다 (DoD 1 필요조건)', () => {
  it('행 수가 100배여도 렌더된 DOM 행은 같은 규모다', () => {
    const small = render(
      <LedgerTable rows={makeRows(1000)} accountName={accountName} activeIndex={-1} onSelect={() => {}} />,
    );
    const smallCount = small.container.querySelectorAll('[data-txn-id]').length;
    cleanup();
    const big = render(
      <LedgerTable rows={makeRows(100_000)} accountName={accountName} activeIndex={-1} onSelect={() => {}} />,
    );
    const bigCount = big.container.querySelectorAll('[data-txn-id]').length;
    // 100배 데이터인데 DOM 은 같은 규모 — 선형 증가가 아니면 가상화가 작동하는 것.
    // (happy-dom 뷰포트 부재로 양쪽 다 작을 수 있으나, 핵심은 '비례하지 않음'.)
    expect(bigCount).toBeLessThan(smallCount + 100);
    expect(bigCount).toBeLessThan(1000); // 10만이 그대로 렌더되지는 않는다
  });

  it('전체 스크롤 높이는 rows × 34px 로 예약된다 (스크롤바가 데이터 전체를 반영)', () => {
    const { container } = render(
      <LedgerTable rows={makeRows(1000)} accountName={accountName} activeIndex={-1} onSelect={() => {}} />,
    );
    const sizer = container.querySelector('[class*="sizer"]');
    // 1000행 × 34 = 34000px 예약 (가상화가 전체 크기를 유지)
    expect(sizer?.style.height).toBe('34000px');
  });
});

describe('마감선 (§4.3) — Row 로직', () => {
  it('기간 경계·settled 행에 3px double 마감선 클래스', () => {
    const { container } = render(
      <Row txn={mkTxn('a', '2026-04-30', 'settled')} rowIndex={0} accountName={accountName}
        translateY={0} active={false} periodEnd settled onSelect={() => {}} />,
    );
    const row = container.querySelector('[data-txn-id="a"]');
    expect([...row.classList].some((c) => /periodEndSettled/.test(c))).toBe(true);
  });

  it('마감 전 기간 경계는 예고선 클래스', () => {
    const { container } = render(
      <Row txn={mkTxn('b', '2026-05-31', 'posted')} rowIndex={0} accountName={accountName}
        translateY={0} active={false} periodEnd settled={false} onSelect={() => {}} />,
    );
    const row = container.querySelector('[data-txn-id="b"]');
    expect([...row.classList].some((c) => /periodEndPending/.test(c))).toBe(true);
  });

  it('기간 중간 행에는 마감선이 없다', () => {
    const { container } = render(
      <Row txn={mkTxn('c', '2026-05-15')} rowIndex={0} accountName={accountName}
        translateY={0} active={false} periodEnd={false} settled={false} onSelect={() => {}} />,
    );
    const row = container.querySelector('[data-txn-id="c"]');
    expect([...row.classList].some((c) => /periodEnd/.test(c))).toBe(false);
  });
});

describe('선택·편집 (§2.2) — Row 로직', () => {
  it('active 행에 aria-selected="true" + active 클래스', () => {
    const { container } = render(
      <Row txn={mkTxn('x', '2026-05-10')} rowIndex={3} accountName={accountName}
        translateY={0} active periodEnd={false} settled={false} onSelect={() => {}} />,
    );
    const row = container.querySelector('[aria-selected="true"]');
    expect(row).toBeTruthy();
    expect([...row.classList].some((c) => /active/.test(c))).toBe(true);
  });

  it('행 클릭이 onSelect(rowIndex) 를 부른다', () => {
    let picked = -1;
    const { container } = render(
      <Row txn={mkTxn('y', '2026-05-10')} rowIndex={7} accountName={accountName}
        translateY={0} active={false} periodEnd={false} settled={false} onSelect={(i) => { picked = i; }} />,
    );
    fireEvent.click(container.querySelector('[data-txn-id="y"]'));
    expect(picked).toBe(7);
  });

  it('posted 행엔 편집 버튼, settled 행엔 편집 버튼이 DOM 에 없다 (DoD 7)', () => {
    const posted = render(
      <Row txn={mkTxn('p', '2026-05-10', 'posted')} rowIndex={0} accountName={accountName}
        translateY={0} active={false} periodEnd={false} settled={false} onSelect={() => {}} onEdit={() => {}} />,
    );
    expect(posted.container.querySelector('button')).toBeTruthy();
    cleanup();
    const settled = render(
      <Row txn={mkTxn('s', '2026-05-10', 'settled')} rowIndex={0} accountName={accountName}
        translateY={0} active={false} periodEnd settled onSelect={() => {}} onEdit={() => {}} />,
    );
    expect(settled.container.querySelector('button')).toBeNull();
  });
});
