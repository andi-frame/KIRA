import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/features/onboarding/onboarding_screen.dart';

import 'support/fakes.dart';

Future<void> answerText(WidgetTester tester, String value) async {
  await tester.enterText(find.byKey(const Key('onb_input')), value);
  await tester.tap(find.byKey(const Key('onb_next')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('menjalankan percakapan kenalan dan menyimpan profil', (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(testApp(const OnboardingScreen(), api: api));
    await tester.pumpAndSettle();
    expect(find.textContaining('kenalan'), findsWidgets);

    await answerText(tester, 'Raka'); // nama
    await answerText(tester, '1998'); // tahun lahir
    await tester.tap(find.text('Laki-laki'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('onb_height')), '170');
    await tester.enterText(find.byKey(const Key('onb_weight')), '78');
    await tester.tap(find.byKey(const Key('onb_next')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onb_skip'))); // lingkar perut dilewati
    await tester.pumpAndSettle();
    await tester.tap(find.text('Orang tua atau saudara kandung'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onb_active_no')));
    await tester.tap(find.byKey(const Key('onb_veg_yes')));
    await tester.tap(find.byKey(const Key('onb_next')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tidak merokok'));
    await tester.pump(const Duration(milliseconds: 200)); // spinner "Menyimpan" berputar sampai router pindah layar

    final saved = api.profileUpdates.single;
    expect(saved['display_name'], 'Raka');
    expect(saved['birth_date'], startsWith('1998'));
    expect(saved['sex'], 'male');
    expect(saved['height_cm'], 170.0);
    expect(saved['weight_kg'], 78.0);
    expect(saved.containsKey('waist_cm'), isFalse);
    expect(saved['family_history_diabetes'], 'first_degree');
    expect(saved['usual_active_30min'], false);
    expect(saved['usual_veg_fruit'], true);
    expect(saved['smoker'], false);
  });

  testWidgets('tahun lahir dan tinggi yang tidak masuk akal ditolak di tempat', (tester) async {
    final api = FakeApi();
    await tester.pumpWidget(testApp(const OnboardingScreen(), api: api));
    await tester.pumpAndSettle();

    await answerText(tester, 'Raka');
    await answerText(tester, '1850');
    expect(find.textContaining('tahun lahir'), findsWidgets);
    expect(find.byKey(const Key('onb_error')), findsOneWidget);

    await answerText(tester, '1998');
    await tester.tap(find.text('Perempuan'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('onb_height')), '5');
    await tester.enterText(find.byKey(const Key('onb_weight')), '60');
    await tester.tap(find.byKey(const Key('onb_next')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('onb_error')), findsOneWidget);
    expect(api.profileUpdates, isEmpty);
  });
}
