// Service worker de la app: permite instalarla y que abra aunque el internet esté lento o caído.
// Las páginas propias se piden primero a internet (así siempre llega la versión nueva) y, si no hay
// conexión, se usa la última copia guardada. Las librerías externas se sirven desde la copia y se
// actualizan por detrás. Los datos de la tienda (Supabase) nunca se guardan aquí.
const CACHE = "almacen-v1";
const SHELL = ["./", "index.html", "config.js", "pagina.js", "manifest.webmanifest", "icons/icono-192.png"];
const CDN = /^https:\/\/(cdn\.jsdelivr\.net|fonts\.googleapis\.com|fonts\.gstatic\.com)\//;

self.addEventListener("install", e => { e.waitUntil(caches.open(CACHE).then(c => c.addAll(SHELL)).catch(() => {})); self.skipWaiting(); });
self.addEventListener("activate", e => { e.waitUntil(caches.keys().then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k)))).then(() => self.clients.claim())); });

self.addEventListener("fetch", e => {
  const req = e.request; if (req.method !== "GET") return;
  const url = new URL(req.url);
  if (url.origin === location.origin){
    e.respondWith(fetch(req).then(res => { if (res.ok){ const copy = res.clone(); caches.open(CACHE).then(c => c.put(req, copy)); } return res; })
      .catch(() => caches.match(req, { ignoreSearch: req.mode === "navigate" }).then(r => r || caches.match("index.html"))));
    return;
  }
  if (CDN.test(req.url)){
    e.respondWith(caches.match(req).then(hit => {
      const net = fetch(req).then(res => { if (res.ok || res.type === "opaque"){ const copy = res.clone(); caches.open(CACHE).then(c => c.put(req, copy)); } return res; });
      return hit ? (net.catch(() => {}), hit) : net;
    }));
  }
});
