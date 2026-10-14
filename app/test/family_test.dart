import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/core/api_client.dart';
import 'package:kira/features/family/family_screen.dart';
import 'package:kira/shared/family_models.dart';

import 'support/fakes.dart';

const mom = FamilyMember(id: 'l1', phone: '081200000077', status: 'active', permissions: FamilyPermissions());
const pending = FamilyMember(id: 'l2', phone: '081200000078', status: 'pending', permissions: FamilyPermissions());

Future<void> pumpFamily(WidgetTester tester, FakeApi api) async {
  tester.view.physicalSize = const Size(900, 2600);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(testApp(const FamilyScreen(), api: api));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('keadaan kosong menjelaskan apa yang dibagikan dan menawarkan undangan', (tester) async {
    await pumpFamily(tester, FakeApi());
    expect(find.byKey(const Key('family_empty')), findsOneWidget);
    expect(find.textContaining('Kamu yang memilih'), findsOneWidget);
    expect(find.byKey(const Key('invite_phone')), findsOneWidget);
  });

  testWidgets('mengundang mengirim nomor dan izin yang dipilih', (tester) async {
    final api = FakeApi();
    await pumpFamily(tester, api);
    await tester.enterText(find.byKey(const Key('invite_phone')), '081200000077');
    await tester.tap(find.byKey(const Key('invite_perm_reminders')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('invite_send')));
    await tester.pumpAndSettle();
    expect(api.invites.single.phone, '081200000077');
    expect(api.invites.single.permissions.checkinStatus, true);
    expect(api.invites.single.permissions.checkReminders, false);
  });

  testWidgets('nomor tidak valid ditolak sebelum dikirim', (tester) async {
    final api = FakeApi();
    await pumpFamily(tester, api);
    await tester.enterText(find.byKey(const Key('invite_phone')), 'abc');
    await tester.tap(find.byKey(const Key('invite_send')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('invite_error')), findsOneWidget);
    expect(api.invites, isEmpty);
  });

  testWidgets('kesalahan dari server ditampilkan dengan ramah', (tester) async {
    final api = FakeApi();
    await pumpFamily(tester, api);
    api.familyError = ApiException('Nomor ini sudah diundang.', status: 409);
    await tester.enterText(find.byKey(const Key('invite_phone')), '081200000077');
    await tester.tap(find.byKey(const Key('invite_send')));
    await tester.pumpAndSettle();
    expect(find.text('Nomor ini sudah diundang.'), findsOneWidget);
  });

  testWidgets('pemilik mengubah izin per anggota dan mencabut akses', (tester) async {
    final api = FakeApi()..family = const FamilyOverview(members: [mom, pending]);
    await pumpFamily(tester, api);
    expect(find.text('081200000077'), findsOneWidget);
    expect(find.textContaining('Menunggu'), findsOneWidget);

    await tester.tap(find.byKey(const Key('perm_checkin_l1')));
    await tester.pumpAndSettle();
    expect(api.permissionChanges.single.id, 'l1');
    expect(api.permissionChanges.single.permissions.checkinStatus, false);
    expect(api.permissionChanges.single.permissions.checkReminders, true);

    await tester.tap(find.byKey(const Key('remove_l1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('confirm_remove')));
    await tester.pumpAndSettle();
    expect(api.ended, ['l1']);
  });

  testWidgets('menerima undangan dari orang lain', (tester) async {
    final api = FakeApi()
      ..family = const FamilyOverview(
        invitesForMe: [FamilyContact(id: 'i1', ownerName: 'Raka', permissions: FamilyPermissions())],
      );
    await pumpFamily(tester, api);
    expect(find.textContaining('Raka'), findsWidgets);
    await tester.tap(find.byKey(const Key('accept_i1')));
    await tester.pumpAndSettle();
    expect(api.accepted, ['i1']);
  });

  testWidgets('pendamping hanya melihat ringkasan yang dibagikan, dengan nada mengajak', (tester) async {
    final api = FakeApi()
      ..family = const FamilyOverview(
        watching: [FamilyContact(id: 'w1', ownerName: 'Raka', permissions: FamilyPermissions())],
      )
      ..statuses = {
        'w1': const FamilyStatus(
          ownerName: 'Raka',
          checkinShared: true,
          daysAgo: 4,
          suggestion: 'Sudah beberapa hari belum check-in. Mungkin ini saat yang baik untuk menyapa.',
          remindersShared: false,
        ),
      };
    await pumpFamily(tester, api);
    await tester.tap(find.byKey(const Key('watch_w1')));
    await tester.pumpAndSettle();
    expect(find.textContaining('4 hari'), findsOneWidget);
    expect(find.textContaining('menyapa'), findsOneWidget);
    expect(find.textContaining('tidak dibagikan'), findsOneWidget); // anjuran cek tidak diizinkan
    expect(find.textContaining('rendang'), findsNothing);
  });
}
