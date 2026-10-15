import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Membagikan berkas lewat menu bagikan sistem (WhatsApp, surel, dll.). Dipisah dari plugin agar mudah diuji.
abstract class ShareService {
  Future<void> sharePdf(Uint8List bytes, String filename, {String? message});
}

class SharePlusService implements ShareService {
  const SharePlusService();

  @override
  Future<void> sharePdf(Uint8List bytes, String filename, {String? message}) async {
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: 'application/pdf', name: filename)],
      fileNameOverrides: [filename],
      text: message,
      subject: 'Ringkasan KIRA untuk dokter',
    ));
  }
}

final shareServiceProvider = Provider<ShareService>((ref) => const SharePlusService());
