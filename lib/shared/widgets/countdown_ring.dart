import 'package:flutter/material.dart';

/// Circular countdown ring widget for TOTP period timer (§7.1 #3, §7.2).
///
/// Displays a progress ring representing `remainingSeconds / period` with the
/// remaining second value rendered inside.
/// Changes color to error red when `remainingSeconds <= 5`.
class CountdownRing extends StatelessWidget {
  const CountdownRing({
    super.key,
    required this.remainingSeconds,
    this.period = 30,
    this.size = 36.0,
    this.strokeWidth = 3.0,
  });

  /// Seconds remaining until the current TOTP step expires.
  final int remainingSeconds;

  /// Full period step size in seconds (default: 30).
  final int period;

  /// Diameter of the ring widget.
  final double size;

  /// Stroke width of the circular progress indicator.
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExpiringSoon = remainingSeconds <= 5;
    final ringColor = isExpiringSoon
        ? theme.colorScheme.error
        : theme.colorScheme.primary;

    final double progress = period > 0
        ? (remainingSeconds / period).clamp(0.0, 1.0)
        : 0.0;

    return Semantics(
      label: '$remainingSeconds seconds remaining',
      excludeSemantics: true,
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            CircularProgressIndicator(
              value: progress,
              strokeWidth: strokeWidth,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(ringColor),
            ),
            Text(
              '$remainingSeconds',
              style: TextStyle(
                fontSize: size * 0.38,
                fontWeight: FontWeight.bold,
                color: ringColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
