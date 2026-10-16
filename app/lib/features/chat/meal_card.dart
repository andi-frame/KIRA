import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../shared/labels.dart';
import '../../shared/meal_models.dart';
import '../../shared/widgets.dart';

/// Aksi koreksi catatan makan di kartu "Yang kucatat" (dan di Riwayat).
class MealCardActions {
  const MealCardActions({
    required this.correct,
    required this.halve,
    required this.remove,
    required this.replace,
    required this.search,
  });

  final Future<void> Function(LoggedItem item, double grams) correct;
  final Future<void> Function(String group) halve;
  final Future<void> Function(LoggedItem item) remove;
  final Future<void> Function(LoggedItem item, FoodSuggestion food) replace;
  final Future<List<FoodSuggestion>> Function(String query) search;
}

/// Hidangan tampil sebagai kelompok dengan komponennya; makanan tunggal satu baris. Gizi ditulis dengan kata dan
/// angka; komponen yang tidak ada di database gizi ditandai "belum terhitung" (bukan nol) dengan tombol cari.
class MealGroupsView extends StatelessWidget {
  const MealGroupsView({super.key, required this.meal, required this.actions});
  final MealLog meal;
  final MealCardActions actions;

  Future<void> _guard(BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = meal.groups;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var g = 0; g < groups.length; g++) ...[
          if (g > 0) const Divider(height: KiraSpace.lg),
          _GroupView(group: groups[g], index: g, actions: actions, guard: _guard),
        ],
      ],
    );
  }
}

class _GroupView extends StatelessWidget {
  const _GroupView({required this.group, required this.index, required this.actions, required this.guard});
  final MealGroup group;
  final int index;
  final MealCardActions actions;
  final Future<void> Function(BuildContext, Future<void> Function()) guard;

  @override
  Widget build(BuildContext context) {
    if (!group.isDish) {
      return _ItemRow(item: group.items.single, actions: actions, guard: guard, emphasize: true);
    }
    final t = group.totals;
    return Column(
      key: Key('meal_group_$index'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text(group.title, style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
          ),
          TextButton(
            key: Key('halve_group_$index'),
            onPressed: () => guard(context, () => actions.halve(group.title)),
            child: const Text('Setengah porsi'),
          ),
        ]),
        Text('Perkiraan resep, gram tiap bagian bisa kamu ubah.', style: context.text.bodySmall),
        for (final item in group.items)
          _ItemRow(item: item, actions: actions, guard: guard, removable: group.items.length > 1),
        Padding(
          padding: const EdgeInsets.only(top: KiraSpace.xs),
          child: Text(
            'Total: ${nutrientNumber(t.kcal)} kkal, ${nutrientLine(sugarG: t.sugarG, sodiumMg: t.sodiumMg, fatG: t.fatG)}'
            '${group.hasUncounted ? ' (belum termasuk yang belum terhitung)' : ''}',
            key: Key('group_total_$index'),
            style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.item,
    required this.actions,
    required this.guard,
    this.removable = false,
    this.emphasize = false,
  });

  final LoggedItem item;
  final MealCardActions actions;
  final Future<void> Function(BuildContext, Future<void> Function()) guard;
  final bool removable;
  final bool emphasize;

  Future<void> _edit(BuildContext context) async {
    final grams = await showDialog<double>(
      context: context,
      builder: (_) => PortionDialog(name: item.name, grams: item.portionG),
    );
    if (grams != null && context.mounted) await guard(context, () => actions.correct(item, grams));
  }

  Future<void> _find(BuildContext context) async {
    final food = await showDialog<FoodSuggestion>(
      context: context,
      builder: (_) => FoodSearchDialog(initial: item.name, search: actions.search),
    );
    if (food != null && context.mounted) await guard(context, () => actions.replace(item, food));
  }

  @override
  Widget build(BuildContext context) {
    final grams = item.portionG == null ? '' : '${nutrientNumber(item.portionG!)} g';
    final detail = item.counted
        ? [
            if (grams.isNotEmpty) grams,
            '${nutrientNumber(item.kcal!)} kkal',
            nutrientLine(sugarG: item.sugarG ?? 0, sodiumMg: item.sodiumMg ?? 0, fatG: item.fatG ?? 0),
          ].join(' · ')
        : [if (grams.isNotEmpty) grams, 'belum terhitung, belum ada di database gizi'].join(' · ');
    return Padding(
      key: Key('meal_item_${item.id}'),
      padding: const EdgeInsets.symmetric(vertical: KiraSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item.name,
                  style: emphasize
                      ? context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w700)
                      : context.text.bodyLarge),
              Text(detail, style: context.text.bodySmall),
            ]),
          ),
          if (!item.counted)
            TextButton.icon(
              key: Key('find_item_${item.id}'),
              onPressed: () => _find(context),
              icon: const Icon(Icons.search, size: 18),
              label: const Text('Cari'),
            ),
          IconButton(
            key: Key('edit_item_${item.id}'),
            tooltip: 'Ubah porsi ${item.name}',
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () => _edit(context),
          ),
          if (removable)
            IconButton(
              key: Key('remove_item_${item.id}'),
              tooltip: 'Hapus ${item.name}',
              icon: const Icon(Icons.remove_circle_outline, size: 20),
              onPressed: () => guard(context, () => actions.remove(item)),
            ),
        ],
      ),
    );
  }
}

/// Isian gram untuk satu makanan/komponen.
class PortionDialog extends StatefulWidget {
  const PortionDialog({super.key, required this.name, this.grams});
  final String name;
  final double? grams;

  @override
  State<PortionDialog> createState() => _PortionDialogState();
}

class _PortionDialogState extends State<PortionDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.grams?.round().toString() ?? '');
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = double.tryParse(_controller.text.trim().replaceAll(',', '.'));
    if (value == null || value <= 0 || value > 5000) {
      setState(() => _error = 'Isi angka gram antara 1 dan 5000.');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Porsi ${widget.name}'),
      content: TextField(
        key: const Key('portion_input'),
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(labelText: 'Berapa gram?', suffixText: 'g', errorText: _error),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(key: const Key('portion_save'), onPressed: _save, child: const Text('Simpan')),
      ],
    );
  }
}

/// Cari makanan di database gizi untuk komponen yang belum terhitung ("maksudmu ...?"). Hanya makanan tunggal.
class FoodSearchDialog extends StatefulWidget {
  const FoodSearchDialog({super.key, required this.initial, required this.search});
  final String initial;
  final Future<List<FoodSuggestion>> Function(String query) search;

  @override
  State<FoodSearchDialog> createState() => _FoodSearchDialogState();
}

class _FoodSearchDialogState extends State<FoodSearchDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);
  List<FoodSuggestion>? _results;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    final q = _controller.text.trim();
    if (q.isEmpty) return;
    setState(() => _busy = true);
    try {
      final found = await widget.search(q);
      if (mounted) {
        setState(() {
          _results = found.where((f) => f.kind == 'food').toList();
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    return AlertDialog(
      title: const Text('Cari di database gizi'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          TextField(
            key: const Key('food_search_input'),
            controller: _controller,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _run(),
            decoration: InputDecoration(
              labelText: 'Nama makanan',
              suffixIcon: IconButton(tooltip: 'Cari', icon: const Icon(Icons.search), onPressed: _run),
            ),
          ),
          const SizedBox(height: KiraSpace.sm),
          if (_busy) const LinearProgressIndicator(),
          if (_error != null) Text(_error!, style: TextStyle(color: context.scheme.error)),
          if (results != null && results.isEmpty && !_busy)
            const Text('Belum ketemu. Coba nama lain, atau biarkan belum terhitung.'),
          if (results != null && results.isNotEmpty)
            Flexible(
              child: ListView(shrinkWrap: true, children: [
                for (final f in results)
                  ListTile(
                    key: Key('food_result_${f.id}'),
                    title: Text(f.name),
                    subtitle: f.portionG == null ? null : Text('porsi biasa ${nutrientNumber(f.portionG!)} g'),
                    onTap: () => Navigator.pop(context, f),
                  ),
              ]),
            ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Tutup'))],
    );
  }
}
