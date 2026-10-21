import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'kdf.dart';

@JS('window')
external JSObject? get _window;

@JS('Blob')
extension type _Blob._(JSObject _) implements JSObject {
  external factory _Blob(JSArray<JSString> blobParts, [JSObject options]);
}

@JS('URL.createObjectURL')
external JSString _createObjectURL(JSObject obj);

@JS('URL.revokeObjectURL')
external void _revokeObjectURL(JSString url);

@JS('Worker')
extension type _Worker._(JSObject _) implements JSObject {
  external factory _Worker(JSString scriptUrl);
  external void postMessage(JSString message);
  external void terminate();
  external set onmessage(JSFunction? callback);
  external set onerror(JSFunction? callback);
}

extension type _MessageEvent(JSObject _) implements JSObject {
  external JSAny get data;
}

@JS('Reflect.get')
external JSAny? _reflectGet(JSObject target, JSString propertyKey);

@JS('Reflect.set')
external bool _reflectSet(JSObject target, JSString propertyKey, JSAny value);

/// Derives key on Web using a background Web Worker so the main UI thread never freezes.
///
/// Falls back gracefully to [deriveKeySync] on the main thread if Web Worker
/// creation is disallowed or fails.
Future<Uint8List> deriveKeyWeb(
  String password,
  Uint8List salt,
  KdfParams params,
) async {
  // Yield briefly to ensure Flutter renders the loading overlay / spinner
  await Future<void>.delayed(const Duration(milliseconds: 20));

  try {
    return await _deriveWithWorker(password, salt, params);
  } catch (_) {
    // Fallback to synchronous derivation on main thread if Web Worker cannot be instantiated
    return deriveKeySync(password, salt, params: params);
  }
}

Future<Uint8List> _deriveWithWorker(
  String password,
  Uint8List salt,
  KdfParams params,
) {
  final completer = Completer<Uint8List>();

  // Locate worker JS code from window.KDF_WORKER_CODE (set by offline_vfs.js or inline script)
  String? workerCode;
  final win = _window;
  if (win != null) {
    final codeAny = _reflectGet(win, 'KDF_WORKER_CODE'.toJS);
    if (codeAny != null && codeAny.isA<JSString>()) {
      workerCode = (codeAny as JSString).toDart;
    }
  }

  final _Worker worker;
  JSString? blobUrl;

  if (workerCode != null && workerCode.isNotEmpty) {
    final options = JSObject();
    _reflectSet(options, 'type'.toJS, 'application/javascript'.toJS);
    final blobParts = <JSString>[workerCode.toJS].toJS;
    final blob = _Blob(blobParts, options);
    blobUrl = _createObjectURL(blob);
    worker = _Worker(blobUrl);
  } else {
    // Fallback to relative script url on HTTP hosts
    worker = _Worker('kdf_worker.js'.toJS);
  }

  void cleanup() {
    try {
      worker.terminate();
    } catch (_) {}
    if (blobUrl != null) {
      try {
        _revokeObjectURL(blobUrl);
      } catch (_) {}
    }
  }

  worker.onmessage = ((_MessageEvent e) {
    try {
      final rawData = (e.data as JSString).toDart;
      final map = jsonDecode(rawData) as Map<String, dynamic>;
      if (map.containsKey('error')) {
        completer.completeError(StateError(map['error'] as String));
      } else {
        final keyB64 = map['key'] as String;
        completer.complete(base64Decode(keyB64));
      }
    } catch (err, st) {
      completer.completeError(err, st);
    } finally {
      cleanup();
    }
  }).toJS;

  worker.onerror = ((JSAny e) {
    cleanup();
    completer.completeError(StateError('KDF Web Worker error: $e'));
  }).toJS;

  final req = jsonEncode({
    'id': 1,
    'password': password,
    'salt': base64Encode(salt),
    'memoryKiB': params.memoryKiB,
    'iterations': params.iterations,
    'parallelism': params.parallelism,
    'keyLength': params.keyLength,
  });

  worker.postMessage(req.toJS);

  return completer.future;
}
