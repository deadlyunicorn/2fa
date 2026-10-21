import 'package:flutter/material.dart';

/// Deterministic letter avatar for OTP account issuers (§1.3, §7.2).
///
/// Displays the first character of [issuer] (or [account] if [issuer] is empty,
/// or `'?'` if both are empty) in uppercase.
/// The background color is deterministically derived from a hash of the issuer,
/// and the text color provides accessible contrast.
class LetterAvatar extends StatelessWidget {
  const LetterAvatar({
    super.key,
    required this.issuer,
    this.account = '',
    this.size = 40.0,
    this.fontSize,
  });

  /// The service provider or issuer name (e.g., "GitHub").
  final String issuer;

  /// Fallback account name if issuer is empty (e.g., "alice@example.com").
  final String account;

  /// Diameter of the avatar circle in logical pixels.
  final double size;

  /// Optional font size for the letter. Defaults to `size * 0.45`.
  final double? fontSize;

  static const List<Color> _avatarColors = <Color>[
    Color(0xFFE53935), // Red 600
    Color(0xFFD81B60), // Pink 600
    Color(0xFF8E24AA), // Purple 600
    Color(0xFF5E35B1), // Deep Purple 600
    Color(0xFF3949AB), // Indigo 600
    Color(0xFF1E88E5), // Blue 600
    Color(0xFF0288D1), // Light Blue 700
    Color(0xFF00897B), // Teal 600
    Color(0xFF2E7D32), // Green 800
    Color(0xFF558B2F), // Light Green 800
    Color(0xFFEF6C00), // Orange 800
    Color(0xFFD84315), // Deep Orange 800
    Color(0xFF4E342E), // Brown 800
    Color(0xFF455A64), // Blue Grey 700
    Color(0xFF00838F), // Cyan 800
    Color(0xFF283593), // Indigo 800
  ];

  static String _extractLetter(String issuer, String account) {
    final trimmedIssuer = issuer.trim();
    if (trimmedIssuer.isNotEmpty) {
      return trimmedIssuer.characters.first.toUpperCase();
    }
    final trimmedAccount = account.trim();
    if (trimmedAccount.isNotEmpty) {
      return trimmedAccount.characters.first.toUpperCase();
    }
    return '?';
  }

  static Color _hashColor(String issuer, String account) {
    final key = issuer.trim().isNotEmpty
        ? issuer.trim().toLowerCase()
        : account.trim().toLowerCase();
    if (key.isEmpty) {
      return const Color(0xFF757575);
    }
    var hash = 5381;
    for (final code in key.codeUnits) {
      hash = ((hash << 5) + hash) + code;
      hash &= 0x7FFFFFFF;
    }
    return _avatarColors[hash % _avatarColors.length];
  }

  @override
  Widget build(BuildContext context) {
    final letter = _extractLetter(issuer, account);
    final backgroundColor = _hashColor(issuer, account);
    final brightness = ThemeData.estimateBrightnessForColor(backgroundColor);
    final textColor = brightness == Brightness.dark
        ? Colors.white
        : Colors.black;
    final effectiveFontSize = fontSize ?? (size * 0.45);

    final semanticName = issuer.trim().isNotEmpty
        ? issuer.trim()
        : (account.trim().isNotEmpty ? account.trim() : 'Account');

    return Semantics(
      label: 'Avatar for $semanticName',
      excludeSemantics: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(
          letter,
          style: TextStyle(
            color: textColor,
            fontSize: effectiveFontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
