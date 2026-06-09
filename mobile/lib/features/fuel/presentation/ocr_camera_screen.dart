import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/api/api_exception.dart';
import '../data/fuel_api.dart';
import '../data/ocr_prefill_model.dart';

/// Receipt OCR camera flow (spec §7).
///
/// Flow:
///   1. User picks a source — camera or library.
///   2. `image_cropper` lets them tighten the frame + rotate.
///   3. `flutter_image_compress` shrinks to ≤1200px / 80% JPEG.
///   4. `POST /cars/:carId/fuel/ocr` — show "Reading receipt…" while waiting.
///   5. On success, navigate forward to a populated `AddFuelScreen` so the
///      user verifies before saving.
///   6. Any failure (denied camera, network, `parsedBy: failed`) shows a
///      snackbar and offers an "Enter manually" route to the plain form.
class OcrCameraScreen extends ConsumerStatefulWidget {
  const OcrCameraScreen({super.key, required this.carId});
  final String carId;

  @override
  ConsumerState<OcrCameraScreen> createState() => _OcrCameraScreenState();
}

enum _Stage {
  /// Initial — two big buttons, no work in flight.
  picking,

  /// User picked an image; we're cropping / compressing / uploading.
  processing,
}

class _OcrCameraScreenState extends ConsumerState<OcrCameraScreen> {
  _Stage _stage = _Stage.picking;
  String _processingLabel = 'Reading receipt…';

  /// Routes the user to the manual fuel-entry form, replacing the OCR
  /// camera screen in the navigation stack so the back arrow goes to the
  /// home dashboard, not back into the camera flow.
  void _goManual() {
    if (!mounted) return;
    context.pushReplacement('/cars/${widget.carId}/fuel/new');
  }

  /// Forwards to the prefilled fuel form. We use `pushReplacement` so the
  /// back arrow returns to wherever the user came from (home dashboard or
  /// fuel tab) rather than the now-pointless OCR screen.
  void _goPrefilled(OcrPrefill prefill) {
    if (!mounted) return;
    context.pushReplacement(
      '/cars/${widget.carId}/fuel/new',
      extra: prefill,
    );
  }

  void _showError(String msg, {bool offerManual = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        action: offerManual
            ? SnackBarAction(label: 'Enter manually', onPressed: _goManual)
            : null,
      ),
    );
  }

  /// Debug-only: load a fixed receipt JPEG from the app's external dir at
  /// `/sdcard/Android/data/com.garage.app/files/garage-test/receipt.jpg`.
  /// Bypasses the system gallery picker entirely so adb-driven testing never
  /// touches the user's actual photo library. The asset is pushed via
  /// `adb push` ahead of testing.
  Future<void> _startWithTestReceipt() async {
    setState(() {
      _stage = _Stage.processing;
      _processingLabel = 'Loading test receipt…';
    });
    try {
      final externalDir = await getExternalStorageDirectory();
      if (externalDir == null) {
        _showError('External storage not available on this device.', offerManual: true);
        if (mounted) setState(() => _stage = _Stage.picking);
        return;
      }
      final src = File(p.join(externalDir.path, 'garage-test', 'receipt.jpg'));
      if (!await src.exists()) {
        _showError(
          'No test receipt at garage-test/receipt.jpg — push one via adb first.',
          offerManual: true,
        );
        if (mounted) setState(() => _stage = _Stage.picking);
        return;
      }

      if (!mounted) return;
      setState(() => _processingLabel = 'Preparing photo…');
      final compressed = await _compress(src);

      if (!mounted) return;
      setState(() => _processingLabel = 'Reading receipt…');
      final prefill = await ref
          .read(fuelApiProvider)
          .ocrReceipt(widget.carId, compressed);

      if (prefill.failed) {
        _showError("Couldn't read the test receipt. Check the image.");
        if (mounted) setState(() => _stage = _Stage.picking);
        return;
      }
      _goPrefilled(prefill);
    } on ApiException catch (e) {
      _showError('OCR failed: ${e.message}');
      if (mounted) setState(() => _stage = _Stage.picking);
    } catch (e) {
      _showError("Couldn't read the test receipt: $e");
      if (mounted) setState(() => _stage = _Stage.picking);
    }
  }

  Future<void> _start(ImageSource source) async {
    setState(() {
      _stage = _Stage.processing;
      _processingLabel = 'Opening ${source == ImageSource.camera ? 'camera' : 'library'}…';
    });

    try {
      // 1. Pick raw image. The image_picker plugin throws on permission
      //    denial; treat that as a recoverable error rather than a crash.
      final picker = ImagePicker();
      final XFile? raw = await picker.pickImage(
        source: source,
        // Down-rez the source slightly so the cropper has less work to do
        // on huge phone-camera frames; the compress step still trims it.
        maxWidth: 2400,
        imageQuality: 92,
      );
      if (raw == null) {
        // User cancelled — drop back to the picker without an error.
        if (mounted) setState(() => _stage = _Stage.picking);
        return;
      }

      // 2. Crop. Cancellation here is also a normal "back" gesture.
      if (!mounted) return;
      setState(() => _processingLabel = 'Crop the receipt…');
      final cropped = await ImageCropper().cropImage(
        sourcePath: raw.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 95,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Crop receipt',
            lockAspectRatio: false,
            initAspectRatio: CropAspectRatioPreset.original,
          ),
          IOSUiSettings(
            title: 'Crop receipt',
            aspectRatioLockEnabled: false,
            resetAspectRatioEnabled: true,
          ),
        ],
      );
      if (cropped == null) {
        if (mounted) setState(() => _stage = _Stage.picking);
        return;
      }

      // 3. Compress to ≤1200px / 80% JPEG before sending. We write the
      //    output into the temp dir so the OS can clean it up — the
      //    upload step reads it back as a real `File`.
      if (!mounted) return;
      setState(() => _processingLabel = 'Preparing photo…');
      final compressed = await _compress(File(cropped.path));

      // 4. Upload + parse.
      if (!mounted) return;
      setState(() => _processingLabel = 'Reading receipt…');
      final prefill =
          await ref.read(fuelApiProvider).ocrReceipt(widget.carId, compressed);

      if (prefill.failed) {
        _showError(
          "Couldn't read this receipt. Try again or enter manually.",
        );
        if (mounted) setState(() => _stage = _Stage.picking);
        return;
      }

      // 5. Forward to the prefilled form.
      _goPrefilled(prefill);
    } on ApiException catch (e) {
      _showError('OCR failed: ${e.message}');
      if (mounted) setState(() => _stage = _Stage.picking);
    } catch (e) {
      // Permissions, plugin failures, missing camera, etc. — uniform handling.
      _showError("Couldn't capture photo. Try again or enter manually.");
      if (mounted) setState(() => _stage = _Stage.picking);
    }
  }

  /// Compresses [src] to ≤1200px on the longest side at 80% quality. Writes
  /// to a fresh path in the system temp dir to avoid collisions if the user
  /// scans multiple receipts in the same session.
  Future<File> _compress(File src) async {
    final tempDir = await getTemporaryDirectory();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final outPath = p.join(tempDir.path, 'ocr_$stamp.jpg');

    // `compressAndGetFile` uses min* as a *minimum* threshold and then
    // keeps the aspect ratio — passing both = 1200 caps the longest side.
    final out = await FlutterImageCompress.compressAndGetFile(
      src.absolute.path,
      outPath,
      minWidth: 1200,
      minHeight: 1200,
      quality: 80,
      format: CompressFormat.jpeg,
    );
    if (out == null) {
      // Compression should be infallible on a valid JPEG; if it fails,
      // upload the original — bandwidth cost is acceptable.
      return src;
    }
    return File(out.path);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Scan receipt')),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: _stage == _Stage.processing
              ? _ProcessingView(label: _processingLabel)
              : _PickerView(
                  theme: theme,
                  onCamera: () => _start(ImageSource.camera),
                  onLibrary: () => _start(ImageSource.gallery),
                  onManual: _goManual,
                  onTestReceipt: kDebugMode ? _startWithTestReceipt : null,
                ),
        ),
      ),
    );
  }
}

class _PickerView extends StatelessWidget {
  const _PickerView({
    required this.theme,
    required this.onCamera,
    required this.onLibrary,
    required this.onManual,
    this.onTestReceipt,
  });

  final ThemeData theme;
  final VoidCallback onCamera;
  final VoidCallback onLibrary;
  final VoidCallback onManual;
  final VoidCallback? onTestReceipt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const ValueKey('picker'),
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          Icon(
            Icons.receipt_long_outlined,
            size: 80,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 24),
          Text(
            'Snap your gas receipt',
            style: theme.textTheme.headlineSmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            "We'll read the liters, price, and total automatically. "
            "You can fix anything before saving.",
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const Spacer(),
          FilledButton.icon(
            onPressed: onCamera,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Take photo'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onLibrary,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Pick from library'),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onManual,
            child: const Text('Skip — enter manually'),
          ),
          if (onTestReceipt != null) ...[
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: onTestReceipt,
              icon: const Icon(Icons.bug_report_outlined, size: 18),
              label: const Text('debug · pick test receipt'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProcessingView extends StatelessWidget {
  const _ProcessingView({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      key: const ValueKey('processing'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 56,
              height: 56,
              child: CircularProgressIndicator(strokeWidth: 3),
            ),
            const SizedBox(height: 24),
            Text(
              label,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'This usually takes a couple of seconds.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
