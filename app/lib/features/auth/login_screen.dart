import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';

final _phonePattern = RegExp(r'^\+?\d{8,15}$');
final _pinPattern = RegExp(r'^\d{4,6}$');

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _phone = TextEditingController();
  final _pin = TextEditingController();
  bool _register = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    _pin.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final phone = _phone.text.trim();
    final pin = _pin.text.trim();
    if (!_phonePattern.hasMatch(phone)) {
      setState(() => _error = 'Nomor HP belum sesuai. Pakai angka saja, 8 sampai 15 digit.');
      return;
    }
    if (!_pinPattern.hasMatch(pin)) {
      setState(() => _error = 'PIN harus 4 sampai 6 angka.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider);
      final token = _register ? await api.register(phone, pin) : await api.login(phone, pin);
      await ref.read(authProvider.notifier).setToken(token);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(KiraSpace.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('KIRA', style: context.text.labelLarge?.copyWith(color: context.scheme.primary, letterSpacing: 2)),
                  const SizedBox(height: KiraSpace.sm),
                  Text('Masuk ke KIRA', style: context.text.headlineMedium),
                  const SizedBox(height: KiraSpace.sm),
                  Text(
                    'Kira-kira kesehatanmu 10 tahun lagi seperti apa? Ceritakan satu menit sehari, KIRA bantu menghitungnya.',
                    style: context.text.bodyLarge?.copyWith(color: context.scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: KiraSpace.xl),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Sudah punya akun')),
                      ButtonSegment(value: true, label: Text('Baru di sini')),
                    ],
                    selected: {_register},
                    onSelectionChanged: (s) => setState(() {
                      _register = s.first;
                      _error = null;
                    }),
                  ),
                  const SizedBox(height: KiraSpace.xl),
                  TextField(
                    controller: _phone,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    decoration: const InputDecoration(labelText: 'Nomor HP', helperText: 'Contoh: 081234567890'),
                  ),
                  const SizedBox(height: KiraSpace.lg),
                  TextField(
                    controller: _pin,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(labelText: 'PIN', helperText: '4 sampai 6 angka'),
                  ),
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
                      onPressed: _busy ? null : _submit,
                      child: _busy
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                          : Text(_register ? 'Daftar' : 'Masuk'),
                    ),
                  ),
                  const SizedBox(height: KiraSpace.lg),
                  Text(
                    'KIRA bukan alat diagnosis. Data demo adalah data dummy.',
                    style: context.text.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
