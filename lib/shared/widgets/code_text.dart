import 'package:flutter/material.dart';

/// Monospace OTP code display widget with tabular figures and grouping (§7.2).
///
/// Groups digits cleanly:
/// - 6 digits: `123 456`
/// - 7 digits: `123 4567`
/// - 8 digits: `1234 5678`
///
/// Wraps formatted text in a screen-reader friendly [Semantics] label with digits
/// spelled out individually (e.g. `'1 2 3 4 5 6'`).
class CodeText extends StatelessWidget {
  const CodeText({
    super.key,
    required this.code,
    this.style,
    this.fontSize,
    this.isFaint = false,
  });

  /// The raw OTP code string (e.g. "123456").
  final String code;

  /// Optional base [TextStyle].
  final TextStyle? style;

  /// Font size for the OTP digits.
  final double? fontSize;

  /// Whether to render the code with faint / muted opacity.
  final bool isFaint;

  /// Formats raw code digits with spaces according to standard grouping.
  static String formatCode(String rawCode) {
    final clean = rawCode.replaceAll(' ', '');
    final len = clean.length;
    if (len == 6) {
      return '${clean.substring(0, 3)} ${clean.substring(3)}';
    } else if (len == 7) {
      return '${clean.substring(0, 3)} ${clean.substring(3)}';
    } else if (len == 8) {
      return '${clean.substring(0, 4)} ${clean.substring(4)}';
    } else if (len > 4 && len % 2 == 0) {
      final mid = len ~/ 2;
      return '${clean.substring(0, mid)} ${clean.substring(mid)}';
    }
    return clean;
  }

  /// Spells out digits separated by spaces for accessible screen-reader speech.
  static String spellingLabel(String rawCode) {
    final clean = rawCode.replaceAll(' ', '');
    return clean.split('').join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatted = formatCode(code);
    final semanticSpelling = spellingLabel(code);

    final defaultStyle = TextStyle(
      fontFamily: 'monospace',
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      fontSize: fontSize ?? 24.0,
      fontWeight: FontWeight.w700,
      letterSpacing: 2.0,
      color: isFaint
          ? theme.colorScheme.onSurface.withValues(alpha: 0.38)
          : theme.colorScheme.onSurface,
    );

    final effectiveStyle = style != null
        ? defaultStyle.merge(style)
        : defaultStyle;

    return Semantics(
      label: semanticSpelling,
      excludeSemantics: true,
      child: Text(formatted, style: effectiveStyle),
    );
  }
}
