import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../shared/labels.dart';
import '../../shared/models.dart';
import '../../shared/widgets.dart';
import '../home/home_screen.dart';

/// Rencana hari ini; "ganti usulan" memperbarui satu bagian dan disimpan di server.
class PlanTodayController extends AsyncNotifier<DayPlan> {
  @override
  Future<DayPlan> build() => ref.read(apiProvider).getPlanToday();

  Future<void> swap(String slot) async {
    final updated = await ref.read(apiProvider).swapPlan(slot);
    state = AsyncData(updated);
    ref.invalidate(dashboardProvider);
  }
}

final planTodayProvider = AsyncNotifierProvider<PlanTodayController, DayPlan>(PlanTodayController.new);
final planWeekProvider = FutureProvider<List<DayPlan>>((ref) => ref.read(apiProvider).getPlanWeek());

const _weekdays = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
String weekdayName(DateTime d) => _weekdays[d.weekday - 1];

class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Rencana'),
          actions: [
            IconButton(
              key: const Key('plan_preferences_button'),
              tooltip: 'Preferensi rencana',
              icon: const Icon(Icons.tune),
              onPressed: () => context.push('/plan/preferences'),
            ),
          ],
          bottom: const TabBar(tabs: [Tab(text: 'Hari ini'), Tab(text: 'Minggu ini')]),
        ),
        body: const TabBarView(children: [_TodayTab(), _WeekTab()]),
      ),
    );
  }
}

class _TodayTab extends ConsumerWidget {
  const _TodayTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(planTodayProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (e, _) => LoadError(message: friendlyError(e), onRetry: () => ref.invalidate(planTodayProvider)),
      data: (plan) => RefreshIndicator(
        onRefresh: () => ref.refresh(planTodayProvider.future),
        child: ListView(
          key: const Key('plan_today_list'),
          padding: context.pagePadding,
          children: [
            Text('Energi hari ini sekitar ${nutrientNumber(plan.kcalTarget)} kkal', style: context.text.titleMedium),
            Text(plan.energySource, style: context.text.bodySmall),
            if (plan.adapted != null) ...[
              const SizedBox(height: KiraSpace.md),
              SoftNote(key: const Key('plan_adapted'), icon: Icons.sync, text: plan.adapted!),
            ],
            const SizedBox(height: KiraSpace.md),
            for (final m in plan.meals) _MealSlotCard(meal: m),
            if (plan.exercise != null) _ExerciseCard(exercise: plan.exercise!),
            _SleepCard(sleep: plan.sleep),
            const SizedBox(height: KiraSpace.md),
            Text(plan.disclaimer, style: context.text.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({
    super.key,
    required this.icon,
    required this.heading,
    required this.title,
    required this.done,
    this.subtitle,
    this.why,
    this.trailing,
    this.details = const [],
  });

  final IconData icon;
  final String heading;
  final String title;
  final bool done;
  final String? subtitle;
  final String? why;
  final Widget? trailing;
  final List<Widget> details;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: KiraSpace.xs),
      child: Padding(
        padding: const EdgeInsets.all(KiraSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(done ? Icons.check_circle : icon, color: done ? context.kira.improve : context.scheme.primary),
            const SizedBox(width: KiraSpace.sm),
            Expanded(child: Text(heading, style: context.text.labelLarge)),
            if (done) Text('sudah tercatat', style: context.text.labelMedium?.copyWith(color: context.kira.improve)),
          ]),
          const SizedBox(height: KiraSpace.xs),
          Text(title, style: context.text.titleMedium),
          if (subtitle != null) Text(subtitle!, style: context.text.bodyMedium),
          if (why != null) ...[
            const SizedBox(height: KiraSpace.xs),
            Text(why!, style: context.text.bodySmall),
          ],
          ...details,
          if (trailing != null) Align(alignment: Alignment.centerRight, child: trailing),
        ]),
      ),
    );
  }
}

class _MealSlotCard extends ConsumerWidget {
  const _MealSlotCard({required this.meal});
  final PlanMeal meal;

  Future<void> _swap(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(planTodayProvider.notifier).swap(meal.slot);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = meal.totals;
    final heading = '${meal.label[0].toUpperCase()}${meal.label.substring(1)}${meal.time != null ? ' · ${meal.time!.replaceAll(':', '.')}' : ''}';
    if (meal.done && meal.eaten != null) {
      return _SlotCard(
        key: Key('plan_meal_${meal.slot}'),
        icon: Icons.restaurant_outlined,
        heading: heading,
        title: meal.eaten!,
        done: true,
        subtitle: meal.title == null ? null : 'Usulan tadi: ${meal.title}',
      );
    }
    return _SlotCard(
      key: Key('plan_meal_${meal.slot}'),
      icon: Icons.restaurant_outlined,
      heading: heading,
      title: meal.title ?? 'Belum ada usulan yang cocok',
      done: meal.done,
      subtitle: meal.title == null
          ? null
          : '${nutrientNumber(t.kcal)} kkal · ${nutrientLine(sugarG: t.sugarG, sodiumMg: t.sodiumMg, fatG: t.fatG)}',
      why: meal.why,
      details: [
        if (meal.components.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: KiraSpace.xs),
            child: Text(
              meal.components
                  .map((c) => c.grams == null ? c.name : '${c.name} ${nutrientNumber(c.grams!)} g')
                  .join(', '),
              style: context.text.bodySmall,
            ),
          ),
      ],
      trailing: meal.done || meal.title == null
          ? null
          : TextButton.icon(
              key: Key('swap_${meal.slot}'),
              onPressed: () => _swap(context, ref),
              icon: const Icon(Icons.swap_horiz),
              label: const Text('Ganti usulan'),
            ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({required this.exercise});
  final PlanExercise exercise;

  @override
  Widget build(BuildContext context) {
    if (exercise.blocked) {
      return _SlotCard(
        key: const Key('plan_exercise'),
        icon: Icons.health_and_safety_outlined,
        heading: 'Olahraga',
        title: 'Latihan baru ditahan dulu',
        done: false,
        why: exercise.why,
      );
    }
    return _SlotCard(
      key: const Key('plan_exercise'),
      icon: Icons.directions_walk,
      heading: 'Olahraga${exercise.time != null ? ' · ${exercise.time!.replaceAll(':', '.')}' : ''}',
      title: '${exercise.activity ?? 'Jalan cepat'} ${exercise.minutes} menit'
          '${exercise.strength ? ' + penguatan otot' : ''}',
      done: exercise.done,
      subtitle: exercise.doneMinutes > 0 ? 'Sudah ${nutrientNumber(exercise.doneMinutes)} menit hari ini' : null,
      why: exercise.why,
    );
  }
}

class _SleepCard extends StatelessWidget {
  const _SleepCard({required this.sleep});
  final PlanSleep sleep;

  @override
  Widget build(BuildContext context) => _SlotCard(
        key: const Key('plan_sleep'),
        icon: Icons.bedtime_outlined,
        heading: 'Tidur',
        title: 'Tidur jam ${sleep.bedtime.replaceAll(':', '.')}, bangun ${sleep.wakeTime.replaceAll(':', '.')}',
        subtitle: 'Target ${nutrientNumber(sleep.hours)} jam',
        done: false,
        why: sleep.why,
      );
}

class _WeekTab extends ConsumerWidget {
  const _WeekTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(planWeekProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator.adaptive()),
      error: (e, _) => LoadError(message: friendlyError(e), onRetry: () => ref.invalidate(planWeekProvider)),
      data: (days) => ListView(
        key: const Key('plan_week_list'),
        padding: context.pagePadding,
        children: [
          for (final d in days)
            Card(
              key: Key('plan_week_${d.date.toIso8601String().substring(0, 10)}'),
              margin: const EdgeInsets.symmetric(vertical: KiraSpace.xs),
              child: Padding(
                padding: const EdgeInsets.all(KiraSpace.lg),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${weekdayName(d.date)}, ${formatDate(d.date)}', style: context.text.titleSmall),
                  const SizedBox(height: KiraSpace.xs),
                  for (final m in d.meals)
                    if (m.title != null) Text('${m.label}: ${m.title}', style: context.text.bodyMedium),
                  Text(
                    d.exercise == null
                        ? 'Olahraga: hari istirahat'
                        : d.exercise!.blocked
                            ? 'Olahraga: ditahan dulu, bicarakan dengan tenaga kesehatan'
                            : 'Olahraga: ${d.exercise!.activity} ${d.exercise!.minutes} menit',
                    style: context.text.bodyMedium,
                  ),
                  Text('Tidur: jam ${d.sleep.bedtime.replaceAll(':', '.')} (${nutrientNumber(d.sleep.hours)} jam)',
                      style: context.text.bodyMedium),
                ]),
              ),
            ),
          if (days.isNotEmpty) ...[
            const SizedBox(height: KiraSpace.md),
            Text(days.first.disclaimer, style: context.text.bodySmall),
          ],
        ],
      ),
    );
  }
}
