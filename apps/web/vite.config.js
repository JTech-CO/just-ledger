import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath } from 'node:url';

// statement-wasm 은 wasm-pack --target web 산출물(modules/statement-wasm/pkg).
// gitignore 라 빌드 전 `wasm-pack build` 가 선행돼야 한다 (Makefile build-web / CI).
const wasmPkg = fileURLToPath(new URL('../../modules/statement-wasm/pkg', import.meta.url));

const demoDir = fileURLToPath(new URL('./client/lib/demo', import.meta.url));
const localDir = fileURLToPath(new URL('./client/lib/local', import.meta.url));

// 프로덕션 코드에는 모드 분기를 두지 않는다 — 여기서 별칭으로만 교체한다.
// find 는 **지정자 전체**에 앵커한다 — 부분 매치면 매치된 조각만 바뀌어
// './App.jsx' 가 './<절대경로>' 처럼 앞의 점이 남는다.
//
// `--mode demo` (GitHub Pages 체험 데모): 인메모리 목, 새로고침 시 초기화.
const DEMO_ALIASES = [
  { find: /^.*\/lib\/api\.js$/, replacement: demoDir + '/mockApi.js' },
  { find: /^.*\/hooks\/useLedgerSocket\.js$/, replacement: demoDir + '/mockSocket.js' },
  { find: /^.*\/App\.jsx$/, replacement: demoDir + '/DemoApp.jsx' },
  { find: /^.*\/components\/ledger\/IngestPanel\.jsx$/, replacement: demoDir + '/DemoIngestPanel.jsx' },
];

// `--mode app` (설치형 PWA, 오프라인 실사용): IndexedDB 영속, 서버 없음.
const APP_ALIASES = [
  { find: /^.*\/lib\/api\.js$/, replacement: localDir + '/localApi.js' },
  { find: /^.*\/hooks\/useLedgerSocket\.js$/, replacement: demoDir + '/mockSocket.js' },
  { find: /^.*\/App\.jsx$/, replacement: localDir + '/LocalApp.jsx' },
  { find: /^.*\/components\/ledger\/IngestPanel\.jsx$/, replacement: localDir + '/LocalIngestPanel.jsx' },
];

// app 모드에서만 PWA 매니페스트·아이콘·테마색을 index.html 에 주입한다.
// href 는 상대경로 — 문서 URL(/just-ledger/app/)에 대해 해석되어 base 에 무관하다.
const pwaInject = {
  name: 'inject-pwa-app',
  transformIndexHtml() {
    return [
      { tag: 'link', attrs: { rel: 'manifest', href: 'manifest.webmanifest' }, injectTo: 'head' },
      { tag: 'link', attrs: { rel: 'icon', type: 'image/svg+xml', href: 'icon.svg' }, injectTo: 'head' },
      { tag: 'link', attrs: { rel: 'apple-touch-icon', href: 'icon.svg' }, injectTo: 'head' },
      { tag: 'meta', attrs: { name: 'theme-color', content: '#14506B' }, injectTo: 'head' },
      { tag: 'meta', attrs: { name: 'mobile-web-app-capable', content: 'yes' }, injectTo: 'head' },
    ];
  },
};

// 클라이언트 루트는 client/. 빌드 산출물은 apps/web/dist (gitignore).
// Pages 프로젝트 사이트: 데모는 /just-ledger/ 루트, 앱은 /just-ledger/app/ 하위.
export default defineConfig(({ mode }) => ({
  root: 'client',
  base: mode === 'demo' ? '/just-ledger/' : mode === 'app' ? '/just-ledger/app/' : '/',
  plugins: [react(), ...(mode === 'app' ? [pwaInject] : [])],
  resolve: {
    alias: [
      { find: 'statement-wasm', replacement: wasmPkg },
      ...(mode === 'demo' ? DEMO_ALIASES : []),
      ...(mode === 'app' ? APP_ALIASES : []),
    ],
  },
  // .wasm 을 자산으로 (statement_wasm_bg.wasm?url)
  assetsInclude: ['**/*.wasm'],
  build: {
    // 앱(PWA)은 데모 사이트 하위 /app/ 에 놓는다. Pages 배포는 build:demo(루트)를
    // 먼저 돌려 dist 를 비운 뒤 build:app 이 dist/app 을 채운다.
    outDir: mode === 'app' ? '../dist/app' : '../dist',
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
