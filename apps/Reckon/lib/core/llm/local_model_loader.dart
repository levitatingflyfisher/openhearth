import 'dart:io';

import 'local_model.dart';

/// The first bytes every MediaPipe `.task` bundle starts with: it is a ZIP
/// archive ("PK\x03\x04"). A raw LiteRT flatbuffer ("TFL3") renamed to
/// `.task` is the case that once died inside the runtime with "unable to
/// open zip archive".
const _zipMagic = [0x50, 0x4B, 0x03, 0x04];

/// Checks [file] and hands it to [runtime]. Fails closed: a missing file, an
/// empty file, a `.task` that is not a ZIP bundle, or any extension Reckon
/// does not know is refused before the runtime runs. A runtime failure is
/// wrapped in [LocalModelStartFailed].
Future<LocalModel> loadLocalModel(
  LocalModelRuntime runtime,
  File file, {
  required String modelType,
  required int maxTokens,
}) async {
  if (!file.existsSync()) throw LocalModelFileMissing(file.path);

  final path = file.path;
  if (!path.toLowerCase().endsWith('.task')) {
    throw LocalModelFileBroken(path, 'not a format Reckon knows');
  }
  final head = await _firstBytes(file, _zipMagic.length);
  if (head.length < _zipMagic.length) {
    throw LocalModelFileBroken(path, 'file is empty or too short');
  }
  for (var i = 0; i < _zipMagic.length; i++) {
    if (head[i] != _zipMagic[i]) {
      throw LocalModelFileBroken(path, '.task file is not a ZIP bundle');
    }
  }

  try {
    return await runtime.load(
      path: path,
      modelType: modelType,
      maxTokens: maxTokens,
    );
  } catch (e) {
    throw LocalModelStartFailed(e);
  }
}

Future<List<int>> _firstBytes(File file, int count) async {
  final raf = await file.open();
  try {
    return await raf.read(count);
  } finally {
    await raf.close();
  }
}
