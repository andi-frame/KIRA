import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/core/api_client.dart';
import 'package:kira/features/auth/login_screen.dart';
import 'package:kira/features/auth/reset_pin_screen.dart';
import 'package:kira/shared/app_shell.dart';
import 'package:kira/shared/models.dart';
import 'package:go_router/go_router.dart';

import 'support/fakes.dart';

Future<void> pumpLogin(WidgetTester tester, FakeApi api) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(testApp(const LoginScreen(), api: api));
  await tester.pumpAndSettle();
}

Future<void> pumpReset(WidgetTester tester, FakeApi api) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(testApp(const ResetPinScreen(), api: api));
  await tester.pumpAndSettle();
}

Future<void> fillRegister(WidgetTester tester) async {
  await tester.tap(find.text('Daftar').first);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('register_username')), 'raka_dev');
  await tester.enterText(find.byKey(const Key('register_phone')), '081234567890');
  await tester.enterText(find.byKey(const Key('login_pin')), '123456');
}

void main() {
  group('persetujuan saat daftar', () {
    testWidgets('daftar ditolak sebelum persetujuan dicentang', (tester) async {
      final api = FakeApi();
      await pumpLogin(tester, api);
      await fillRegister(tester);
      await tester.tap(find.byKey(const Key('auth_submit')));
      await tester.pumpAndSettle();
      expect(find.text('Centang persetujuan data kesehatan dulu ya.'), findsOneWidget);
      expect(api.registrations, isEmpty);
    });

    testWidgets('setelah dicentang, daftar mengirim consent: true', (tester) async {
      final api = FakeApi();
      await pumpLogin(tester, api);
      await fillRegister(tester);
      await tester.tap(find.descendant(of: find.byKey(const Key('register_consent')), matching: find.byType(Checkbox)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('auth_submit')));
      await tester.pumpAndSettle();
      expect(api.registrations.single.consent, isTrue);
      expect(api.registrations.single.username, 'raka_dev');
    });

    testWidgets('isi persetujuan bisa dibaca sebelum menyetujui', (tester) async {
      await pumpLogin(tester, FakeApi());
      await tester.tap(find.text('Daftar').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('consent_read')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('consent_sheet')), findsOneWidget);
      expect(find.text('Data apa yang diproses'), findsOneWidget);
      expect(find.text('Batas KIRA'), findsOneWidget);
    });

    testWidgets('kotak persetujuan tidak muncul saat masuk; ada tautan Lupa PIN', (tester) async {
      await pumpLogin(tester, FakeApi());
      expect(find.byKey(const Key('register_consent')), findsNothing);
      expect(find.byKey(const Key('forgot_pin')), findsOneWidget);
    });
  });

  group('persetujuan ulang untuk akun lama', () {
    Future<FakeApi> pumpShell(WidgetTester tester, {required bool consented}) async {
      final api = FakeApi()
        ..profile = Profile(
          birthDate: '1998-03-14', sex: 'male', heightCm: 170, weightKg: 78, consented: consented,
        );
      final router = GoRouter(routes: [
        StatefulShellRoute.indexedStack(
          builder: (_, _, shell) => AppShell(shell: shell),
          branches: [
            StatefulShellBranch(routes: [GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('beranda')))]),
            StatefulShellBranch(routes: [GoRoute(path: '/b', builder: (_, _) => const Scaffold())]),
            StatefulShellBranch(routes: [GoRoute(path: '/c', builder: (_, _) => const Scaffold())]),
          ],
        ),
      ]);
      await tester.pumpWidget(_Host(api: api, router: router));
      await tester.pumpAndSettle();
      return api;
    }

    testWidgets('akun yang sudah menyetujui langsung masuk tanpa dialog', (tester) async {
      await pumpShell(tester, consented: true);
      expect(find.byKey(const Key('consent_gate')), findsNothing);
      expect(find.text('beranda'), findsOneWidget);
    });

    testWidgets('akun yang belum menyetujui dihadang dialog yang tidak bisa dilewati, lalu disetujui', (tester) async {
      final api = await pumpShell(tester, consented: false);
      expect(find.byKey(const Key('consent_gate')), findsOneWidget);
      await tester.tapAt(const Offset(5, 5)); // ketuk di luar dialog tidak menutupnya
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('consent_gate')), findsOneWidget);

      await tester.tap(find.byKey(const Key('consent_agree')));
      await tester.pumpAndSettle();
      expect(api.consents, 1);
      expect(find.byKey(const Key('consent_gate')), findsNothing);
    });
  });

  group('lupa PIN', () {
    testWidgets('langkah 1 meminta kode untuk nama pengguna atau nomor, lalu menampilkan isian kode', (tester) async {
      final api = FakeApi();
      await pumpReset(tester, api);
      expect(find.textContaining('WhatsApp sudah ditautkan'), findsOneWidget);
      await tester.tap(find.byKey(const Key('reset_submit')));
      await tester.pumpAndSettle();
      expect(find.text('Isi nama pengguna atau nomor HP-mu.'), findsOneWidget);
      expect(api.pinResetRequests, isEmpty);

      await tester.enterText(find.byKey(const Key('reset_identifier')), 'Raka_Dev');
      await tester.tap(find.byKey(const Key('reset_submit')));
      await tester.pumpAndSettle();
      expect(api.pinResetRequests, ['raka_dev']);
      expect(find.byKey(const Key('reset_code')), findsOneWidget);
      expect(find.byKey(const Key('reset_resend')), findsOneWidget);
    });

    testWidgets('langkah 2 memeriksa kode dan kedua PIN sebelum mengirim', (tester) async {
      final api = FakeApi();
      await pumpReset(tester, api);
      await tester.enterText(find.byKey(const Key('reset_identifier')), 'raka_dev');
      await tester.tap(find.byKey(const Key('reset_submit')));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('reset_code')), '12');
      await tester.tap(find.byKey(const Key('reset_submit')));
      await tester.pumpAndSettle();
      expect(find.text('Kodenya 6 angka.'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('reset_code')), '123456');
      await tester.enterText(find.byKey(const Key('reset_pin')), '654321');
      await tester.enterText(find.byKey(const Key('reset_pin2')), '111111');
      await tester.tap(find.byKey(const Key('reset_submit')));
      await tester.pumpAndSettle();
      expect(find.text('Kedua PIN belum sama.'), findsOneWidget);
      expect(api.pinResets, isEmpty);
    });

    testWidgets('kode salah menampilkan pesan server dan tidak berpindah', (tester) async {
      final api = FakeApi();
      await pumpReset(tester, api);
      await tester.enterText(find.byKey(const Key('reset_identifier')), 'raka_dev');
      await tester.tap(find.byKey(const Key('reset_submit')));
      await tester.pumpAndSettle();
      api.pinResetError = ApiException('Kode salah atau sudah kedaluwarsa.', status: 400);
      await tester.enterText(find.byKey(const Key('reset_code')), '123456');
      await tester.enterText(find.byKey(const Key('reset_pin')), '654321');
      await tester.enterText(find.byKey(const Key('reset_pin2')), '654321');
      await tester.tap(find.byKey(const Key('reset_submit')));
      await tester.pumpAndSettle();
      expect(find.text('Kode salah atau sudah kedaluwarsa.'), findsOneWidget);
    });

    testWidgets('berhasil: PIN baru dikirim bersama kode', (tester) async {
      final api = FakeApi();
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => const ResetPinScreen()),
        GoRoute(path: '/login', builder: (_, _) => const Scaffold(body: Text('halaman masuk'))),
      ]);
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_Host(api: api, router: router));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('reset_identifier')), 'raka_dev');
      await tester.tap(find.byKey(const Key('reset_submit')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('reset_code')), '123456');
      await tester.enterText(find.byKey(const Key('reset_pin')), '654321');
      await tester.enterText(find.byKey(const Key('reset_pin2')), '654321');
      await tester.tap(find.byKey(const Key('reset_submit')));
      await tester.pumpAndSettle();
      expect(api.pinResets, [(identifier: 'raka_dev', code: '123456', newPin: '654321')]);
      expect(find.text('halaman masuk'), findsOneWidget);
    });
  });
}

class _Host extends StatelessWidget {
  const _Host({required this.api, required this.router});
  final FakeApi api;
  final GoRouter router;

  @override
  Widget build(BuildContext context) => testAppRouter(router, api: api);
}
