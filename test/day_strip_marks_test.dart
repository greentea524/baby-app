import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:baby_app/features/insights/chart_palette.dart';
import 'package:baby_app/features/insights/day_timeline_strip.dart';
import 'package:baby_app/features/insights/day_view_data.dart';

/// What the day strip actually draws (#26).
///
/// Three lanes became one row of haloed lines. Both halves of that are claims
/// about pixels, so they are checked as pixels: that every kind lands on the
/// same row, and that two events minutes apart are still two marks rather
/// than one blob.
void main() {
  const width = 340.0;

  /// The strip's default height — the band plus its hour labels, above the
  /// legend. Used to keep pixel sampling off the legend.
  const stripHeight = 46.0;
  final key = GlobalKey();

  /// Renders the strip and hands back the pixels.
  Future<ui.Image> paint(WidgetTester tester, List<DayMark> marks) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: Brightness.light),
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: key,
              child: SizedBox(
                width: width,
                child: DayTimelineStrip(marks: marks),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    // toImage completes on the real event loop, which the fake async zone a
    // widget test runs in never pumps — awaiting it directly just hangs.
    return (await tester.runAsync(boundary.toImage))!;
  }

  /// Every pixel exactly [colour], as (x, y). Exact rather than near, so an
  /// antialiased edge never counts as the mark itself.
  Future<List<(int, int)>> pixelsOf(
    WidgetTester tester,
    ui.Image image,
    Color colour,
  ) async {
    final data = await tester.runAsync(
      () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
    );
    final bytes = data!.buffer.asUint8List();
    final want = Uint8List.fromList([
      (colour.r * 255).round(),
      (colour.g * 255).round(),
      (colour.b * 255).round(),
      255,
    ]);
    // Only the band. The legend swatches below it carry the very same
    // colours, and counting those would put every mark's centre of mass
    // somewhere near the bottom left.
    final scale = image.width / width;
    final bandBottom = stripHeight * scale;

    final found = <(int, int)>[];
    for (var i = 0; i < bytes.length; i += 4) {
      if (bytes[i] == want[0] &&
          bytes[i + 1] == want[1] &&
          bytes[i + 2] == want[2] &&
          bytes[i + 3] == want[3]) {
        final p = i ~/ 4;
        final y = p ~/ image.width;
        if (y < bandBottom) found.add((p % image.width, y));
      }
    }
    return found;
  }

  double mean(Iterable<int> values) =>
      values.reduce((a, b) => a + b) / values.length;

  final colours = DayColours.forBrightness(Brightness.light);

  testWidgets('every kind lands on the same row', (tester) async {
    // The whole point of the change: three lanes meant the day's rhythm had
    // to be assembled by eye across rows.
    final image = await paint(tester, const [
      (hour: 2.5, kind: DayMarkKind.feed),
      (hour: 9, kind: DayMarkKind.diaper),
      (hour: 14.25, kind: DayMarkKind.pump),
    ]);

    final centres = <double>[];
    for (final colour in [colours.feed, colours.diaper, colours.pump]) {
      final pixels = await pixelsOf(tester, image, colour);
      expect(pixels, isNotEmpty, reason: 'nothing drawn for $colour');
      centres.add(mean(pixels.map((p) => p.$2)));
    }

    // Within a few points of each other, which they cannot be if any of them
    // is in a lane of its own.
    expect(centres.reduce((a, b) => a > b ? a : b) - centres.reduce((a, b) => a < b ? a : b),
        lessThan(8));
  });

  testWidgets('and in time order across the band', (tester) async {
    final image = await paint(tester, const [
      (hour: 2, kind: DayMarkKind.feed),
      (hour: 12, kind: DayMarkKind.diaper),
      (hour: 22, kind: DayMarkKind.pump),
    ]);

    final xs = <double>[];
    for (final colour in [colours.feed, colours.diaper, colours.pump]) {
      xs.add(mean((await pixelsOf(tester, image, colour)).map((p) => p.$1)));
    }
    expect(xs[0], lessThan(xs[1]));
    expect(xs[1], lessThan(xs[2]));
    // Midday sits mid-band; the earlier failure mode would be a scale that
    // silently lost a chunk of the day to padding.
    expect(xs[1], closeTo(width / 2, 6));
  });

  testWidgets('a mark at midnight is not cut in half by the edge', (
    tester,
  ) async {
    final image = await paint(tester, const [
      (hour: 0, kind: DayMarkKind.feed),
    ]);
    final pixels = await pixelsOf(tester, image, colours.feed);
    expect(pixels, isNotEmpty);
    // Fully inside the band: a mark centred on x=0 would lose its left half.
    expect(pixels.map((p) => p.$1).reduce((a, b) => a < b ? a : b),
        greaterThan(0));
  });

  testWidgets('two events ten minutes apart stay two marks', (tester) async {
    // At this width the band is about 14pt an hour, so these two overlap —
    // the halo, and the nudge behind it, are what keep them legible.
    final image = await paint(tester, const [
      (hour: 12, kind: DayMarkKind.feed),
      (hour: 12.17, kind: DayMarkKind.diaper),
    ]);

    final feed = await pixelsOf(tester, image, colours.feed);
    final diaper = await pixelsOf(tester, image, colours.diaper);
    expect(feed, isNotEmpty, reason: 'the earlier mark was painted over');
    expect(diaper, isNotEmpty);

    // A gap of background between them on the row they share: that sliver of
    // surface is the whole mechanism.
    final row = mean(diaper.map((p) => p.$2)).round();
    final feedRight =
        feed.where((p) => p.$2 == row).map((p) => p.$1).reduce((a, b) => a > b ? a : b);
    final diaperLeft = diaper
        .where((p) => p.$2 == row)
        .map((p) => p.$1)
        .reduce((a, b) => a < b ? a : b);
    expect(diaperLeft, greaterThan(feedRight + 1));
  });

  testWidgets('a top-up runs short', (tester) async {
    // Same colour as a feed by design, so the height is the only thing
    // telling them apart. It replaces the old hollow outline, which at 3pt
    // wide left a hole barely wider than the antialiasing around it.
    final full = await paint(tester, const [
      (hour: 12, kind: DayMarkKind.feed),
    ]);
    final short = await paint(tester, const [
      (hour: 12, kind: DayMarkKind.snack),
    ]);

    double heightOf(List<(int, int)> pixels) {
      final ys = pixels.map((p) => p.$2);
      return (ys.reduce((a, b) => a > b ? a : b) -
              ys.reduce((a, b) => a < b ? a : b))
          .toDouble();
    }

    final feedHeight = heightOf(await pixelsOf(tester, full, colours.feed));
    final snackHeight = heightOf(await pixelsOf(tester, short, colours.feed));
    expect(snackHeight, lessThan(feedHeight * 0.6));
    expect(snackHeight, greaterThan(2), reason: 'too short to see');
  });

  testWidgets('a mark is narrow enough to point at a time', (tester) async {
    // The reason lines and not dots. A mark this wide spans about 13 minutes
    // on a phone; an 8pt dot spanned 35, on a chart that is nothing but when.
    final image = await paint(tester, const [
      (hour: 12, kind: DayMarkKind.feed),
    ]);
    final pixels = await pixelsOf(tester, image, colours.feed);
    final xs = pixels.map((p) => p.$1);
    final width =
        xs.reduce((a, b) => a > b ? a : b) - xs.reduce((a, b) => a < b ? a : b);
    expect(width, lessThan(5));
  });

  testWidgets('and tall enough to read as a mark on the band', (tester) async {
    // The other half of that trade: a line has to span the band, or it is
    // just a smaller dot.
    final image = await paint(tester, const [
      (hour: 12, kind: DayMarkKind.feed),
    ]);
    final pixels = await pixelsOf(tester, image, colours.feed);
    final ys = pixels.map((p) => p.$2);
    final height =
        ys.reduce((a, b) => a > b ? a : b) - ys.reduce((a, b) => a < b ? a : b);
    expect(height, greaterThan(12));
  });

  testWidgets('is shorter than the three lanes it replaced', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: DayTimelineStrip(
                marks: [(hour: 9, kind: DayMarkKind.feed)],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // The lanes needed 92pt to be visible at all. Freeing that is most of the
    // reason for the change, so it is worth failing if it creeps back.
    expect(tester.getSize(find.byType(DayTimelineStrip)).height, lessThan(75));
  });

  testWidgets('two events at the same minute are still two marks', (
    tester,
  ) async {
    // The worst case, and not a rare one: a nappy change logged at the same
    // moment as the feed it followed. Exact positions give way here so that
    // neither event disappears.
    final image = await paint(tester, const [
      (hour: 12, kind: DayMarkKind.feed),
      (hour: 12, kind: DayMarkKind.diaper),
    ]);

    expect(await pixelsOf(tester, image, colours.feed), isNotEmpty);
    expect(await pixelsOf(tester, image, colours.diaper), isNotEmpty);
  });

  testWidgets('a nudged mark stays within the band', (tester) async {
    // Pushing right has to stop at the edge rather than paint into the
    // legend or off the end.
    final image = await paint(tester, const [
      (hour: 23.95, kind: DayMarkKind.feed),
      (hour: 23.96, kind: DayMarkKind.diaper),
      (hour: 23.97, kind: DayMarkKind.pump),
    ]);

    final pixels = await pixelsOf(tester, image, colours.pump);
    expect(pixels, isNotEmpty);
    expect(
      pixels.map((p) => p.$1).reduce((a, b) => a > b ? a : b),
      lessThan(image.width),
    );
  });

  testWidgets('every mark is announced, however close together', (
    tester,
  ) async {
    // Nudging moves pixels, not times — and the semantics rects overlap far
    // more on one row than they did across three lanes, so this checks the
    // nodes are all still there to be swiped through.
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              child: DayTimelineStrip(
                marks: [
                  (hour: 12, kind: DayMarkKind.feed),
                  (hour: 12.05, kind: DayMarkKind.diaper),
                  (hour: 12.1, kind: DayMarkKind.pump),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final found = <String>[];
    void visit(SemanticsNode node) {
      if (node.label.isNotEmpty) found.add(node.label);
      node.visitChildren((child) {
        visit(child);
        return true;
      });
    }

    visit(tester.getSemantics(find.byType(DayTimelineStrip)));
    expect(found, contains('Feed at 12p'));
    expect(found, contains('Diaper at 12p 3'));
    expect(found, contains('Pump at 12p 6'));
    handle.dispose();
  });
}
