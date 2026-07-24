// lib/ledgerCore.js — 데모·로컬 앱이 공유하는 클라이언트측 원장 규칙.
// 서버(PostgreSQL 트리거·COBOL)가 정본이지만, 오프라인 모드가 같은 규칙을 재현하므로
// 그 재현이 정확한지(복식부기·금액 규율·부호) 여기서 못 박는다. 금액은 문자열/BigInt.

import { describe, it, expect } from 'vitest';
import {
  LedgerError,
  isPositiveMinor,
  validateAccountBody,
  validateTxnBody,
  computeBalances,
  periodTotals,
} from '../client/lib/ledgerCore.js';

const ACCOUNTS = [
  { id: 'a-asset', code: '1000', name: '현금', type: 'asset', currency: 'KRW' },
  { id: 'a-exp', code: '5000', name: '식비', type: 'expense', currency: 'KRW' },
];

const entry = (account_id, direction, amount_minor, currency = 'KRW') => ({
  account_id,
  direction,
  amount_minor,
  currency,
});

const balanced = (amt = '150000') => ({
  occurred_on: '2026-07-15',
  memo: '점심',
  status: 'posted',
  entries: [entry('a-exp', 'debit', amt), entry('a-asset', 'credit', amt)],
});

describe('금액 규율 (INV-4)', () => {
  it('양의 최소단위 정수 문자열만 통과한다', () => {
    expect(isPositiveMinor('1')).toBe(true);
    expect(isPositiveMinor('999999999999999999')).toBe(true); // 18자리
    expect(isPositiveMinor('0')).toBe(false);
    expect(isPositiveMinor('-5')).toBe(false);
    expect(isPositiveMinor('1.5')).toBe(false);
    expect(isPositiveMinor(150000)).toBe(false); // 숫자 타입 거부(문자열만)
    expect(isPositiveMinor('1000000000000000000')).toBe(false); // 19자리 초과
  });
});

describe('복식부기 검증 (INV-1)', () => {
  it('차변합=대변합 균형 거래를 통과시킨다', () => {
    const norm = validateTxnBody(ACCOUNTS, balanced());
    expect(norm.entries).toHaveLength(2);
    expect(norm.status).toBe('posted');
  });

  it('대차 불일치는 422 로 거절한다', () => {
    const bad = balanced();
    bad.entries[1].amount_minor = '140000'; // 대변만 줄임
    expect(() => validateTxnBody(ACCOUNTS, bad)).toThrow(LedgerError);
    try {
      validateTxnBody(ACCOUNTS, bad);
    } catch (e) {
      expect(e.status).toBe(422);
    }
  });

  it('분개 1줄은 400 (복식부기 최소 2줄)', () => {
    const one = { occurred_on: '2026-07-15', entries: [entry('a-exp', 'debit', '1000')] };
    expect(() => validateTxnBody(ACCOUNTS, one)).toThrow(/2줄 이상/);
  });

  it('음수·소수 금액은 400 (부호는 direction 이 담당)', () => {
    const bad = balanced();
    bad.entries[0].amount_minor = '-150000';
    expect(() => validateTxnBody(ACCOUNTS, bad)).toThrow(/최소단위 양의 정수/);
  });

  it('알 수 없는 계정은 400', () => {
    const bad = balanced();
    bad.entries[0].account_id = 'a-nope';
    expect(() => validateTxnBody(ACCOUNTS, bad)).toThrow(/알 수 없는 계정/);
  });

  it('잘못된 날짜 형식은 400', () => {
    const bad = balanced();
    bad.occurred_on = '2026/07/15';
    expect(() => validateTxnBody(ACCOUNTS, bad)).toThrow(/YYYY-MM-DD/);
  });

  it('19자리 대차라도 부동소수점을 경유하지 않고 정확히 판정한다 (2^53 초과)', () => {
    const big = '90000000000000000'; // 17자리
    const tx = {
      occurred_on: '2026-07-15',
      entries: [entry('a-exp', 'debit', big), entry('a-asset', 'credit', big)],
    };
    expect(() => validateTxnBody(ACCOUNTS, tx)).not.toThrow();
    // 1 최소단위만 어긋나도 거절 (float 였다면 반올림으로 통과했을 값)
    const off = { ...tx, entries: [entry('a-exp', 'debit', big), entry('a-asset', 'credit', '90000000000000001')] };
    expect(() => validateTxnBody(ACCOUNTS, off)).toThrow(/대차/);
  });
});

describe('잔액 계산 (부호 규약)', () => {
  it('비용 차변 +, 자산 대변 − (문자열)', () => {
    const bal = computeBalances([balanced('150000')]);
    const byId = Object.fromEntries(bal.map((b) => [b.account_id, b.balance_minor]));
    expect(byId['a-exp']).toBe('150000');
    expect(byId['a-asset']).toBe('-150000');
    expect(typeof byId['a-exp']).toBe('string');
  });

  it('여러 거래를 BigInt 로 정확히 누적한다', () => {
    const bal = computeBalances([balanced('100'), balanced('250')]);
    const byId = Object.fromEntries(bal.map((b) => [b.account_id, b.balance_minor]));
    expect(byId['a-exp']).toBe('350');
    expect(byId['a-asset']).toBe('-350');
  });
});

describe('계정 검증', () => {
  it('필수 항목 누락은 400', () => {
    expect(() => validateAccountBody([], { code: 'X' })).toThrow(/필수 항목/);
  });
  it('통화는 대문자 3자리', () => {
    expect(() => validateAccountBody([], { code: 'X', name: 'x', type: 'asset', currency: 'krw' })).toThrow(/통화/);
  });
  it('중복 코드는 409', () => {
    try {
      validateAccountBody([{ code: '1000' }], { code: '1000', name: 'x', type: 'asset', currency: 'KRW' });
    } catch (e) {
      expect(e.status).toBe(409);
    }
  });
});

describe('기간 합계', () => {
  it('월별로 묶고 최신월을 먼저 준다', () => {
    const t1 = { ...balanced('100'), occurred_on: '2026-06-10' };
    const t2 = { ...balanced('200'), occurred_on: '2026-07-10' };
    const totals = periodTotals([t1, t2]);
    expect(totals[0].period).toBe('2026-07');
    expect(totals[0].debit_minor).toBe('200');
    expect(totals[1].period).toBe('2026-06');
  });
});
