import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../shared/engagement_models.dart';
import 'chat_controller.dart';

final frequentFoodsProvider = FutureProvider<List<FrequentFood>>((ref) {
  ref.watch(authProvider.select((s) => s.token));
  return ref.read(apiProvider).getFrequentFoods();
});

/// Baris chip "yang sering kamu catat": satu ketukan mencatat ulang tanpa mengetik. Kosong (tidak memakan ruang)
/// bila belum ada makanan yang tercatat dua kali atau lebih.
class FrequentFoodChips extends ConsumerWidget {
  const FrequentFoodChips({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final foods = ref.watch(frequentFoodsProvider).value ?? const <FrequentFood>[];
    if (foods.isEmpty) return const SizedBox.shrink();
    return Semantics(
      container: true,
      label: 'Sering kamu catat',
      child: SizedBox(
        height: 52,
        child: ListView.separated(
          key: const Key('frequent_foods'),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: KiraSpace.lg, vertical: KiraSpace.xs),
          itemCount: foods.length,
          separatorBuilder: (_, _) => const SizedBox(width: KiraSpace.sm),
          itemBuilder: (_, i) {
            final f = foods[i];
            return ActionChip(
              key: Key('frequent_$i'),
              avatar: Icon(f.isDrink ? Icons.local_cafe_outlined : Icons.restaurant_outlined, size: 18),
              label: Text(f.name),
              tooltip: '${f.phrase} (dicatat ${f.count} kali)',
              onPressed: () => ref.read(chatProvider.notifier).send(f.phrase),
            );
          },
        ),
      ),
    );
  }
}
