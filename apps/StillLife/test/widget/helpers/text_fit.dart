import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every laid-out paragraph under [of].
List<RenderParagraph> paragraphsUnder(WidgetTester tester, Finder of) {
  final out = <RenderParagraph>[];
  void visit(RenderObject node) {
    if (node is RenderParagraph) out.add(node);
    node.visitChildren(visit);
  }

  visit(tester.renderObject(of));
  return out;
}

/// Fails when a paragraph under [of] hides text: cut off by maxLines, faded
/// or ellipsized, or a word split across two lines because its line was too
/// narrow for it. These are the faults a golden shows as "Sony A7III Ca...",
/// "Long Tag Na" or "Digit / al".
void expectAllTextReadable(WidgetTester tester, Finder of) {
  for (final p in paragraphsUnder(tester, of)) {
    final text = p.text.toPlainText();
    expect(p.didExceedMaxLines, isFalse, reason: '"$text" is cut off');
    expect(p.size.width, greaterThan(0), reason: '"$text" has no room');
    // A one-line label (softWrap off, as in a chip) lays out wider than its
    // box and is faded or clipped at the edge without exceeding maxLines.
    expect(
      p.textSize.width,
      lessThanOrEqualTo(p.size.width + 0.5),
      reason: '"$text" is wider than its box and clipped',
    );
    final style = p.text.style;
    for (final word in text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty)) {
      final tp = TextPainter(
        text: TextSpan(text: word, style: style),
        textDirection: TextDirection.ltr,
        textScaler: p.textScaler,
        maxLines: 1,
      )..layout();
      expect(
        tp.width,
        lessThanOrEqualTo(p.constraints.maxWidth + 0.5),
        reason: 'the word "$word" in "$text" does not fit its line '
            '(${tp.width.toStringAsFixed(1)} > '
            '${p.constraints.maxWidth.toStringAsFixed(1)})',
      );
      tp.dispose();
    }
  }
}

/// The global left and right edges of the glyphs [p] actually paints, which
/// for centred or short text sit inside the paragraph's own box. Spaces are
/// left out: the space at a line break hangs past the line and paints
/// nothing.
(double, double) inkExtent(RenderParagraph p) {
  final text = p.text.toPlainText();
  var left = double.infinity;
  var right = double.negativeInfinity;
  for (var i = 0; i < text.length; i++) {
    if (text[i].trim().isEmpty) continue;
    for (final b in p.getBoxesForSelection(
      TextSelection(baseOffset: i, extentOffset: i + 1),
    )) {
      if (b.left < left) left = b.left;
      if (b.right > right) right = b.right;
    }
  }
  final origin = p.localToGlobal(Offset.zero);
  return (origin.dx + left, origin.dx + right);
}
