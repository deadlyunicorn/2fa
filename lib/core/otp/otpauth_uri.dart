import 'package:uuid/uuid.dart';

import '../models/otp_algorithm.dart';
import '../models/otp_entry.dart';
import '../models/otp_type.dart';
import 'base32.dart';

/// Base exception for otpauth URI errors.
abstract class OtpAuthUriException implements Exception {
  const OtpAuthUriException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Thrown when an `otpauth-migration://` URI is encountered.
class MigrationNotSupportedException extends OtpAuthUriException {
  const MigrationNotSupportedException([
    super.message = 'otpauth-migration URIs are not supported yet',
  ]);
}

/// Alias for [MigrationNotSupportedException].
typedef MigrationNotSupported = MigrationNotSupportedException;

/// Thrown when an `otpauth://` URI is malformed or invalid.
class InvalidOtpAuthUriException extends OtpAuthUriException {
  const InvalidOtpAuthUriException(super.message);
}

/// Parser and serializer for `otpauth://` URIs (Key Uri Format).
class OtpAuthUri {
  const OtpAuthUri();

  static const _uuid = Uuid();

  /// Parses an `otpauth://` URI into an [OtpEntry].
  ///
  /// Throws [MigrationNotSupportedException] if the scheme is `otpauth-migration`.
  /// Throws [InvalidOtpAuthUriException] if the URI is invalid, missing required fields,
  /// or contains invalid parameters.
  static OtpEntry parse(String uriString, {String? id}) {
    final trimmed = uriString.trim();

    if (trimmed.toLowerCase().startsWith('otpauth-migration:')) {
      throw const MigrationNotSupportedException();
    }

    final Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } on FormatException catch (e) {
      throw InvalidOtpAuthUriException('Malformed URI: ${e.message}');
    }

    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'otpauth-migration') {
      throw const MigrationNotSupportedException();
    }
    if (scheme != 'otpauth') {
      throw InvalidOtpAuthUriException(
        'Unsupported URI scheme "$scheme", expected "otpauth"',
      );
    }

    // Determine type (totp or hotp)
    final String typeStr;
    if (uri.host.isNotEmpty) {
      typeStr = uri.host;
    } else if (uri.pathSegments.isNotEmpty) {
      typeStr = uri.pathSegments[0];
    } else {
      throw const InvalidOtpAuthUriException('Missing OTP type in URI');
    }

    final OtpType type;
    try {
      type = OtpType.fromString(typeStr);
    } on FormatException catch (e) {
      throw InvalidOtpAuthUriException('Unsupported OTP type: ${e.message}');
    }

    // Extract label
    final String rawLabel;
    if (uri.host.isNotEmpty) {
      rawLabel = uri.path.startsWith('/') ? uri.path.substring(1) : uri.path;
    } else {
      rawLabel = uri.pathSegments.length > 1
          ? uri.pathSegments.sublist(1).join('/')
          : '';
    }

    final decodedLabel = Uri.decodeComponent(rawLabel).trim();
    final firstColon = decodedLabel.indexOf(':');
    final String issuerFromLabel;
    final String account;
    if (firstColon != -1) {
      issuerFromLabel = decodedLabel.substring(0, firstColon).trim();
      account = decodedLabel.substring(firstColon + 1).trim();
    } else {
      issuerFromLabel = '';
      account = decodedLabel.trim();
    }

    // Issuer query param takes precedence over label issuer
    final queryIssuer = uri.queryParameters['issuer']?.trim();
    final issuer = (queryIssuer != null && queryIssuer.isNotEmpty)
        ? queryIssuer
        : issuerFromLabel;

    // Secret is required and must be valid Base32
    final rawSecret = uri.queryParameters['secret'];
    if (rawSecret == null || rawSecret.trim().isEmpty) {
      throw const InvalidOtpAuthUriException(
        'Secret query parameter is required',
      );
    }
    final String secret;
    try {
      secret = Base32Codec.normalize(rawSecret);
    } on FormatException catch (e) {
      throw InvalidOtpAuthUriException('Invalid Base32 secret: ${e.message}');
    }

    // Algorithm (defaults to SHA1)
    final rawAlgo = uri.queryParameters['algorithm'];
    final OtpAlgorithm algorithm;
    if (rawAlgo != null && rawAlgo.trim().isNotEmpty) {
      try {
        algorithm = OtpAlgorithm.fromString(rawAlgo);
      } on FormatException catch (e) {
        throw InvalidOtpAuthUriException('Invalid algorithm: ${e.message}');
      }
    } else {
      algorithm = OtpAlgorithm.sha1;
    }

    // Digits (defaults to 6, 6..8 allowed)
    final rawDigits = uri.queryParameters['digits'];
    final int digits;
    if (rawDigits != null && rawDigits.trim().isNotEmpty) {
      final parsedDigits = int.tryParse(rawDigits.trim());
      if (parsedDigits == null || parsedDigits < 6 || parsedDigits > 8) {
        throw const InvalidOtpAuthUriException(
          'Digits parameter must be 6, 7, or 8',
        );
      }
      digits = parsedDigits;
    } else {
      digits = 6;
    }

    // Period (defaults to 30, 1..300 allowed)
    final rawPeriod = uri.queryParameters['period'];
    final int period;
    if (rawPeriod != null && rawPeriod.trim().isNotEmpty) {
      final parsedPeriod = int.tryParse(rawPeriod.trim());
      if (parsedPeriod == null || parsedPeriod < 1 || parsedPeriod > 300) {
        throw const InvalidOtpAuthUriException(
          'Period parameter must be between 1 and 300',
        );
      }
      period = parsedPeriod;
    } else {
      period = 30;
    }

    // Counter (required for HOTP, must be >= 0)
    final rawCounter = uri.queryParameters['counter'];
    final int counter;
    if (type == OtpType.hotp) {
      if (rawCounter == null || rawCounter.trim().isEmpty) {
        throw const InvalidOtpAuthUriException(
          'Counter parameter is required for HOTP',
        );
      }
      final parsedCounter = int.tryParse(rawCounter.trim());
      if (parsedCounter == null || parsedCounter < 0) {
        throw const InvalidOtpAuthUriException(
          'Counter parameter must be an integer >= 0',
        );
      }
      counter = parsedCounter;
    } else {
      counter =
          (rawCounter != null ? int.tryParse(rawCounter.trim()) : null) ?? 0;
    }

    final entryId = id ?? _uuid.v4();
    final now = DateTime.now().toUtc();

    return OtpEntry(
      id: entryId,
      type: type,
      issuer: issuer,
      account: account,
      secret: secret,
      algorithm: algorithm,
      digits: digits,
      period: period,
      counter: counter,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Serializes an [OtpEntry] into an `otpauth://` URI string.
  ///
  /// Conforms to Google Authenticator Key Uri Format.
  static String serialize(OtpEntry entry) {
    final String label;
    if (entry.issuer.isNotEmpty) {
      final encodedIssuer = Uri.encodeComponent(entry.issuer);
      final encodedAccount = Uri.encodeComponent(entry.account);
      label = '$encodedIssuer:$encodedAccount';
    } else {
      label = Uri.encodeComponent(entry.account);
    }

    final queryParams = <String, String>{'secret': entry.secret};

    if (entry.issuer.isNotEmpty) {
      queryParams['issuer'] = entry.issuer;
    }

    queryParams['algorithm'] = entry.algorithm.nameValue;
    queryParams['digits'] = entry.digits.toString();

    if (entry.type == OtpType.totp) {
      queryParams['period'] = entry.period.toString();
    } else if (entry.type == OtpType.hotp) {
      queryParams['counter'] = entry.counter.toString();
    }

    final queryString = queryParams.entries
        .map(
          (e) =>
              '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}',
        )
        .join('&');

    return 'otpauth://${entry.type.nameValue}/$label?$queryString';
  }
}
