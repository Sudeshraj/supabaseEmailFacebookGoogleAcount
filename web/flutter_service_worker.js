'use strict';

const CACHE_NAME = 'offline-cache-v1';
const OFFLINE_URL = 'index.html';

// Cache all Flutter assets automatically
self.addEventListener('install', (event) => {
  self.skipWaiting();

  event.waitUntil(
    caches.open(CACHE_NAME).then((cache) => {
      return cache.addAll([
        '/',
        '/index.html',
        '/main.dart.js',
        '/flutter.js',
        '/flutter_bootstrap.js',
        '/manifest.json',
        '/assets/AssetManifest.json',
        '/assets/FontManifest.json',
        '/assets/NOTICES',
        // Cache entire assets folder
        ...ASSET_LIST
      ]);
    })
  );
});

// Intercept all requests
self.addEventListener('fetch', (event) => {
  event.respondWith(
    caches.match(event.request).then((cached) => {
      return cached || fetch(event.request).catch(() => caches.match('/index.html'));
    })
  );
});

// Build list of Flutter assets from service worker manifest
const ASSET_LIST = self.__flutter_manifest__ ? Object.keys(self.__flutter_manifest__) : [];
