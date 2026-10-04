import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/router/app_router.dart';

/// The way into the fridge — on Home's "In the fridge" row and on nursery
/// mode's pump card.
///
/// A filled button with a fridge on it, where there used to be a bare
/// chevron. The chevron said "this goes somewhere" without saying where, and
/// on a row that otherwise only reports it read as decoration. A filled
/// circle reads as a thing to press, and the icon says what is behind it.
///
/// One widget for both screens so they cannot drift: the same icon, the same
/// name, the same destination.
class FridgeButton extends StatelessWidget {
  const FridgeButton({super.key, this.glyph = icon});

  /// Material's refrigerator. The icon set calls it `kitchen` and has nothing
  /// named fridge.
  static const icon = Icons.kitchen_outlined;

  /// What the button shows: the fridge, unless the row it sits on already
  /// does — Home's "In the fridge" row, which says where it goes in words
  /// and an icon of its own, and shows an arrow rather than a second fridge.
  final IconData glyph;

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    icon: Icon(glyph),
    // The button's name as well as its tooltip: it is what a screen reader
    // announces, so the icon is never the only thing saying where this goes.
    tooltip: 'In the fridge',
    onPressed: () => context.push(AppRoutes.fridge),
  );
}
