import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../shared/clinical_extras_models.dart';
import '../../shared/models.dart';
import 'projection_providers.dart';

final scenariosProvider = FutureProvider<List<SavedScenario>>((ref) {
  ref.watch(authProvider.select((s) => s.token));
  return ref.read(apiProvider).listScenarios();
});

WhatIfChange changeFromParams(Map<String, dynamic> p) => WhatIfChange(
      active30min: p['active_30min'] as bool?,
      dailyVegFruit: p['daily_veg_fruit'] as bool?,
      weightDeltaKg: (p['weight_delta_kg'] as num?)?.toDouble(),
      sweetDrinksDeltaPerDay: (p['sweet_drinks_delta_per_day'] as num?)?.toDouble() ?? 0,
    );

/// Skenario "bagaimana kalau" yang disimpan. Hasilnya dihitung ulang dengan datamu hari ini dan dibandingkan dengan saat disimpan.
class ScenariosCard extends ConsumerStatefulWidget {
  const ScenariosCard({super.key, required this.whatIf});
  final WhatIfState whatIf;

  @override
  ConsumerState<ScenariosCard> createState() => _ScenariosCardState();
}

class _ScenariosCardState extends ConsumerState<ScenariosCard> {
  bool _busy = false;

  Future<void> _save() async {
    final name = await showDialog<String>(context: context, builder: (_) => const _NameDialog());
    if (name == null || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(apiProvider).saveScenario(name, widget.whatIf.change);
      ref.invalidate(scenariosProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Skenario tersimpan.')));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(SavedScenario s) async {
    await ref.read(apiProvider).deleteScenario(s.id);
    ref.invalidate(scenariosProvider);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.whatIf;
    final canSave = !w.change.isEmpty && w.result != null && !w.loading && !_busy;
    final saved = ref.watch(scenariosProvider).value ?? const <SavedScenario>[];
    if (saved.isEmpty && w.change.isEmpty) return const SizedBox.shrink();
    return Card(
      key: const Key('scenarios_card'),
      child: Padding(
        padding: const EdgeInsets.all(KiraSpace.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Skenariomu', style: context.text.titleMedium),
          const SizedBox(height: KiraSpace.xs),
          Text('Simpan kombinasi kebiasaan yang ingin kamu coba, lalu lihat nanti apakah rentangnya bergeser.',
              style: context.text.bodyMedium?.copyWith(color: context.scheme.onSurfaceVariant)),
          const SizedBox(height: KiraSpace.md),
          OutlinedButton.icon(
            key: const Key('save_scenario'),
            icon: const Icon(Icons.bookmark_add_outlined),
            label: const Text('Simpan skenario ini'),
            onPressed: canSave ? _save : null,
          ),
          if (saved.isNotEmpty) ...[
            const SizedBox(height: KiraSpace.md),
            for (final s in saved)
              ListTile(
                key: Key('scenario_${s.id}'),
                contentPadding: EdgeInsets.zero,
                title: Text(s.name),
                subtitle: Text(
                  '${s.habits}\n'
                  'Sekarang: skor ${s.nowBefore.text} → ${s.nowAfter.text}'
                  '${s.changed ? ' (saat disimpan ${s.savedBefore.text} → ${s.savedAfter.text}; datamu sudah berubah)' : ''}',
                ),
                isThreeLine: true,
                onTap: () => ref.read(whatIfProvider.notifier).update(changeFromParams(s.params)),
                trailing: IconButton(
                  key: Key('delete_scenario_${s.id}'),
                  tooltip: 'Hapus skenario ${s.name}',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _delete(s),
                ),
              ),
            Text('Ketuk skenario untuk memuatnya ke pengaturan di atas.', style: context.text.bodySmall),
          ],
        ]),
      ),
    );
  }
}

class _NameDialog extends StatefulWidget {
  const _NameDialog();

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _ok() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Beri nama dulu, misalnya "Jalan pagi dan kurangi teh manis".');
      return;
    }
    Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Nama skenario'),
        content: TextField(
          key: const Key('scenario_name'),
          controller: _controller,
          autofocus: true,
          maxLength: 40,
          onSubmitted: (_) => _ok(),
          decoration: InputDecoration(labelText: 'Nama', errorText: _error, errorMaxLines: 2),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(key: const Key('scenario_save_confirm'), onPressed: _ok, child: const Text('Simpan')),
        ],
      );
}
