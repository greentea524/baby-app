import 'package:flutter/material.dart';

/// Category colours for the day charts.
///
/// Deliberately spelled out rather than taken from the [ColorScheme], for the
/// same reason the "due soon" chip spells its amber out: no Material role
/// means "diaper" or "pump". The app offers four seeds, and
/// `ColorScheme.fromSeed` puts `secondary` close beside `primary` on all of
/// them — so a chart keyed to scheme roles had a feed and a pump in nearly
/// the same colour, and derived its remaining categories by dropping the
/// opacity of one it already had. Two segments of the same hue at different
/// alpha are not two colours; they are one colour and a mistake.
///
/// Four hues, spaced around the wheel and none of them a red/green pair, so
/// they stay apart for the commonest colour-vision deficiencies. Colour is
/// still never the only cue: the strip puts each kind in its own lane and
/// draws top-ups hollow, and the diaper bar labels every count in words.
@immutable
class DayColours {
  const DayColours({
    required this.feed,
    required this.diaper,
    required this.pump,
    required this.wet,
  });

  factory DayColours.of(BuildContext context) =>
      DayColours.forBrightness(Theme.of(context).brightness);

  /// Split out so a test can ask for a set without building a theme.
  factory DayColours.forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? _dark : _light;

  /// Indigo. Feeds, and top-ups drawn as an outline of the same.
  final Color feed;

  /// Amber. Diapers on the strip, and the dirty share of the bar.
  final Color diaper;

  /// Magenta. Pump sessions.
  final Color pump;

  /// Teal. The wet share of the bar — kept off the feed indigo so a glance
  /// at one chart does not read as the other.
  final Color wet;

  static const _light = DayColours(
    feed: Color(0xFF2B4BD8),
    diaper: Color(0xFFB4690E),
    pump: Color(0xFF9B3B8F),
    wet: Color(0xFF0F7F73),
  );

  // Lifted and desaturated for a dark surface: the light values are legible
  // on white and muddy on charcoal.
  static const _dark = DayColours(
    feed: Color(0xFF5C8DF6),
    diaper: Color(0xFFF0A93A),
    pump: Color(0xFFC36BE0),
    wet: Color(0xFF1FB09A),
  );

  /// A diaper that was both: literally both colours, split down the middle.
  ///
  /// A third invented hue would have to be remembered; this one is read
  /// straight off the other two.
  Gradient get both => LinearGradient(
    colors: [wet, wet, diaper, diaper],
    stops: const [0, 0.5, 0.5, 1],
  );

  @override
  bool operator ==(Object other) =>
      other is DayColours &&
      other.feed == feed &&
      other.diaper == diaper &&
      other.pump == pump &&
      other.wet == wet;

  @override
  int get hashCode => Object.hash(feed, diaper, pump, wet);
}
