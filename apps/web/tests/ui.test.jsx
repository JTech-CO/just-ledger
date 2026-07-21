// @vitest-environment happy-dom
// make test-ui — M2 DoD 4: 브라우저(DOM) 경로에서 수기 입력 → 저장 → 재조회 시
// 금액 문자열 왕복 무손실. 실제 서버(스크래치 DB) + 실제 fetch 로 UI 코드 경로를 관통한다.
// same-origin: beforeAll 에서 happy-dom 의 URL 을 서버 오리진으로 맞춘다 (setURL).

import { describe, it, expect, beforeAll, afterAll, afterEach } from 'vitest';
import { render, screen, waitFor, within, cleanup } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { buildApp } from '../server/app.js';
import { createScratchDb, dropScratchDb } from './helpers/db.js';
import { setApiBase, createAccount } from '../client/lib/api.js';
import { useLedgerStore } from '../client/store/ledgerStore.js';
import LedgerPage from '../client/pages/LedgerPage.jsx';

afterEach(cleanup);

const DB = 'ledger_ui_test';
// Number 였다면 파괴됐을 값: 2^53 근방 초과 18자리
const AMOUNT = '900719925474099301';

/** @type {import('fastify').FastifyInstance} */
let app;

beforeAll(async () => {
  const url = await createScratchDb(DB);
  app = await buildApp({ databaseUrl: url, ownerUsername: 'ui_test' });
  await app.listen({ host: '127.0.0.1', port: 0 });
  const { port } = app.server.address();
  // happy-dom 문서 오리진을 서버와 일치시켜 same-origin 을 충족시킨다
  window.happyDOM.setURL(`http://127.0.0.1:${port}`);
  setApiBase(`http://127.0.0.1:${port}`);
  await createAccount({ code: 'UI.CASH', name: '현금', type: 'asset', currency: 'KRW' });
  await createAccount({ code: 'UI.FOOD', name: '식비', type: 'expense', currency: 'KRW' });
});

afterAll(async () => {
  await app?.close();
  await dropScratchDb(DB);
});

describe('M2 DoD 4 — 브라우저 경로 문자열 왕복 무손실', () => {
  it('수기 입력(전각·구분자 포함) → 저장 → 재조회에서 금액이 자릿수 하나 다르지 않다', async () => {
    const user = userEvent.setup();
    // 스토어 로드를 명시적으로 await — 실패 시 원인이 이 자리에서 드러난다
    await useLedgerStore.getState().loadAll();
    render(<LedgerPage />);

    // 계정 로드 대기
    await waitFor(() => {
      expect(screen.getAllByText(/UI\.CASH/).length).toBeGreaterThan(0);
    }, { timeout: 5000 });

    const form = screen.getByRole('form', { name: '수기 거래 입력' });
    await user.selectOptions(within(form).getByLabelText(/차변/), screen.getAllByRole('option', { name: /UI\.FOOD/ })[0]);
    await user.selectOptions(within(form).getByLabelText(/대변/), screen.getAllByRole('option', { name: /UI\.CASH/ })[1]);

    // 사용자가 구분자를 섞어 입력해도 정규화되어 문자열 정수로만 흐른다
    const grouped = AMOUNT.replace(/\B(?=(\d{3})+(?!\d))/g, ',');
    await user.type(within(form).getByLabelText('금액'), grouped);
    await user.type(within(form).getByLabelText(/적요/), '왕복 검증');
    await user.click(within(form).getByRole('button', { name: '기입' }));

    // 저장 후 재조회된 원장 표의 data-amount 가 원본 문자열과 정확히 일치
    await waitFor(() => {
      const cells = document.querySelectorAll(`[data-amount="${AMOUNT}"]`);
      expect(cells.length).toBe(2);   // debit + credit
    });

    // 잔액 요약도 동일 문자열 (credit 계정은 부호 반전)
    await waitFor(() => {
      expect(document.querySelector(`[data-balance="${AMOUNT}"]`)).not.toBeNull();
      expect(document.querySelector(`[data-balance="-${AMOUNT}"]`)).not.toBeNull();
    });

    // 서버 재조회로 교차 확인 (UI 상태가 아닌 영속 상태)
    const res = await fetch(`http://127.0.0.1:${app.server.address().port}/api/txns?limit=10`);
    const txns = await res.json();
    const found = txns.find((t) => t.memo === '왕복 검증');
    expect(found.entries.map((e) => e.amount_minor)).toEqual([AMOUNT, AMOUNT]);
  });

  it('소수점 입력은 클라이언트에서 즉시 거절된다 (기입 버튼 비활성)', async () => {
    const user = userEvent.setup();
    await useLedgerStore.getState().loadAll();
    render(<LedgerPage />);
    await waitFor(() => {
      expect(screen.getAllByText(/UI\.CASH/).length).toBeGreaterThan(0);
    }, { timeout: 5000 });
    const form = screen.getAllByRole('form', { name: '수기 거래 입력' })[0];
    const input = within(form).getByLabelText('금액');
    await user.type(input, '1500.75');
    // 타이핑이 실제 입력에 도달했는지 먼저 확인 (도달 실패 시에도 참인 공허 단언 방지)
    expect(input.value).toBe('1500.75');
    expect(within(form).getByRole('button', { name: '기입' }).disabled).toBe(true);
  });
});
