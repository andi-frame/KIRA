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
      leading: const [DashboardCards()],
      trailing: [
        const SizedBox(height: KiraSpace.sm),
        Card(
          child: Column(
            children: [
              ListTile(
                key: const Key('home_trends_link'),
                leading: Icon(Icons.timeline, color: context.scheme.primary),
                title: const Text('Tren dan penanda'),
                subtitle: Text('Grafik tensi, glukosa, dan penanda triase', style: context.text.bodySmall),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => context.push('/trends'),
              ),
              const Divider(height: 1),
              ListTile(
                key: const Key('home_doctor_link'),
                leading: Icon(Icons.description_outlined, color: context.scheme.primary),
                title: const Text('Ringkasan untuk dokter'),
                subtitle: Text('Teks siap salin atau bagikan PDF', style: context.text.bodySmall),
                trailing: const Icon(Icons.chevron_right, size: 20),
                onTap: () => context.push('/doctor'),
              ),
            ],
          ),
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
        const SizedBox(height: KiraSpace.md),
        _TodayCard(today: d.today),
        if (d.planToday != null) ...[
          const SizedBox(height: KiraSpace.md),
          _PlanCardView(plan: d.planToday!),
        ],
        const SizedBox(height: KiraSpace.md),
        _SignalsCard(data: d),
        const SizedBox(height: KiraSpace.lg),
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
    final greet = greeting(now);
    final greetIcon = switch (now.hour) {
      < 11 => Icons.wb_sunny_outlined,
      < 15 => Icons.wb_sunny,
      < 18 => Icons.wb_twilight,
      _ => Icons.bedtime_outlined,
    };
    return Container(
      key: const Key('next_action_card'),
      decoration: BoxDecoration(
        color: context.scheme.primaryContainer.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(KiraRadius.card),
        border: Border.all(color: context.scheme.primary.withValues(alpha: 0.25), width: 1),
      ),
      padding: const EdgeInsets.all(KiraSpace.lg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          children: [
            Icon(greetIcon, size: 15, color: context.scheme.onPrimaryContainer),
            const SizedBox(width: 6),
            Text(greet,
                style: context.text.labelMedium
                    ?.copyWith(color: context.scheme.onPrimaryContainer, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: KiraSpace.xs),
        Text(
          action.text,
          key: const Key('next_action_text'),
          style: context.text.titleMedium?.copyWith(color: context.scheme.onPrimaryContainer, height: 1.3),
        ),
        if (label != null) ...[
          const SizedBox(height: KiraSpace.md),
          FilledButton.icon(
            key: const Key('next_action_button'),
            onPressed: go,
            icon: const Icon(Icons.arrow_forward, size: 16),
            label: Text(label),
            style: FilledButton.styleFrom(
              backgroundColor: context.scheme.primary,
              foregroundColor: context.scheme.onPrimary,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              minimumSize: const Size(64, 40),
            ),
          ),
        ],
      ]),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hari ini', style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(
                      today.mealsLogged == 0 ? 'Belum ada catatan makan hari ini.' : '${today.mealsLogged} kali makan tercatat.',
                      style: context.text.bodySmall?.copyWith(color: context.scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: context.scheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  today.kcalTarget == null
                      ? '${nutrientNumber(n.kcal)} kkal'
                      : '${nutrientNumber(n.kcal)} dari ${nutrientNumber(today.kcalTarget!)} kkal',
                  key: const Key('today_kcal'),
                  style: context.text.labelMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: KiraSpace.sm),
          LimitBar(label: 'Gula', value: n.sugarG, limit: today.limits.sugarG, unit: 'g'),
          LimitBar(label: 'Natrium', value: n.sodiumMg, limit: today.limits.sodiumMg, unit: 'mg'),
          LimitBar(label: 'Lemak', value: n.fatG, limit: today.limits.fatG, unit: 'g'),
          const Divider(height: KiraSpace.lg),
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
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: context.scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, size: 15, color: context.scheme.primary),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(label, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    Text(words, style: context.text.bodySmall?.copyWith(color: context.scheme.onSurfaceVariant)),
                  ],
                ),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: target <= 0 ? 0 : (value / target).clamp(0, 1).toDouble(),
                    minHeight: 6,
                    color: context.scheme.primary,
                    backgroundColor: context.scheme.surfaceContainerHighest.withValues(alpha: 0.5),
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
          Text('Sinyal kebiasaan',
              style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
            data.enoughData
                ? 'Dari catatanmu 7 hari terakhir (${data.loggedDays} hari tercatat). Penanda, bukan diagnosis.'
                : 'Catatan minggu ini masih sedikit, jadi KIRA belum menyimpulkan kebiasaanmu.',
            style: context.text.bodySmall?.copyWith(color: context.scheme.onSurfaceVariant),
          ),
          const SizedBox(height: KiraSpace.xs),
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
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: Key('signal_${signal.key}'),
        tilePadding: EdgeInsets.zero,
        leading: Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, color: color, size: 15),
        ),
        title: Text(signal.title, style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Row(
          children: [
            Container(
              margin: const EdgeInsets.only(top: 2),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                levelLabel(signal.level),
                style: context.text.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
        childrenPadding: const EdgeInsets.only(left: 36, bottom: KiraSpace.sm, top: 4),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(signal.detail, style: context.text.bodyMedium?.copyWith(height: 1.35)),
          const SizedBox(height: KiraSpace.xs),
          Text('Sumber: ${signal.source}',
              style: context.text.bodySmall?.copyWith(color: context.scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _PlanCardView extends StatelessWidget {
  const _PlanCardView({required this.plan});
  final PlanCard plan;

  @override
  Widget build(BuildContext context) {
    Widget row(IconData icon, String text, bool done) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Icon(done ? Icons.check_circle : icon,
                size: 16, color: done ? context.kira.improve : context.scheme.onSurfaceVariant),
            const SizedBox(width: KiraSpace.sm),
            Expanded(
              child: Text(
                done ? '$text (sudah)' : text,
                style: context.text.bodyMedium?.copyWith(
                  color: done ? context.scheme.onSurfaceVariant : null,
                  decoration: done ? TextDecoration.lineThrough : null,
                ),
              ),
            ),
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
              Expanded(
                child: Text('Rencana hari ini',
                    style: context.text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              ),
              Icon(Icons.chevron_right, size: 20, color: context.scheme.onSurfaceVariant),
            ]),
            if (plan.adapted != null) ...[
              const SizedBox(height: 2),
              Text(plan.adapted!, style: context.text.bodySmall?.copyWith(color: context.scheme.primary)),
            ],
            const SizedBox(height: KiraSpace.sm),
            for (final m in plan.meals)
              if (m.title != null)
                row(Icons.restaurant_outlined,
                    '${m.time?.replaceAll(':', '.') ?? ''} ${m.label}: ${m.title}'.trim(), m.done),
            if (plan.exerciseText != null)
              row(Icons.directions_walk, 'Olahraga: ${plan.exerciseText}', plan.exerciseDone),
            if (plan.bedtime != null)
              row(Icons.bedtime_outlined, 'Tidur jam ${plan.bedtime!.replaceAll(':', '.')}', false),
            const SizedBox(height: KiraSpace.xs),
            Text('Usulan, bukan resep. Ketuk untuk rincian dan ganti usulan.',
                style: context.text.bodySmall?.copyWith(color: context.scheme.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}
