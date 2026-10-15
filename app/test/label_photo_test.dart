import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/features/chat/chat_screen.dart';
import 'package:kira/shared/models.dart';

import 'support/fakes.dart';

Future<void> pickLabel(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('camera_button')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('photo_kind_label')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('photo_source_gallery')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('foto label gizi dikirim dengan jenis label dan hasilnya tampil sebagai angka tercetak', (tester) async {
    String? sentKind;
    final api = FakeApi()
      ..onPhoto = (kind) async {
        sentKind = kind;
        return ChatReply(
          reply: 'Tercatat: teh kotak, 24 g gula.',
          logIds: const ['log-1'],
          extraction: ExtractionData(
            label: const LabelEntry(
              productName: 'Teh Kotak Jasmine',
              isDrink: true,
              servingG: 250,
              sugarG: 24,
              sodiumMg: 50,
              kcal: 100,
            ),
          ),
        );
      };
    await tester.pumpWidget(testApp(
      const ChatScreen(),
      api: api,
      overrides: [photoPickerOverride(Uint8List.fromList([1, 2, 3]))],
    ));
    await tester.pumpAndSettle();
    await pickLabel(tester);

    expect(sentKind, 'label');
    expect(find.text('Foto label gizi kemasan'), findsOneWidget);
    expect(find.byKey(const Key('extraction_card')), findsOneWidget);
    expect(find.text('Teh Kotak Jasmine'), findsOneWidget);
    expect(find.textContaining('label kemasan'), findsWidgets);
    expect(find.textContaining('gula 24 g'), findsOneWidget);
    expect(find.textContaining('per sajian'), findsOneWidget);
  });

  testWidgets('label per 100 g menyebut basisnya dan jumlah sajian yang dimakan', (tester) async {
    final api = FakeApi()
      ..onPhoto = (kind) async => ChatReply(
            reply: 'Tercatat.',
            logIds: const ['log-1'],
            extraction: ExtractionData(
              label: const LabelEntry(
                productName: 'Keripik Singkong',
                perServing: false,
                servingG: 30,
                servings: 2,
                sugarG: 3,
              ),
            ),
          );
    await tester.pumpWidget(testApp(
      const ChatScreen(),
      api: api,
      overrides: [photoPickerOverride(Uint8List.fromList([1, 2, 3]))],
    ));
    await tester.pumpAndSettle();
    await pickLabel(tester);

    expect(find.textContaining('per 100 g'), findsOneWidget);
    expect(find.textContaining('2 sajian'), findsOneWidget);
    expect(find.textContaining('natrium'), findsNothing); // yang tidak tertera tidak dikarang
  });
}
