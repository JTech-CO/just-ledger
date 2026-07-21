import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// 클라이언트 루트는 client/. 빌드 산출물은 apps/web/dist (gitignore).
export default defineConfig({
  root: 'client',
  plugins: [react()],
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
  },
});
