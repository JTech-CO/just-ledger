// M9 DoD 5 — 전체 스택 스모크의 HTTP 검증부.
// smoke.sh 가 스택을 기동한 뒤 호스트에서 실행한다(포트 매핑 3000/7070/4000).
//   1) 네 서비스 중 HTTP 헬스가 있는 셋(web·prolog·realtime) 레디니스 대기
//   2) web 원장 E2E: 계정 2개 → posted txn(균형) → 재조회·잔액 부호·금액 문자열 왕복
// 금액은 전 경로 문자열이어야 한다(INV-4). 실패 1건이라도 있으면 종료코드 1.

const WEB = process.env.SMOKE_WEB || 'http://localhost:3000';
const PROLOG = process.env.SMOKE_PROLOG || 'http://localhost:7070';
const REALTIME = process.env.SMOKE_REALTIME || 'http://localhost:4000';

let fails = 0;
const ok = (m) => console.log('  PASS  ' + m);
const bad = (m) => { console.log('  FAIL  ' + m); fails += 1; };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function waitHealth(name, url, tries = 45) {
  let last = '연결 실패';
  for (let i = 0; i < tries; i += 1) {
    try {
      const r = await fetch(url);
      if (r.status === 200) { ok(`${name} /health 200`); return true; }
      last = String(r.status);
    } catch { last = '연결 실패'; }
    await sleep(2000);
  }
  bad(`${name} /health 미준비 (마지막=${last})`);
  return false;
}

async function api(method, path, body) {
  const r = await fetch(WEB + path, {
    method,
    headers: { 'content-type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await r.text();
  let data;
  try { data = JSON.parse(text); } catch { data = text; }
  return { status: r.status, data };
}

async function main() {
  console.log('── 헬스 프로브 (web·prolog·realtime) ──');
  const hWeb = await waitHealth('web', WEB + '/health');
  await waitHealth('prolog', PROLOG + '/health');
  await waitHealth('realtime', REALTIME + '/health');

  if (!hWeb) {
    console.log('\nSMOKE E2E: web 미준비로 중단');
    process.exit(1);
  }

  console.log('── web 원장 E2E (계정 → txn → 잔액) ──');
  const asset = await api('POST', '/api/accounts',
    { code: 'CASH', name: '현금', type: 'asset', currency: 'KRW' });
  asset.status === 201 ? ok('계정 asset(CASH) 생성 201')
    : bad(`계정 asset ${asset.status} ${JSON.stringify(asset.data)}`);

  const expense = await api('POST', '/api/accounts',
    { code: 'FOOD', name: '식비', type: 'expense', currency: 'KRW' });
  expense.status === 201 ? ok('계정 expense(FOOD) 생성 201')
    : bad(`계정 expense ${expense.status} ${JSON.stringify(expense.data)}`);

  const assetId = asset.data?.id;
  const expenseId = expense.data?.id;
  if (!assetId || !expenseId) {
    console.log('\nSMOKE E2E: 계정 생성 실패로 중단');
    process.exit(1);
  }

  const AMT = '150000';
  const txn = await api('POST', '/api/txns', {
    occurred_on: '2026-07-15',
    memo: '스모크',
    status: 'posted',
    entries: [
      { account_id: expenseId, direction: 'debit', amount_minor: AMT, currency: 'KRW' },
      { account_id: assetId, direction: 'credit', amount_minor: AMT, currency: 'KRW' },
    ],
  });
  txn.status === 201 ? ok('posted txn(균형) 생성 201')
    : bad(`txn ${txn.status} ${JSON.stringify(txn.data)}`);
  const txnId = txn.data?.id;

  // 금액 문자열 왕복 무손실 (INV-4 — API 경계 문자열)
  if (txnId) {
    const got = await api('GET', `/api/txns/${txnId}`);
    const entries = Array.isArray(got.data?.entries) ? got.data.entries : [];
    const strOk = entries.length === 2
      && entries.every((x) => typeof x.amount_minor === 'string' && x.amount_minor === AMT);
    strOk ? ok('txn 금액 문자열 왕복 무손실')
      : bad(`txn 금액 왕복 ${JSON.stringify(entries)}`);
  } else {
    bad('txn id 없음 — 재조회 불가');
  }

  // 잔액 부호 (복식부기: 비용 차변 +, 자산 대변 −), 문자열
  const bal = await api('GET', '/api/balances');
  const rows = Array.isArray(bal.data) ? bal.data : [];
  const byAcc = Object.fromEntries(rows.map((b) => [b.account_id, b]));
  const eb = byAcc[expenseId];
  const ab = byAcc[assetId];
  (eb && typeof eb.balance_minor === 'string' && eb.balance_minor === AMT)
    ? ok(`비용 잔액 +${AMT} (문자열)`)
    : bad(`비용 잔액 ${JSON.stringify(eb)}`);
  (ab && typeof ab.balance_minor === 'string' && ab.balance_minor === `-${AMT}`)
    ? ok(`자산 잔액 -${AMT} (문자열)`)
    : bad(`자산 잔액 ${JSON.stringify(ab)}`);

  console.log(fails === 0 ? '\nSMOKE E2E: 전부 통과' : `\nSMOKE E2E: 실패 ${fails}건`);
  process.exit(fails === 0 ? 0 : 1);
}

main().catch((err) => {
  console.log('SMOKE E2E: 예외 — ' + (err?.stack || err));
  process.exit(1);
});
