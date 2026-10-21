import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:offline2fa/core/otp/base32.dart';

void main() {
  group('Base32Codec', () {
    group('RFC 4648 test vectors (encode & decode)', () {
      final vectors = <String, String>{
        '': '',
        'f': 'MY',
        'fo': 'MZXQ',
        'foo': 'MZXW6',
        'foob': 'MZXW6YQ',
        'fooba': 'MZXW6YTB',
        'foobar': 'MZXW6YTBOI',
      };

      for (final entry in vectors.entries) {
        test('encode "${entry.key}" -> "${entry.value}"', () {
          final inputBytes = utf8.encode(entry.key);
          final encoded = Base32Codec.encode(inputBytes);
          expect(encoded, equals(entry.value));
        });

        if (entry.key.isNotEmpty) {
          test('decode "${entry.value}" -> "${entry.key}"', () {
            final decoded = Base32Codec.decode(entry.value);
            expect(utf8.decode(decoded), equals(entry.key));
          });
        }
      }
    });

    group('Lenient decoding', () {
      test('accepts lowercase input', () {
        expect(utf8.decode(Base32Codec.decode('my')), equals('f'));
        expect(utf8.decode(Base32Codec.decode('mzxq')), equals('fo'));
        expect(utf8.decode(Base32Codec.decode('mzxw6ytboi')), equals('foobar'));
      });

      test('strips spaces and hyphens', () {
        expect(utf8.decode(Base32Codec.decode('M Z X W 6')), equals('foo'));
        expect(
          utf8.decode(Base32Codec.decode('mzxw-6ytb-oi')),
          equals('foobar'),
        );
        expect(utf8.decode(Base32Codec.decode('  M Z-X-W 6  ')), equals('foo'));
      });

      test('strips standard RFC 4648 padding', () {
        expect(utf8.decode(Base32Codec.decode('MY======')), equals('f'));
        expect(utf8.decode(Base32Codec.decode('MZXQ====')), equals('fo'));
        expect(utf8.decode(Base32Codec.decode('MZXW6===')), equals('foo'));
        expect(utf8.decode(Base32Codec.decode('MZXW6YQ=')), equals('foob'));
        expect(utf8.decode(Base32Codec.decode('MZXW6YTB')), equals('fooba'));
        expect(
          utf8.decode(Base32Codec.decode('MZXW6YTBOI======')),
          equals('foobar'),
        );
      });

      test('combined lowercase, padding, spaces, hyphens', () {
        expect(
          utf8.decode(Base32Codec.decode(' mzxw - 6ytb - oi === ')),
          equals('foobar'),
        );
      });
    });

    group('Empty input rejection', () {
      test('empty string throws FormatException', () {
        expect(() => Base32Codec.decode(''), throwsA(isA<FormatException>()));
      });

      test('string with only whitespace throws FormatException', () {
        expect(
          () => Base32Codec.decode('   '),
          throwsA(isA<FormatException>()),
        );
      });

      test('string with only hyphens throws FormatException', () {
        expect(
          () => Base32Codec.decode('---'),
          throwsA(isA<FormatException>()),
        );
      });

      test('string with only padding throws FormatException', () {
        expect(
          () => Base32Codec.decode('======'),
          throwsA(isA<FormatException>()),
        );
      });

      test('string with mixture of space, hyphen, and padding throws FormatException', () {
        expect(
          () => Base32Codec.decode(' - = = - '),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('Invalid character rejection', () {
      test('rejects 0, 1, 8, 9', () {
        expect(
          () => Base32Codec.decode('MY0'),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => Base32Codec.decode('MY1'),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => Base32Codec.decode('MY8'),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => Base32Codec.decode('MY9'),
          throwsA(isA<FormatException>()),
        );
      });

      test(
        'rejects symbols and punctuation other than hyphens and padding',
        () {
          expect(
            () => Base32Codec.decode('MY@'),
            throwsA(isA<FormatException>()),
          );
          expect(
            () => Base32Codec.decode('MY!'),
            throwsA(isA<FormatException>()),
          );
          expect(
            () => Base32Codec.decode('MY#'),
            throwsA(isA<FormatException>()),
          );
          expect(
            () => Base32Codec.decode('MY\$'),
            throwsA(isA<FormatException>()),
          );
          expect(
            () => Base32Codec.decode('MY/'),
            throwsA(isA<FormatException>()),
          );
        },
      );
    });

    group('Invalid length rejection', () {
      test('rejects lengths mod 8 == 1, 3, 6', () {
        expect(() => Base32Codec.decode('M'), throwsA(isA<FormatException>()));
        expect(
          () => Base32Codec.decode('MZX'),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => Base32Codec.decode('MZXW6Y'),
          throwsA(isA<FormatException>()),
        );
      });
    });

    group('normalize and isValid', () {
      test('normalize standardizes and strips noise', () {
        expect(
          Base32Codec.normalize('jbsw y3dp-ehpk 3pxp='),
          equals('JBSWY3DPEHPK3PXP'),
        );
      });

      test('normalize throws on invalid input', () {
        expect(
          () => Base32Codec.normalize('invalid0'),
          throwsA(isA<FormatException>()),
        );
        expect(
          () => Base32Codec.normalize(''),
          throwsA(isA<FormatException>()),
        );
      });

      test('isValid returns true for valid Base32', () {
        expect(Base32Codec.isValid('JBSWY3DPEHPK3PXP'), isTrue);
        expect(Base32Codec.isValid('jbsw y3dp-ehpk 3pxp='), isTrue);
        expect(Base32Codec.isValid('MY'), isTrue);
      });

      test('isValid returns false for invalid Base32', () {
        expect(Base32Codec.isValid(''), isFalse);
        expect(Base32Codec.isValid('0189'), isFalse);
        expect(Base32Codec.isValid('M'), isFalse);
        expect(Base32Codec.isValid('MZX'), isFalse);
      });
    });

    group('Round trip arbitrary byte lengths', () {
      for (var length = 1; length <= 40; length++) {
        test('round trip $length bytes', () {
          final original = Uint8List(length);
          for (var i = 0; i < length; i++) {
            original[i] = (i * 37 + 13) & 0xff;
          }

          final encoded = Base32Codec.encode(original);
          final decoded = Base32Codec.decode(encoded);
          expect(decoded, equals(original));
        });
      }
    });

    test('Base32 typedef works interchangeably', () {
      expect(Base32.encode(utf8.encode('foo')), equals('MZXW6'));
      expect(utf8.decode(Base32.decode('MZXW6')), equals('foo'));
    });
  });
}
