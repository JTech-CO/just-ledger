// 명세서 파싱·암호화 Web Worker (백서 §2.2·§7: WASM 은 반드시 Web Worker 에서 —
// 메인 스레드 파싱 금지). 50MB 파싱이 UI 스레드를 막지 않게 한다 (M3 DoD 3 롱태스크 0).
//
// 기동 시 예열: V8 은 wasm 을 Liftoff(베이스라인)로 먼저 돌리고 백그라운드에서
// TurboFan 최적화한다 — 첫 대형 파싱은 미최적 코드로 수 배 느리다. 소형 CSV 를 1회
// 파싱해 티어업을 앞당긴다 (make bench-wasm 웜 게이트의 전제 조건).
//
// 메시지 프로토콜 (id 로 요청/응답 상관):
//   {id, type:'parse',   bytes:Uint8Array, passphrase} → {id, ok, records}|{id, ok:false, error}
//   {id, type:'payload', recordsJson, passphrase, accountId, filename, bytes}
//                                                     → {id, ok, payload}|{id, ok:false, error}

import init, { parse_statement, parse_statement_count, build_ingest_payload } from 'statement-wasm';
import wasmUrl from 'statement-wasm/statement_wasm_bg.wasm?url';

let ready = null;

async function ensureReady() {
  if (!ready) {
    ready = (async () => {
      await init({ module_or_path: wasmUrl });
      // 예열: 소형 합성 CSV 1회 파싱으로 티어업을 앞당긴다
      const warm =
        '﻿거래 일시,적요,거래 유형,거래 금액,거래 후 잔액,메모\n' +
        '2026-06-01 08:00:00,예열,체크카드,-1,0,\n';
      try {
        parse_statement_count(new TextEncoder().encode(warm), 'warmup');
      } catch {
        /* 예열 실패는 무해 — 실호출에서 다시 시도 */
      }
    })();
  }
  return ready;
}

self.onmessage = async (e) => {
  const { id, type } = e.data;
  try {
    await ensureReady();
    if (type === 'parse') {
      const json = parse_statement(e.data.bytes, e.data.passphrase);
      self.postMessage({ id, ok: true, records: JSON.parse(json).records });
    } else if (type === 'payload') {
      const payloadJson = build_ingest_payload(
        e.data.recordsJson,
        e.data.passphrase,
        e.data.accountId,
        e.data.filename,
        e.data.bytes,
      );
      self.postMessage({ id, ok: true, payload: JSON.parse(payloadJson) });
    } else {
      self.postMessage({ id, ok: false, error: `알 수 없는 type: ${type}` });
    }
  } catch (err) {
    // 오류 메시지에 명세서 내용을 싣지 않는다 (INV-6) — 메시지 문자열만 전달
    self.postMessage({ id, ok: false, error: String(err?.message ?? err) });
  }
};

// 기동 즉시 예열 시작 (첫 파일 드롭 전에 티어업을 끝내 둔다)
ensureReady();
