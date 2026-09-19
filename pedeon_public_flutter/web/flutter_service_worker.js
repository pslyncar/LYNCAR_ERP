// Migração de builds antigos do Flutter Web que ainda estejam presos ao cache
// offline. O PedeOn usa atualização pelo servidor e não registra um novo PWA.
self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.map((key) => caches.delete(key)));
    await self.registration.unregister();
    await self.clients.claim();
    const clients = await self.clients.matchAll({
      type: 'window',
      includeUncontrolled: true,
    });
    for (const client of clients) await client.navigate(client.url);
  })());
});

self.addEventListener('fetch', (event) => {
  event.respondWith(fetch(event.request, {cache: 'no-store'}));
});
