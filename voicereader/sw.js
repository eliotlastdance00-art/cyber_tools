// VoiceReader service worker — caches the app shell for offline use.
const CACHE = 'voicereader-v1';
const ASSETS = [
  './',
  'index.html',
  'app.html',
  'manifest.webmanifest',
  'assets/css/style.css',
  'assets/js/app.js',
  'assets/js/license.js',
  'assets/js/config.js',
  'assets/js/vendor/pdf.min.mjs',
  'assets/js/vendor/pdf.worker.min.mjs',
  'assets/img/icon.png',
  'assets/img/hero.png'
];
self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(CACHE).then((c) => c.addAll(ASSETS)).then(() => self.skipWaiting()));
});
self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== CACHE).map((k) => caches.delete(k)))).then(() => self.clients.claim())
  );
});
self.addEventListener('fetch', (event) => {
  const url = new URL(event.request.url);
  if (event.request.method !== 'GET' || url.origin !== location.origin) return;
  event.respondWith(
    caches.match(event.request).then((cached) => cached || fetch(event.request).then((res) => {
      const copy = res.clone();
      caches.open(CACHE).then((c) => c.put(event.request, copy));
      return res;
    }))
  );
});
