import 'package:flutter/material.dart';

import '../../data/models/fridge_bottle.dart';
import 'fridge_order.dart';

/// A feeding bottle, drawn filled to how much is in it.
///
/// Standing at an open fridge, "how full is it" is answered faster by a
/// picture of a bottle than by a number: the eye compares levels across a
/// row of bottles before it has read any of their labels. The number stays on
/// the card beside it for the record.
///
/// Full means [bottleCapacityMl]. Quarter marks up the side, so a level can
/// be read to the nearest 30 ml of a 120 ml bottle the way the real bottle's
/// own markings are read.
///
/// Coloured by kind, from the theme rather than chosen by hand, so it follows
/// the accent and the dark theme like everything else: breast milk in the
/// primary colours, formula in the tertiary, whole milk in the secondary.
class BottleGauge extends StatelessWidget {
  const BottleGauge({super.key, required this.amountMl, required this.kind});

  final double amountMl;
  final MilkKind kind;

  /// Width to height: a feeding bottle, tall and narrow.
  static const aspectRatio = 0.5;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final level = fullness(amountMl);
    final (milk, surface) = switch (kind) {
      MilkKind.expressed => (scheme.primaryContainer, scheme.primary),
      MilkKind.formula => (scheme.tertiaryContainer, scheme.tertiary),
      MilkKind.wholeMilk => (scheme.secondaryContainer, scheme.secondary),
    };

    // The drawing carries nothing a screen reader could use, so it says the
    // one thing it adds to the card: the level. The amount is read out from
    // the text beside it.
    return Semantics(
      label: '${(level * 100).round()}% full',
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: CustomPaint(
          painter: BottlePainter(
            level: level,
            milk: milk,
            surface: surface,
            glass: scheme.surfaceContainerLowest,
            outline: scheme.outline,
            teat: scheme.surfaceContainerHighest,
            collar: scheme.outlineVariant,
          ),
        ),
      ),
    );
  }
}

/// The bottle itself: teat, collar and body, with the milk inside the body.
///
/// Public for its [shouldRepaint] and for tests, which check the level it is
/// asked to draw rather than pixels.
class BottlePainter extends CustomPainter {
  const BottlePainter({
    required this.level,
    required this.milk,
    required this.surface,
    required this.glass,
    required this.outline,
    required this.teat,
    required this.collar,
  });

  /// How full, 0 to 1.
  final double level;
  final Color milk;

  /// The line across the top of the milk. Its own colour, darker than the
  /// milk, because a level is read off an edge.
  final Color surface;
  final Color glass;
  final Color outline;
  final Color teat;
  final Color collar;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final stroke = (w * 0.035).clamp(1.2, 3.0);
    final half = stroke / 2;
    final cx = w / 2;

    final teatBottom = h * 0.2;
    final collarBottom = h * 0.3;

    final lines = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = outline;

    // The body: squared-off shoulders under the collar, a rounded base.
    final body = RRect.fromLTRBAndCorners(
      half,
      collarBottom,
      w - half,
      h - half,
      topLeft: Radius.circular(w * 0.1),
      topRight: Radius.circular(w * 0.1),
      bottomLeft: Radius.circular(w * 0.22),
      bottomRight: Radius.circular(w * 0.22),
    );
    canvas.drawRRect(body, Paint()..color = glass);

    // The milk, clipped to the body so it takes the shape of the base.
    if (level > 0) {
      final top = body.bottom - body.height * level;
      canvas
        ..save()
        ..clipRRect(body)
        ..drawRect(
          Rect.fromLTRB(body.left, top, body.right, body.bottom),
          Paint()..color = milk,
        );
      // A full bottle's surface would sit on the shoulder line, where it only
      // thickens the outline.
      if (level < 1) {
        canvas.drawLine(
          Offset(body.left, top),
          Offset(body.right, top),
          Paint()
            ..color = surface
            ..strokeWidth = stroke,
        );
      }
      canvas.restore();
    }

    // Quarter marks down the left, like the printed scale on a real bottle.
    final ticks = Paint()
      ..color = outline.withValues(alpha: 0.6)
      ..strokeWidth = (stroke * 0.7).clamp(1.0, 2.0);
    for (final quarter in const [0.25, 0.5, 0.75]) {
      final y = body.bottom - body.height * quarter;
      canvas.drawLine(
        Offset(body.left, y),
        Offset(body.left + w * (quarter == 0.5 ? 0.26 : 0.16), y),
        ticks,
      );
    }
    canvas.drawRRect(body, lines);

    // The collar screwed on over the shoulders, narrower than the body.
    final collarRect = RRect.fromLTRBR(
      cx - w * 0.36,
      teatBottom,
      cx + w * 0.36,
      collarBottom,
      Radius.circular(w * 0.06),
    );
    canvas
      ..drawRRect(collarRect, Paint()..color = collar)
      ..drawRRect(collarRect, lines);

    // The teat: a rounded dome on the collar.
    final teatHalf = w * 0.17;
    final teatRect = RRect.fromLTRBAndCorners(
      cx - teatHalf,
      half,
      cx + teatHalf,
      teatBottom,
      topLeft: Radius.circular(teatHalf),
      topRight: Radius.circular(teatHalf),
    );
    canvas
      ..drawRRect(teatRect, Paint()..color = teat)
      ..drawRRect(teatRect, lines);
  }

  @override
  bool shouldRepaint(BottlePainter old) =>
      old.level != level ||
      old.milk != milk ||
      old.surface != surface ||
      old.glass != glass ||
      old.outline != outline ||
      old.teat != teat ||
      old.collar != collar;
}
