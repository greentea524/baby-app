import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/repository_providers.dart';
import '../reminders/feed_prediction.dart';
import '../reminders/reminder_providers.dart';
import 'companion_art.dart';
import 'home_prefs.dart';

/// A small companion in the corner of Home that reads how close the next feed
/// is, and celebrates when one is logged (#14, #16).
///
/// Decorative on purpose: a second, glanceable read of what the next-feed chip
/// already says in words, and the chip stays the thing you actually read. Not
/// tappable — the quick-action feed button is a few centimetres below, and a
/// live control tucked in the app bar corner is one you hit by accident rather
/// than on purpose.
///
/// Which companion is drawn is the caregiver's choice; everything here is the
/// part that does not care. See [CompanionArt] for the styles themselves.
class FeedCompanion extends ConsumerStatefulWidget {
  const FeedCompanion({super.key, required this.now});

  final DateTime now;

  /// How long the celebration runs before handing back to the resting phase.
  static const celebrateDuration = Duration(milliseconds: 1400);

  @override
  ConsumerState<FeedCompanion> createState() => _FeedCompanionState();
}

class _FeedCompanionState extends ConsumerState<FeedCompanion>
    with TickerProviderStateMixin {
  /// The idle loop. Deliberately long: it repaints for as long as Home is
  /// open, and a fast loop is battery spent on decoration.
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 9),
  );

  late final AnimationController _celebrate = AnimationController(
    vsync: this,
    duration: FeedCompanion.celebrateDuration,
  );

  @override
  void initState() {
    super.initState();
    _celebrate.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _drift.dispose();
    _celebrate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A feed that drives the clock is the only thing that resets the
    // companion. Snacks and solids do not move the due time, so triggering on
    // those would celebrate and un-celebrate inside the same second.
    ref.listen(lastClockFeedProvider, (previous, next) {
      // `previous == null` is the stream arriving, not a feed being logged —
      // otherwise every cold start would celebrate.
      if (previous == null || next == null) return;
      if (previous.id != next.id) {
        _celebrate
          ..reset()
          ..forward();
      }
    });

    final art = ref.watch(companionStyleProvider).art;
    if (art == null) return const SizedBox.shrink();

    final due = ref.watch(nextFeedDueProvider);
    // Reminders off: no due time, so there is no phase to be in.
    if (due == null) return const SizedBox.shrink();

    final settings = ref.watch(reminderSettingsProvider);
    final resting = phaseFor(
      feedDueState(due, now: widget.now, within: settings.headsUp),
    );
    final progress = _progress(ref.read(lastClockFeedProvider)?.startTime, due);
    final phase = _celebrate.isAnimating ? CompanionPhase.justFed : resting;

    // Stilled, the companion still carries its phase — it just does not move.
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final shouldIdle = !still && art.idles(resting) && !_celebrate.isAnimating;
    if (shouldIdle && !_drift.isAnimating) {
      _drift.repeat();
    } else if (!shouldIdle && _drift.isAnimating) {
      _drift.stop();
    }

    return Semantics(
      label: _semantics(phase),
      child: SizedBox(
        width: 48,
        height: kToolbarHeight,
        child: AnimatedBuilder(
          animation: Listenable.merge([_drift, _celebrate]),
          builder: (context, _) => CustomPaint(
            painter: _CompanionPainter(
              art: art,
              phase: _celebrate.isAnimating
                  ? CompanionPhase.justFed
                  : resting,
              drift: still ? 0.35 : _drift.value,
              celebrate: still ? 0 : _celebrate.value,
              progress: progress,
              colors: CompanionColors.of(context),
            ),
          ),
        ),
      ),
    );
  }

  /// How far through the wait we are: 0 at the last feed, 1 once due.
  ///
  /// Returns 1 — nothing left — whenever the span cannot be measured. A
  /// missing last feed and a due time already behind it are both "you are
  /// out of time", which is the safe direction for a countdown to round.
  double _progress(DateTime? lastFedAt, DateTime due) {
    if (lastFedAt == null) return 1;
    final span = due.difference(lastFedAt).inSeconds;
    if (span <= 0) return 1;
    return (widget.now.difference(lastFedAt).inSeconds / span).clamp(0.0, 1.0);
  }

  /// Shared across styles on purpose: a screen reader wants the state, not
  /// the metaphor.
  String _semantics(CompanionPhase phase) => switch (phase) {
    CompanionPhase.easy => 'Next feed is a while off',
    CompanionPhase.soon => 'Next feed is due soon',
    CompanionPhase.due => 'Feed is due',
    CompanionPhase.justFed => 'Feed logged',
  };
}

/// The companion borrows the next-feed chip's palette so the two always agree.
class CompanionColors {
  const CompanionColors({
    required this.easy,
    required this.soon,
    required this.due,
    required this.ground,
  });

  final Color easy;
  final Color soon;
  final Color due;
  final Color ground;

  factory CompanionColors.of(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return CompanionColors(
      easy: scheme.onSurfaceVariant,
      // The same amber the chip uses, for the same reason: no Material role
      // means "warning", so a seed-derived colour would stop reading as one.
      soon: theme.brightness == Brightness.dark
          ? const Color(0xFFFFC64D)
          : const Color(0xFF8A6600),
      due: scheme.error,
      ground: scheme.outlineVariant,
    );
  }

  Color forPhase(CompanionPhase phase) => switch (phase) {
    CompanionPhase.easy => easy,
    CompanionPhase.soon => soon,
    CompanionPhase.due => due,
    CompanionPhase.justFed => easy,
  };
}

/// Laid-out glyphs, kept between frames.
///
/// [TextPainter.layout] builds a `ui.Paragraph`, and a paragraph holds native
/// Skia memory that is only released when the Dart object is collected. The
/// painter used to build one — two, for the bottle — inside `paint()`, which
/// runs on every frame the plane is cruising: sixty a second, for as long as
/// Home is open. That is a lot of native allocation to leave to the garbage
/// collector, and on the web it is a known way to grow a tab until it dies.
///
/// The position changes every frame; the glyph does not. Caching on what
/// actually varies takes the steady state to no allocation at all.
///
/// Unbounded because the key space is not: four icons across a handful of
/// theme colours, so a few dozen entries at the very most.
final _glyphCache = <(int, int), TextPainter>{};

TextPainter _glyph(IconData icon, Color color) =>
    _glyphCache.putIfAbsent((icon.codePoint, color.toARGB32()), () {
      return TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontSize: _CompanionPainter._iconSize,
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });

/// How many distinct glyphs are being held. The point of the cache is that
/// this stays flat while a companion animates, so a test can assert the
/// steady state rather than trusting the comment above it.
@visibleForTesting
int get companionGlyphCacheSize => _glyphCache.length;

@visibleForTesting
void clearCompanionGlyphCache() => _glyphCache.clear();

class _CompanionPainter extends CustomPainter {
  _CompanionPainter({
    required this.art,
    required this.phase,
    required this.drift,
    required this.celebrate,
    required this.progress,
    required this.colors,
  });

  final CompanionArt art;
  final CompanionPhase phase;
  final double drift;
  final double celebrate;
  final double progress;
  final CompanionColors colors;

  static const _iconSize = 22.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (art.ground(phase)) {
      final y = size.height * 0.72;
      canvas.drawLine(
        Offset(4, y),
        Offset(size.width - 4, y),
        Paint()
          ..color = colors.ground
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
      );
    }

    final pose = art.pose(phase, size, drift: drift, celebrate: celebrate);
    final icon = art.icon(phase);
    final alpha = pose.opacity.clamp(0.0, 1.0);
    final level = art.level(phase, progress: progress, celebrate: celebrate);

    canvas.save();
    canvas.translate(pose.at.dx, pose.at.dy);
    if (pose.angle != 0) canvas.rotate(pose.angle);

    // Fading is done with a layer rather than by tinting the glyph, so a
    // continuously changing alpha does not mint a cache entry per frame.
    final fading = alpha < 1;
    if (fading) {
      canvas.saveLayer(
        Rect.fromCenter(
          center: Offset.zero,
          width: _iconSize * 2,
          height: _iconSize * 2,
        ),
        Paint()..color = Color.fromRGBO(0, 0, 0, alpha),
      );
    }

    final full = colors.forPhase(phase);
    if (level == null) {
      final p = _glyph(icon, full);
      p.paint(canvas, Offset(-p.width / 2, -p.height / 2));
    } else {
      // Drawn twice: the whole glyph faintly, so the vessel is still there
      // when it is empty, then the same glyph again clipped to the bottom
      // [level] of its box. Clipping the glyph rather than drawing a bar
      // keeps the fill inside whatever shape the icon happens to be.
      //
      // The empty part is not as faint as it could be, on purpose. A drained
      // bottle *is* the urgent state, and at a whisper it was the one moment
      // this style said less than the others — every one of them goes solid
      // red when the feed is due.
      final ghost = _glyph(icon, full.withValues(alpha: 0.45));
      ghost.paint(canvas, Offset(-ghost.width / 2, -ghost.height / 2));

      final p = _glyph(icon, full);
      final half = p.height / 2;
      canvas.save();
      canvas.clipRect(
        Rect.fromLTRB(
          -p.width / 2,
          half - p.height * level.clamp(0.0, 1.0),
          p.width / 2,
          half,
        ),
      );
      p.paint(canvas, Offset(-p.width / 2, -half));
      canvas.restore();
    }

    if (fading) canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(_CompanionPainter old) =>
      old.art.runtimeType != art.runtimeType ||
      old.phase != phase ||
      old.drift != drift ||
      old.celebrate != celebrate ||
      old.progress != progress ||
      old.colors.easy != colors.easy;
}
