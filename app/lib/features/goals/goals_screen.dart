import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../shared/goal_models.dart';
import '../../shared/widgets.dart';

final goalsProvider = FutureProvider<GoalsData>((ref) {
  ref.watch(authProvider.select((s) => s.token));
  return ref.read(apiProvider).getGoals();
});

String _n(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1).replaceAll('.', ',');

/// Bilah kemajuan + kalimat. Tanpa nada menghukum: minggu tanpa catatan ditulis "tanpa catatan", bukan gagal.
class GoalProgress extends StatelessWidget {
  const GoalProgress({super.key, required this.goal, this.showHistory = true});
  final Goal goal;
  final bool showHistory;

  @override
  Widget build(BuildContext context) {
    final kira = context.kira;
    final over = goal.isMax && !goal.met;
    final color = over ? kira.attention : (goal.met ? kira.improve : context.scheme.primary);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(goal.label, style: context.text.titleSmall),
      const SizedBox(height: KiraSpace.xs),
      Semantics(
        label: '${goal.label}: ${goal.progressText}',
        child: ExcludeSemantics(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(KiraRadius.chip),
            child: LinearProgressIndicator(
              key: Key('goal_bar_${goal.kind}'),
              value: goal.fraction,
              minHeight: 10,
              color: color,
              backgroundColor: context.scheme.surfaceContainerHighest,
            ),
          ),
        ),
      ),
      const SizedBox(height: KiraSpace.xs),
      Text(goal.progressText, key: Key('goal_text_${goal.kind}'), style: context.text.bodyMedium),
      if (showHistory && goal.weeksWithData > 0)
        Padding(
          padding: const EdgeInsets.only(top: KiraSpace.xs),
          child: Text(
            '${goal.metWeeks} dari ${goal.weeksWithData} minggu terakhir ${goal.isMax ? 'sesuai batas' : 'tercapai'}',
            key: Key('goal_history_${goal.kind}'),
            style: context.text.bodySmall,
          ),
        ),
    ]);
  }
}

/// Ringkasan target di layar 10 Tahun.
class GoalsCard extends ConsumerWidget {
  const GoalsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(goalsProvider).value;
    if (data == null) return const SizedBox.shrink();
    return Card(
      key: const Key('goals_card'),
      child: Padding(
        padding: const EdgeInsets.all(KiraSpace.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Targetmu minggu ini', style: context.text.titleMedium),
          const SizedBox(height: KiraSpace.xs),
          if (data.goals.isEmpty)
            Text(
              'Pasang satu atau dua target kecil, misalnya bergerak 150 menit seminggu. KIRA menghitung kemajuannya dari catatanmu.',
              style: context.text.bodyMedium?.copyWith(color: context.scheme.onSurfaceVariant),
            )
          else ...[
            Text('${data.daysLeft} hari lagi sampai Minggu', style: context.text.bodySmall),
            const SizedBox(height: KiraSpace.md),
            for (final g in data.goals) ...[GoalProgress(goal: g, showHistory: false), const SizedBox(height: KiraSpace.md)],
          ],
          OutlinedButton.icon(
            key: const Key('goals_manage'),
            icon: const Icon(Icons.flag_outlined),
            label: Text(data.goals.isEmpty ? 'Pasang target' : 'Atur target'),
            onPressed: () => context.push('/goals'),
          ),
        ]),
      ),
    );
  }
}

class GoalsScreen extends ConsumerStatefulWidget {
  const GoalsScreen({super.key});

  @override
  ConsumerState<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends ConsumerState<GoalsScreen> {
  Future<void> _run(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      ref.invalidate(goalsProvider);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _add(GoalsData data) async {
    final kind = await showModalBottomSheet<GoalKind>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final k in data.available)
            ListTile(
              key: Key('add_${k.kind}'),
              title: Text(k.label),
              subtitle: Text('${k.isMax ? 'Batas' : 'Target'} bawaan ${_n(k.defaultTarget)} ${k.unit}'),
              onTap: () => Navigator.pop(ctx, k),
            ),
        ]),
      ),
    );
    if (kind == null || !mounted) return;
    final target = await showDialog<double>(context: context, builder: (_) => _TargetDialog(kind: kind, initial: kind.defaultTarget));
    if (target == null) return;
    await _run(() => ref.read(apiProvider).createGoal(kind.kind, target));
  }

  Future<void> _edit(Goal g, GoalsData data) async {
    final kind = data.kinds.firstWhere((k) => k.kind == g.kind);
    final target = await showDialog<double>(context: context, builder: (_) => _TargetDialog(kind: kind, initial: g.target));
    if (target == null) return;
    await _run(() => ref.read(apiProvider).updateGoal(g.id, target));
  }

  @override
  Widget build(BuildContext context) {
    final goals = ref.watch(goalsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Target mingguan')),
      body: goals.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => LoadError(
          message: e is ApiException ? e.message : 'Target belum bisa dimuat. Coba lagi sebentar lagi ya.',
          onRetry: () => ref.invalidate(goalsProvider),
        ),
        data: (data) => ListView(
          padding: context.pagePadding,
          children: [
            const PageIntro('Dihitung otomatis dari catatanmu Senin sampai Minggu. Minggu tanpa catatan tidak dihitung sebagai gagal.'),
            if (data.goals.isEmpty)
              const EmptyState(
                key: Key('goals_empty'),
                title: 'Belum ada target',
                message: 'Pilih satu target kecil untuk mulai, misalnya bergerak 150 menit seminggu.',
              ),
            for (final g in data.goals)
              Card(
                key: Key('goal_${g.kind}'),
                child: Padding(
                  padding: const EdgeInsets.all(KiraSpace.lg),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    GoalProgress(goal: g),
                    const SizedBox(height: KiraSpace.sm),
                    Wrap(spacing: KiraSpace.sm, children: [
                      TextButton(key: Key('edit_${g.kind}'), onPressed: () => _edit(g, data), child: const Text('Ubah angka')),
                      TextButton(
                        key: Key('delete_${g.kind}'),
                        onPressed: () => _run(() => ref.read(apiProvider).deleteGoal(g.id)),
                        child: const Text('Hapus'),
                      ),
                    ]),
                  ]),
                ),
              ),
            if (data.available.isNotEmpty) ...[
              const SizedBox(height: KiraSpace.md),
              FilledButton.icon(
                key: const Key('goal_add'),
                icon: const Icon(Icons.add),
                label: const Text('Tambah target'),
                onPressed: () => _add(data),
              ),
            ],
            const SizedBox(height: KiraSpace.sm),
            const Align(
              alignment: Alignment.centerLeft,
              child: SourceLink(
                'Acuan: 150 menit aktivitas sedang per minggu (WHO 2020) dan tidur 7 jam atau lebih (konsensus AASM/SRS). '
                'Batas minuman manis dan hari mencatat adalah usul KIRA; sesuaikan dengan dirimu.',
                label: 'Acuan',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TargetDialog extends StatefulWidget {
  const _TargetDialog({required this.kind, required this.initial});
  final GoalKind kind;
  final double initial;

  @override
  State<_TargetDialog> createState() => _TargetDialogState();
}

class _TargetDialogState extends State<_TargetDialog> {
  late final TextEditingController _controller = TextEditingController(text: _n(widget.initial));
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final v = double.tryParse(_controller.text.trim().replaceAll(',', '.'));
    final k = widget.kind;
    if (v == null || v < k.min || v > k.max) {
      setState(() => _error = 'Isi angka ${_n(k.min)} sampai ${_n(k.max)} ${k.unit}.');
      return;
    }
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.kind.label),
        content: TextField(
          key: const Key('goal_target_input'),
          controller: _controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
          onSubmitted: (_) => _save(),
          decoration: InputDecoration(
            labelText: widget.kind.isMax ? 'Batas per minggu' : 'Target per minggu',
            suffixText: widget.kind.unit,
            errorText: _error,
            errorMaxLines: 2,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
          FilledButton(key: const Key('goal_target_save'), onPressed: _save, child: const Text('Simpan')),
        ],
      );
}
