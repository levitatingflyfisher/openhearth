// The porch accent on the fleet theme: text on the one big button must be
// readable in both brightnesses. Goldens cannot see a contrast ratio.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openhearth_design/openhearth_design.dart';

import 'package:porch_app/presentation/app.dart';

double _channel(double v) =>
    v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();

double _luminance(Color c) =>
    0.2126 * _channel(c.r) + 0.7152 * _channel(c.g) + 0.0722 * _channel(c.b);

double contrast(Color a, Color b) {
  final x = _luminance(a), y = _luminance(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

void main() {
  final themes = {
    'light': OhTheme.light(appAccent: porchAmberLight),
    'dark': OhTheme.hearthDark(appAccent: porchAmberDark),
  };

  test('the accents are the values recorded for fleet check C12', () {
    // test/fleet_conformance_test.dart records these by value; change
    // both together.
    expect(porchAmberLight, const Color(0xFF845416));
    expect(porchAmberDark, const Color(0xFFFBBA73));
  });

  for (final MapEntry(key: name, value: theme) in themes.entries) {
    test('$name: on-primary text on the accent is at least 4.5:1', () {
      final s = theme.colorScheme;
      expect(s.primary, name == 'light' ? porchAmberLight : porchAmberDark);
      expect(contrast(s.primary, s.onPrimary), greaterThanOrEqualTo(4.5));
    });

    test('$name: the accent as text on the page is at least 4.5:1', () {
      expect(contrast(theme.colorScheme.primary, theme.scaffoldBackgroundColor),
          greaterThanOrEqualTo(4.5));
    });
  }
}
