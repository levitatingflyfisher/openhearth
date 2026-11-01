// FFmpeg arg-injection guard (fleet finding, ffmpeg_runner_native.dart:228/:163).
//
// The native runner used to hand FFmpegKit.execute() ONE interpolated string
// with double-quoted paths — a '"' in a clip path (or a quote in the concat
// list) closed the quoted token and the remainder became injected ffmpeg argv.
// The fix is structural: pure List<String> builders (tested here) fed to
// FFmpegKit.executeWithArguments(), where each path is one discrete argv
// element and no shell-style tokenization ever happens. The drawtext overlay
// TEXT still goes through ffmpeg's own text expansion, so its special chars
// (\ : ' %) are escaped per the drawtext rules.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:one_second_a_day/platform/ffmpeg_args.dart';

void main() {
  group('escapeDrawtextText', () {
    test('leaves plain overlay text unchanged', () {
      expect(escapeDrawtextText('JUL 4 2026 : PARIS'), r'JUL 4 2026 \: PARIS');
      expect(escapeDrawtextText('JUL 4 2026'), 'JUL 4 2026');
    });

    test('escapes the drawtext-special characters \\ : \' %', () {
      expect(escapeDrawtextText(r'a\b'), r'a\\b');
      expect(escapeDrawtextText('10:30'), r'10\:30');
      expect(escapeDrawtextText("O'NEILL"), r"O\'NEILL");
      expect(escapeDrawtextText('100%'), r'100\%');
    });

    test('neutralizes a %{...} expansion sequence', () {
      // Un-escaped, drawtext would EXPAND this instead of drawing it.
      expect(escapeDrawtextText('%{pts}'), r'\%{pts}');
    });

    test('escapes the backslash before other escapes (no double-escaping)', () {
      expect(escapeDrawtextText(r'\:'), r'\\\:');
    });
  });

  group('concatListEntry', () {
    test('wraps a plain path in single quotes', () {
      expect(concatListEntry('/a/b.mp4'), "file '/a/b.mp4'");
    });

    test("a single quote in the path cannot terminate the quoted token", () {
      // ffconcat quoting: close the quote, emit \', reopen — the classic
      // '\'' idiom. Without it, the quote ends the token and the rest of
      // the path is parsed as further concat directives.
      expect(concatListEntry("/a/it's.mp4"), r"file '/a/it'\''s.mp4'");
    });
  });

  group('buildDateOverlayArgs', () {
    test('keeps the exact legacy argument order, paths as whole argv', () {
      final args = buildDateOverlayArgs(
        inputPath: '/in/my "clip".mp4',
        outputPath: '/out/o.mp4',
        fontPath: '/system/fonts/Roboto-Regular.ttf',
        textFilePath: '/tmp/overlay_text_1.txt',
        x: '30',
        y: 'h-th-30',
        fontSize: 36,
      );
      expect(args, [
        '-y',
        '-i',
        '/in/my "clip".mp4',
        '-vf',
        "drawtext=fontfile='/system/fonts/Roboto-Regular.ttf'"
            ":textfile='/tmp/overlay_text_1.txt'"
            ':x=30:y=h-th-30:fontsize=36'
            ':fontcolor=white:borderw=3:bordercolor=black',
        '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-r', '30', '-crf', '23',
        '-preset', 'fast',
        '-c:a', 'aac', '-ar', '44100', '-ac', '2', '-b:a', '128k',
        '/out/o.mp4',
      ]);
    });

    test('a quote-bearing input path stays exactly one argv element', () {
      final args = buildDateOverlayArgs(
        inputPath: 'a".mp4',
        outputPath: 'o.mp4',
        fontPath: 'f.ttf',
        textFilePath: 't.txt',
        x: '30',
        y: '30',
        fontSize: 36,
      );
      expect(args.where((a) => a == 'a".mp4').length, 1,
          reason: 'the path must never be wrapped into a quoted blob '
              'that a \'"\' could break out of');
    });
  });

  group('buildConcatArgs', () {
    test('keeps the exact legacy argument order, paths as whole argv', () {
      final args = buildConcatArgs(
        concatListPath: '/tmp/concat_list.txt',
        outputPath: '/out/monta ge".mp4',
      );
      expect(args, [
        '-y', '-f', 'concat', '-safe', '0', '-i', '/tmp/concat_list.txt',
        '-c:v', 'libx264', '-crf', '23', '-preset', 'fast',
        '-c:a', 'aac', '-b:a', '128k',
        '/out/monta ge".mp4',
      ]);
    });
  });
  group('quoted-string builders stay one argv element per path', () {
    const evil = 'a" -f lavfi -i evil".mp4';

    int count(List<String> args, String v) => args.where((a) => a == v).length;

    test('photo to video', () {
      final a = buildPhotoToVideoArgs(
          imagePath: evil, outputPath: 'o.mp4', duration: 1.0);
      expect(count(a, evil), 1);
      expect(a.sublist(0, 5), ['-y', '-loop', '1', '-i', evil]);
      expect(a[a.indexOf('-t') + 1], '1.0');
      expect(a.last, 'o.mp4');
    });

    test('extract segment', () {
      final a = buildExtractSegmentArgs(
          inputPath: evil, outputPath: 'o.mp4', startSeconds: 2.5, duration: 1.0);
      expect(count(a, evil), 1);
      expect(a.sublist(0, 5), ['-y', '-ss', '2.5', '-i', evil]);
      expect(a[a.indexOf('-vf') + 1], contains(r'min(1080/iw\,1920/ih)'));
      expect(a.last, 'o.mp4');
    });

    test('trim video', () {
      final a = buildTrimVideoArgs(
          inputPath: evil, outputPath: 'o.mp4', duration: 1.0);
      expect(count(a, evil), 1);
      expect(a.sublist(0, 5), ['-y', '-i', evil, '-t', '1.0']);
      expect(a.last, 'o.mp4');
    });

    test('thumbnail', () {
      final a = buildThumbnailArgs(videoPath: evil, outputPath: 'o.jpg');
      expect(count(a, evil), 1);
      expect(a, [
        '-y', '-i', evil, '-ss', '0.5', '-vframes', '1', '-q:v', '2',
        '-vf', 'scale=320:-1', 'o.jpg',
      ]);
    });

    test('normalize with audio has no silent input', () {
      final a = buildNormalizeArgs(
          inputPath: evil, outputPath: 'o.mp4', hasAudio: true);
      expect(count(a, evil), 1);
      expect(a.contains('lavfi'), isFalse);
      expect(a.last, 'o.mp4');
    });

    test('normalize without audio adds silence and the known length', () {
      final a = buildNormalizeArgs(
          inputPath: evil, outputPath: 'o.mp4', hasAudio: false, duration: 3.2);
      expect(count(a, evil), 1);
      expect(a.contains('lavfi'), isTrue);
      expect(a.sublist(a.length - 3), ['-t', '3.2', 'o.mp4']);
    });

    test('normalize without audio and unknown length has no -t', () {
      final a = buildNormalizeArgs(
          inputPath: 'i.mp4', outputPath: 'o.mp4', hasAudio: false);
      expect(a.contains('-t'), isFalse);
    });

    test('add silent audio', () {
      final a = buildAddSilentAudioArgs(
          inputPath: evil, outputPath: 'o.mp4', duration: 4.0);
      expect(count(a, evil), 1);
      expect(a.sublist(a.length - 3), ['-t', '4.0', 'o.mp4']);
      expect(buildAddSilentAudioArgs(inputPath: 'i', outputPath: 'o')
          .contains('-t'), isFalse);
    });

    test('background music', () {
      final a = buildBackgroundMusicArgs(
        videoPath: evil,
        musicPath: 'm"x.mp3',
        outputPath: 'o.mp4',
        musicVolume: 0.3,
        originalVolume: 0.5,
        duration: 6.0,
      );
      expect(count(a, evil), 1);
      expect(count(a, 'm"x.mp3'), 1);
      expect(a[a.indexOf('-filter_complex') + 1],
          startsWith('[0:a]volume=0.5[a0];[1:a]volume=0.3[a1];'));
      expect(a.sublist(a.length - 3), ['-t', '6.0', 'o.mp4']);
    });

    test('multi-track audio', () {
      final a = buildMultiTrackAudioArgs(
        videoPath: evil,
        audioPaths: ['one".mp3', 'two.mp3'],
        filterGraph: '[0:a]volume=0.3[orig];...[aout]',
        outputPath: 'o.mp4',
        duration: 9.0,
      );
      expect(count(a, evil), 1);
      expect(a.sublist(0, 7),
          ['-y', '-i', evil, '-i', 'one".mp3', '-i', 'two.mp3']);
      expect(a[a.indexOf('-filter_complex') + 1], contains('[aout]'));
      expect(a.sublist(a.length - 3), ['-t', '9.0', 'o.mp4']);
    });
  });

  test('the native runner never builds a quoted command string', () {
    final src = File('lib/platform/ffmpeg_runner_native.dart').readAsStringSync();
    expect(src.contains('FFmpegKit.execute('), isFalse,
        reason: 'use executeWithArguments with a List<String>');
    expect(RegExp(r'\b_run\(').hasMatch(src), isFalse);
  });
}
