import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/core/providers.dart';
import 'package:kira/features/jeda/jeda_bridge.dart';
import 'package:kira/features/jeda/jeda_facts.dart';
import 'package:kira/features/jeda/jeda_models.dart';
import 'package:kira/features/jeda/jeda_screen.dart';

import 'jeda_test.dart' show FakeJedaBridge, allowed;
import 'support/fakes.dart';

Future<(FakeApi, FakeJedaBridge)> pump(WidgetTester tester, {FakeJedaBridge? bridge, JedaSettings? saved, FakeApi? api}) async {
  tester.view.physicalSize = const Size(900, 4200);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final prefs = MemoryPrefsStore();
  if (saved != null) await prefs.write('jeda_v1', saved.toJson());
  final fakeApi = api ?? FakeApi();
  final fakeBridge = bridge ?? FakeJedaBridge(perms: allowed);
  await tester.pumpWidget(testApp(const JedaScreen(), api: fakeApi, prefs: prefs, overrides: [jedaBridgeProvider.overrideWithValue(fakeBridge)]));
  await tester.pumpAndSettle();
  return (fakeApi, fakeBridge);
}

void main() {
  group('fun fact kesehatan', () {
    test('setiap fakta punya sumber dan teks, dan tidak ada yang melanggar aturan produk', () {
      expect(jedaFacts.length, greaterThanOrEqualTo(10));
      final ids = jedaFacts.map((f) => f.id).toSet();
      expect(ids.length, jedaFacts.length, reason: 'id harus unik');
      for (final f in jedaFacts) {
        expect(f.source.trim(), isNotEmpty, reason: f.id);
        expect(f.text.trim().length, greaterThan(40), reason: f.id);
        final all = '${f.category} ${f.text}'.toLowerCase();
        expect(all, isNot(contains('aman')), reason: '${f.id}: kata "aman" dilarang');
        expect(all, isNot(contains('menderita')), reason: f.id);
        expect(all, isNot(contains('dosis')), reason: '${f.id}: tidak memberi saran obat atau dosis');
        expect(all, isNot(contains('obat')), reason: f.id);
      }
    });

    test('fakta dari studi kecil mengatakan itu studi kecil', () {
      for (final id in ['sleep_appetite', 'screen_melatonin', 'walk_after_meal']) {
        final f = jedaFacts.firstWhere((x) => x.id == id);
        expect(f.text.toLowerCase(), contains('studi kecil'), reason: id);
      }
    });

    test('angka yang dikutip cocok dengan sumbernya', () {
      String text(String id) => jedaFacts.firstWhere((f) => f.id == id).text;
      expect(text('dpp_lifestyle_58'), allOf(contains('3.234'), contains('58%')));
      expect(text('who_veg_400'), contains('400 gram'));
      expect(text('who_hypertension_silent'), contains('44%'));
      expect(text('riskesdas_hypertension'), contains('34,1%'));
      expect(text('who_salt'), allOf(contains('5 gram'), contains('2 gram natrium')));
      expect(text('heart_rate_rest'), contains('60 sampai 100'));
      expect(text('sleep_appetite'), allOf(contains('28%'), contains('18%'), contains('24%')));
    });

    test('pengaturan: bawaan mati, fakta hanya ikut ke perangkat bila dinyalakan', () {
      const off = JedaSettings(enabled: true);
      expect(off.funFact, isFalse);
      expect(off.toBridgeMap().containsKey('facts'), isFalse);
      final on = off.copyWith(funFact: true);
      final facts = on.toBridgeMap()['facts'] as List;
      expect(facts.length, jedaFacts.length);
      expect((facts.first as Map)['source'], isNotEmpty);
      expect(on.toMap().containsKey('facts'), isFalse); // tidak disimpan di preferensi lokal
    });

    test('pengaturan lama tanpa kolom baru dimuat dengan nilai bawaan', () {
      final s = JedaSettings.fromJson('{"enabled":true,"apps":["com.instagram.android"],"grace_minutes":60}');
      expect((s.funFact, s.useGrace, s.graceMinutes), (false, true, 60));
    });

    testWidgets('menyalakan Jeda pertama kali ikut menyalakan fun fact; saklarnya bisa dimatikan dan dinyalakan lagi', (tester) async {
      final (_, bridge) = await pump(tester);
      await tester.tap(find.byKey(const Key('jeda_enabled')));
      await tester.pumpAndSettle();
      expect(bridge.applied.last.settings.funFact, isTrue);
      expect(bridge.applied.last.settings.toBridgeMap()['facts'], isNotEmpty);
      await tester.ensureVisible(find.byKey(const Key('jeda_preview_fact')));
      await tester.tap(find.byKey(const Key('jeda_preview_fact')));
      await tester.pumpAndSettle();
      expect(bridge.previews, ['fact']);

      await tester.ensureVisible(find.byKey(const Key('jeda_fun_fact')));
      await tester.tap(find.byKey(const Key('jeda_fun_fact')));
      await tester.pumpAndSettle();
      expect(bridge.applied.last.settings.funFact, isFalse);
      expect(find.byKey(const Key('jeda_preview_fact')), findsNothing);
      await tester.tap(find.byKey(const Key('jeda_fun_fact')));
      await tester.pumpAndSettle();
      expect(bridge.applied.last.settings.funFact, isTrue);
    });

    testWidgets('tanpa sinyal: fakta tetap sampai ke perangkat karena ikut di pengaturan, bukan di isi kartu', (tester) async {
      final api = FakeApi()..planError = Exception('offline');
      final (_, bridge) = await pump(tester,
          api: api, saved: const JedaSettings(enabled: true, apps: ['com.instagram.android'], funFact: true));
      expect(bridge.applied.last.payload, isNull);
      expect(bridge.applied.last.settings.funFact, isTrue);
    });
  });

  group('masa bebas setelah kartu ditutup', () {
    testWidgets('bisa dimatikan: pilihan menit hilang dan keterangan menjelaskan kartu muncul lagi tiap kali', (tester) async {
      final (_, bridge) = await pump(tester);
      await tester.tap(find.byKey(const Key('jeda_enabled')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('jeda_use_grace')));
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('jeda_use_grace'))).value, isTrue);
      expect(find.byKey(const Key('jeda_grace_30')), findsOneWidget);

      await tester.tap(find.byKey(const Key('jeda_use_grace')));
      await tester.pumpAndSettle();
      expect(bridge.applied.last.settings.useGrace, isFalse);
      expect(find.byKey(const Key('jeda_grace_30')), findsNothing);
      expect(find.textContaining('kartu muncul lagi setiap kali sosmed dibuka'), findsOneWidget);
    });

    testWidgets('dinyalakan lagi: menit pilihan sebelumnya tetap', (tester) async {
      final (_, bridge) = await pump(tester,
          saved: const JedaSettings(enabled: true, apps: ['com.instagram.android'], graceMinutes: 60, useGrace: false));
      await tester.ensureVisible(find.byKey(const Key('jeda_use_grace')));
      await tester.tap(find.byKey(const Key('jeda_use_grace')));
      await tester.pumpAndSettle();
      expect((bridge.applied.last.settings.useGrace, bridge.applied.last.settings.graceMinutes), (true, 60));
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('jeda_grace_60'))).selected, isTrue);
    });
  });

  group('izin terkunci "setelan terbatas"', () {
    testWidgets('bantuan tampil bila izin belum lengkap, menjelaskan langkahnya, dan membuka Info aplikasi', (tester) async {
      final (_, bridge) = await pump(tester, bridge: FakeJedaBridge());
      await tester.tap(find.byKey(const Key('jeda_enabled')));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('jeda_restricted_help')));
      await tester.tap(find.byKey(const Key('jeda_restricted_help')));
      await tester.pumpAndSettle();
      final steps = tester.widget<Text>(find.byKey(const Key('jeda_restricted_steps'))).data!;
      expect(steps, contains('Izinkan setelan terbatas'));
      expect(steps, contains('titik tiga'));

      await tester.ensureVisible(find.byKey(const Key('jeda_open_app_info')));
      await tester.tap(find.byKey(const Key('jeda_open_app_info')));
      await tester.pump();
      expect(bridge.appInfoOpened, 1);
    });

    testWidgets('semua izin sudah ada: bantuan disembunyikan', (tester) async {
      await pump(tester, saved: const JedaSettings(enabled: true, apps: ['com.instagram.android']));
      expect(find.byKey(const Key('jeda_restricted_help')), findsNothing);
    });
  });
}
