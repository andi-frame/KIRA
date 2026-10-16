import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/features/records/records_screen.dart';
import 'package:kira/shared/record_models.dart';

import 'support/fakes.dart';

final _lab = MedicalRecord(
  id: 'r1',
  kind: 'lab',
  title: 'Panel lipid',
  recordedOn: DateTime(2026, 9, 1),
  provider: 'Lab Prodia',
  details: 'Puasa 10 jam',
  values: const [RecordValue(name: 'Kolesterol total', value: '210', unit: 'mg/dL')],
);
final _drug = MedicalRecord(id: 'r2', kind: 'medication', title: 'Metformin 500 mg', recordedOn: DateTime(2026, 10, 1), source: 'chat');

Future<FakeApi> pump(WidgetTester tester, {List<MedicalRecord> records = const []}) async {
  tester.view.physicalSize = const Size(900, 3000);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final api = FakeApi()..records = [...records];
  await tester.pumpWidget(testApp(const RecordsScreen(), api: api));
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('kosong: ajakan menambah atau bercerita di Ngobrol, dengan catatan bahwa KIRA hanya menyimpan', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('records_empty')), findsOneWidget);
    expect(find.byKey(const Key('records_tell_in_chat')), findsOneWidget);
    expect(find.textContaining('tidak menilai isinya dan tidak menyarankan obat'), findsOneWidget);
  });

  testWidgets('daftar menampilkan jenis, tanggal, dokter, catatan, nilai, dan asal catatan dari chat', (tester) async {
    await pump(tester, records: [_lab, _drug]);
    expect(find.text('Panel lipid'), findsOneWidget);
    expect(find.text('Hasil laboratorium · 01/09/2026 · Lab Prodia'), findsOneWidget);
    expect(find.text('Puasa 10 jam'), findsOneWidget);
    expect(find.text('Kolesterol total'), findsOneWidget);
    expect(find.text('210 mg/dL'), findsOneWidget);
    expect(find.text('Dicatat dari cerita di Ngobrol'), findsOneWidget);
  });

  testWidgets('saringan jenis hanya muncul bila ada lebih dari satu jenis dan menyaring daftar', (tester) async {
    await pump(tester, records: [_lab, _drug]);
    await tester.tap(find.byKey(const Key('records_filter_medication')));
    await tester.pumpAndSettle();
    expect(find.text('Metformin 500 mg'), findsOneWidget);
    expect(find.text('Panel lipid'), findsNothing);
    await tester.tap(find.byKey(const Key('records_filter_all')));
    await tester.pumpAndSettle();
    expect(find.text('Panel lipid'), findsOneWidget);
  });

  testWidgets('hanya satu jenis: tidak ada saringan yang tidak berguna', (tester) async {
    await pump(tester, records: [_lab]);
    expect(find.byKey(const Key('records_filter_all')), findsNothing);
  });

  testWidgets('tambah lewat formulir mengirim jenis, judul, tanggal, dan nilai hasil', (tester) async {
    final api = await pump(tester);
    await tester.tap(find.byKey(const Key('record_add')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('record_kind_lab')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('record_title')), 'Gula darah puasa');
    await tester.enterText(find.byKey(const Key('record_provider')), 'Puskesmas Dago');
    await tester.tap(find.byKey(const Key('record_add_value')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('record_value_name_0')), 'Glukosa puasa');
    await tester.enterText(find.byKey(const Key('record_value_value_0')), '104');
    await tester.enterText(find.byKey(const Key('record_value_unit_0')), 'mg/dL');
    await tester.ensureVisible(find.byKey(const Key('record_save')));
    await tester.tap(find.byKey(const Key('record_save')));
    await tester.pumpAndSettle();

    final sent = api.createdRecords.single;
    expect(sent['kind'], 'lab');
    expect(sent['title'], 'Gula darah puasa');
    expect(sent['provider'], 'Puskesmas Dago');
    expect(sent['details'], isNull);
    expect(sent['values'], [
      {'name': 'Glukosa puasa', 'value': '104', 'unit': 'mg/dL'},
    ]);
    expect(find.text('Gula darah puasa'), findsOneWidget); // muncul di daftar setelah disimpan
  });

  testWidgets('judul wajib diisi', (tester) async {
    final api = await pump(tester);
    await tester.tap(find.byKey(const Key('record_add')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('record_save')));
    await tester.tap(find.byKey(const Key('record_save')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('record_error')), findsOneWidget);
    expect(api.createdRecords, isEmpty);
  });

  testWidgets('ubah rekam medis mengirim perubahan ke yang sama', (tester) async {
    final api = await pump(tester, records: [_lab]);
    await tester.tap(find.byKey(const Key('record_menu_r1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ubah'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('record_title')), 'Panel lipid lengkap');
    await tester.ensureVisible(find.byKey(const Key('record_save')));
    await tester.tap(find.byKey(const Key('record_save')));
    await tester.pumpAndSettle();
    expect(api.updatedRecords.single.id, 'r1');
    expect(api.updatedRecords.single.fields['title'], 'Panel lipid lengkap');
    expect(find.text('Panel lipid lengkap'), findsOneWidget);
  });

  testWidgets('hapus meminta konfirmasi lalu menghapus', (tester) async {
    final api = await pump(tester, records: [_lab]);
    await tester.tap(find.byKey(const Key('record_menu_r1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hapus'));
    await tester.pumpAndSettle();
    expect(api.deletedRecords, isEmpty);
    await tester.tap(find.byKey(const Key('record_delete_confirm')));
    await tester.pumpAndSettle();
    expect(api.deletedRecords, ['r1']);
    expect(find.byKey(const Key('records_empty')), findsOneWidget);
  });

  testWidgets('gagal memuat: pesan ramah dengan tombol coba lagi', (tester) async {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final api = FakeApi()..recordsError = Exception('x');
    await tester.pumpWidget(testApp(const RecordsScreen(), api: api));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('retry_button')), findsOneWidget);
  });
}
