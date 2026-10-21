import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/otp/otpauth_uri.dart';
import '../../core/platform/platform_caps.dart';
import 'add_entry_screen.dart';

/// Signature for custom scanner builder used in widget testing.
typedef ScannerBuilder = Widget Function(
  BuildContext context,
  void Function(BarcodeCapture capture) onDetect,
);

/// Camera QR scanner screen for mobile devices (§7.1 #6, §8, §9 M6).
///
/// Strictly guarded by [supportsCamera] to avoid loading camera plugins on desktop.
class ScanQrScreen extends ConsumerStatefulWidget {
  const ScanQrScreen({super.key, this.scannerBuilder});

  /// Optional custom builder for testing without native camera access.
  final ScannerBuilder? scannerBuilder;

  @override
  ConsumerState<ScanQrScreen> createState() => _ScanQrScreenState();
}

class _ScanQrScreenState extends ConsumerState<ScanQrScreen> {
  MobileScannerController? _controller;
  bool _isProcessing = false;
  DateTime? _lastErrorTime;

  @override
  void initState() {
    super.initState();
    // Guard strictly against instantiating MobileScannerController on unsupported platforms (§8).
    if (supportsCamera && widget.scannerBuilder == null) {
      _controller = MobileScannerController(
        formats: const <BarcodeFormat>[BarcodeFormat.qrCode],
        detectionSpeed: DetectionSpeed.normal,
      );
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _showThrottledError(String message) {
    final now = DateTime.now();
    if (_lastErrorTime != null &&
        now.difference(_lastErrorTime!) < const Duration(seconds: 2)) {
      return;
    }
    _lastErrorTime = now;
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  void _onDetect(BarcodeCapture capture) {
    if (_isProcessing) return;

    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue;
      if (rawValue == null || rawValue.trim().isEmpty) continue;
      final trimmed = rawValue.trim();

      if (trimmed.toLowerCase().startsWith('otpauth-migration:')) {
        _showThrottledError('Not supported yet');
        continue;
      }

      try {
        final entry = OtpAuthUri.parse(trimmed);
        _isProcessing = true;
        unawaited(_controller?.stop());
        if (mounted) {
          context.pushReplacement('/add/manual', extra: entry);
        }
        return;
      } on MigrationNotSupportedException {
        _showThrottledError('Not supported yet');
      } on OtpAuthUriException {
        _showThrottledError('Invalid 2FA QR code');
      } catch (_) {
        _showThrottledError('Invalid 2FA QR code');
      }
    }
  }

  Future<void> _handleGalleryImport() async {
    await _controller?.stop();
    if (!mounted) return;
    await handleImageQrImport(context, ref, replace: true);
    if (mounted && !_isProcessing) {
      unawaited(_controller?.start());
    }
  }

  @override
  Widget build(BuildContext context) {
    // If camera is unsupported and no test builder is provided, show fallback (§8).
    if (!supportsCamera && widget.scannerBuilder == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Scan QR Code')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(Icons.videocam_off_outlined, size: 48.0),
                const SizedBox(height: 16.0),
                const Text(
                  'Camera scanning is not supported on this platform.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16.0),
                FilledButton.icon(
                  onPressed: () => context.go('/add/manual'),
                  icon: const Icon(Icons.edit_note_outlined),
                  label: const Text('Enter Manually'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final theme = Theme.of(context);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Scan QR Code'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        actions: <Widget>[
          if (_controller != null)
            ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller!,
              builder: (BuildContext context, MobileScannerState state, _) {
                final isTorchOn = state.torchState == TorchState.on;
                return IconButton(
                  icon: Icon(isTorchOn ? Icons.flash_on : Icons.flash_off),
                  tooltip: isTorchOn ? 'Turn off flash' : 'Turn on flash',
                  onPressed: () => _controller?.toggleTorch(),
                );
              },
            ),
          IconButton(
            icon: const Icon(Icons.image_outlined),
            tooltip: 'Import QR from image',
            onPressed: _handleGalleryImport,
          ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          if (widget.scannerBuilder != null)
            widget.scannerBuilder!(context, _onDetect)
          else if (_controller != null)
            MobileScanner(controller: _controller, onDetect: _onDetect),
          IgnorePointer(
            child: CustomPaint(
              painter: _ScanOverlayPainter(
                borderColor: theme.colorScheme.primary,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            left: 24.0,
            right: 24.0,
            bottom: 60.0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16.0,
                    vertical: 8.0,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20.0),
                  ),
                  child: const Text(
                    'Align QR code within the frame',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14.0,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for the camera scan reticle overlay.
class _ScanOverlayPainter extends CustomPainter {
  const _ScanOverlayPainter({required this.borderColor});

  final Color borderColor;

  @override
  void paint(Canvas canvas, Size size) {
    final scanSize = math.min(size.width, size.height) * 0.7;
    final left = (size.width - scanSize) / 2;
    final top = (size.height - scanSize) / 2;
    final scanRect = Rect.fromLTWH(left, top, scanSize, scanSize);

    // Dark semi-transparent background around viewfinder
    final backgroundPath = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final cutoutPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(scanRect, const Radius.circular(16.0)),
      );
    final overlayPath = Path.combine(
      PathOperation.difference,
      backgroundPath,
      cutoutPath,
    );

    final bgPaint = Paint()..color = Colors.black.withValues(alpha: 0.5);
    canvas.drawPath(overlayPath, bgPaint);

    // Corner brackets
    final cornerPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    const cornerLength = 24.0;
    const radius = 16.0;

    // Top-left
    canvas.drawPath(
      Path()
        ..moveTo(left, top + cornerLength)
        ..lineTo(left, top + radius)
        ..arcToPoint(
          Offset(left + radius, top),
          radius: const Radius.circular(radius),
        )
        ..lineTo(left + cornerLength, top),
      cornerPaint,
    );

    // Top-right
    canvas.drawPath(
      Path()
        ..moveTo(left + scanSize - cornerLength, top)
        ..lineTo(left + scanSize - radius, top)
        ..arcToPoint(
          Offset(left + scanSize, top + radius),
          radius: const Radius.circular(radius),
        )
        ..lineTo(left + scanSize, top + cornerLength),
      cornerPaint,
    );

    // Bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(left, top + scanSize - cornerLength)
        ..lineTo(left, top + scanSize - radius)
        ..arcToPoint(
          Offset(left + radius, top + scanSize),
          radius: const Radius.circular(radius),
        )
        ..lineTo(left + cornerLength, top + scanSize),
      cornerPaint,
    );

    // Bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(left + scanSize - cornerLength, top + scanSize)
        ..lineTo(left + scanSize - radius, top + scanSize)
        ..arcToPoint(
          Offset(left + scanSize, top + scanSize - radius),
          radius: const Radius.circular(radius),
        )
        ..lineTo(left + scanSize, top + scanSize - cornerLength),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScanOverlayPainter oldDelegate) =>
      oldDelegate.borderColor != borderColor;
}
