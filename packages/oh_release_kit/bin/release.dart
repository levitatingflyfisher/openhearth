import 'dart:io';

import 'package:oh_release_kit/oh_release_kit.dart';

Future<void> main(List<String> args) async {
  exitCode = await runRelease(args);
}
