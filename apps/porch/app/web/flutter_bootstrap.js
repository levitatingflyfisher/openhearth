{{flutter_js}}
{{flutter_build_config}}
// Flutter's default bootstrap, plus a config that keeps every engine fetch on
// this origin. canvasKitBaseUrl: the copy `flutter build web` always puts in
// canvaskit/ (otherwise Google's CDN unless built with --no-web-resources-cdn).
// fontFallbackBaseUrl: where the engine fetches a fallback font when text has
// a glyph the app's bundled fonts lack (ř, box drawing, symbols, CJK, emoji).
// It is root-relative on purpose: the site that serves porch mirrors
// Google's fallback fonts under /fonts/flutter-fallback/. Same origin, only
// fetched on demand. The engine's eager Roboto request 404s there by design.
// Guarded by conformance C13 and the deploy script.
// porch keeps its keys in browser storage, which is per origin, so its web
// build must be served from an origin of its own, shared with no other app.
_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}}
  },
  config: {
    canvasKitBaseUrl: "canvaskit/",
    fontFallbackBaseUrl: "/fonts/flutter-fallback/"
  }
});
