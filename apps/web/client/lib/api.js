// API 클라이언트. 금액은 항상 문자열로 오간다 (JSON.parse 는 문자열을 그대로 보존 — INV-4).
// 클라이언트 측 ajv 검증(§2.2 3중 검증의 1단)은 폼 제출 경로에서 수행한다.

let base = '';

/** 테스트·개발에서 API 오리진 주입 (기본: 동일 오리진 + vite proxy) */
export function setApiBase(url) {
  base = url.replace(/\/$/, '');
}

export class ApiError extends Error {
  constructor(status, body) {
    super(body?.message ?? `HTTP ${status}`);
    this.status = status;
    this.body = body;
  }
}

/**
 * @param {string} path
 * @param {{method?: string, body?: unknown}} [opts]
 */
export async function api(path, opts = {}) {
  const res = await fetch(base + path, {
    method: opts.method ?? 'GET',
    headers: opts.body !== undefined ? { 'content-type': 'application/json' } : undefined,
    body: opts.body !== undefined ? JSON.stringify(opts.body) : undefined,
  });
  if (res.status === 204) return null;
  if (!res.ok) {
    const body = await res.json().catch(() => null);
    throw new ApiError(res.status, body);
  }
  // 2xx 인데 JSON 이 아니면 조용히 null 을 흘리지 않고 즉시 실패시킨다
  try {
    return await res.json();
  } catch {
    throw new ApiError(res.status, { message: '서버 응답이 JSON 이 아닙니다' });
  }
}

export const listAccounts = () => api('/api/accounts');
export const createAccount = (body) => api('/api/accounts', { method: 'POST', body });
export const listTxns = (qs = '') => api('/api/txns' + qs);
export const createTxn = (body) => api('/api/txns', { method: 'POST', body });
export const listBalances = () => api('/api/balances');
export const listPeriodTotals = (qs = '') => api('/api/balances/period' + qs);
