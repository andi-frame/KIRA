import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/core/providers.dart';
import 'package:kira/main.dart';
import 'package:kira/shared/models.dart';

import 'support/fakes.dart';

void main() {
  testWidgets('tanpa token, aplikasi menampilkan layar masuk', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiProvider.overrideWithValue(FakeApi()),
        tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
      ],
      child: const KiraApp(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Masuk ke KIRA'), findsOneWidget);
  });

  testWidgets('dengan token dan profil lengkap, aplikasi membuka layar ngobrol', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiProvider.overrideWithValue(FakeApi()),
        tokenStoreProvider.overrideWithValue(MemoryTokenStore('token')),
      ],
      child: const KiraApp(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Ngobrol'), findsWidgets);
    expect(find.text('Masuk ke KIRA'), findsNothing);
  });

  testWidgets('dengan token tetapi profil belum lengkap, aplikasi membuka onboarding', (tester) async {
    final api = FakeApi()..profile = const Profile();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        apiProvider.overrideWithValue(api),
        tokenStoreProvider.overrideWithValue(MemoryTokenStore('token')),
      ],
      child: const KiraApp(),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('kenalan'), findsWidgets);
  });
}
