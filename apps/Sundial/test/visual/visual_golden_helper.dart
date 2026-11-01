import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sundial/shared/theme/app_theme.dart';

/// Absorbs sub-pixel anti-aliasing drift between machines: the local bake
/// box and the CI runner rasterize the stats charts' curved paths a hair
/// apart (0.17% of pixels on the phone golden), while real layout or
/// content changes land far above this bar (the fleet's recent alpha
/// re-bakes measured 5–16%).
class _TolerantGoldenComparator extends LocalFileComparator {
  _TolerantGoldenComparator(super.testFile);

  static const double _maxDiffRate = 0.005;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final ComparisonResult result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= _maxDiffRate) {
      return true;
    }
    final String error = await generateFailureOutput(result, golden, basedir);
    throw FlutterError(error);
  }
}

/// Named logical device sizes for responsive golden sweeps.
///
/// Rendering one widget at several viewport sizes captures layout reflow
/// (responsiveness) as separate golden PNGs that can be inspected directly.
const Map<String, Size> kResponsiveSizes = <String, Size>{
  'phone': Size(360, 740),
  'tablet': Size(768, 1024),
  'desktop': Size(1280, 800),
};

/// Renders [home] at every combination of [sizes] × [textScales] (logical px,
/// dpr 1.0) and writes/compares one golden PNG per combination under
/// `test/visual/goldens/`.
///
/// [home] is the screen/widget content (it becomes `MaterialApp.home`); the
/// helper supplies the `MaterialApp` and injects the text scale via the app
/// builder so it actually reaches the content (a `MediaQuery` placed *above*
/// `MaterialApp` is ignored, because the app rebuilds its own from the view).
///
/// [theme] defaults to the app's own light theme ([AppTheme.light], the one
/// `main.dart` installs), so the pictures show what a user sees. Pass
/// [AppTheme.dark] for a dark picture. The app's fonts load through
/// `flutter_test_config.dart` from the font manifest.
///
/// [skip] names combinations (`narrow_ts3.0`) to leave out because they show
/// a known app defect; each use must say which defect, so the gap is visible.
///
/// [textScales] sweeps accessibility font scaling — the axis most likely to
/// surface overflow on a mobile app. A single default scale leaves filenames
/// unchanged; multiple scales append a `_tsN.N` suffix.
///
/// Run `flutter test --update-goldens` to (re)generate, then read the PNGs
/// (montage with contact-sheet.sh) to inspect layout.
Future<void> goldenAtSizes(
  WidgetTester tester, {
  required String name,
  required Widget home,
  Map<String, Size> sizes = kResponsiveSizes,
  List<double> textScales = const <double>[1.0],
  ThemeData? theme,
  Set<String> skip = const <String>{},
}) async {
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.view.devicePixelRatio = 1.0;

  final GoldenFileComparator current = goldenFileComparator;
  if (current is LocalFileComparator && current is! _TolerantGoldenComparator) {
    goldenFileComparator =
        _TolerantGoldenComparator(Uri.parse('${current.basedir}x_test.dart'));
  }

  for (final MapEntry<String, Size> size in sizes.entries) {
    for (final double scale in textScales) {
      final String scaleKey =
          textScales.length > 1 ? '_ts${scale.toStringAsFixed(1)}' : '';
      if (skip.contains('${size.key}$scaleKey')) continue;
      tester.view.physicalSize = size.value;
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme ?? AppTheme.light,
        builder: (BuildContext context, Widget? child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: home,
      ));
      await tester.pumpAndSettle();
      final String scaleTag =
          textScales.length > 1 ? '_ts${scale.toStringAsFixed(1)}' : '';
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('goldens/${name}_${size.key}$scaleTag.png'),
      );
    }
  }
}
