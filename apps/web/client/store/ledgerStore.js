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
  /** @type {Set<string>} 마감된 기간(YYYY-MM) 집합. 한 기간 마감이 다른 기간을
   *  잠그지 않는다 — settlement_done 계약의 period 로 이 집합만 갱신한다. */
  settledPeriods: new Set(),
  /** @type {string|null} */
  lastError: null,
  /** 초기/재조회 실패 여부 — 빈 원장과 구분해 재시도 UI 를 띄운다 */
  loadFailed: false,
  /** @type {Set<string>} 방금 변한 잔액 키 — 120ms 하이라이트 1회 (§4.3) */
  flashKeys: new Set(),
  /** @type {Map<string, Object>} budget_id → 최근 budget_alert 프레임 (M7) */
  budgetAlerts: new Map(),
  /** @type {Map<string, Object>} batch_id → ingest_progress 상태 (M3/M7) */
  ingest: new Map(),
  /** 실시간 채널 연결 상태 — 끊김을 UI 에 표면화 (조용한 정지 금지) */
  socketConnected: false,

  // ── 실시간 병합 단일 진입점 (M7 채널이 이 함수만 호출한다) ───────────────
  // 프레임은 contracts/notify-event.schema.json — evt.type 으로 분기한다.
  applyRealtime(evt) {
    switch (evt.type) {
      case 'balance_changed': {
        set((s) => {
          const key = `${evt.row.account_id}:${evt.row.currency}`;
          const balances = new Map(s.balances);
          balances.set(key, evt.row.balance_minor);
          const flashKeys = new Set(s.flashKeys);
          flashKeys.add(key);
          return { balances, flashKeys };
        });
        break;
      }
      case 'sync': {
        // 재접속 보정(M7 DoD 3): 스냅샷으로 잔액 전체를 교체(수렴)
        set(() => ({
          balances: new Map(evt.balances.map((b) => [`${b.account_id}:${b.currency}`, b.balance_minor])),
        }));
        break;
      }
      case 'settlement_done':
        // 계약의 period.end 가 속한 달만 마감 처리한다 — 전역 잠금이 아니다.
        // (한 기간 마감이 열린 다른 기간의 수기 입력·편집까지 막으면 안 된다.)
        set((s) => {
          const settledPeriods = new Set(s.settledPeriods);
          const month = evt.period?.end?.slice(0, 7);
          if (month) settledPeriods.add(month);
          return { settledPeriods };
        });
        break;
      case 'budget_alert':
        set((s) => {
          const budgetAlerts = new Map(s.budgetAlerts);
          budgetAlerts.set(evt.budget_id, evt);
          return { budgetAlerts };
        });
        break;
      case 'ingest_progress':
        set((s) => {
          const ingest = new Map(s.ingest);
          ingest.set(evt.batch_id, evt);
          return { ingest };
        });
        break;
      default:
        // 알 수 없는 프레임은 무시 — 계약 밖 이벤트가 store 를 깨지 않는다
        break;
    }
  },

  /** 하이라이트 종료 — 키 하나를 flash 집합에서 제거 (컴포넌트가 120ms 후 호출) */
  clearFlash(key) {
    set((s) => {
      if (!s.flashKeys.has(key)) return {};
      const flashKeys = new Set(s.flashKeys);
      flashKeys.delete(key);
      return { flashKeys };
    });
  },

  setSocketConnected(connected) {
    set({ socketConnected: connected });
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
