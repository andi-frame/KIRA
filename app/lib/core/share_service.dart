import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Membagikan berkas atau teks lewat menu bagikan sistem (WhatsApp, surel, dll.). Dipisah dari plugin agar mudah diuji.
abstract class ShareService {
  Future<void> sharePdf(Uint8List bytes, String filename, {String? message});
  Future<void> shareFile(Uint8List bytes, String filename, String mimeType, {String? subject, String? message});
  Future<void> shareText(String text, {String? subject});
}

class SharePlusService implements ShareService {
  const SharePlusService();

  @override
  Future<void> sharePdf(Uint8List bytes, String filename, {String? message}) =>
      shareFile(bytes, filename, 'application/pdf', subject: 'Ringkasan KIRA untuk dokter', message: message);

  @override
  Future<void> shareFile(Uint8List bytes, String filename, String mimeType, {String? subject, String? message}) async {
    await SharePlus.instance.share(ShareParams(
      files: [XFile.fromData(bytes, mimeType: mimeType, name: filename)],
      fileNameOverrides: [filename],
      text: message,
      subject: subject,
    ));
  }

  @override
  Future<void> shareText(String text, {String? subject}) async {
    await SharePlus.instance.share(ShareParams(text: text, subject: subject));
  }
}

final shareServiceProvider = Provider<ShareService>((ref) => const SharePlusService());
