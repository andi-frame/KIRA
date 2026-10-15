import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../privacy/consent_text.dart';

final _phonePattern = RegExp(r'^\+?\d{8,15}$');
final _pinPattern = RegExp(r'^\d{4,6}$');

/// Nama pengguna selalu diawali huruf, jadi tidak pernah bisa menyerupai nomor HP.
final usernamePattern = RegExp(r'^[a-z][a-z0-9_.]{2,19}$');
const usernameRule = 'Nama pengguna 3-20 karakter: huruf kecil, angka, titik, atau garis bawah, diawali huruf.';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _identifier = TextEditingController(); // masuk: nama pengguna atau nomor HP
  final _username = TextEditingController(); // daftar
  final _phone = TextEditingController(); // daftar
  final _pin = TextEditingController();
  bool _register = false;
  bool _consent = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _identifier.dispose();
    _username.dispose();
    _phone.dispose();
    _pin.dispose();
    super.dispose();
  }

  String? _validate(String pin) {
    if (_register) {
      if (!usernamePattern.hasMatch(_username.text.trim().toLowerCase())) return usernameRule;
      if (!_phonePattern.hasMatch(_phone.text.trim())) {
        return 'Nomor HP belum sesuai. Pakai angka saja, 8 sampai 15 digit.';
      }
    } else if (_identifier.text.trim().isEmpty) {
      return 'Isi nama pengguna atau nomor HP-mu.';
    }
    if (!_pinPattern.hasMatch(pin)) return 'PIN harus 4 sampai 6 angka.';
    if (_register && !_consent) return 'Centang persetujuan data kesehatan dulu ya.';
    return null;
  }

  Future<void> _submit() async {
    final pin = _pin.text.trim();
    final problem = _validate(pin);
    if (problem != null) {
      setState(() => _error = problem);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider);
      final tokens = _register
          ? await api.register(_phone.text.trim(), _username.text.trim().toLowerCase(), pin, consent: _consent)
          : await api.login(_identifier.text.trim().toLowerCase(), pin);
      await ref.read(authProvider.notifier).setTokens(tokens);
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
                  Text(_register ? 'Daftar ke KIRA' : 'Masuk ke KIRA', style: context.text.headlineMedium),
                  const SizedBox(height: KiraSpace.sm),
                  Text(
                    'Kira-kira kesehatanmu 10 tahun lagi seperti apa? Ceritakan satu menit sehari, KIRA bantu menghitungnya.',
                    style: context.text.bodyLarge?.copyWith(color: context.scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: KiraSpace.xl),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: false, label: Text('Masuk')),
                      ButtonSegment(value: true, label: Text('Daftar')),
                    ],
                    selected: {_register},
                    onSelectionChanged: (s) => setState(() {
                      _register = s.first;
                      _error = null;
                    }),
                  ),
                  const SizedBox(height: KiraSpace.xl),
                  if (_register) ...[
                    TextField(
                      key: const Key('register_username'),
                      controller: _username,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: const [AutofillHints.newUsername],
                      decoration: const InputDecoration(
                        labelText: 'Nama pengguna',
                        helperText: 'Untuk masuk. Contoh: raka_dev',
                      ),
                    ),
                    const SizedBox(height: KiraSpace.lg),
                    TextField(
                      key: const Key('register_phone'),
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.telephoneNumber],
                      decoration: const InputDecoration(
                        labelText: 'Nomor HP',
                        helperText: 'Wajib: dipakai untuk menautkan WhatsApp dan undangan keluarga',
                        helperMaxLines: 2,
                      ),
                    ),
                  ] else
                    TextField(
                      key: const Key('login_identifier'),
                      controller: _identifier,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      enableSuggestions: false,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(
                        labelText: 'Nama pengguna atau nomor HP',
                        helperText: 'Contoh: raka_dev atau 081234567890',
                      ),
                    ),
                  const SizedBox(height: KiraSpace.lg),
                  TextField(
                    key: const Key('login_pin'),
                    controller: _pin,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(labelText: 'PIN', helperText: '4 sampai 6 angka'),
                  ),
                  if (_register) ...[
                    const SizedBox(height: KiraSpace.md),
                    CheckboxListTile(
                      key: const Key('register_consent'),
                      value: _consent,
                      onChanged: (v) => setState(() => _consent = v ?? false),
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      title: const Text('Saya setuju datanya diproses untuk proyeksi dan rekomendasi.'),
                      subtitle: Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          key: const Key('consent_read'),
                          style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: const Size(0, 36)),
                          onPressed: () => showConsentSheet(context),
                          child: const Text('Baca apa saja yang diproses'),
                        ),
                      ),
                    ),
                  ] else
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: const Key('forgot_pin'),
                        style: TextButton.styleFrom(padding: EdgeInsets.zero),
                        onPressed: () => context.push('/reset-pin'),
                        child: const Text('Lupa PIN?'),
                      ),
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
                      key: const Key('auth_submit'),
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
