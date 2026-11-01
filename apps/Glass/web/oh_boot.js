// Moved out of index.html so the Content-Security-Policy needs no inline-script rule.
/* keep local data across sessions (resist eviction on installed PWAs) */if(navigator.storage&&navigator.storage.persist){try{navigator.storage.persist();}catch(e){}}
(function(){
  // Self-heal stale PWA caches: when a new service worker takes over after a
  // redeploy, reload once so a returning visitor never sees a blank stale shell.
  if('serviceWorker' in navigator){var done=false;
    navigator.serviceWorker.addEventListener('controllerchange',function(){if(done)return;done=true;location.reload();});
    navigator.serviceWorker.getRegistrations().then(function(rs){rs.forEach(function(r){r.update();});}).catch(function(){});}
  // Remove the boot spinner once Flutter has painted (or after a hard timeout).
  var iv=setInterval(function(){
    if(document.querySelector('flt-glass-pane,flutter-view,flt-scene-host')){
      clearInterval(iv);var b=document.getElementById('oh-boot');
      if(b){b.style.opacity='0';setTimeout(function(){if(b.parentNode)b.parentNode.removeChild(b);},400);}
    }},150);
  setTimeout(function(){var b=document.getElementById('oh-boot');if(b&&b.parentNode)b.parentNode.removeChild(b);},25000);
})();
