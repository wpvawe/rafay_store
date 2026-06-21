import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:url_launcher/url_launcher.dart';

/// Full-screen barcode / QR-code scanner.
///
/// Plays a professional beep sound on successful scan (via audioplayers).
/// Falls back silently if audio is unavailable.
///
/// Usage:
/// ```dart
/// final code = await Navigator.push<String>(
///   context,
///   MaterialPageRoute(builder: (_) => const BarcodeScannerScreen()),
/// );
/// if (code != null) { /* use code */ }
/// ```
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({super.key});

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen>
    with TickerProviderStateMixin {
  late final MobileScannerController _controller;
  late final AnimationController _lineAnim;
  late final Animation<double> _lineTween;

  // Audio player — one-shot, low-latency mode
  final AudioPlayer _audioPlayer = AudioPlayer();

  bool _torchOn = false;
  bool _scanned = false;
  String? _lastCode;
  String? _lastFormat;
  Timer? _resetTimer;

  // Manual-entry controller
  final _manualCtrl = TextEditingController();
  bool _showManual = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );

    _lineAnim = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _lineTween = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _lineAnim, curve: Curves.easeInOut),
    );

    // Pre-warm the audio player so first beep has no delay
    _prewarmAudio();
  }

  /// Load the beep asset once so the first scan fires instantly.
  Future<void> _prewarmAudio() async {
    try {
      await _audioPlayer.setReleaseMode(ReleaseMode.stop);
      await _audioPlayer.setVolume(1.0);
      await _audioPlayer.setSource(AssetSource('sounds/beep.wav'));
    } catch (_) {
      // Audio unavailable — scanner still works, just no beep
    }
  }

  /// Play the scan beep. Rewinds before playing so rapid rescans always fire.
  Future<void> _playBeep() async {
    try {
      await _audioPlayer.stop();
      await _audioPlayer.play(AssetSource('sounds/beep.wav'));
    } catch (_) {
      // Fail silently — scanner functionality is unaffected
    }
  }

  @override
  void dispose() {
    _lineAnim.dispose();
    _controller.dispose();
    _manualCtrl.dispose();
    _resetTimer?.cancel();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    final code = barcode!.rawValue!;
    final formatName = _formatLabel(barcode.format);

    setState(() {
      _scanned = true;
      _lastCode = code;
      _lastFormat = formatName;
    });

    // Beep + haptic together for a professional scanner feel
    _playBeep();
    HapticFeedback.mediumImpact();

    // Pop immediately — no delay, fastest possible UX
    if (mounted) Navigator.of(context).pop(code);
  }

  void _reset() {
    _resetTimer?.cancel();
    setState(() {
      _scanned = false;
      _lastCode = null;
      _lastFormat = null;
    });
  }

  String _formatLabel(BarcodeFormat f) {
    switch (f) {
      case BarcodeFormat.qrCode: return 'QR Code';
      case BarcodeFormat.ean13: return 'EAN-13';
      case BarcodeFormat.ean8: return 'EAN-8';
      case BarcodeFormat.code128: return 'Code 128';
      case BarcodeFormat.code39: return 'Code 39';
      case BarcodeFormat.code93: return 'Code 93';
      case BarcodeFormat.upcA: return 'UPC-A';
      case BarcodeFormat.upcE: return 'UPC-E';
      case BarcodeFormat.pdf417: return 'PDF417';
      case BarcodeFormat.aztec: return 'Aztec';
      case BarcodeFormat.dataMatrix: return 'Data Matrix';
      default: return 'Barcode';
    }
  }

  void _toggleTorch() {
    _controller.toggleTorch();
    setState(() => _torchOn = !_torchOn);
  }

  void _submitManual() {
    final v = _manualCtrl.text.trim();
    if (v.isEmpty) return;
    Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // ── Camera feed ─────────────────────────────────────────────────
          Positioned.fill(
            child: MobileScanner(
              controller: _controller,
              onDetect: _scanned ? null : _onDetect,
              errorBuilder: (context, error, child) {
                final isPermissionError =
                    error.errorCode == MobileScannerErrorCode.permissionDenied;
                return Container(
                  color: Colors.black,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            isPermissionError
                                ? Icons.no_photography_outlined
                                : Icons.error_outline_rounded,
                            color: Colors.white60,
                            size: 64,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            isPermissionError
                                ? 'Camera Permission Denied'
                                : 'Camera Error',
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            isPermissionError
                                ? 'Please enable camera permission in Settings to scan barcodes.'
                                : error.errorDetails?.message ??
                                    'Camera could not be opened.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 13),
                          ),
                          const SizedBox(height: 24),
                          if (isPermissionError)
                            ElevatedButton.icon(
                              onPressed: () async {
                                // url_launcher can open app settings with this scheme
                                final opened = await launchUrl(
                                  Uri.parse('app-settings:'),
                                );
                                if (!opened && context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'Settings mein Camera permission manually enable karen.',
                                      ),
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.settings_outlined,
                                  size: 16),
                              label: const Text('Open Settings'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: Colors.black,
                              ),
                            ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Go Back',
                                style: TextStyle(color: Colors.white60)),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // ── Dark vignette overlay ────────────────────────────────────────
          Positioned.fill(
            child: CustomPaint(
              painter: _ScanOverlayPainter(
                scanned: _scanned,
              ),
            ),
          ),

          // ── Animated scan line ───────────────────────────────────────────
          if (!_scanned)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _lineTween,
                builder: (_, __) {
                  return CustomPaint(
                    painter: _ScanLinePainter(progress: _lineTween.value),
                  );
                },
              ),
            ),

          // ── Top bar ──────────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  // Back
                  _CircleBtn(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.of(context).pop(),
                  ),
                  const Spacer(),
                  // Torch
                  _CircleBtn(
                    icon: _torchOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                    onTap: _toggleTorch,
                    active: _torchOn,
                  ),
                  const SizedBox(width: 10),
                  // Camera flip
                  _CircleBtn(
                    icon: Icons.flip_camera_android_rounded,
                    onTap: () => _controller.switchCamera(),
                  ),
                ],
              ),
            ),
          ),

          // ── Title + hint ──────────────────────────────────────────────────
          SafeArea(
            child: Align(
              alignment: const Alignment(0, -0.52),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Scan Barcode',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _scanned
                        ? '✓ Barcode detected!'
                        : 'Align the barcode within the frame',
                    style: TextStyle(
                      color: _scanned ? Colors.greenAccent : Colors.white60,
                      fontSize: 13,
                      fontWeight: _scanned ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Scanned result banner ─────────────────────────────────────────
          if (_lastCode != null)
            Align(
              alignment: const Alignment(0, 0.35),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.6), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.greenAccent.withValues(alpha: 0.15),
                      blurRadius: 16,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.qr_code_scanner_rounded,
                            color: Colors.greenAccent, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          _lastFormat ?? 'Barcode',
                          style: const TextStyle(
                              color: Colors.greenAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _lastCode!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton.icon(
                          onPressed: _reset,
                          icon: const Icon(Icons.refresh_rounded, size: 16,
                              color: Colors.white60),
                          label: const Text('Scan Again',
                              style: TextStyle(color: Colors.white60, fontSize: 12)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            minimumSize: Size.zero,
                          ),
                        ),
                        const SizedBox(width: 12),
                        ElevatedButton.icon(
                          onPressed: () =>
                              Navigator.of(context).pop(_lastCode),
                          icon: const Icon(Icons.check_rounded, size: 16),
                          label: const Text('Use This',
                              style: TextStyle(fontSize: 12)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.greenAccent.shade700,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 6),
                            minimumSize: Size.zero,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

          // ── Bottom panel — manual entry ───────────────────────────────────
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_showManual) ...[
                      // Manual entry field
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.keyboard_alt_outlined,
                                size: 20, color: Colors.grey),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _manualCtrl,
                                autofocus: true,
                                style: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w600),
                                decoration: const InputDecoration(
                                  hintText: 'Type barcode / SKU...',
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding:
                                      EdgeInsets.symmetric(vertical: 10),
                                ),
                                textInputAction: TextInputAction.done,
                                onSubmitted: (_) => _submitManual(),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.send_rounded,
                                  color: Color(0xFFE53935)),
                              onPressed: _submitManual,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Toggle manual entry
                        GestureDetector(
                          onTap: () =>
                              setState(() => _showManual = !_showManual),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 18, vertical: 10),
                            decoration: BoxDecoration(
                              color: _showManual
                                  ? Colors.white.withValues(alpha: 0.15)
                                  : Colors.white.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                  color: Colors.white30, width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  _showManual
                                      ? Icons.close_rounded
                                      : Icons.keyboard_alt_outlined,
                                  size: 16,
                                  color: Colors.white70,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  _showManual ? 'Hide Keyboard' : 'Enter Manually',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Overlay painter ────────────────────────────────────────────────────────────

class _ScanOverlayPainter extends CustomPainter {
  final bool scanned;
  const _ScanOverlayPainter({required this.scanned});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint dark = Paint()..color = Colors.black.withValues(alpha: 0.62);
    final double frameSize = size.width * 0.62;
    final double left = (size.width - frameSize) / 2;
    final double top = (size.height - frameSize) / 2 - 30;
    final Rect frame = Rect.fromLTWH(left, top, frameSize, frameSize);

    // Darken outside the scan frame
    final Path path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(frame, const Radius.circular(12)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, dark);

    // Corner accent lines
    final Paint corner = Paint()
      ..color = scanned ? Colors.greenAccent : Colors.white
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const double cLen = 24.0;
    const double r = 12.0;

    // top-left
    canvas.drawLine(
        Offset(left + r, top), Offset(left + r + cLen, top), corner);
    canvas.drawLine(
        Offset(left, top + r), Offset(left, top + r + cLen), corner);
    // top-right
    canvas.drawLine(
        Offset(left + frameSize - r - cLen, top),
        Offset(left + frameSize - r, top), corner);
    canvas.drawLine(
        Offset(left + frameSize, top + r),
        Offset(left + frameSize, top + r + cLen), corner);
    // bottom-left
    canvas.drawLine(
        Offset(left + r, top + frameSize),
        Offset(left + r + cLen, top + frameSize), corner);
    canvas.drawLine(
        Offset(left, top + frameSize - r - cLen),
        Offset(left, top + frameSize - r), corner);
    // bottom-right
    canvas.drawLine(
        Offset(left + frameSize - r - cLen, top + frameSize),
        Offset(left + frameSize - r, top + frameSize), corner);
    canvas.drawLine(
        Offset(left + frameSize, top + frameSize - r - cLen),
        Offset(left + frameSize, top + frameSize - r), corner);
  }

  @override
  bool shouldRepaint(_ScanOverlayPainter old) => old.scanned != scanned;
}

// ── Scan-line painter ──────────────────────────────────────────────────────────

class _ScanLinePainter extends CustomPainter {
  final double progress;
  const _ScanLinePainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final double frameSize = size.width * 0.62;
    final double left = (size.width - frameSize) / 2;
    final double top = (size.height - frameSize) / 2 - 30;

    final double y = top + progress * frameSize;

    final Paint paint = Paint()
      ..shader = LinearGradient(
        colors: [
          Colors.transparent,
          const Color(0xFFE53935).withValues(alpha: 0.7),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(left, y - 2, frameSize, 4))
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(left + 8, y), Offset(left + frameSize - 8, y), paint);
  }

  @override
  bool shouldRepaint(_ScanLinePainter old) => old.progress != progress;
}

// ── Circle icon button ─────────────────────────────────────────────────────────

class _CircleBtn extends StatelessWidget {
  const _CircleBtn({
    required this.icon,
    required this.onTap,
    this.active = false,
  });
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: active
              ? Colors.white.withValues(alpha: 0.25)
              : Colors.black.withValues(alpha: 0.45),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white24, width: 1),
        ),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}
