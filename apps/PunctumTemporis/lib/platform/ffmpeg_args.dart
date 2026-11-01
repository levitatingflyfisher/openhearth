/// Pure FFmpeg argv builders — no dart:io, no plugin imports, fully unit
/// tested (test/services/ffmpeg_args_test.dart).
///
/// Why these exist: the native runner used to interpolate paths and overlay
/// text into ONE command string with double-quoted values and hand it to
/// `FFmpegKit.execute(String)`, whose tokenizer re-parses the quoting — so a
/// `"` (or backslash) inside a clip path closed the quoted token and the
/// remainder became injected ffmpeg argv. Building a `List<String>` for
/// `FFmpegKit.executeWithArguments` removes that parsing step entirely: each
/// path is one discrete argv element and no shell-style quoting exists to
/// break out of. (Mirrors the `buildMultiTrackFilterGraph` "pure seam for
/// testability" pattern in ffmpeg_service.dart.)
library;

/// Escapes a literal text value for ffmpeg's drawtext filter.
///
/// drawtext applies its own text expansion to the value (whether it arrives
/// via `text=` or a `textfile=`): `\X` expands to `X`, `%{...}` expands to
/// clip metadata, `:` ends an option and `'` quotes when inline. Escaping
/// the four drawtext-special characters `\ : ' %` with a backslash makes any
/// user-supplied overlay text (date + location) render literally instead of
/// being interpreted.
String escapeDrawtextText(String text) {
  return text
      .replaceAll('\\', r'\\') // first, so later escapes aren't re-escaped
      .replaceAll(':', r'\:')
      .replaceAll("'", r"\'")
      .replaceAll('%', r'\%');
}

/// One line of an ffmpeg concat-demuxer list file for [path].
///
/// The path is single-quoted; an embedded `'` is emitted as the `'\''`
/// idiom (close the quote, escaped quote, reopen), so a quote inside a clip
/// path can never terminate the token and smuggle further concat directives
/// into the list.
String concatListEntry(String path) {
  return "file '${path.replaceAll("'", r"'\''")}'";
}

/// Argv for the date/location drawtext overlay pass — the exact argument
/// order of the legacy interpolated command, minus its quoting.
///
/// The overlay text itself travels in a temp [textFilePath] (written by the
/// caller, content escaped via [escapeDrawtextText]); only app-controlled
/// paths appear inside the filter expression.
List<String> buildDateOverlayArgs({
  required String inputPath,
  required String outputPath,
  required String fontPath,
  required String textFilePath,
  required String x,
  required String y,
  required int fontSize,
}) {
  return [
    '-y',
    '-i',
    inputPath,
    '-vf',
    "drawtext=fontfile='$fontPath'"
        ":textfile='$textFilePath'"
        ':x=$x:y=$y:fontsize=$fontSize'
        ':fontcolor=white:borderw=3:bordercolor=black',
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-r', '30', '-crf', '23',
    '-preset', 'fast',
    '-c:a', 'aac', '-ar', '44100', '-ac', '2', '-b:a', '128k',
    outputPath,
  ];
}

/// Argv for the concat-demuxer montage pass — the exact argument order of
/// the legacy interpolated command, minus its quoting.
List<String> buildConcatArgs({
  required String concatListPath,
  required String outputPath,
}) {
  return [
    '-y', '-f', 'concat', '-safe', '0', '-i', concatListPath,
    '-c:v', 'libx264', '-crf', '23', '-preset', 'fast',
    '-c:a', 'aac', '-b:a', '128k',
    outputPath,
  ];
}

// ── Builders for the former quoted-string commands ──────────────────────────
//
// Each of these used to be one interpolated string run through
// FFmpegKit.execute, where a double quote in a path closed the quoted token
// and the rest became ffmpeg options. Each path is now one list element.

/// Scale-to-fit then pad to a 1080x1920 portrait frame. The `\,` is the
/// filtergraph escape for a comma inside `min(...)`, so it is sent as is.
const String _fitPortraitFilter =
    r'scale=iw*min(1080/iw\,1920/ih):ih*min(1080/iw\,1920/ih),'
    r'pad=1080:1920:(1080-iw*min(1080/iw\,1920/ih))/2:(1920-ih*min(1080/iw\,1920/ih))/2,'
    'setsar=1';

/// A still photo turned into a short video with a silent audio track.
List<String> buildPhotoToVideoArgs({
  required String imagePath,
  required String outputPath,
  required double duration,
}) {
  return [
    '-y', '-loop', '1', '-i', imagePath,
    '-f', 'lavfi', '-i', 'anullsrc=r=44100:cl=stereo',
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-r', '30', '-crf', '23',
    '-preset', 'fast',
    '-c:a', 'aac', '-ar', '44100', '-ac', '2', '-b:a', '128k',
    '-vf',
    'scale=1080:1920:force_original_aspect_ratio=decrease,'
        'pad=1080:1920:(ow-iw)/2:(oh-ih)/2,setsar=1',
    '-t', '$duration',
    outputPath,
  ];
}

/// A [duration]-second piece of a video starting at [startSeconds].
List<String> buildExtractSegmentArgs({
  required String inputPath,
  required String outputPath,
  required double startSeconds,
  required double duration,
}) {
  return [
    '-y', '-ss', '$startSeconds', '-i', inputPath,
    '-t', '$duration',
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-r', '30', '-crf', '23',
    '-preset', 'fast',
    '-c:a', 'aac', '-ar', '44100', '-ac', '2', '-b:a', '128k',
    '-vf', _fitPortraitFilter,
    outputPath,
  ];
}

/// The first [duration] seconds of a video, fitted to the portrait frame.
List<String> buildTrimVideoArgs({
  required String inputPath,
  required String outputPath,
  required double duration,
}) {
  return [
    '-y', '-i', inputPath,
    '-t', '$duration',
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-r', '30', '-crf', '23',
    '-preset', 'fast',
    '-c:a', 'aac', '-ar', '44100', '-ac', '2', '-b:a', '128k',
    '-vf', _fitPortraitFilter,
    outputPath,
  ];
}

/// One 320 px wide frame, half a second in.
List<String> buildThumbnailArgs({
  required String videoPath,
  required String outputPath,
}) {
  return [
    '-y', '-i', videoPath,
    '-ss', '0.5', '-vframes', '1', '-q:v', '2',
    '-vf', 'scale=320:-1',
    outputPath,
  ];
}

/// Re-encode a clip to the common format before joining. A clip with no
/// audio gets a silent track, cut to [duration] when it is known.
List<String> buildNormalizeArgs({
  required String inputPath,
  required String outputPath,
  required bool hasAudio,
  double? duration,
}) {
  if (hasAudio) {
    return [
      '-y', '-i', inputPath,
      '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-r', '30', '-crf', '23',
      '-preset', 'fast',
      '-vf', _fitPortraitFilter,
      '-c:a', 'aac', '-ar', '44100', '-ac', '2', '-b:a', '128k',
      outputPath,
    ];
  }
  return [
    '-y', '-i', inputPath,
    '-f', 'lavfi', '-i', 'anullsrc=r=44100:cl=stereo',
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-r', '30', '-crf', '23',
    '-preset', 'fast',
    '-vf', _fitPortraitFilter,
    '-c:a', 'aac', '-ar', '44100', '-ac', '2', '-b:a', '128k',
    if (duration != null) ...['-t', '$duration'],
    outputPath,
  ];
}

/// Copy the video and add a silent audio track, cut to [duration] when known.
List<String> buildAddSilentAudioArgs({
  required String inputPath,
  required String outputPath,
  double? duration,
}) {
  return [
    '-y', '-i', inputPath,
    '-f', 'lavfi', '-i', 'anullsrc=r=44100:cl=stereo',
    '-c:v', 'copy', '-c:a', 'aac', '-b:a', '128k',
    if (duration != null) ...['-t', '$duration'],
    outputPath,
  ];
}

/// Mix a music file under the video's own audio.
List<String> buildBackgroundMusicArgs({
  required String videoPath,
  required String musicPath,
  required String outputPath,
  required double musicVolume,
  required double originalVolume,
  double? duration,
}) {
  return [
    '-y', '-i', videoPath, '-i', musicPath,
    '-filter_complex',
    '[0:a]volume=$originalVolume[a0];[1:a]volume=$musicVolume[a1];'
        '[a0][a1]amix=inputs=2:duration=longest:dropout_transition=2[aout]',
    '-map', '0:v', '-map', '[aout]',
    '-c:v', 'copy', '-c:a', 'aac', '-b:a', '128k',
    if (duration != null) ...['-t', '$duration'],
    outputPath,
  ];
}

/// Mix several timed audio files under the video. [filterGraph] is built by
/// the caller from the segments; [audioPaths] are the segment files in the
/// same order, as inputs 1..n.
List<String> buildMultiTrackAudioArgs({
  required String videoPath,
  required List<String> audioPaths,
  required String filterGraph,
  required String outputPath,
  double? duration,
}) {
  return [
    '-y', '-i', videoPath,
    for (final p in audioPaths) ...['-i', p],
    '-filter_complex', filterGraph,
    '-map', '0:v', '-map', '[aout]',
    '-c:v', 'copy', '-c:a', 'aac', '-b:a', '128k',
    if (duration != null) ...['-t', '$duration'],
    outputPath,
  ];
}
