// @vitest-environment happy-dom
// make test-ui (M8) — 실시간 병합 단일 진입점 applyRealtime 이 M7 계약 프레임
// 5종(balance_changed·sync·settlement_done·budget_alert·ingest_progress)을
// 올바른 store 슬라이스로 병합하는지. 금액은 문자열 그대로(INV-4).

import { describe, it, expect, beforeEach } from 'vitest';
import { useLedgerStore } from '../client/store/ledgerStore.js';

const reset = () =>
  useLedgerStore.setState({
    balances: new Map(),
    flashKeys: new Set(),
    budgetAlerts: new Map(),
    ingest: new Map(),
    isSettled: false,
  });

describe('applyRealtime — M7 계약 프레임 병합', () => {
  beforeEach(reset);

  it('balance_changed: 잔액 갱신 + flash 표시(문자열 보존)', () => {
    const { applyRealtime } = useLedgerStore.getState();
    applyRealtime({
      type: 'balance_changed',
      row: { account_id: 'acc-1', currency: 'KRW', balance_minor: '900719925474099301' },
    });
    const s = useLedgerStore.getState();
    expect(s.balances.get('acc-1:KRW')).toBe('900719925474099301'); // 18자리 무손실
    expect(s.flashKeys.has('acc-1:KRW')).toBe(true);
  });

  it('sync: 스냅샷으로 잔액 전체 교체(재접속 수렴)', () => {
    useLedgerStore.getState().applyRealtime({
      type: 'balance_changed',
      row: { account_id: 'old', currency: 'KRW', balance_minor: '5' },
    });
    useLedgerStore.getState().applyRealtime({
      type: 'sync',
      balances: [
        { account_id: 'a', currency: 'KRW', balance_minor: '100' },
        { account_id: 'b', currency: 'USD', balance_minor: '-200' },
      ],
    });
    const s = useLedgerStore.getState();
    expect(s.balances.has('old:KRW')).toBe(false); // 교체(수렴)
    expect(s.balances.get('a:KRW')).toBe('100');
    expect(s.balances.get('b:USD')).toBe('-200');
  });

  it('settlement_done: isSettled=true', () => {
    useLedgerStore.getState().applyRealtime({ type: 'settlement_done', period: { start: '2026-05-01', end: '2026-05-31' } });
    expect(useLedgerStore.getState().isSettled).toBe(true);
  });

  it('budget_alert: budgetAlerts 에 budget_id 키로 병합', () => {
    const evt = { type: 'budget_alert', budget_id: 'b1', period: '2026-05', limit_minor: '400000', spent_minor: '320000', ratio: '8/10' };
    useLedgerStore.getState().applyRealtime(evt);
    expect(useLedgerStore.getState().budgetAlerts.get('b1')).toEqual(evt);
  });

  it('ingest_progress: ingest 에 batch_id 키로 병합', () => {
    useLedgerStore.getState().applyRealtime({ type: 'ingest_progress', batch_id: 'x', state: 'parsing' });
    expect(useLedgerStore.getState().ingest.get('x').state).toBe('parsing');
  });

  it('알 수 없는 프레임은 store 를 깨지 않는다', () => {
    const before = useLedgerStore.getState().balances.size;
    useLedgerStore.getState().applyRealtime({ type: 'nonsense', foo: 1 });
    expect(useLedgerStore.getState().balances.size).toBe(before);
  });

  it('clearFlash: 하이라이트 키 제거', () => {
    useLedgerStore.getState().applyRealtime({
      type: 'balance_changed',
      row: { account_id: 'z', currency: 'KRW', balance_minor: '1' },
    });
    useLedgerStore.getState().clearFlash('z:KRW');
    expect(useLedgerStore.getState().flashKeys.has('z:KRW')).toBe(false);
  });
});
