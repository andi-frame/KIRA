import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../shared/labels.dart';
import '../../shared/limit_bar.dart';
import '../../shared/models.dart';
import '../../shared/widgets.dart';
import '../projection/projection_screen.dart';

/// Beranda dari GET /dashboard; dimuat ulang saat ada catatan baru dan saat aplikasi dibuka kembali.
final dashboardProvider = FutureProvider<DashboardData>((ref) => ref.read(apiProvider).getDashboard());

/// Beranda: langkah berikutnya, kondisi hari ini, sinyal kebiasaan, lalu proyeksi 10 tahun (pindahan tab "10 Tahun").
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ProjectionScreen(
      title: 'Beranda',
      onRefresh: () => ref.invalidate(dashboardProvider),
      leading: const [DashboardCards(), SizedBox(height: KiraSpace.lg)],
      trailing: [
        const Divider(height: KiraSpace.xl),
        ListTile(
          key: const Key('home_trends_link'),
          leading: const Icon(Icons.timeline),
          title: const Text('Tren dan penanda'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/trends'),
        ),
        ListTile(
          key: const Key('home_doctor_link'),
          leading: const Icon(Icons.description_outlined),
          title: const Text('Ringkasan untuk dokter'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push('/doctor'),
        ),
      ],
    );
  }
}

class DashboardCards extends ConsumerWidget {
  const DashboardCards({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dashboardProvider);
    return async.when(
      loading: () => const Padding(
        padding: EdgeInsets.all(KiraSpace.xl),
        child: Center(child: CircularProgressIndicator.adaptive()),
      ),
      error: (e, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(KiraSpace.lg),
          child: Row(children: [
            Expanded(child: Text('Kondisi hari ini belum termuat. ${friendlyError(e)}')),
            TextButton(
              key: const Key('dashboard_retry'),
              onPressed: () => ref.invalidate(dashboardProvider),
              child: const Text('Coba lagi'),
            ),
          ]),
        ),
      ),
      data: (d) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _NextActionCard(action: d.nextAction, now: ref.read(clockProvider)()),
        const SizedBox(height: KiraSpace.lg),
        _TodayCard(today: d.today),
        if (d.planToday != null) ...[
          const SizedBox(height: KiraSpace.lg),
          _PlanCardView(plan: d.planToday!),
        ],
        const SizedBox(height: KiraSpace.lg),
        _SignalsCard(data: d),
      ]),
    );
  }
}

String greeting(DateTime now) => switch (now.hour) {
      < 11 => 'Selamat pagi',
      < 15 => 'Selamat siang',
      < 18 => 'Selamat sore',
      _ => 'Selamat malam',
    };

class _NextActionCard extends StatelessWidget {
  const _NextActionCard({required this.action, required this.now});
  final NextAction action;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final (String? label, VoidCallback? go) = switch (action.kind) {
      'log_meal' => ('Catat di Ngobrol', () => context.go('/chat')),
      'check' => ('Buka Cek', () => context.go('/check')),
      'measure_bp' => ('Buka protokol tensi', () => context.push('/bp-protocol')),
      _ => (null, null),
    };
    return Card(
      key: const Key('next_action_card'),
      color: context.scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(KiraSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(greeting(now), style: context.text.labelLarge?.copyWith(color: context.scheme.onPrimaryContainer)),
          const SizedBox(height: KiraSpace.xs),
          Text(action.text,
              key: const Key('next_action_text'),
              style: context.text.titleMedium?.copyWith(color: context.scheme.onPrimaryContainer)),
          if (label != null) ...[
            const SizedBox(height: KiraSpace.md),
            FilledButton(key: const Key('next_action_button'), onPressed: go, child: Text(label)),
          ],
        ]),
      ),
    );
  }
}

class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.today});
  final TodayStatus today;

  @override
  Widget build(BuildContext context) {
    final n = today.nutrition;
    final activityLeft = today.activityTarget - today.activityMinutes;
    final sleep = today.sleepHours;
    return Card(
      key: const Key('today_card'),
      child: Padding(
        padding: const EdgeInsets.all(KiraSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Hari ini', style: context.text.titleMedium)),
            Text(
              today.kcalTarget == null
                  ? '${nutrientNumber(n.kcal)} kkal'
                  : '${nutrientNumber(n.kcal)} dari ${nutrientNumber(today.kcalTarget!)} kkal',
              key: const Key('today_kcal'),
              style: context.text.titleSmall,
            ),
          ]),
          Text(
            today.mealsLogged == 0 ? 'Belum ada catatan makan hari ini.' : '${today.mealsLogged} kali makan tercatat.',
            style: context.text.bodySmall,
          ),
          const SizedBox(height: KiraSpace.sm),
          LimitBar(label: 'Gula', value: n.sugarG, limit: today.limits.sugarG, unit: 'g'),
          LimitBar(label: 'Natrium', value: n.sodiumMg, limit: today.limits.sodiumMg, unit: 'mg'),
          LimitBar(label: 'Lemak', value: n.fatG, limit: today.limits.fatG, unit: 'g'),
          const Divider(height: KiraSpace.xl),
          _ProgressRow(
            key: const Key('today_activity'),
            icon: Icons.directions_walk,
            label: 'Bergerak',
            value: today.activityMinutes,
            target: today.activityTarget,
            words: activityLeft > 0
                ? '${nutrientNumber(today.activityMinutes)} dari ${nutrientNumber(today.activityTarget)} menit, sisa ${nutrientNumber(activityLeft)} menit'
                : '${nutrientNumber(today.activityMinutes)} menit, target hari ini tercapai',
          ),
          _ProgressRow(
            key: const Key('today_sleep'),
            icon: Icons.bedtime_outlined,
            label: 'Tidur semalam',
            value: sleep ?? 0,
            target: today.sleepTargetHours,
            words: sleep == null
                ? 'belum tercatat (target ${nutrientNumber(today.sleepTargetHours)} jam)'
                : sleep >= today.sleepTargetHours
                    ? '${nutrientNumber(sleep)} jam, sesuai target ${nutrientNumber(today.sleepTargetHours)} jam'
                    : '${nutrientNumber(sleep)} jam, kurang ${nutrientNumber(today.sleepTargetHours - sleep)} jam dari target',
          ),
        ]),
      ),
    );
  }
}

class _ProgressRow extends StatelessWidget {
  const _ProgressRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.target,
    required this.words,
  });

  final IconData icon;
  final String label;
  final double value;
  final double target;
  final String words;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label: $words',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: KiraSpace.xs),
          child: Row(children: [
            Icon(icon, size: 20, color: context.scheme.onSurfaceVariant),
            const SizedBox(width: KiraSpace.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(label, style: context.text.bodyMedium),
                Text(words, style: context.text.bodySmall),
                const SizedBox(height: 2),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: target <= 0 ? 0 : (value / target).clamp(0, 1).toDouble(),
                    minHeight: 6,
                    backgroundColor: context.scheme.surfaceContainerHighest,
                  ),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

String levelLabel(String level) => switch (level) {
      'perhatian' => 'Perhatian',
      'pantau' => 'Pantau',
      'baik' => 'Baik',
      _ => 'Info',
    };

class _SignalsCard extends StatelessWidget {
  const _SignalsCard({required this.data});
  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('signals_card'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(KiraSpace.lg, KiraSpace.lg, KiraSpace.lg, KiraSpace.sm),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Sinyal kebiasaan', style: context.text.titleMedium),
          Text(
            data.enoughData
                ? 'Dari catatanmu 7 hari terakhir (${data.loggedDays} hari tercatat). Penanda, bukan diagnosis.'
                : 'Catatan minggu ini masih sedikit, jadi KIRA belum menyimpulkan kebiasaanmu.',
            style: context.text.bodySmall,
          ),
          for (final s in data.signals) _SignalTile(signal: s),
        ]),
      ),
    );
  }
}

class _SignalTile extends StatelessWidget {
  const _SignalTile({required this.signal});
  final HabitSignal signal;

  @override
  Widget build(BuildContext context) {
    final kira = context.kira;
    final (Color color, IconData icon) = switch (signal.level) {
      'perhatian' => (kira.attention, Icons.priority_high),
      'pantau' => (context.scheme.tertiary, Icons.visibility_outlined),
      'baik' => (kira.improve, Icons.check_circle_outline),
      _ => (context.scheme.onSurfaceVariant, Icons.info_outline),
    };
    return ExpansionTile(
      key: Key('signal_${signal.key}'),
      tilePadding: EdgeInsets.zero,
      leading: Icon(icon, color: color),
      title: Text(signal.title),
      subtitle: Text(levelLabel(signal.level), style: context.text.labelMedium?.copyWith(color: color)),
      childrenPadding: const EdgeInsets.only(bottom: KiraSpace.md),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(signal.detail, style: context.text.bodyMedium),
        const SizedBox(height: KiraSpace.xs),
        Text('Sumber: ${signal.source}', style: context.text.bodySmall),
      ],
    );
  }
}


class _PlanCardView extends StatelessWidget {
  const _PlanCardView({required this.plan});
  final PlanCard plan;

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String text, bool done) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Icon(done ? Icons.check_circle : icon, size: 18,
                color: done ? context.kira.improve : context.scheme.onSurfaceVariant),
            const SizedBox(width: KiraSpace.sm),
            Expanded(child: Text(done ? '$text (sudah)' : text, style: context.text.bodyMedium)),
          ]),
        );
    return Card(
      key: const Key('plan_card'),
      child: InkWell(
        onTap: () => context.push('/plan'),
        borderRadius: BorderRadius.circular(KiraRadius.card),
        child: Padding(
          padding: const EdgeInsets.all(KiraSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Rencana hari ini', style: context.text.titleMedium)),
              const Icon(Icons.chevron_right),
            ]),
            if (plan.adapted != null) Text(plan.adapted!, style: context.text.bodySmall),
            const SizedBox(height: KiraSpace.xs),
            for (final m in plan.meals)
              if (m.title != null)
                row(Icons.restaurant_outlined, '${m.time?.replaceAll(':', '.') ?? ''} ${m.label}: ${m.title}'.trim(), m.done),
            if (plan.exerciseText != null) row(Icons.directions_walk, 'Olahraga: ${plan.exerciseText}', plan.exerciseDone),
            if (plan.bedtime != null) row(Icons.bedtime_outlined, 'Tidur jam ${plan.bedtime!.replaceAll(':', '.')}', false),
            const SizedBox(height: KiraSpace.xs),
            Text('Usulan, bukan resep. Ketuk untuk rincian dan ganti usulan.', style: context.text.bodySmall),
          ]),
        ),
      ),
    );
  }
}
