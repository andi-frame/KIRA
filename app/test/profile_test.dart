import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/features/profile/profile_screen.dart';

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
}
