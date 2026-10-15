import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/core/api_client.dart';
import 'package:kira/features/auth/login_screen.dart';

import 'support/fakes.dart';

Future<void> pumpLogin(WidgetTester tester, FakeApi api) async {
  tester.view.physicalSize = const Size(900, 2000);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(testApp(const LoginScreen(), api: api));
  await tester.pumpAndSettle();
}

Future<void> submit(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('auth_submit')));
  await tester.pumpAndSettle();
}

/// Mencentang persetujuan lewat kotaknya (bukan bagian tengah baris, yang membuka teks persetujuan).
Future<void> tickConsent(WidgetTester tester) async {
  await tester.tap(find.descendant(of: find.byKey(const Key('register_consent')), matching: find.byType(Checkbox)));
  await tester.pumpAndSettle();
}

Future<void> openRegister(WidgetTester tester) async {
  await tester.tap(find.text('Daftar').first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('masuk memakai satu kolom: nama pengguna atau nomor HP', (tester) async {
    final api = FakeApi();
    await pumpLogin(tester, api);
    expect(find.byKey(const Key('login_identifier')), findsOneWidget);
    expect(find.byKey(const Key('register_username')), findsNothing);

    await tester.enterText(find.byKey(const Key('login_identifier')), 'Raka');
    await tester.enterText(find.byKey(const Key('login_pin')), '123456');
    await submit(tester);
    expect(api.logins, [(identifier: 'raka', pin: '123456')]); // huruf kecil, tanpa spasi

    await tester.enterText(find.byKey(const Key('login_identifier')), '081234567890');
    await submit(tester);
    expect(api.logins.last.identifier, '081234567890');
  });

  testWidgets('masuk menolak kolom kosong dan PIN yang bukan angka 4-6 digit sebelum memanggil server', (tester) async {
    final api = FakeApi();
    await pumpLogin(tester, api);
    await submit(tester);
    expect(find.textContaining('nama pengguna atau nomor HP'), findsWidgets);
    await tester.enterText(find.byKey(const Key('login_identifier')), 'raka');
    await tester.enterText(find.byKey(const Key('login_pin')), '12');
    await submit(tester);
    expect(find.textContaining('PIN harus 4 sampai 6 angka'), findsOneWidget);
    expect(api.logins, isEmpty);
  });

  testWidgets('daftar meminta nama pengguna DAN nomor HP, dan menjelaskan nomor dipakai untuk WhatsApp', (tester) async {
    final api = FakeApi();
    await pumpLogin(tester, api);
    await openRegister(tester);
    expect(find.byKey(const Key('register_username')), findsOneWidget);
    expect(find.byKey(const Key('register_phone')), findsOneWidget);
    expect(find.textContaining('WhatsApp'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('register_username')), 'Raka.Dev');
    await tester.enterText(find.byKey(const Key('register_phone')), '081234567890');
    await tester.enterText(find.byKey(const Key('login_pin')), '123456');
    await tickConsent(tester);
    await submit(tester);
    expect(api.registrations, [(phone: '081234567890', username: 'raka.dev', pin: '123456', consent: true)]);
  });

  testWidgets('daftar tanpa nomor HP ditolak walau nama pengguna benar', (tester) async {
    final api = FakeApi();
    await pumpLogin(tester, api);
    await openRegister(tester);
    await tester.enterText(find.byKey(const Key('register_username')), 'raka_dev');
    await tester.enterText(find.byKey(const Key('login_pin')), '123456');
    await submit(tester);
    expect(find.textContaining('Nomor HP'), findsWidgets);
    expect(api.registrations, isEmpty);
  });

  testWidgets('nama pengguna yang tidak sesuai aturan dijelaskan', (tester) async {
    final api = FakeApi();
    await pumpLogin(tester, api);
    await openRegister(tester);
    for (final bad in ['ab', '1raka', 'raka dev', '081234567890', 'raka-dev']) {
      await tester.enterText(find.byKey(const Key('register_username')), bad);
      await tester.enterText(find.byKey(const Key('register_phone')), '081234567890');
      await tester.enterText(find.byKey(const Key('login_pin')), '123456');
      await submit(tester);
      expect(find.textContaining('3-20 karakter'), findsOneWidget, reason: bad);
    }
    expect(api.registrations, isEmpty);
  });

  testWidgets('pesan dari server (mis. nama pengguna dipakai) ditampilkan', (tester) async {
    final api = FakeApi()..loginError = ApiException('Nama pengguna sudah dipakai', status: 409);
    await pumpLogin(tester, api);
    await openRegister(tester);
    await tester.enterText(find.byKey(const Key('register_username')), 'raka_dev');
    await tester.enterText(find.byKey(const Key('register_phone')), '081234567890');
    await tester.enterText(find.byKey(const Key('login_pin')), '123456');
    await tickConsent(tester);
    await submit(tester);
    expect(find.text('Nama pengguna sudah dipakai'), findsOneWidget);
  });
}
