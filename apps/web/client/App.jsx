// 앱 루트. 셸(Topbar·사이드바·상세)은 LedgerPage 가 AppShell 로 구성한다 —
// 여기서 별도 헤더를 두지 않는다(중복 헤더 + 내부-스크롤 모델 붕괴 방지, M8).

import LedgerPage from './pages/LedgerPage.jsx';

export default function App() {
  return <LedgerPage />;
}
