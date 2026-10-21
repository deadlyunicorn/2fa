// Offline 2FA Web Offline Bundler
// Generates offline_vfs.js, launcher scripts, and release tar.gz.

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

Future<void> main(List<String> args) async {
  final skipBuild = args.contains('--skip-build');
  final projectDir = Directory.current;
  final webBuildDir = Directory('${projectDir.path}/build/web');

  stdout.writeln('=== Offline 2FA Web Offline Bundler ===');

  if (!skipBuild) {
    stdout.writeln(
      'Building web release (--release --no-web-resources-cdn)...',
    );
    final buildProcess = await Process.run('flutter', [
      'build',
      'web',
      '--release',
      '--no-web-resources-cdn',
    ]);
    if (buildProcess.exitCode != 0) {
      stderr.writeln('Flutter web build failed:');
      stderr.writeln(buildProcess.stderr);
      exit(1);
    }
    stdout.writeln('Flutter web build completed successfully.');
  } else {
    stdout.writeln('Skipping Flutter web build as requested (--skip-build).');
  }

  if (!webBuildDir.existsSync()) {
    stderr.writeln(
      'Error: build/web directory does not exist at ${webBuildDir.path}',
    );
    exit(1);
  }

  // 1. Compile KDF Web Worker
  stdout.writeln(
    'Compiling KDF Web Worker (web/kdf_worker.dart -> build/web/kdf_worker.js)...',
  );
  final workerProcess = await Process.run('dart', [
    'compile',
    'js',
    '-O4',
    '--packages=.dart_tool/package_config.json',
    '-o',
    '${webBuildDir.path}/kdf_worker.js',
    '${projectDir.path}/web/kdf_worker.dart',
  ]);
  if (workerProcess.exitCode != 0) {
    stderr.writeln('Worker compilation failed:');
    stderr.writeln(workerProcess.stderr);
    exit(1);
  }
  final workerBuildFile = File('${webBuildDir.path}/kdf_worker.js');
  workerBuildFile.copySync('${projectDir.path}/web/kdf_worker.js');
  stdout.writeln(
    'KDF Web Worker compiled successfully (${workerBuildFile.lengthSync()} bytes).',
  );

  // 2. Sanitize build/web/index.html to remove any residual <base> tag
  final indexHtmlFile = File('${webBuildDir.path}/index.html');
  if (indexHtmlFile.existsSync()) {
    var indexHtml = indexHtmlFile.readAsStringSync();
    indexHtml = indexHtml.replaceAll(
      RegExp(r'<base\s+href="[^"]*"\s*/?>', caseSensitive: false),
      '',
    );
    indexHtmlFile.writeAsStringSync(indexHtml);
    stdout.writeln('Verified index.html has no <base> tag.');
  }

  // 2. Collect VFS assets
  stdout.writeln('Collecting assets and CanvasKit binaries for Offline VFS...');
  final vfsMap = <String, String>{};

  // Helper to add files relative to build/web
  void addFileToVfs(File file) {
    if (file.path.endsWith('.symbols')) return; // Skip debug symbol maps
    final relPath = file.path
        .substring(webBuildDir.path.length + 1)
        .replaceAll(r'\', '/');
    final bytes = file.readAsBytesSync();
    vfsMap[relPath] = base64Encode(bytes);
  }

  // Assets directory
  final assetsDir = Directory('${webBuildDir.path}/assets');
  if (assetsDir.existsSync()) {
    for (final entity in assetsDir.listSync(recursive: true)) {
      if (entity is File) {
        addFileToVfs(entity);
      }
    }
  }

  // CanvasKit directory - only include canvaskit engine files (skip skwasm/wimp/symbols)
  final canvaskitDir = Directory('${webBuildDir.path}/canvaskit');
  if (canvaskitDir.existsSync()) {
    for (final entity in canvaskitDir.listSync(recursive: true)) {
      if (entity is File) {
        final fileName = entity.uri.pathSegments
            .where((s) => s.isNotEmpty)
            .last;
        if (fileName.startsWith('canvaskit.') &&
            !fileName.endsWith('.symbols')) {
          addFileToVfs(entity);
        }
      }
    }
  }

  // Include kdf_worker.js in VFS as well
  if (workerBuildFile.existsSync()) {
    addFileToVfs(workerBuildFile);
  }

  stdout.writeln('Collected ${vfsMap.length} files into Offline VFS.');

  // 3. Generate build/web/offline_vfs.js
  stdout.writeln('Generating build/web/offline_vfs.js...');
  final vfsJsFile = File('${webBuildDir.path}/offline_vfs.js');
  final vfsJson = jsonEncode(vfsMap);
  final kdfWorkerCode = workerBuildFile.existsSync()
      ? workerBuildFile.readAsStringSync()
      : '';

  final vfsCode = StringBuffer();
  vfsCode.writeln('// Offline VFS & file:// Protocol Shim for Offline 2FA');
  vfsCode.writeln('window.OFFLINE_VFS = $vfsJson;');
  vfsCode.writeln('window.KDF_WORKER_CODE = ${jsonEncode(kdfWorkerCode)};');
  vfsCode.writeln(r'''
(function() {
  var isFile = (window.location.protocol === 'file:');

  function base64ToUint8(b64) {
    var bin = atob(b64);
    var len = bin.length;
    var bytes = new Uint8Array(len);
    for (var i = 0; i < len; i++) {
      bytes[i] = bin.charCodeAt(i);
    }
    return bytes;
  }

  function base64ToUtf8(b64) {
    var bytes = base64ToUint8(b64);
    if (typeof TextDecoder !== 'undefined') {
      return new TextDecoder('utf-8').decode(bytes);
    }
    var str = '';
    for (var i = 0; i < bytes.length; i++) {
      str += String.fromCharCode(bytes[i]);
    }
    return decodeURIComponent(escape(str));
  }

  function getMime(path) {
    if (path.endsWith('.wasm')) return 'application/wasm';
    if (path.endsWith('.js') || path.endsWith('.mjs')) return 'application/javascript';
    if (path.endsWith('.json')) return 'application/json';
    if (path.endsWith('.otf')) return 'font/otf';
    if (path.endsWith('.ttf')) return 'font/ttf';
    if (path.endsWith('.woff')) return 'font/woff';
    if (path.endsWith('.woff2')) return 'font/woff2';
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.jpg') || path.endsWith('.jpeg')) return 'image/jpeg';
    if (path.endsWith('.svg')) return 'image/svg+xml';
    if (path.endsWith('.frag') || path.endsWith('.vert') || path.endsWith('.txt')) return 'text/plain';
    return 'application/octet-stream';
  }

  function normalize(input) {
    var urlStr = (typeof input === 'string') ? input : (input && input.url) ? input.url : String(input);
    var clean = urlStr.split('?')[0].split('#')[0];
    if (clean.startsWith('file://')) {
      var baseDir = window.location.href.split('?')[0].split('#')[0];
      var lastSlash = baseDir.lastIndexOf('/');
      if (lastSlash >= 0) {
        baseDir = baseDir.substring(0, lastSlash + 1);
      }
      if (clean.startsWith(baseDir)) {
        clean = clean.substring(baseDir.length);
      } else {
        var idx = clean.indexOf('/assets/');
        if (idx !== -1) {
          clean = clean.substring(idx + 1);
        } else {
          idx = clean.indexOf('/canvaskit/');
          if (idx !== -1) {
            clean = clean.substring(idx + 1);
          }
        }
      }
    }
    return clean.replace(/^\.?\//, '');
  }

  function lookup(path) {
    if (!window.OFFLINE_VFS) return null;
    var norm = normalize(path);
    if (window.OFFLINE_VFS[norm]) return { key: norm, data: window.OFFLINE_VFS[norm] };
    var decoded = decodeURIComponent(norm);
    if (window.OFFLINE_VFS[decoded]) return { key: decoded, data: window.OFFLINE_VFS[decoded] };
    var keys = Object.keys(window.OFFLINE_VFS);
    for (var i = 0; i < keys.length; i++) {
      if (norm.endsWith(keys[i]) || decoded.endsWith(keys[i])) {
        return { key: keys[i], data: window.OFFLINE_VFS[keys[i]] };
      }
    }
    return null;
  }

  if (isFile) {
    // 1. Intercept window.fetch
    var origFetch = window.fetch;
    window.fetch = function(input, init) {
      try {
        var item = lookup(input);
        if (item) {
          var bytes = base64ToUint8(item.data);
          var mime = getMime(item.key);
          var res = new Response(bytes.buffer, {
            status: 200,
            statusText: 'OK',
            headers: {
              'Content-Type': mime,
              'Content-Length': String(bytes.length)
            }
          });
          return Promise.resolve(res);
        }
      } catch (err) {
        console.warn('[OfflineVFS] Fetch intercept notice:', err);
      }
      return origFetch ? origFetch.apply(window, arguments) : Promise.reject(new Error('Fetch failed'));
    };

    // 2. Fallback for WebAssembly.compileStreaming
    if (typeof WebAssembly !== 'undefined' && WebAssembly.compileStreaming) {
      var origCompileStreaming = WebAssembly.compileStreaming;
      WebAssembly.compileStreaming = async function(responsePromise) {
        try {
          var r = await responsePromise;
          return await origCompileStreaming(Promise.resolve(r));
        } catch (_) {
          var r = await responsePromise;
          var buf = await r.arrayBuffer();
          return await WebAssembly.compile(buf);
        }
      };
    }

    // 3. Prevent Service Worker exceptions on file://
    if ('serviceWorker' in navigator) {
      try {
        Object.defineProperty(navigator, 'serviceWorker', {
          get: function() {
            return {
              register: function() { return Promise.reject(new Error('ServiceWorker disabled on file://')); },
              getRegistration: function() { return Promise.resolve(null); },
              getRegistrations: function() { return Promise.resolve([]); },
              addEventListener: function() {},
              removeEventListener: function() {},
            };
          },
          configurable: true,
        });
      } catch (_) {}
    }

    // 4. Wrap _flutter loader to omit serviceWorkerSettings on file://
    window._flutter = window._flutter || {};
    var _realLoader = null;
    Object.defineProperty(window._flutter, 'loader', {
      get: function() { return _realLoader; },
      set: function(val) {
        _realLoader = val;
        if (_realLoader && typeof _realLoader.load === 'function') {
          var origLoad = _realLoader.load.bind(_realLoader);
          _realLoader.load = function(options) {
            options = options || {};
            delete options.serviceWorkerSettings;
            return origLoad(options);
          };
        }
      },
      configurable: true,
    });

    // 5. Pre-initialize CanvasKit
    window._offlineVfsReady = (async function() {
      try {
        var isBlink = navigator.vendor === 'Google Inc.' || navigator.userAgent.includes('Edg/');
        var hasImageCodecs = (typeof ImageDecoder !== 'undefined') && isBlink;
        var hasChromiumBreakIterators = (typeof Intl.v8BreakIterator !== 'undefined') && (typeof Intl.Segmenter !== 'undefined');
        var useChromium = hasImageCodecs && hasChromiumBreakIterators;

        var jsKey = useChromium ? 'canvaskit/chromium/canvaskit.js' : 'canvaskit/canvaskit.js';
        var wasmKey = useChromium ? 'canvaskit/chromium/canvaskit.wasm' : 'canvaskit/canvaskit.wasm';

        if (!window.OFFLINE_VFS[jsKey]) jsKey = 'canvaskit/canvaskit.js';
        if (!window.OFFLINE_VFS[wasmKey]) wasmKey = 'canvaskit/canvaskit.wasm';

        if (window.OFFLINE_VFS[jsKey] && window.OFFLINE_VFS[wasmKey]) {
          var jsText = base64ToUtf8(window.OFFLINE_VFS[jsKey]);
          var wasmBytes = base64ToUint8(window.OFFLINE_VFS[wasmKey]);
          var wasmModule = await WebAssembly.compile(wasmBytes);

          var instantiateWasm = function(imports, successCallback) {
            WebAssembly.instantiate(wasmModule, imports).then(function(instance) {
              successCallback(instance, wasmModule);
            });
            return {};
          };

          var blob = new Blob([jsText], { type: 'application/javascript' });
          var blobUrl = URL.createObjectURL(blob);
          var mod = await import(blobUrl);
          URL.revokeObjectURL(blobUrl);

          var ckInit = mod.default || mod.CanvasKitInit || window.CanvasKitInit;
          if (typeof ckInit === 'function') {
            window.flutterCanvasKit = await ckInit({ instantiateWasm: instantiateWasm });
          }
        }
      } catch (err) {
        console.warn('[OfflineVFS] CanvasKit pre-init warning:', err);
      }
    })();
  } else {
    window._offlineVfsReady = Promise.resolve();
  }
})();
''');

  vfsJsFile.writeAsStringSync(vfsCode.toString());
  stdout.writeln('Generated offline_vfs.js (${vfsJsFile.lengthSync()} bytes).');

  // 4. Create launcher scripts in build/web
  stdout.writeln('Creating launcher scripts...');

  final runSh = File('${webBuildDir.path}/run-offline-web.sh');
  runSh.writeAsStringSync('''#!/usr/bin/env bash
set -e
cd "\$(dirname "\$0")"

PORT=8080
HOST="127.0.0.1"
URL="http://\${HOST}:\${PORT}/index.html"

echo "=========================================================="
echo " Offline 2FA - Local Web Runner"
echo " Strictly bound to \${HOST} (localhost only, NO network access)"
echo " Serving from: \$(pwd)"
echo " URL: \${URL}"
echo " Press Ctrl+C to stop the server."
echo "=========================================================="

if command -v xdg-open >/dev/null 2>&1; then
  (sleep 1 && xdg-open "\${URL}") &
elif command -v open >/dev/null 2>&1; then
  (sleep 1 && open "\${URL}") &
fi

if command -v python3 >/dev/null 2>&1; then
  exec python3 -m http.server \${PORT} --bind \${HOST}
elif command -v python >/dev/null 2>&1; then
  exec python -m http.server \${PORT} --bind \${HOST}
else
  echo "Error: python3 is required to run the local server."
  exit 1
fi
''');
  Process.runSync('chmod', ['+x', runSh.path]);

  final runBat = File('${webBuildDir.path}/run-offline-web.bat');
  runBat.writeAsStringSync('''@echo off
cd /d "%~dp0"
echo ==========================================================
echo  Offline 2FA - Local Web Runner
echo  Strictly bound to 127.0.0.1 (localhost only, NO network)
echo  URL: http://127.0.0.1:8080/index.html
echo  Press Ctrl+C to stop the server.
echo ==========================================================
start http://127.0.0.1:8080/index.html
python -m http.server 8080 --bind 127.0.0.1
if errorlevel 1 (
  python3 -m http.server 8080 --bind 127.0.0.1
)
pause
''');

  // 5. Package into release tar.gz with staging directory
  stdout.writeln('Packaging into offline2fa-v0.1.0-web-offline.tar.gz...');
  final stagingDir = Directory(
    '${projectDir.path}/build/offline_web_staging/offline2fa-v0.1.0-web-offline',
  );
  if (stagingDir.existsSync()) {
    stagingDir.deleteSync(recursive: true);
  }
  stagingDir.createSync(recursive: true);

  // Copy build/web into stagingDir
  copyDirectorySync(webBuildDir, stagingDir);

  final tarGzPath =
      '${projectDir.path}/build/offline2fa-v0.1.0-web-offline.tar.gz';
  final tarResult = Process.runSync('tar', [
    '-czf',
    tarGzPath,
    '-C',
    '${projectDir.path}/build/offline_web_staging',
    'offline2fa-v0.1.0-web-offline',
  ]);

  if (tarResult.exitCode != 0) {
    stderr.writeln('Failed to create tar.gz: ${tarResult.stderr}');
    exit(1);
  }

  final tarGzFile = File(tarGzPath);
  final tarGzBytes = tarGzFile.readAsBytesSync();
  final newSha256 = sha256.convert(tarGzBytes).toString();
  stdout.writeln('Created archive: $tarGzPath (${tarGzBytes.length} bytes)');
  stdout.writeln('New SHA-256: $newSha256');

  // 6. Update build/SHA256SUMS.txt
  final sumsFile = File('${projectDir.path}/build/SHA256SUMS.txt');
  if (sumsFile.existsSync()) {
    var sumsContent = sumsFile.readAsStringSync();
    sumsContent = sumsContent.replaceAll(
      RegExp(
        r'^[0-9a-f]{64}\s+offline2fa-v0\.1\.0-web-offline\.tar\.gz',
        multiLine: true,
      ),
      '$newSha256  offline2fa-v0.1.0-web-offline.tar.gz',
    );
    sumsFile.writeAsStringSync(sumsContent);
    stdout.writeln('Updated build/SHA256SUMS.txt');
  }

  // 7. Update build/RELEASE_NOTES.md
  final releaseNotesFile = File('${projectDir.path}/build/RELEASE_NOTES.md');
  if (releaseNotesFile.existsSync()) {
    var notesContent = releaseNotesFile.readAsStringSync();
    notesContent = notesContent.replaceAll(
      RegExp(
        r'^[0-9a-f]{64}\s+offline2fa-v0\.1\.0-web-offline\.tar\.gz',
        multiLine: true,
      ),
      '$newSha256  offline2fa-v0.1.0-web-offline.tar.gz',
    );
    releaseNotesFile.writeAsStringSync(notesContent);
    stdout.writeln('Updated build/RELEASE_NOTES.md');
  }

  // Clean staging
  try {
    Directory('${projectDir.path}/build/offline_web_staging')
        .deleteSync(recursive: true);
  } catch (_) {}

  stdout.writeln('=== Done! ===');
}

void copyDirectorySync(Directory source, Directory destination) {
  if (!destination.existsSync()) {
    destination.createSync(recursive: true);
  }
  for (final entity in source.listSync(recursive: false)) {
    final newPath =
        '${destination.path}/${entity.uri.pathSegments.where((s) => s.isNotEmpty).last}';
    if (entity is Directory) {
      copyDirectorySync(entity, Directory(newPath));
    } else if (entity is File) {
      entity.copySync(newPath);
    }
  }
}
