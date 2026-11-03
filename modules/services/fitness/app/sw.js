// Offline shell for Fitness. API calls pass straight through: the page keeps its
// own offline copy of the data and a queue of unsent changes.
'use strict';
var CACHE = 'fitness-shell-v3';
var SHELL = ['./', 'app.js', 'app.css', 'manifest.webmanifest', 'icon-192.png', 'icon-512.png'];
var SLOW_MS = 3000;

self.addEventListener('install', function(e){
  e.waitUntil(caches.open(CACHE).then(function(c){ return c.addAll(SHELL); }).then(function(){ return self.skipWaiting(); }));
});

self.addEventListener('activate', function(e){
  e.waitUntil(caches.keys().then(function(keys){
    return Promise.all(keys.filter(function(k){ return k !== CACHE; }).map(function(k){ return caches.delete(k); }));
  }).then(function(){ return self.clients.claim(); }));
});

function cached(req){
  return caches.match(req, {ignoreSearch:true}).then(function(hit){
    return hit || (req.mode === 'navigate' ? caches.match('./') : undefined);
  });
}

// Network first so updates arrive; fall back to the cached shell when the
// network fails or is slower than SLOW_MS (weak gym signal).
self.addEventListener('fetch', function(e){
  var req = e.request, url = new URL(req.url);
  if (req.method !== 'GET' || url.origin !== self.location.origin || url.pathname.indexOf('/api/') === 0) return;
  e.respondWith(new Promise(function(resolve){
    var done = false;
    function finish(r){ if (!done && r){ done = true; resolve(r); } }
    var timer = setTimeout(function(){ cached(req).then(finish); }, SLOW_MS);
    fetch(req).then(function(res){
      clearTimeout(timer);
      if (res.ok && res.type === 'basic'){
        var copy = res.clone();
        caches.open(CACHE).then(function(c){ return c.put(req, copy); });
      }
      if (!done){ done = true; resolve(res); }
    }, function(){
      clearTimeout(timer);
      cached(req).then(function(hit){ if (!done){ done = true; resolve(hit || Response.error()); } });
    });
  }));
});

self.addEventListener('notificationclick', function(e){
  e.notification.close();
  e.waitUntil(self.clients.matchAll({type: 'window', includeUncontrolled: true}).then(function(cs){
    for (var i = 0; i < cs.length; i++) if ('focus' in cs[i]) return cs[i].focus();
    return self.clients.openWindow('./');
  }));
});
