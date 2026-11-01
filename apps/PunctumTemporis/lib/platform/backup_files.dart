// Platform twin: streamed backup files on Android (dart:io, one chunk in
// memory at a time), in-memory on web (no file handles in the browser).
export 'backup_files_native.dart'
    if (dart.library.js_interop) 'backup_files_web.dart';
