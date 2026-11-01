// FileStorage.writeString carries metadata.json, the app's only record of
// which clip belongs to which day. A plain write truncates the file first, so
// a kill or a full disk partway through leaves it damaged. The write must go
// to a temporary file in the same folder, reach the disk, and then rename
// over the target, so the target is always the whole old file or the whole
// new one.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_second_a_day/platform/file_storage_native.dart';

enum _Fault { none, tornWrite, failedRename }

/// A real file with a fault injected, recording the order of the steps.
class _FaultyFile implements File {
  _FaultyFile(this._real, this._fault, this._steps);
  final File _real;
  final _Fault _fault;
  final List<String> _steps;

  @override
  String get path => _real.path;
  @override
  Future<bool> exists() => _real.exists();
  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      _real.delete(recursive: recursive);

  @override
  Future<File> writeAsString(String contents,
      {FileMode mode = FileMode.write,
      Encoding encoding = utf8,
      bool flush = false}) async {
    _steps.add('write flush=$flush');
    if (_fault == _Fault.tornWrite) {
      // What a kill or a full disk leaves: the file is truncated and only
      // the front of the new content arrived.
      await _real.writeAsString(contents.substring(0, contents.length ~/ 2));
      throw FileSystemException('No space left on device', path);
    }
    return _real.writeAsString(contents,
        mode: mode, encoding: encoding, flush: flush);
  }

  @override
  Future<File> rename(String newPath) async {
    _steps.add('rename');
    if (_fault == _Fault.failedRename) {
      throw FileSystemException('rename failed', path);
    }
    return _real.rename(newPath);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

final class _FaultyOverrides extends IOOverrides {
  _FaultyOverrides(this.fault, this.steps);
  final _Fault fault;
  final List<String> steps;

  @override
  File createFile(String path) =>
      _FaultyFile(super.createFile(path), fault, steps);
}

void main() {
  late Directory tmp;
  late File target;
  const oldContent = '{"clips":{"2026-11-01":[]}}';
  const newContent = '{"clips":{"2026-11-01":[],"2026-11-02":[]}}';

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pt_atomic_');
    target = File('${tmp.path}/metadata.json');
    await target.writeAsString(oldContent);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  Future<void> writeWith(_Fault fault, [List<String>? steps]) =>
      IOOverrides.runWithIOOverrides(
        () => FileStorage.writeString(target.path, newContent),
        _FaultyOverrides(fault, steps ?? []),
      );

  List<String> folder() =>
      tmp.listSync().map((e) => e.path.split('/').last).toList();

  test('replaces the file and leaves nothing else in the folder', () async {
    await FileStorage.writeString(target.path, newContent);

    expect(target.readAsStringSync(), newContent);
    expect(folder(), ['metadata.json']);
  });

  test('creates a file that was not there', () async {
    await target.delete();

    await FileStorage.writeString(target.path, newContent);

    expect(target.readAsStringSync(), newContent);
  });

  test('a partial write leaves the old file whole', () async {
    await expectLater(writeWith(_Fault.tornWrite), throwsA(isA<FileSystemException>()));

    expect(target.readAsStringSync(), oldContent);
  });

  test('a failed rename leaves the old file whole', () async {
    await expectLater(
        writeWith(_Fault.failedRename), throwsA(isA<FileSystemException>()));

    expect(target.readAsStringSync(), oldContent);
  });

  test('a failed write cleans up its temporary file', () async {
    await expectLater(writeWith(_Fault.tornWrite), throwsA(isA<FileSystemException>()));

    expect(folder(), ['metadata.json']);
  });

  test('reaches the disk before the rename', () async {
    final steps = <String>[];

    await writeWith(_Fault.none, steps);

    expect(steps, ['write flush=true', 'rename']);
  });

  test('two overlapping writes each land whole', () async {
    final longer = 'x' * 200000;

    await Future.wait([
      FileStorage.writeString(target.path, longer),
      FileStorage.writeString(target.path, newContent),
    ]);

    expect(target.readAsStringSync(), anyOf(longer, newContent));
    expect(folder(), ['metadata.json']);
  });
}
