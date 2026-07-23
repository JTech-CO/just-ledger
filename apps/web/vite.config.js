import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { fileURLToPath } from 'node:url';

// statement-wasm 은 wasm-pack --target web 산출물(modules/statement-wasm/pkg).
// gitignore 라 빌드 전 `wasm-pack build` 가 선행돼야 한다 (Makefile build-web / CI).
const wasmPkg = fileURLToPath(new URL('../../modules/statement-wasm/pkg', import.meta.url));

// 클라이언트 루트는 client/. 빌드 산출물은 apps/web/dist (gitignore).
export default defineConfig({
  root: 'client',
  plugins: [react()],
  resolve: {
    alias: { 'statement-wasm': wasmPkg },
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
});
