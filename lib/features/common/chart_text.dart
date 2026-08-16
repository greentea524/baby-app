import 'dart:math' as math;

import 'package:flutter/material.dart';

/// How far the charts let the system text size push their axis labels (#24).
///
/// [TextPainter] ignores the system text scale unless it is handed one, and
/// neither chart was handing it one — so at 200% the axis labels stayed 9px
/// while everything around them doubled, which is smaller in relative terms
/// than they were at 100%.
///
/// Honouring 200% in full is not the answer either: the gutter is measured
/// from the widest label, so a doubled label doubles the gutter, and past a
/// point the chart is all axis and no data. The axis grows to a point and
/// stops. What does not stop is the caption underneath — a real `Text`,
/// scaling all the way — and that is where the number a reader actually
/// wants is written.
const double chartMaxTextScale = 1.3;

/// A label style, the scale to draw it at, and the measuring that goes with
/// it.
///
/// Exists because the gutters are no longer constants: their width is
/// whatever the widest tick label comes to, which depends on the reader's
/// text size. Painter and layout have to agree on that number, so it is
/// measured once and passed to both.
@immutable
class ChartText {
  const ChartText({required this.style, required this.scaler});

  /// Reads the reader's text size from [context] and clamps it to
  /// [chartMaxTextScale].
  factory ChartText.of(
    BuildContext context, {
    required TextStyle style,
    double maxScale = chartMaxTextScale,
  }) => ChartText(
    style: style,
    scaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: maxScale),
  );

  final TextStyle style;
  final TextScaler scaler;

  TextPainter _painter(String text, [TextStyle? override]) => TextPainter(
    text: TextSpan(text: text, style: override ?? style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
  )..layout();

  Size measure(String text) => _painter(text).size;

  /// The width of the longest of [texts], or 0 for none — what a gutter has
  /// to be to fit them all.
  double widest(Iterable<String> texts) =>
      texts.fold(0, (w, t) => math.max(w, measure(t).width));

  /// One line's height at this scale, for the space under an x-axis.
  double get lineHeight => measure('0').height;

  void paint(
    Canvas canvas,
    String text,
    Offset at, {
    bool anchorRight = false,
    bool centerX = false,
    TextStyle? override,
  }) {
    final tp = _painter(text, override);
    var dx = at.dx;
    if (anchorRight) dx -= tp.width;
    if (centerX) dx -= tp.width / 2;
    tp.paint(canvas, Offset(dx, at.dy - tp.height / 2));
  }

  // Value equality so a painter's shouldRepaint notices the reader changing
  // their text size — otherwise the labels would only resize on the next
  // unrelated rebuild.
  @override
  bool operator ==(Object other) =>
      other is ChartText && other.style == style && other.scaler == scaler;

  @override
  int get hashCode => Object.hash(style, scaler);
}
