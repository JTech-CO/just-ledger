// 데모용 실시간 소켓 대체 — GitHub Pages UI 데모 전용.
// 실제 useLedgerSocket 은 Phoenix 채널(WebSocket)에 붙지만 데모에는 서버가 없다.
// 연결 시도를 하지 않고 "연결됨"으로만 표시한다 — 존재하지 않는 서버로 무한
// 재접속을 돌리면 콘솔이 오류로 뒤덮이고 UI 가 고장난 것처럼 보인다.
//
// 실시간 이벤트를 가짜로 흘려보내지는 않는다. 데모에서 잔액이 저절로 움직이면
// 사용자가 실제 데이터로 오인한다.

import { useEffect } from 'react';
import { useLedgerStore } from '../../store/ledgerStore.js';

/** 실제 훅과 시그니처만 맞춘 대체 구현 */
export function useLedgerSocket() {
  const setConnected = useLedgerStore((s) => s.setSocketConnected);
  useEffect(() => {
    setConnected(true);
    return () => setConnected(false);
  }, [setConnected]);
}
