import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/core/theme.dart';
import 'package:kira/features/check/check_screen.dart';
import 'package:kira/features/trends/trends_screen.dart';
import 'package:kira/shared/insight_models.dart';
import 'package:kira/shared/models.dart';

import 'support/fakes.dart';

Future<FakeApi> pumpCheck(WidgetTester tester, {FakeApi? api, FakeLinks? links}) async {
  tester.view.physicalSize = const Size(900, 3200);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final fake = api ?? FakeApi();
  await tester.pumpWidget(testApp(const CheckScreen(),
      api: fake, overrides: [locationOverride((lat: -6.893, lng: 107.613)), if (links != null) linksOverride(links)]));
  await tester.pumpAndSettle();
  return fake;
}

Future<void> openHeartRate(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(const Key('heart_rate_button')));
  await tester.tap(find.byKey(const Key('heart_rate_button')));
  await tester.pumpAndSettle();
}

void main() {
  group('detak jantung', () {
    testWidgets('tombol di Cek membuka isian detak jantung dan menyimpannya sebagai hasil istirahat', (tester) async {
      final api = await pumpCheck(tester,
          api: FakeApi()..onResult = (k, v) async => const ResultOutcome(saved: true, hrRange: 'normal_range'));
      await openHeartRate(tester);
      expect(find.byKey(const Key('hr_input')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('hr_input')), '72');
      await tester.tap(find.byKey(const Key('result_save')));
      await tester.pumpAndSettle();

      expect(api.results.single.kind, 'resting_heart_rate');
      expect(api.results.single.value, {'bpm': 72});
      expect(find.byKey(const Key('hr_outcome')), findsOneWidget);
      expect(find.textContaining('rentang 60-100'), findsOneWidget);
      // Detak jantung tidak masuk proyeksi diabetes: tidak boleh mengklaim proyeksi dikalibrasi ulang.
      expect(find.textContaining('tidak mengubah proyeksi diabetes'), findsOneWidget);
      expect(find.textContaining('dikalibrasi ulang'), findsNothing);
    });

    testWidgets('angka mustahil ditolak sebelum dikirim', (tester) async {
      final api = await pumpCheck(tester);
      await openHeartRate(tester);
      for (final bad in ['9', '400', 'abc']) {
        await tester.enterText(find.byKey(const Key('hr_input')), bad);
        await tester.tap(find.byKey(const Key('result_save')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('result_error')), findsOneWidget, reason: bad);
      }
      expect(api.results, isEmpty);
    });

    testWidgets('di atas 100 dijelaskan dengan nada tenang, tanpa diagnosis atau kata "aman"', (tester) async {
      await pumpCheck(tester,
          api: FakeApi()..onResult = (k, v) async => const ResultOutcome(saved: true, hrRange: 'above_range'));
      await openHeartRate(tester);
      await tester.enterText(find.byKey(const Key('hr_input')), '112');
      await tester.tap(find.byKey(const Key('result_save')));
      await tester.pumpAndSettle();
      final text = tester.widget<Text>(find.byKey(const Key('hr_outcome'))).data!;
      expect(text, contains('di atas 100'));
      expect(text.toLowerCase(), isNot(contains('aman')));
      expect(text, isNot(contains('menderita')));
    });

    testWidgets('tensi boleh disertai nadi', (tester) async {
      final api = await pumpCheck(tester, api: FakeApi()..onResult = (k, v) async => const ResultOutcome(saved: true));
      await tester.tap(find.byKey(const Key('enter_result_button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('result_kind_bp')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('sys_input')), '124');
      await tester.enterText(find.byKey(const Key('dia_input')), '82');
      await tester.enterText(find.byKey(const Key('pulse_input')), '76');
      await tester.tap(find.byKey(const Key('result_save')));
      await tester.pumpAndSettle();
      expect(api.results.single.value, {'sys': 124, 'dia': 82, 'pulse': 76});
    });

    test('validasi: nadi kosong boleh, angka di luar 25-250 tidak', () {
      expect(validatePulse(''), isNull);
      expect(validatePulse('72'), isNull);
      expect(validatePulse('300'), isNotNull);
      expect(validateHeartRate('24'), isNotNull);
      expect(validateHeartRate('25'), isNull);
      expect(validateHeartRate('250'), isNull);
    });

    testWidgets('grafik tren memuat detak jantung istirahat dengan rentang normalnya', (tester) async {
      tester.view.physicalSize = const Size(900, 4200);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final data = TrendsData(
        clinical: {
          'resting_heart_rate': const ClinicalSeries(
            points: [
              ClinicalPoint(date: '2026-10-10', source: 'self', value: 70, band: 'normal_range'),
              ClinicalPoint(date: '2026-10-15', source: 'self', value: 104, band: 'above_range'),
            ],
            trend: 'naik',
            references: [RefLine('Batas bawah normal istirahat', 60), RefLine('Batas atas normal istirahat', 100)],
          ),
        },
        triage: const [],
      );
      await tester.pumpWidget(testApp(const TrendsScreen(), api: FakeApi()..trends = data));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chart_resting_heart_rate')), findsOneWidget);
      expect(find.textContaining('Detak jantung istirahat'), findsWidgets);
      expect(find.textContaining('104 kali/menit'), findsWidgets);
      expect(find.textContaining('di atas 100'), findsWidgets);
    });
  });

  group('tempat cek terdekat', () {
    testWidgets('data peta ditampilkan lengkap dengan jenis, alamat, jam buka, telepon, dan sumbernya', (tester) async {
      final api = FakeApi()
        ..faskes = const [
          Faskes(
            name: 'Puskesmas Sekeloa',
            kind: 'puskesmas',
            distanceKm: 0.7,
            address: 'Jl. Sekeloa No. 3',
            lat: -6.8951,
            lng: 107.6107,
            source: 'osm',
            phone: '022-1234',
            openingHours: 'Mo-Sa 08:00-14:00',
          ),
          Faskes(name: 'Rumah Sakit Advent', kind: 'rumah_sakit', distanceKm: 0.8, lat: -6.89, lng: 107.6, source: 'osm'),
        ];
      await pumpCheck(tester, api: api);
      expect(find.textContaining('Puskesmas, 0,7 km'), findsOneWidget);
      expect(find.textContaining('Rumah sakit, 0,8 km'), findsOneWidget);
      expect(find.textContaining('Buka: Mo-Sa 08:00-14:00'), findsOneWidget);
      expect(find.textContaining('022-1234'), findsOneWidget);
      expect(find.textContaining('Data dari OpenStreetMap'), findsOneWidget);
    });

    testWidgets('server hanya punya daftar contoh: daftar itu tidak ditampilkan, ada keterangan dan tombol Google Maps', (tester) async {
      final api = FakeApi()
        ..faskes = const [Faskes(name: 'Puskesmas Contoh', kind: 'puskesmas', distanceKm: 0.4, source: 'seed')];
      await pumpCheck(tester, api: api);
      expect(find.text('Puskesmas Contoh'), findsNothing);
      expect(find.byKey(const Key('faskes_unavailable')), findsOneWidget);
      expect(find.byKey(const Key('faskes_search_maps')), findsOneWidget);
    });

    testWidgets('cari di Google Maps memakai lokasi pengguna', (tester) async {
      final links = FakeLinks();
      await pumpCheck(tester, links: links);
      await tester.ensureVisible(find.byKey(const Key('faskes_search_maps')));
      await tester.tap(find.byKey(const Key('faskes_search_maps')));
      await tester.pumpAndSettle();
      expect(links.opened.single.toString(), 'https://www.google.com/maps/search/puskesmas/@-6.893,107.613,15z');
    });

    testWidgets('daftar gagal dimuat: pencarian di Google Maps tetap tersedia sebagai jalan keluar', (tester) async {
      tester.view.physicalSize = const Size(900, 3200);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final api = FakeApi()..faskesError = Exception('down');
      await tester.pumpWidget(testApp(const CheckScreen(), api: api, overrides: [locationOverride(), linksOverride(FakeLinks())]));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('faskes_search_maps')), findsOneWidget);
    });
  });

  group('ruang bawah di atas bilah navigasi sistem', () {
    testWidgets('halaman Tren memberi ruang bawah sebesar bilah Home/Back agar baris terakhir tidak tertutup', (tester) async {
      await tester.pumpWidget(testApp(
        Builder(
          builder: (c) => MediaQuery(
            data: MediaQuery.of(c).copyWith(padding: const EdgeInsets.only(bottom: 48)),
            child: const TrendsScreen(),
          ),
        ),
        api: FakeApi(),
      ));
      await tester.pumpAndSettle();
      final list = tester.widget<ListView>(find.byType(ListView).first);
      final padding = list.padding!.resolve(TextDirection.ltr);
      expect(padding.bottom, KiraSpace.lg + 48);
    });

    testWidgets('tanpa bilah sistem, padding bawah tetap normal', (tester) async {
      await tester.pumpWidget(testApp(const TrendsScreen(), api: FakeApi()));
      await tester.pumpAndSettle();
      final list = tester.widget<ListView>(find.byType(ListView).first);
      expect(list.padding!.resolve(TextDirection.ltr).bottom, KiraSpace.lg);
    });
  });
}
