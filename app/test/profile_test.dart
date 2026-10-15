import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/core/api_client.dart';
import 'package:kira/features/profile/profile_screen.dart';
import 'package:kira/shared/models.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('profil menyediakan jalan ke keluarga, ringkasan dokter, dan WhatsApp', (tester) async {
    await tester.pumpWidget(testApp(const ProfileScreen(), token: 'token'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tile_family')), findsOneWidget);
    expect(find.byKey(const Key('tile_doctor')), findsOneWidget);
    expect(find.byKey(const Key('tile_whatsapp')), findsOneWidget);
    expect(find.byKey(const Key('tile_health')), findsOneWidget);
  });

  testWidgets('menautkan WhatsApp menampilkan kode dan peringatan prototype', (tester) async {
    await tester.pumpWidget(testApp(const ProfileScreen(), api: FakeApi()..linkCode = 'KIRA 4821', token: 'token'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('tile_whatsapp')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tile_whatsapp')));
    await tester.pumpAndSettle();
    expect(find.text('KIRA 4821'), findsOneWidget);
    expect(find.textContaining('prototype'), findsOneWidget);
  });

  testWidgets('akun yang sudah punya nama pengguna menampilkannya, tanpa tombol membuat', (tester) async {
    final api = FakeApi()..profile = const Profile(username: 'raka_dev', birthDate: '1998-03-14', sex: 'male', heightCm: 170, weightKg: 78);
    await tester.pumpWidget(testApp(const ProfileScreen(), api: api, token: 'token'));
    await tester.pumpAndSettle();
    expect(find.text('@raka_dev'), findsOneWidget);
    expect(find.byKey(const Key('tile_username')), findsNothing);
  });

  testWidgets('akun lama tanpa nama pengguna bisa membuatnya dari profil', (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(testApp(const ProfileScreen(), api: api, token: 'token'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tile_username')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('username_input')), '1x');
    await tester.tap(find.byKey(const Key('username_save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('3-20 karakter'), findsOneWidget);
    expect(api.usernameChanges, isEmpty);

    await tester.enterText(find.byKey(const Key('username_input')), 'Dian_01');
    await tester.tap(find.byKey(const Key('username_save')));
    await tester.pumpAndSettle();
    expect(api.usernameChanges, ['dian_01']);
    expect(find.text('@dian_01'), findsOneWidget);
    expect(find.byKey(const Key('tile_username')), findsNothing);
  });

  testWidgets('nama pengguna yang sudah dipakai orang lain menampilkan pesan server dan dialog tetap terbuka', (tester) async {
    final api = FakeApi()..usernameError = ApiException('Nama pengguna sudah dipakai', status: 409);
    await tester.pumpWidget(testApp(const ProfileScreen(), api: api, token: 'token'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tile_username')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('username_input')), 'dipakai');
    await tester.tap(find.byKey(const Key('username_save')));
    await tester.pumpAndSettle();
    expect(find.text('Nama pengguna sudah dipakai'), findsOneWidget);
    expect(find.byKey(const Key('username_input')), findsOneWidget);
  });
}
