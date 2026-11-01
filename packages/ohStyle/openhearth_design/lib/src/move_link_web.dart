import 'dart:js_interop';

@JS('window.open')
external JSAny? _windowOpen(String url, String target, String features);

/// Opens [uri] in a new browser tab, with no link back to this page.
void ohOpenMoveLink(Uri uri) {
  _windowOpen(uri.toString(), '_blank', 'noopener');
}
