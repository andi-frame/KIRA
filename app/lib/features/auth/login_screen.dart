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

const _headerHeight = 248.0;

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
  bool _showPin = false;
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

  void _switchMode() => setState(() {
        _register = !_register;
        _error = null;
      });

  @override
  Widget build(BuildContext context) {
    final dark = context.scheme.brightness == Brightness.dark;
    final headerColor = dark ? context.scheme.primaryContainer : context.scheme.primary;
    final onHeader = dark ? context.scheme.onPrimaryContainer : context.scheme.onPrimary;
    final insets = MediaQuery.paddingOf(context);
    final headerHeight = insets.top + _headerHeight;
    return Scaffold(
      backgroundColor: headerColor,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: LayoutBuilder(
          builder: (context, viewport) => SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Column(
                  children: [
                    _AuthHeader(height: headerHeight, color: onHeader),
                    Material(
                      color: context.scheme.surface,
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
                      child: Container(
                        width: double.infinity,
                        constraints: BoxConstraints(minHeight: (viewport.maxHeight - headerHeight).clamp(0, double.infinity)),
                        padding: EdgeInsets.fromLTRB(KiraSpace.xl, KiraSpace.xxl, KiraSpace.xl, KiraSpace.xl + insets.bottom),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: _form(context)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _form(BuildContext context) {
    final muted = context.text.bodyMedium?.copyWith(color: context.scheme.onSurfaceVariant);
    return [
      Text(_register ? 'Buat akun KIRA' : 'Masuk ke KIRA', style: context.text.headlineSmall),
      const SizedBox(height: KiraSpace.xs),
      Text(
        _register
            ? 'Nomor HP dipakai untuk menautkan WhatsApp dan undangan keluarga.'
            : 'Senang kamu kembali.',
        style: muted,
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
          decoration: const InputDecoration(labelText: 'Nama pengguna', hintText: 'raka_dev'),
        ),
        const SizedBox(height: KiraSpace.lg),
        TextField(
          key: const Key('register_phone'),
          controller: _phone,
          keyboardType: TextInputType.phone,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.telephoneNumber],
          decoration: const InputDecoration(labelText: 'Nomor HP', hintText: '081234567890'),
        ),
      ] else
        TextField(
          key: const Key('login_identifier'),
          controller: _identifier,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.username],
          decoration: const InputDecoration(labelText: 'Nama pengguna atau nomor HP'),
        ),
      const SizedBox(height: KiraSpace.lg),
      TextField(
        key: const Key('login_pin'),
        controller: _pin,
        obscureText: !_showPin,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          labelText: 'PIN',
          hintText: '4–6 angka',
          suffixIcon: IconButton(
            tooltip: _showPin ? 'Sembunyikan PIN' : 'Tampilkan PIN',
            icon: Icon(_showPin ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            onPressed: () => setState(() => _showPin = !_showPin),
          ),
        ),
      ),
      if (_register) ...[
        const SizedBox(height: KiraSpace.md),
        Row(
          key: const Key('register_consent'),
          children: [
            Checkbox(value: _consent, onChanged: (v) => setState(() => _consent = v ?? false)),
            Expanded(
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _consent = !_consent),
                    child: Text('Saya menyetujui ', style: context.text.bodyMedium),
                  ),
                  InkWell(
                    key: const Key('consent_read'),
                    onTap: () => showConsentSheet(context),
                    child: Text(
                      'pemrosesan data kesehatan',
                      style: context.text.bodyMedium?.copyWith(
                        color: context.scheme.primary,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        decorationColor: context.scheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ] else
        Align(
          alignment: Alignment.centerRight,
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
      const SizedBox(height: KiraSpace.md),
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            _register ? 'Sudah punya akun?' : 'Belum punya akun?',
            style: context.text.bodyMedium?.copyWith(color: context.scheme.onSurfaceVariant),
          ),
          TextButton(
            key: const Key('auth_toggle'),
            style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: KiraSpace.sm)),
            onPressed: _busy ? null : _switchMode,
            child: Text(_register ? 'Masuk di sini' : 'Daftar di sini'),
          ),
        ],
      ),
    ];
  }
}

/// Kepala layar masuk: maskot KIRA di atas warna utama, dengan lengkungan tipis sebagai hiasan.
class _AuthHeader extends StatelessWidget {
  const _AuthHeader({required this.height, required this.color});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(right: -70, top: -40, child: _Ring(size: 220, color: color)),
          Positioned(left: -90, bottom: -60, child: _Ring(size: 200, color: color)),
          Positioned.fill(
            top: MediaQuery.paddingOf(context).top,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.18), blurRadius: 24, offset: const Offset(0, 10)),
                    ],
                  ),
                  child: Image.asset('assets/icon/icon.png', width: 104, height: 104, excludeFromSemantics: true),
                ),
                const SizedBox(height: KiraSpace.lg),
                Text(
                  'KIRA',
                  style: context.text.titleLarge?.copyWith(color: color, fontWeight: FontWeight.w700, letterSpacing: 4),
                ),
                const SizedBox(height: KiraSpace.xs),
                Text(
                  'Satu menit sehari untuk kesehatanmu nanti',
                  style: context.text.bodyMedium?.copyWith(color: color.withValues(alpha: 0.8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.12), width: 1.5),
      ),
    );
  }
}
