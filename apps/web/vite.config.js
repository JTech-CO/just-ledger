import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath } from 'node:url';

// statement-wasm 은 wasm-pack --target web 산출물(modules/statement-wasm/pkg).
// gitignore 라 빌드 전 `wasm-pack build` 가 선행돼야 한다 (Makefile build-web / CI).
const wasmPkg = fileURLToPath(new URL('../../modules/statement-wasm/pkg', import.meta.url));

const demoDir = fileURLToPath(new URL('./client/lib/demo', import.meta.url));

// `--mode demo` (GitHub Pages UI 데모) 에서만 갈아끼우는 모듈들.
// 프로덕션 코드에는 데모 분기를 두지 않는다 — 여기서 별칭으로만 교체한다.
//   · lib/api.js          → 인메모리 목 API (서버 없음)
//   · useLedgerSocket.js  → 접속 시도 없는 대체 훅
//   · App.jsx             → 고지 배너를 두른 데모 셸
//   · IngestPanel.jsx     → 업로더 대신 안내 (공개 데모에 실제 명세서를 올리지 않게)
// find 는 **지정자 전체**에 앵커한다 — 부분 매치면 매치된 조각만 바뀌어
// './App.jsx' 가 './<절대경로>' 처럼 앞의 점이 남는다.
const DEMO_ALIASES = [
  { find: /^.*\/lib\/api\.js$/, replacement: demoDir + '/mockApi.js' },
  { find: /^.*\/hooks\/useLedgerSocket\.js$/, replacement: demoDir + '/mockSocket.js' },
  { find: /^.*\/App\.jsx$/, replacement: demoDir + '/DemoApp.jsx' },
  { find: /^.*\/components\/ledger\/IngestPanel\.jsx$/, replacement: demoDir + '/DemoIngestPanel.jsx' },
];

// 클라이언트 루트는 client/. 빌드 산출물은 apps/web/dist (gitignore).
export default defineConfig(({ mode }) => ({
  root: 'client',
  // Pages 프로젝트 사이트는 /<repo>/ 하위에 놓인다.
  base: mode === 'demo' ? '/just-ledger/' : '/',
  plugins: [react()],
  resolve: {
    alias: [
      { find: 'statement-wasm', replacement: wasmPkg },
      ...(mode === 'demo' ? DEMO_ALIASES : []),
    ],
  },
  // .wasm 을 자산으로 (statement_wasm_bg.wasm?url)
  assetsInclude: ['**/*.wasm'],
  build: {
    outDir: '../dist',
    emptyOutDir: true,
  },
  server: {
    port: 5173,
    proxy: {
      '/api': 'http://localhost:3000',
      '/health': 'http://localhost:3000',
    },
  },
  test: {
    // 기본 node (API 테스트). UI 테스트 파일은 @vitest-environment 주석으로 happy-dom 지정.
    environment: 'node',
    environmentOptions: {
      // UI 통합 테스트가 로컬 임시 서버(다른 포트)로 실제 fetch 를 보낸다 — 테스트 한정 해제
      happyDOM: { settings: { fetch: { disableSameOriginPolicy: true } } },
    },
    root: '.',
    fileParallelism: false,
    testTimeout: 30000,
    hookTimeout: 60000,
    // happy-dom 뷰포트·ResizeObserver stub (가상 스크롤 테스트용). node 환경엔 무영향.
    setupFiles: ['./tests/setup.js'],
  },
}));
