import 'dart:io' show Directory;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';

class PickedMedia {
  const PickedMedia(this.bytes, this.name);
  final Uint8List bytes;
  final String name;
}

/// Pengambil foto; foto dikecilkan (lebar maks 1280 px) sebelum diunggah agar cepat di jaringan seluler.
abstract class PhotoPicker {
  Future<PickedMedia?> pick(ImageSource source);
}

class DevicePhotoPicker implements PhotoPicker {
  final _picker = ImagePicker();

  @override
  Future<PickedMedia?> pick(ImageSource source) async {
    final file = await _picker.pickImage(source: source, maxWidth: 1280, imageQuality: 85);
    if (file == null) return null;
    return PickedMedia(await file.readAsBytes(), file.name.isEmpty ? 'foto.jpg' : file.name);
  }
}

/// Perekam suara ketuk-untuk-mulai, ketuk-lagi-untuk-berhenti. Audio diunggah apa adanya; STT dikerjakan backend.
abstract class VoiceRecorder {
  /// false bila izin mikrofon ditolak.
  Future<bool> start();
  Future<PickedMedia?> stop();
  Future<void> cancel();
}

class DeviceVoiceRecorder implements VoiceRecorder {
  final _recorder = AudioRecorder();

  @override
  Future<bool> start() async {
    if (!await _recorder.hasPermission()) return false;
    final path = kIsWeb ? 'kira_voice' : '${Directory.systemTemp.path}/kira_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
    return true;
  }

  @override
  Future<PickedMedia?> stop() async {
    final path = await _recorder.stop();
    if (path == null) return null;
    final bytes = await XFile(path).readAsBytes();
    return bytes.isEmpty ? null : PickedMedia(bytes, 'suara.m4a');
  }

  @override
  Future<void> cancel() async {
    await _recorder.cancel();
  }
}

final photoPickerProvider = Provider<PhotoPicker>((ref) => DevicePhotoPicker());
final voiceRecorderProvider = Provider<VoiceRecorder>((ref) => DeviceVoiceRecorder());
