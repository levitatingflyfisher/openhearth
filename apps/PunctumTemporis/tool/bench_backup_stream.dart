// Measures the chunked backup cipher on a real file, file to file, so peak
// memory and time can be read at sizes a phone library reaches.
//
//   dart compile exe tool/bench_backup_stream.dart -o <out>
//   <out> encrypt <plain> <sealed>
//   <out> decrypt <sealed> <plain>
//
// The key is a fixed test key through the same HKDF parameters the app
// uses; this tool never sees recovery words. Not shipped: tool/ is not in
// the app bundle.
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:one_second_a_day/services/backup_stream_cipher.dart';

Future<Uint8List> _benchKey(Uint8List salt) async {
  final key = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
    secretKey: SecretKey([...List<int>.filled(32, 0x42), ...salt]),
    nonce: const <int>[],
    info: 'openhearth.punctum.backupstream.v1'.codeUnits,
  );
  return Uint8List.fromList(await key.extractBytes());
}

Future<void> main(List<String> args) async {
  if (args.length != 3 || !{'encrypt', 'decrypt'}.contains(args[0])) {
    stderr.writeln('usage: bench encrypt|decrypt <in> <out>');
    exit(64);
  }
  final input = File(args[1]).openRead();
  final sink = File(args[2]).openWrite();
  final watch = Stopwatch()..start();
  // addStream waits on the file, so a slow disk slows the cipher instead
  // of piling chunks up in memory.
  await sink.addStream(args[0] == 'encrypt'
      ? BackupStreamCipher.encrypt(input, _benchKey)
      : BackupStreamCipher.decrypt(input, _benchKey));
  await sink.close();
  watch.stop();
  final size = await File(args[2]).length();
  final mbps = size / 1048576 / (watch.elapsedMilliseconds / 1000);
  // Peak resident memory of this whole process (the kernel's high-water
  // mark), the figure that would kill an app on a phone.
  final peakMiB = ProcessInfo.maxRss / 1048576;
  stdout.writeln('${args[0]} ${args[1]} -> ${args[2]}: $size bytes, '
      '${watch.elapsedMilliseconds} ms, ${mbps.toStringAsFixed(1)} MiB/s, '
      'peak RSS ${peakMiB.toStringAsFixed(1)} MiB');
}
