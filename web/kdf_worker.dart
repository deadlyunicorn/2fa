import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:hashlib/hashlib.dart';

@JS('postMessage')
external void _postMessage(JSString message);

@JS('addEventListener')
external void _addEventListener(JSString type, JSFunction listener);

@JS('JSON.stringify')
external JSString _jsonStringify(JSAny? value);

extension type _MessageEvent(JSObject _) implements JSObject {
  external JSAny get data;
}

void _onMessage(_MessageEvent event) {
  try {
    final data = event.data;
    final String rawData;
    if (data.isA<JSString>()) {
      rawData = (data as JSString).toDart;
    } else {
      rawData = _jsonStringify(data).toDart;
    }
    final map = jsonDecode(rawData) as Map<String, dynamic>;
    final id = map['id'] as int;
    final password = map['password'] as String;
    final salt = base64Decode(map['salt'] as String);
    final memoryKiB = map['memoryKiB'] as int;
    final iterations = map['iterations'] as int;
    final parallelism = map['parallelism'] as int;
    final keyLength = map['keyLength'] as int;

    final argon2 = Argon2(
      type: Argon2Type.argon2id,
      version: Argon2Version.v13,
      salt: salt,
      parallelism: parallelism,
      memorySizeKB: memoryKiB,
      iterations: iterations,
      hashLength: keyLength,
    );
    final digest = argon2.convert(utf8.encode(password));
    final keyB64 = base64Encode(digest.bytes);
    final response = jsonEncode({'id': id, 'key': keyB64});
    _postMessage(response.toJS);
  } catch (e) {
    try {
      final response = jsonEncode({'error': e.toString()});
      _postMessage(response.toJS);
    } catch (_) {}
  }
}

void main() {
  _addEventListener('message'.toJS, _onMessage.toJS);
}
