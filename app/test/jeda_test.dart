import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/core/providers.dart';
import 'package:kira/features/jeda/jeda_bridge.dart';
import 'package:kira/features/jeda/jeda_content.dart';
import 'package:kira/features/jeda/jeda_controller.dart';
import 'package:kira/features/jeda/jeda_models.dart';
import 'package:kira/features/jeda/jeda_screen.dart';
import 'package:kira/shared/account_models.dart';
import 'package:kira/shared/models.dart';

import 'support/fakes.dart';

/// Jembatan Android palsu: mencatat apa yang dikirim ke perangkat.
class FakeJedaBridge implements JedaBridge {
  FakeJedaBridge({
    this.supported = true,
    this.perms = const JedaPermissions(),
    this.installed = const [JedaApp('com.instagram.android', 'Instagram'), JedaApp('com.twitter.android', 'X'), JedaApp('com.google.android.youtube', 'YouTube')],
  });

  @override
  final bool supported;
  JedaPermissions perms;
  final List<JedaApp> installed;
  final applied = <({JedaSettings settings, JedaPayload? payload})>[];
  final previews = <String>[];
  int stops = 0, usageOpened = 0, overlayOpened = 0;
  String? launchRoute;

  @override
  Future<JedaPermissions> permissions() async => perms;

  @override
  Future<void> openUsageAccess() async => usageOpened++;

  @override
  Future<void> openOverlay() async => overlayOpened++;

  @override
  Future<List<JedaApp>> installedApps() async => installed;

  @override
  Future<void> apply(JedaSettings settings, JedaPayload? payload) async => applied.add((settings: settings, payload: payload));

  @override
  Future<void> stop() async => stops++;

  @override
  Future<void> preview(String kind) async => previews.add(kind);

  @override
  Future<String?> takeLaunchRoute() async {
    final r = launchRoute;
    launchRoute = null;
    return r;
  }
}

const allowed = JedaPermissions(usageAccess: true, overlay: true);
final evening = DateTime(2026, 10, 16, 20, 5);

PlanMeal meal(String slot, String label, String title, {bool done = false, String why = ''}) =>
    PlanMeal(slot: slot, label: label, time: '12:00', title: title, why: why, done: done);

DayPlan plan({List<PlanMeal>? meals, PlanExercise? exercise, DateTime? date}) => DayPlan(
      date: date ?? DateTime(2026, 10, 16),
      kcalTarget: 2650,
      energySource: 'AKG 2019',
      meals: meals ?? fakeDayPlan(DateTime(2026, 10, 16)).meals,
      exercise: exercise ?? const PlanExercise(minutes: 30, activity: 'jalan cepat', time: '17:00'),
      sleep: const PlanSleep(hours: 8, bedtime: '22:00', wakeTime: '06:00'),
    );

String textOf(JedaCard c) => [c.title, ...c.sections.expand((s) => [s.heading, s.body]), c.footnote, c.actionLabel].join(' ');

void main() {
  group('isi kartu (fungsi murni)', () {
    test('pagi: olahraga, tiap waktu makan dengan contoh dan alasannya, lalu tidur', () {
      final card = morningCard(fakeDayPlan(DateTime(2026, 10, 16)));
      expect(card.kind, 'morning');
      final byHeading = {for (final s in card.sections) s.heading: s.body};
      expect(byHeading['Olahraga'], 'Jalan cepat 10 menit, sekitar 17.00.');
      expect(byHeading['Sarapan'], contains('Roti telur (roti tawar dan telur ceplok)'));
      expect(byHeading['Sarapan'], contains('Gula 4 g, masih di bawah anggaran sarapan 12 g; 280 kkal.'));
      expect(byHeading['Makan siang'], contains('Nasi warteg'));
      expect(byHeading['Tidur'], 'Target 8 jam: tidur sekitar 22.00, bangun 06.00.');
      expect(card.route, '/plan');
    });

    test('pagi: waktu makan yang sudah tercatat tidak diulang', () {
      final p = plan(meals: [meal('breakfast', 'sarapan', 'Roti', done: true), meal('lunch', 'makan siang', 'Nasi')]);
      expect(morningCard(p).sections.map((s) => s.heading), isNot(contains('Sarapan')));
    });

    test('pagi: olahraga yang ditahan memakai penjelasan dari server, tanpa menyuruh', () {
      final p = plan(exercise: const PlanExercise(blocked: true, why: 'Bicarakan dengan tenaga kesehatan dulu.'));
      expect(morningCard(p).sections.first.body, 'Bicarakan dengan tenaga kesehatan dulu.');
      expect(morningCard(plan(exercise: const PlanExercise())).sections.first.body, contains('tidak ada usulan olahraga'));
    });

    test('malam: menyebut yang belum tercatat (tanpa selingan), dan olahraga', () {
      final p = plan(meals: [
        meal('breakfast', 'sarapan', 'Roti', done: true),
        meal('lunch', 'makan siang', 'Nasi'),
        meal('snack', 'selingan', 'Pisang'),
        meal('dinner', 'makan malam', 'Pecel'),
      ]);
      final card = eveningCard(p, evening)!;
      expect(card.sections.first.body, 'Belum ada catatan makan siang dan makan malam.');
      expect(card.sections.map((s) => s.heading), contains('Olahraga'));
      expect(card.footnote, contains('20.05'));
      expect(card.route, '/chat');
    });

    test('malam: semua sudah tercatat berarti tidak ada kartu', () {
      final p = plan(
        meals: [meal('breakfast', 'sarapan', 'Roti', done: true), meal('lunch', 'makan siang', 'Nasi', done: true), meal('dinner', 'makan malam', 'Pecel', done: true)],
        exercise: const PlanExercise(minutes: 30, activity: 'jalan cepat', done: true),
      );
      expect(eveningCard(p, evening), isNull);
    });

    test('malam: olahraga yang ditahan tidak dianggap terlewat', () {
      final p = plan(
        meals: [meal('lunch', 'makan siang', 'Nasi', done: true)],
        exercise: const PlanExercise(blocked: true, why: 'x'),
      );
      expect(eveningCard(p, evening), isNull);
    });

    test('tidur memuat jam tidur dan bangun dari rencana', () {
      final card = nightCard(plan());
      expect(card.sections.single.body, contains('tidur sekitar 22.00 dan bangun 06.00'));
    });

    test('info lain hanya bila saran cek sudah waktunya ditanyakan', () {
      expect(otherCard(null), isNull);
      expect(otherCard(const CheckRecommendation(id: 'r', testKind: 'bp', reason: 'x')), isNull);
      final card = otherCard(const CheckRecommendation(id: 'r', testKind: 'fasting_glucose', reason: 'x', followUp: true))!;
      expect(card.sections.single.heading, 'Cek gula darah puasa');
      expect(card.route, '/check');
    });

    test('payload: kartu pagi untuk hari ini dan hari-hari berikutnya, dan bisa dijadikan JSON', () {
      final today = fakeDayPlan(DateTime(2026, 10, 16));
      final week = [for (var i = 0; i < 7; i++) fakeDayPlan(DateTime(2026, 10, 16 + i), lunch: 'Menu hari $i')];
      final payload = buildJedaPayload(today: today, week: week, now: evening);
      expect(payload.morningByDate.keys, containsAll(['2026-10-16', '2026-10-17', '2026-10-22']));
      expect(payload.morningByDate['2026-10-17']!.sections.any((s) => s.body.contains('Menu hari 1')), isTrue);
      expect(payload.morningByDate['2026-10-16']!.sections.any((s) => s.body.contains('Nasi warteg')), isTrue);
      final map = jsonDecode(jsonEncode(payload.toMap())) as Map<String, dynamic>;
      expect(map['generated_at'], evening.millisecondsSinceEpoch);
      expect(map['other'], isNull);
      expect((map['night'] as Map)['kind'], 'night');
    });

    test('kata dan klaim yang dilarang tidak muncul di kartu mana pun', () {
      final payload = buildJedaPayload(
        today: fakeDayPlan(DateTime(2026, 10, 16)),
        week: [fakeDayPlan(DateTime(2026, 10, 17))],
        check: const CheckRecommendation(id: 'r', testKind: 'bp', reason: 'x', followUp: true),
        now: evening,
      );
      final cards = [...payload.morningByDate.values, payload.morningGeneric, payload.evening!, payload.eveningGeneric, payload.night, payload.other!];
      final text = cards.map(textOf).join(' ').toLowerCase();
      for (final forbidden in ['aman', 'diagnosis', 'obat', 'penyakit', 'mmhg', 'mg/dl']) {
        expect(text, isNot(contains(forbidden)), reason: forbidden);
      }
    });
  });

  group('pengaturan', () {
    test('disimpan dan dibaca kembali; rusak jatuh ke bawaan; nilai dijepit', () {
      const s = JedaSettings(enabled: true, apps: ['com.instagram.android'], morningStart: 6 * 60, eveningStart: 20 * 60, graceMinutes: 60, showOther: false);
      final back = JedaSettings.fromJson(s.toJson());
      expect(back.apps, ['com.instagram.android']);
      expect((back.enabled, back.morningStart, back.eveningStart, back.graceMinutes, back.showOther), (true, 360, 1200, 60, false));
      expect(JedaSettings.fromJson('bukan json').enabled, isFalse);
      expect(JedaSettings.fromJson(null).enabled, isFalse);
      expect(JedaSettings.fromJson('{"morning_start": 99999, "grace_minutes": 0}').morningStart, 1439);
      expect(JedaSettings.fromJson('{"grace_minutes": 0}').graceMinutes, 5);
    });

    test('mati secara bawaan dan WhatsApp tidak ada di daftar aplikasi', () {
      expect(const JedaSettings().enabled, isFalse);
      expect(knownSocialApps.keys.any((k) => k.contains('whatsapp')), isFalse);
      expect(defaultSocialApps.every(knownSocialApps.containsKey), isTrue);
    });
  });

  group('layar dan pengendali', () {
    Future<(FakeApi, FakeJedaBridge, MemoryPrefsStore)> pump(
      WidgetTester tester, {
      FakeJedaBridge? bridge,
      FakeApi? api,
      MemoryPrefsStore? prefs,
    }) async {
      tester.view.physicalSize = const Size(900, 3200);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final a = api ?? FakeApi();
      final b = bridge ?? FakeJedaBridge();
      final p = prefs ?? MemoryPrefsStore();
      await tester.pumpWidget(testApp(const JedaScreen(), api: a, prefs: p, overrides: [jedaBridgeProvider.overrideWithValue(b)]));
      await tester.pumpAndSettle();
      return (a, b, p);
    }

    testWidgets('di platform tanpa dukungan: dijelaskan, tidak ada saklar', (tester) async {
      await pump(tester, bridge: FakeJedaBridge(supported: false));
      expect(find.byKey(const Key('jeda_unsupported')), findsOneWidget);
      expect(find.byKey(const Key('jeda_enabled')), findsNothing);
    });

    testWidgets('mati secara bawaan; belum ada yang dikirim ke perangkat', (tester) async {
      final (_, bridge, _) = await pump(tester);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('jeda_enabled'))).value, isFalse);
      expect(find.byKey(const Key('jeda_perm_usage')), findsNothing);
      expect(bridge.applied, isEmpty);
    });

    testWidgets('menyalakan: aplikasi sosmed terpasang dicentang (YouTube tidak), isi kartu dikirim, tersimpan', (tester) async {
      final (_, bridge, prefs) = await pump(tester, bridge: FakeJedaBridge(perms: allowed));
      await tester.tap(find.byKey(const Key('jeda_enabled')));
      await tester.pumpAndSettle();
      final sent = bridge.applied.last;
      expect(sent.settings.enabled, isTrue);
      expect(sent.settings.apps, ['com.instagram.android', 'com.twitter.android']);
      expect(sent.payload, isNotNull);
      expect(sent.payload!.morningByDate, isNotEmpty);
      expect(await prefs.read('jeda_v1'), contains('"enabled":true'));
      expect(tester.widget<CheckboxListTile>(find.byKey(const Key('jeda_app_com.google.android.youtube'))).value, isFalse);
      expect(find.text('Menjaga 2 aplikasi'), findsOneWidget);
    });

    testWidgets('izin belum lengkap: dijelaskan, tombol membuka pengaturan, tanpa contoh kartu', (tester) async {
      final (_, bridge, _) = await pump(tester, bridge: FakeJedaBridge(perms: const JedaPermissions(usageAccess: true)));
      await tester.tap(find.byKey(const Key('jeda_enabled')));
      await tester.pumpAndSettle();
      expect(find.text('Menunggu izin di bawah'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('jeda_perm_usage')), matching: find.text('Diizinkan')), findsOneWidget);
      await tester.tap(find.descendant(of: find.byKey(const Key('jeda_perm_overlay')), matching: find.text('Izinkan')));
      await tester.pumpAndSettle();
      expect(bridge.overlayOpened, 1);
      expect(bridge.usageOpened, 0);
      expect(find.byKey(const Key('jeda_preview_morning')), findsNothing);
    });

    testWidgets('kembali dari pengaturan izin: izin dibaca ulang dan kartu dikirim', (tester) async {
      final bridge = FakeJedaBridge();
      final (_, _, _) = await pump(tester, bridge: bridge);
      await tester.tap(find.byKey(const Key('jeda_enabled')));
      await tester.pumpAndSettle();
      bridge.perms = allowed;
      final before = bridge.applied.length;
      final container = ProviderScope.containerOf(tester.element(find.byType(JedaScreen)));
      await container.read(jedaProvider.notifier).refreshPermissions();
      await tester.pumpAndSettle();
      expect(container.read(jedaProvider).running, isTrue);
      expect(bridge.applied.length, greaterThan(before));
    });

    testWidgets('contoh kartu: memanggil perangkat dengan jenis yang dipilih', (tester) async {
      final (_, bridge, _) = await pump(tester, bridge: FakeJedaBridge(perms: allowed));
      await tester.tap(find.byKey(const Key('jeda_enabled')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('jeda_preview_night')));
      await tester.pumpAndSettle();
      expect(bridge.previews, ['night']);
    });

    testWidgets('mencentang dan melepas aplikasi mengirim daftar baru', (tester) async {
      final (_, bridge, _) = await pump(tester, bridge: FakeJedaBridge(perms: allowed));
      await tester.tap(find.byKey(const Key('jeda_enabled')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('jeda_app_com.twitter.android')));
      await tester.pumpAndSettle();
      expect(bridge.applied.last.settings.apps, ['com.instagram.android']);
      await tester.tap(find.byKey(const Key('jeda_app_com.google.android.youtube')));
      await tester.pumpAndSettle();
      expect(bridge.applied.last.settings.apps, ['com.instagram.android', 'com.google.android.youtube']);
    });

    testWidgets('jeda dan info lain dapat diubah dan sampai ke perangkat', (tester) async {
      final (_, bridge, _) = await pump(tester, bridge: FakeJedaBridge(perms: allowed));
      await tester.tap(find.byKey(const Key('jeda_enabled')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('jeda_grace_60')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('jeda_other')));
      await tester.pumpAndSettle();
      final s = bridge.applied.last.settings;
      expect((s.graceMinutes, s.showOther), (60, false));
    });

    testWidgets('mematikan menghentikan penjagaan dan menghapus pengaturan tersimpan', (tester) async {
      final (_, bridge, prefs) = await pump(tester, bridge: FakeJedaBridge(perms: allowed));
      await tester.tap(find.byKey(const Key('jeda_enabled')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('jeda_enabled')));
      await tester.pumpAndSettle();
      expect(bridge.stops, 1);
      expect(await prefs.read('jeda_v1'), isNull);
    });

    testWidgets('tanpa sinyal: pengaturan tetap dikirim, isi kartu lama dipertahankan (payload null)', (tester) async {
      final api = FakeApi()..planError = Exception('offline');
      final (_, bridge, _) = await pump(tester, api: api, bridge: FakeJedaBridge(perms: allowed));
      await tester.tap(find.byKey(const Key('jeda_enabled')));
      await tester.pumpAndSettle();
      expect(bridge.applied.last.settings.enabled, isTrue);
      expect(bridge.applied.last.payload, isNull);
    });

    testWidgets('pengaturan tersimpan dimuat dan langsung disinkronkan saat layar dibuka', (tester) async {
      final prefs = MemoryPrefsStore();
      await prefs.write('jeda_v1', const JedaSettings(enabled: true, apps: ['com.instagram.android']).toJson());
      final (_, bridge, _) = await pump(tester, prefs: prefs, bridge: FakeJedaBridge(perms: allowed));
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('jeda_enabled'))).value, isTrue);
      expect(bridge.applied, isNotEmpty);
      expect(bridge.applied.last.payload, isNotNull);
    });

    test('keluar dari akun mematikan penjagaan dan menghapus pengaturan', () async {
      final bridge = FakeJedaBridge(perms: allowed);
      final prefs = MemoryPrefsStore();
      final c = ProviderContainer(overrides: [
        apiProvider.overrideWithValue(FakeApi()),
        tokenStoreProvider.overrideWithValue(MemoryTokenStore('a')),
        prefsStoreProvider.overrideWithValue(prefs),
        jedaBridgeProvider.overrideWithValue(bridge),
      ]);
      addTearDown(c.dispose);
      await c.read(authProvider.notifier).setTokens(const AuthTokens('akun-a', 'r'));
      await c.read(jedaProvider.notifier).load();
      await c.read(jedaProvider.notifier).update(const JedaSettings(enabled: true, apps: ['com.instagram.android']));
      expect(await prefs.read('jeda_v1'), isNotNull);
      await c.read(authProvider.notifier).setTokens(const AuthTokens('akun-b', 'r'));
      await Future<void>.delayed(Duration.zero);
      expect(c.read(jedaProvider).settings.enabled, isFalse);
      expect(bridge.stops, 1);
      expect(await prefs.read('jeda_v1'), isNull);
    });
  });
}
