import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../data/pantry_store.dart';
import '../models/pantry_models.dart';
import '../services/barcode_lookup_service.dart';
import 'product_editor_dialog.dart';

Future<ProductDefinition?> scanProductBarcode(
  BuildContext context,
  PantryStore store, {
  OpenFoodFactsBarcodeLookup? lookup,
}) async {
  final scanned = await scanBarcodeValue(context);
  if (scanned == null || !context.mounted) return null;

  final barcode = normalizeBarcode(scanned);
  final existing = store.productForBarcode(barcode);
  if (existing != null) return existing;

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('New barcode — checking Open Food Facts…'),
      duration: Duration(seconds: 2),
    ),
  );

  BarcodeProductSuggestion? suggestion;
  String? lookupError;
  try {
    suggestion = await (lookup ?? OpenFoodFactsBarcodeLookup()).lookup(barcode);
  } on BarcodeLookupException catch (exception) {
    lookupError = exception.message;
  }
  if (!context.mounted) return null;

  if (lookupError != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$lookupError You can still define it manually.')),
    );
  } else if (suggestion == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'That barcode is not in Open Food Facts yet. Define it once and future scans will recognize it.',
        ),
      ),
    );
  }

  return showProductEditor(
    context,
    store,
    seed: suggestion == null
        ? ProductEditorSeed(barcode: barcode)
        : ProductEditorSeed.fromSuggestion(suggestion),
  );
}

Future<String?> scanBarcodeValue(BuildContext context) => showDialog<String>(
  context: context,
  builder: (context) => const _BarcodeScannerDialog(),
);

class _BarcodeScannerDialog extends StatefulWidget {
  const _BarcodeScannerDialog();

  @override
  State<_BarcodeScannerDialog> createState() => _BarcodeScannerDialogState();
}

class _BarcodeScannerDialogState extends State<_BarcodeScannerDialog> {
  late final MobileScannerController controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean8,
      BarcodeFormat.ean13,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ],
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool handled = false;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Scan a product barcode'),
    content: SizedBox(
      width: 520,
      height: (MediaQuery.sizeOf(context).height - 190).clamp(160, 390),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(
              controller: controller,
              onDetect: _onDetect,
              errorBuilder: (context, error) => _ScannerMessage(
                icon: Icons.no_photography_outlined,
                message: _scannerErrorMessage(error),
              ),
              placeholderBuilder: (context) => const _ScannerMessage(
                icon: Icons.camera_alt_outlined,
                message: 'Starting camera…',
              ),
            ),
            IgnorePointer(
              child: Center(
                child: Container(
                  width: 300,
                  height: 150,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.white, width: 2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Text(
                'Center the UPC or EAN in the frame. Scanning happens on this device.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  shadows: [Shadow(blurRadius: 5, color: Colors.black)],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(onPressed: _enterManually, child: const Text('Enter barcode')),
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
    ],
  );

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (handled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value == null || value.isEmpty) continue;
      handled = true;
      await controller.stop();
      if (mounted) Navigator.pop(context, value);
      return;
    }
  }

  Future<void> _enterManually() async {
    try {
      await controller.stop();
    } on MobileScannerException {
      // Manual entry remains available when the camera never started.
    }
    if (!mounted) return;
    final input = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Enter barcode'),
        content: TextField(
          controller: input,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'UPC or EAN',
            hintText: 'Numbers beneath the barcode',
          ),
          onSubmitted: (value) {
            if (value.trim().isNotEmpty) Navigator.pop(dialogContext, value);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (input.text.trim().isNotEmpty) {
                Navigator.pop(dialogContext, input.text);
              }
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    input.dispose();
    if (value != null && mounted) Navigator.pop(context, value);
  }

  String _scannerErrorMessage(
    MobileScannerException error,
  ) => switch (error.errorCode) {
    MobileScannerErrorCode.permissionDenied =>
      'Camera permission was denied. Allow camera access in your browser and try again.',
    MobileScannerErrorCode.unsupported =>
      'Barcode scanning is not supported by this browser or device.',
    _ =>
      'The camera could not start. Check browser camera permissions and try again.',
  };
}

class _ScannerMessage extends StatelessWidget {
  const _ScannerMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    ),
  );
}
