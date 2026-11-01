// The web shell's start-up script. It lives in its own file, not inline in
// index.html, because the page's Content-Security-Policy runs only scripts
// from this origin's files.
(function () {
  // Keep local data across sessions (resist eviction on installed PWAs).
  if (navigator.storage && navigator.storage.persist) {
    try { navigator.storage.persist(); } catch (e) {}
  }
  // Self-heal stale PWA caches: when a new service worker takes over after a
  // redeploy, reload once so a returning visitor never sees a blank stale shell.
  if ('serviceWorker' in navigator) {
    var done = false;
    navigator.serviceWorker.addEventListener('controllerchange', function () {
      if (done) return;
      done = true;
      location.reload();
    });
    navigator.serviceWorker.getRegistrations().then(function (rs) {
      rs.forEach(function (r) { r.update(); });
    }).catch(function () {});
  }
  // Remove the boot screen (#oh-boot) once Flutter has painted, or after a
  // hard timeout.
  var iv = setInterval(function () {
    if (document.querySelector('flt-glass-pane,flutter-view,flt-scene-host')) {
      clearInterval(iv);
      var b = document.getElementById('oh-boot');
      if (b) {
        b.style.opacity = '0';
        setTimeout(function () { if (b.parentNode) b.parentNode.removeChild(b); }, 400);
      }
    }
  }, 150);
  setTimeout(function () {
    var b = document.getElementById('oh-boot');
    if (b && b.parentNode) b.parentNode.removeChild(b);
  }, 25000);
})();
