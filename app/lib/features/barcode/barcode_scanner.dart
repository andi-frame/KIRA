import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/theme.dart';

/// Pemindai kode batang. Dipisah dari plugin kamera agar layar bisa diuji tanpa kamera.
abstract class BarcodeScanner {
  /// Tampilan pemindai; `onCode` dipanggil tiap kali kode terbaca (pemanggil yang menyaring duplikat).
  Widget view(BuildContext context, void Function(String code) onCode);
}

class CameraBarcodeScanner implements BarcodeScanner {
  const CameraBarcodeScanner();

  @override
  Widget view(BuildContext context, void Function(String code) onCode) {
    if (kIsWeb) {
      return const _ScannerNote('Pemindai kamera tersedia di aplikasi Android. Di sini, ketik nomor kode batang di bawah.');
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(KiraRadius.card),
      child: MobileScanner(
        key: const Key('camera_scanner'),
        onDetect: (capture) {
          for (final b in capture.barcodes) {
            final raw = b.rawValue;
            if (raw != null && raw.isNotEmpty) {
              onCode(raw);
              return;
            }
          }
        },
        errorBuilder: (context, error) => const _ScannerNote(
          'Kamera belum bisa dipakai (izin kamera mungkin belum diberikan). Kamu tetap bisa mengetik nomor kode batang di bawah.',
        ),
      ),
    );
  }
}

class _ScannerNote extends StatelessWidget {
  const _ScannerNote(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('scanner_note'),
        padding: const EdgeInsets.all(KiraSpace.xl),
        decoration: BoxDecoration(
          color: context.scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(KiraRadius.card),
        ),
        child: Row(children: [
          Icon(Icons.qr_code_scanner, color: context.scheme.onSurfaceVariant),
          const SizedBox(width: KiraSpace.md),
          Expanded(child: Text(text, style: context.text.bodyMedium)),
        ]),
      );
}

final barcodeScannerProvider = Provider<BarcodeScanner>((ref) => const CameraBarcodeScanner());
