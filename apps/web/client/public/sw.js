// 로컬 앱 서비스워커 — 오프라인 앱 셸. vite --mode app 에서만 등록된다(LocalApp).
// 자산 파일명이 해시되어 미리 알 수 없으므로 런타임 캐싱을 쓴다:
//   · 내비게이션: 네트워크 우선 → 실패 시 캐시된 시작 페이지(오프라인 진입).
//   · 동일 출처 GET 자산: 캐시 우선 → 없으면 네트워크 후 캐시에 채운다.
// 데이터(IndexedDB)는 이 워커와 무관하게 이미 영속된다.

const CACHE = 'jl-local-v1';

self.addEventListener('install', (e) => {
  self.skipWaiting();
  // 시작 페이지를 선캐시(오프라인 첫 진입 보장). './' 는 스코프 루트로 해석된다.
  e.waitUntil(
    caches.open(CACHE).then((c) => c.add(new Request('./', { cache: 'reload' })).catch(() => {})),
  );
});

self.addEventListener('activate', (e) => {
  e.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET') return;
  if (new URL(req.url).origin !== self.location.origin) return;

  if (req.mode === 'navigate') {
    e.respondWith(
      fetch(req)
        .then((res) => {
          const copy = res.clone();
          caches.open(CACHE).then((c) => c.put('./', copy)).catch(() => {});
          return res;
        })
        .catch(() => caches.match('./').then((r) => r || caches.match(req))),
    );
    return;
  }

  e.respondWith(
    caches.match(req).then(
      (hit) =>
        hit ||
        fetch(req).then((res) => {
          if (res.ok) {
            const copy = res.clone();
            caches.open(CACHE).then((c) => c.put(req, copy)).catch(() => {});
          }
          return res;
        }),
    ),
  );
});
