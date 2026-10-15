import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/core/api_client.dart';
import 'package:kira/features/barcode/barcode_screen.dart';
import 'package:kira/features/chat/chat_screen.dart';
import 'package:kira/shared/engagement_models.dart';

import 'support/fakes.dart';

Future<void> pumpBarcode(WidgetTester tester, FakeApi api, {String scanned = '089686010947'}) async {
  tester.view.physicalSize = const Size(900, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(testApp(const BarcodeScreen(), api: api, overrides: [scannerOverride(scanned)]));
  await tester.pumpAndSettle();
}

Future<void> scan(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('fake_scan')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('pindai kode: gizi per 100 g tampil dengan sumbernya, nilai yang tidak tertera ditulis apa adanya', (tester) async {
    final api = FakeApi()..product = sampleProduct();
    await pumpBarcode(tester, api);
    await scan(tester);
    expect(api.productLookups, ['089686010947']);
    expect(find.text('Indomie Mi Goreng Original'), findsOneWidget);
    expect(find.text('Per 100 g'), findsOneWidget);
    expect(find.text('Gula 7,1 g'), findsOneWidget);
    expect(find.textContaining('Open Food Facts'), findsOneWidget);
    expect(find.textContaining('bisa keliru'), findsOneWidget);
  });

  testWidgets('kamera memanggil berulang untuk kode yang sama: hanya satu pencarian', (tester) async {
    final api = FakeApi()..product = sampleProduct();
    await pumpBarcode(tester, api);
    await tester.tap(find.byKey(const Key('fake_scan')));
    await tester.tap(find.byKey(const Key('fake_scan')), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(api.productLookups, hasLength(1));
  });

  testWidgets('mencatat per sajian (setengah-setengah) mengirim jumlah sajian, bukan angka gizi', (tester) async {
    final api = FakeApi()..product = sampleProduct();
    await pumpBarcode(tester, api);
    await scan(tester);
    expect(find.text('1 sajian'), findsOneWidget);
    await tester.tap(find.byKey(const Key('servings_plus')));
    await tester.pumpAndSettle();
    expect(find.text('1,5 sajian'), findsOneWidget);
    await tester.tap(find.byKey(const Key('barcode_log')));
    await tester.pumpAndSettle();
    expect(api.barcodeLogs, [(barcode: '089686010947', grams: null, servings: 1.5)]);
    expect(find.byKey(const Key('barcode_logged')), findsOneWidget);
    expect(find.text('Tercatat: Indomie Mi Goreng Original'), findsOneWidget);
  });

  testWidgets('sajian tidak bisa kurang dari setengah', (tester) async {
    final api = FakeApi()..product = sampleProduct();
    await pumpBarcode(tester, api);
    await scan(tester);
    await tester.tap(find.byKey(const Key('servings_minus')));
    await tester.pumpAndSettle();
    expect(find.text('0,5 sajian'), findsOneWidget);
    final minus = tester.widget<IconButton>(find.byKey(const Key('servings_minus')));
    expect(minus.onPressed, isNull);
  });

  testWidgets('mode gram: porsi divalidasi lalu dikirim', (tester) async {
    final api = FakeApi()..product = sampleProduct();
    await pumpBarcode(tester, api);
    await scan(tester);
    await tester.tap(find.text('Gram'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('barcode_grams')), '0');
    await tester.tap(find.byKey(const Key('barcode_log')));
    await tester.pumpAndSettle();
    expect(find.text('Isi gram antara 1 dan 5000.'), findsOneWidget);
    expect(api.barcodeLogs, isEmpty);

    await tester.enterText(find.byKey(const Key('barcode_grams')), '60,5');
    await tester.tap(find.byKey(const Key('barcode_log')));
    await tester.pumpAndSettle();
    expect(api.barcodeLogs.single.grams, 60.5);
    expect(api.barcodeLogs.single.servings, isNull);
  });

  testWidgets('tanpa takaran saji hanya ada mode gram', (tester) async {
    final api = FakeApi()..product = sampleProduct(servingG: null);
    await pumpBarcode(tester, api);
    await scan(tester);
    expect(find.byKey(const Key('amount_mode')), findsNothing);
    expect(find.byKey(const Key('barcode_grams')), findsOneWidget);
    expect(tester.widget<TextField>(find.byKey(const Key('barcode_grams'))).controller!.text, '100');
  });

  testWidgets('minuman memakai satuan ml', (tester) async {
    final api = FakeApi()..product = sampleProduct(servingG: null, drink: true);
    await pumpBarcode(tester, api);
    await scan(tester);
    expect(find.text('Per 100 ml'), findsOneWidget);
    expect(find.text('Berapa ml?'), findsOneWidget);
  });

  testWidgets('data gizi tidak lengkap: tidak bisa dicatat, diarahkan ke foto label', (tester) async {
    final api = FakeApi()..product = sampleProduct(complete: false);
    await pumpBarcode(tester, api);
    await scan(tester);
    expect(find.byKey(const Key('product_incomplete')), findsOneWidget);
    expect(find.byKey(const Key('barcode_log')), findsNothing);
    expect(find.text('Gula tidak tertera'), findsOneWidget);
  });

  testWidgets('produk tidak ada: pesan server tampil dan kode yang sama boleh dicoba lagi', (tester) async {
    final api = FakeApi()..productError = ApiException('Produk ini belum ada di basis data.', status: 404);
    await pumpBarcode(tester, api);
    await scan(tester);
    expect(find.text('Produk ini belum ada di basis data.'), findsOneWidget);
    api.productError = null;
    api.product = sampleProduct();
    await scan(tester);
    expect(api.productLookups, hasLength(2));
    expect(find.byKey(const Key('product_card')), findsOneWidget);
  });

  testWidgets('ketik nomor manual: divalidasi dulu sebelum menghubungi server', (tester) async {
    final api = FakeApi()..product = sampleProduct();
    await pumpBarcode(tester, api);
    await tester.enterText(find.byKey(const Key('barcode_manual')), '123');
    await tester.tap(find.byKey(const Key('barcode_lookup')));
    await tester.pumpAndSettle();
    expect(find.text('Nomor kode batang berisi 8 sampai 14 angka.'), findsOneWidget);
    expect(api.productLookups, isEmpty);

    await tester.enterText(find.byKey(const Key('barcode_manual')), '089686010947');
    await tester.tap(find.byKey(const Key('barcode_lookup')));
    await tester.pumpAndSettle();
    expect(api.productLookups, ['089686010947']);
  });

  testWidgets('gagal mencatat menampilkan pesan server dan tidak menandai tercatat', (tester) async {
    final api = FakeApi()
      ..product = sampleProduct()
      ..barcodeLogError = ApiException('Angka gizi produk ini tampak tidak masuk akal.', status: 422);
    await pumpBarcode(tester, api);
    await scan(tester);
    await tester.tap(find.byKey(const Key('barcode_log')));
    await tester.pumpAndSettle();
    expect(find.textContaining('tidak masuk akal'), findsOneWidget);
    expect(find.byKey(const Key('barcode_logged')), findsNothing);
  });

  testWidgets('pindai produk lain kembali ke pemindai', (tester) async {
    final api = FakeApi()..product = sampleProduct();
    await pumpBarcode(tester, api);
    await scan(tester);
    await tester.tap(find.byKey(const Key('barcode_back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('fake_scan')), findsOneWidget);
    expect(find.byKey(const Key('product_card')), findsNothing);
  });

  group('makanan yang sering dicatat', () {
    Future<void> pumpChat(WidgetTester tester, FakeApi api) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(testApp(const ChatScreen(), api: api));
      await tester.pumpAndSettle();
    }

    testWidgets('chip muncul setelah sapaan, ketukan mengirim kalimat pencatatan', (tester) async {
      final api = FakeApi()
        ..frequentFoods = const [
          FrequentFood(name: 'nasi uduk', kind: 'meal', count: 5),
          FrequentFood(name: 'teh manis', kind: 'drink', count: 3),
        ];
      await pumpChat(tester, api);
      // Sapaan awal masih menampilkan contoh kalimat; chip muncul sesudah percakapan dimulai.
      await tester.tap(find.byKey(const Key('suggestion_0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('frequent_foods')), findsOneWidget);
      await tester.tap(find.byKey(const Key('frequent_1')));
      await tester.pumpAndSettle();
      expect(api.messages.last, 'Tadi minum teh manis');
      await tester.tap(find.byKey(const Key('frequent_0')));
      await tester.pumpAndSettle();
      expect(api.messages.last, 'Tadi makan nasi uduk');
    });

    testWidgets('tanpa makanan sering, tidak ada baris chip', (tester) async {
      final api = FakeApi();
      await pumpChat(tester, api);
      await tester.tap(find.byKey(const Key('suggestion_0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('frequent_foods')), findsNothing);
    });

    testWidgets('menu foto punya pindai kode batang', (tester) async {
      await pumpChat(tester, FakeApi());
      await tester.tap(find.byKey(const Key('camera_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('photo_kind_barcode')), findsOneWidget);
    });
  });
}
