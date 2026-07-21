// 원장 스토어 (기술 백서 §4.1). 실시간 이벤트는 applyRealtime 단일 진입점으로만
// 병합한다 — 컴포넌트가 채널을 직접 구독하지 않는다.

import { create } from 'zustand';
import { listAccounts, listTxns, listBalances, createTxn, createAccount } from '../lib/api.js';

/** @typedef {import('../../types/contracts.gen.js')} _types */

export const useLedgerStore = create((set, get) => ({
  /** @type {Array<Object>} 조회 창의 txn 행 (M8 에서 가상 스크롤 윈도우로 확장) */
  rows: [],
  /** @type {Array<Object>} 계정 목록 */
  accounts: [],
  /** @type {Map<string, string>} `${account_id}:${currency}` → balance_minor 문자열 */
  balances: new Map(),
  totalCount: 0,
  selection: new Set(),
  isSettled: false,
  /** @type {string|null} */
  lastError: null,
  /** 초기/재조회 실패 여부 — 빈 원장과 구분해 재시도 UI 를 띄운다 */
  loadFailed: false,

  // ── 실시간 병합 단일 진입점 (M7 채널이 이 함수만 호출한다) ───────────────
  applyRealtime(evt) {
    if (evt.type === 'balance_changed') {
      set((s) => {
        const balances = new Map(s.balances);
        balances.set(`${evt.row.account_id}:${evt.row.currency}`, evt.row.balance_minor);
        return { balances };
      });
    } else if (evt.type === 'settlement_done') {
      set({ isSettled: true });
    } else if (evt.type === 'ingest_progress') {
      // M3: 인제스트 진행률 슬라이스에 병합
    }
  },

  // ── 조회 ────────────────────────────────────────────────────────────────
  // 실패를 삼키지 않는다: 빈 원장과 '불러오기 실패'는 반드시 구분돼야 한다
  // (셀프호스팅에서 서버/DB 재시작 중 접속은 일상 — 데이터 유실로 오인되면 안 됨).
  async loadAll() {
    try {
      const [accounts, rows, balanceRows] = await Promise.all([
        listAccounts(),
        listTxns('?limit=100'),
        listBalances(),
      ]);
      const balances = new Map(balanceRows.map((b) => [`${b.account_id}:${b.currency}`, b.balance_minor]));
      set({ accounts, rows, balances, totalCount: rows.length, lastError: null, loadFailed: false });
    } catch (e) {
      set({ lastError: `원장을 불러오지 못했습니다: ${e.message}`, loadFailed: true });
      throw e;
    }
  },

  // ── 쓰기 (낙관적 갱신은 M8 — M2 는 저장 후 재조회로 왕복 무손실을 검증) ───
  async addAccount(body) {
    try {
      await createAccount(body);
    } catch (e) {
      set({ lastError: e.message });
      throw e;
    }
    await get().loadAll();
  },

  async addTxn(body) {
    // 생성 실패와 재조회 실패를 구분한다 — 저장은 됐는데 '실패'로 보이면
    // 사용자가 재제출해 중복 거래가 생긴다.
    try {
      await createTxn(body);
    } catch (e) {
      set({ lastError: e.message });
      throw e;
    }
    try {
      await get().loadAll();
    } catch {
      set({ lastError: '거래는 저장되었으나 목록 갱신에 실패했습니다 — 새로고침 해주세요' });
    }
  },
}));
