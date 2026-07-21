// money.js 단위 테스트 — 정규화·포맷·합산이 문자열/BigInt 만으로 정확한지 (INV-4).

import { describe, it, expect } from 'vitest';
import {
  normalizeAmountInput, formatMinor, addMinor, compareMinor,
  isMoneyMinor, isPositiveMinor, sumByDirection,
} from '../client/lib/money.js';

describe('normalizeAmountInput (§2.2 입력 정규화)', () => {
  it('천단위 구분자·통화기호·공백 제거', () => {
    expect(normalizeAmountInput('12,345')).toBe('12345');
    expect(normalizeAmountInput('₩ 1,000,000')).toBe('1000000');
    expect(normalizeAmountInput(' 42000원 ')).toBe('42000');
  });
  it('전각 숫자(IME) → ASCII', () => {
    expect(normalizeAmountInput('１２３４')).toBe('1234');
    expect(normalizeAmountInput('１,０００')).toBe('1000');
  });
  it('선행 0 정규화', () => {
    expect(normalizeAmountInput('007')).toBe('7');
  });
  it('소수점·음수·비숫자·빈값 거절', () => {
    expect(normalizeAmountInput('12.5')).toBeNull();
    expect(normalizeAmountInput('-100')).toBeNull();
    expect(normalizeAmountInput('abc')).toBeNull();
    expect(normalizeAmountInput('')).toBeNull();
    expect(normalizeAmountInput('0')).toBeNull();   // entry 는 양수만 (INV-2)
  });
  it('18자리 최대 통과, 19자리 거절 (i64 안전 상한)', () => {
    expect(normalizeAmountInput('999999999999999999')).toBe('999999999999999999');
    expect(normalizeAmountInput('9999999999999999999')).toBeNull();
  });
});

describe('formatMinor (표시용 문자열 연산)', () => {
  it('천단위 구분자', () => {
    expect(formatMinor('0')).toBe('0');
    expect(formatMinor('100')).toBe('100');
    expect(formatMinor('1000')).toBe('1,000');
    expect(formatMinor('1234567')).toBe('1,234,567');
    expect(formatMinor('-1234567')).toBe('-1,234,567');
    expect(formatMinor('999999999999999999')).toBe('999,999,999,999,999,999');
  });
});

describe('addMinor / compareMinor (BigInt 정확 산술)', () => {
  it('Number 정밀도 한계를 넘는 합산이 정확하다', () => {
    // Number 였다면 900719925474099299 + 1 은 정밀도 손실로 틀렸을 값
    expect(addMinor('900719925474099299', '1')).toBe('900719925474099300');
    expect(addMinor('999999999999999999', '-999999999999999999')).toBe('0');
  });
  it('비교', () => {
    expect(compareMinor('2', '10')).toBe(-1);      // 문자열 사전순이었다면 틀렸을 케이스
    expect(compareMinor('-1', '0')).toBe(-1);
    expect(compareMinor('5', '5')).toBe(0);
  });
  it('유효성 가드', () => {
    expect(isMoneyMinor('007')).toBe(false);
    expect(isMoneyMinor('-0')).toBe(false);
    expect(isPositiveMinor('0')).toBe(false);
    expect(() => addMinor('1.5')).toThrow();
  });
});

describe('sumByDirection (원장 표 합계)', () => {
  it('방향별 BigInt 합', () => {
    const s = sumByDirection([
      { direction: 'debit', amount_minor: '900719925474099299' },
      { direction: 'debit', amount_minor: '1' },
      { direction: 'credit', amount_minor: '900719925474099300' },
    ]);
    expect(s.debit).toBe('900719925474099300');
    expect(s.credit).toBe('900719925474099300');
  });
});
