import 'package:flutter/material.dart';

/// The way from a Home row into its own screen: a small rounded pill at the
/// row's top-right, saying what is there, with a chevron after it.
///
/// One shape for every row that leads somewhere. The fridge row had a round
/// arrow button and the diaper row a pill with the stock count, so the same
/// job looked like two different kinds of control.
class DetailPill extends StatelessWidget {
  const DetailPill({
    super.key,
    required this.label,
    required this.semanticLabel,
    required this.onTap,
    this.icon,
    this.background,
    this.foreground,
  });

  /// What is behind it, in a word or two: "25 left", "Open".
  final String label;

  /// What a screen reader announces: where the pill goes, not only what it
  /// says.
  final String semanticLabel;

  final VoidCallback onTap;

  final IconData? icon;

  /// A state's colours, for a pill that is also a warning — stock running
  /// low. The calm tonal ones otherwise.
  final Color? background;
  final Color? foreground;

  static const _radius = 14.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = background ?? theme.colorScheme.secondaryContainer;
    final fg = foreground ?? theme.colorScheme.onSecondaryContainer;
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(_radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(_radius),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon case final it?) ...[
                  Icon(it, size: 16, color: fg),
                  const SizedBox(width: 4),
                ],
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Icon(Icons.chevron_right, size: 18, color: fg),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
