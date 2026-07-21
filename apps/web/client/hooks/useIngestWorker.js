// 인제스트 Web Worker 훅 — 파싱·암호화를 워커에 위임한다 (메인 스레드 파싱 금지).
// 워커는 마운트 시 1회 생성되어 기동 예열을 끝내 둔다.

import { useEffect, useRef, useCallback } from 'react';

export function useIngestWorker() {
  const workerRef = useRef(null);
  const nextId = useRef(0);
  const pending = useRef(new Map());

  useEffect(() => {
    // 테스트 DOM(happy-dom)에는 Worker 가 없다 — 패널 렌더 자체는 가능해야 하므로
    // 생성 실패를 삼키고, 실제 호출 시점에 명확한 오류를 낸다.
    const pendingMap = pending.current; // cleanup 시점 ref 변동 경고 회피
    let worker = null;
    try {
      worker = new Worker(new URL('../workers/ingest.worker.js', import.meta.url), {
        type: 'module',
      });
      worker.onmessage = (e) => {
        const { id, ok, error, ...rest } = e.data;
        const p = pending.current.get(id);
        if (!p) return;
        pending.current.delete(id);
        if (ok) p.resolve(rest);
        else p.reject(new Error(error));
      };
      workerRef.current = worker;
    } catch {
      workerRef.current = null;
    }
    return () => {
      worker?.terminate();
      pendingMap.clear();
    };
  }, []);

  const call = useCallback((message, transfer = []) => {
    return new Promise((resolve, reject) => {
      if (!workerRef.current) {
        reject(new Error('이 환경에서는 Web Worker 를 사용할 수 없습니다'));
        return;
      }
      const id = nextId.current++;
      pending.current.set(id, { resolve, reject });
      workerRef.current.postMessage({ id, ...message }, transfer);
    });
  }, []);

  /** 파일 바이트 → 정규화 레코드 배열 */
  const parse = useCallback(
    async (bytes, passphrase) => {
      const { records } = await call({ type: 'parse', bytes, passphrase });
      return records;
    },
    [call],
  );

  /** 레코드 배열 → 업로드 봉투 (암호화 포함) */
  const buildPayload = useCallback(
    async (records, passphrase, accountId, filename, bytes) => {
      const { payload } = await call({
        type: 'payload',
        recordsJson: JSON.stringify(records),
        passphrase,
        accountId,
        filename,
        bytes,
      });
      return payload;
    },
    [call],
  );

  return { parse, buildPayload };
}
