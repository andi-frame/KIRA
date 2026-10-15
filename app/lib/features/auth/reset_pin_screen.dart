import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';

/// Atur ulang PIN: kode 6 angka dikirim ke WhatsApp yang sudah tertaut ke akun.
/// Tanpa WhatsApp tertaut, KIRA tidak punya cara membuktikan pemilik akun, jadi layar ini menyatakannya terang-terangan.
class ResetPinScreen extends ConsumerStatefulWidget {
  const ResetPinScreen({super.key});

  @override
  ConsumerState<ResetPinScreen> createState() => _ResetPinScreenState();
}

class _ResetPinScreenState extends ConsumerState<ResetPinScreen> {
  final _identifier = TextEditingController();
  final _code = TextEditingController();
  final _pin = TextEditingController();
  final _pin2 = TextEditingController();
  bool _codeSent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _identifier.dispose();
    _code.dispose();
    _pin.dispose();
    _pin2.dispose();
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _request() async {
    final id = _identifier.text.trim().toLowerCase();
    if (id.isEmpty) {
      setState(() => _error = 'Isi nama pengguna atau nomor HP-mu.');
      return;
    }
    await _guard(() async {
      await ref.read(apiProvider).requestPinReset(id);
      if (mounted) setState(() => _codeSent = true);
    });
  }

  Future<void> _confirm() async {
    if (!RegExp(r'^\d{6}$').hasMatch(_code.text.trim())) {
      setState(() => _error = 'Kodenya 6 angka.');
      return;
    }
    if (!RegExp(r'^\d{4,6}$').hasMatch(_pin.text)) {
      setState(() => _error = 'PIN baru harus 4 sampai 6 angka.');
      return;
    }
    if (_pin.text != _pin2.text) {
      setState(() => _error = 'Kedua PIN belum sama.');
      return;
    }
    await _guard(() async {
      await ref.read(apiProvider).confirmPinReset(_identifier.text.trim().toLowerCase(), _code.text.trim(), _pin.text);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN sudah diganti. Silakan masuk.')));
      context.go('/login');
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Lupa PIN')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(KiraSpace.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  _codeSent ? 'Masukkan kode dari WhatsApp' : 'Kami kirim kode ke WhatsApp-mu',
                  style: context.text.headlineSmall,
                ),
                const SizedBox(height: KiraSpace.sm),
                Text(
                  _codeSent
                      ? 'Kalau akun ini punya WhatsApp yang tertaut, kode 6 angka sudah dikirim. Berlaku 10 menit.'
                      : 'Ini hanya bisa jika WhatsApp sudah ditautkan ke akunmu di Profil. Kalau belum, KIRA belum bisa '
                          'memastikan kamu pemilik akunnya.',
                  style: context.text.bodyLarge?.copyWith(color: context.scheme.onSurfaceVariant),
                ),
                const SizedBox(height: KiraSpace.xl),
                TextField(
                  key: const Key('reset_identifier'),
                  controller: _identifier,
                  enabled: !_codeSent,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: const InputDecoration(labelText: 'Nama pengguna atau nomor HP'),
                ),
                if (_codeSent) ...[
                  const SizedBox(height: KiraSpace.lg),
                  TextField(
                    key: const Key('reset_code'),
                    controller: _code,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                    autofillHints: const [AutofillHints.oneTimeCode],
                    decoration: const InputDecoration(labelText: 'Kode 6 angka'),
                  ),
                  const SizedBox(height: KiraSpace.lg),
                  TextField(
                    key: const Key('reset_pin'),
                    controller: _pin,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                    decoration: const InputDecoration(labelText: 'PIN baru', helperText: '4 sampai 6 angka'),
                  ),
                  const SizedBox(height: KiraSpace.lg),
                  TextField(
                    key: const Key('reset_pin2'),
                    controller: _pin2,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                    onSubmitted: (_) => _confirm(),
                    decoration: const InputDecoration(labelText: 'Ulangi PIN baru'),
                  ),
                ],
                if (_error != null) ...[
                  const SizedBox(height: KiraSpace.md),
                  Semantics(
                    liveRegion: true,
                    child: Text(_error!, style: context.text.bodyMedium?.copyWith(color: context.scheme.error)),
                  ),
                ],
                const SizedBox(height: KiraSpace.xl),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    key: const Key('reset_submit'),
                    onPressed: _busy ? null : (_codeSent ? _confirm : _request),
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : Text(_codeSent ? 'Ganti PIN' : 'Kirim kode'),
                  ),
                ),
                if (_codeSent)
                  TextButton(
                    key: const Key('reset_resend'),
                    onPressed: _busy ? null : _request,
                    child: const Text('Kirim ulang kode'),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
