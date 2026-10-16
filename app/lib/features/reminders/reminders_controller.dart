import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import 'notification_service.dart';
import 'reminder_plan.dart';

const _prefsKey = 'reminders_v1';

/// Pengaturan pengingat + penjadwalannya. Disusun ulang tiap aplikasi dibuka, tiap ada catatan baru, dan tiap pengaturan
/// berubah, sehingga pengingat hari ini tidak muncul bila pengguna sudah mencatat.
class RemindersController extends Notifier<ReminderSettings> {
  bool _loaded = false;

  @override
  ReminderSettings build() {
    // Pengingat milik satu akun: berhenti begitu keluar, supaya akun berikutnya di ponsel ini tidak ikut diganggu.
    ref.listen(authProvider.select((s) => s.token), (prev, next) {
      if (prev != null && next != prev) unawaited(_reset());
    });
    return const ReminderSettings();
  }

  Future<void> _reset() async {
    state = const ReminderSettings();
    await ref.read(prefsStoreProvider).write(_prefsKey, null);
    await ref.read(notificationServiceProvider).cancelAll();
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    state = ReminderSettings.fromJson(await ref.read(prefsStoreProvider).read(_prefsKey));
    await reschedule();
  }

  /// false bila pengguna menyalakan pengingat tetapi izin notifikasi ditolak (pengaturan tidak disimpan menyala).
  Future<bool> update(ReminderSettings next) async {
    var granted = true;
    if (next.anyEnabled && !state.anyEnabled) granted = await ref.read(notificationServiceProvider).ensurePermission();
    if (next.anyEnabled && !granted) {
      state = const ReminderSettings();
      await ref.read(prefsStoreProvider).write(_prefsKey, null);
      return false;
    }
    state = next;
    await ref.read(prefsStoreProvider).write(_prefsKey, next.anyEnabled ? next.toJson() : null);
    await reschedule();
    return true;
  }

  Future<void> reschedule({DateTime? now}) async {
    final service = ref.read(notificationServiceProvider);
    if (!state.anyEnabled) {
      await service.cancelAll();
      return;
    }
    final api = ref.read(apiProvider);
    var loggedToday = false, followUpDue = false;
    try {
      loggedToday = await api.hasLoggedToday();
    } catch (_) {} // tanpa sinyal: lebih baik mengingatkan daripada diam
    if (state.checkFollowUp) {
      try {
        followUpDue = (await api.getCheck())?.followUp ?? false;
      } catch (_) {}
    }
    PlanReminderInput? plan;
    if (state.plan) {
      try {
        plan = await _planInput(api);
      } catch (_) {} // tanpa sinyal: pengingat rencana menunggu jadwal ulang berikutnya
    }
    await service.apply(planReminders(
      now: now ?? DateTime.now(),
      settings: state,
      loggedToday: loggedToday,
      checkFollowUpDue: followUpDue,
      plan: plan,
    ));
  }

  Future<PlanReminderInput> _planInput(KiraApi api) async {
    final prefs = await api.getPlanPreferences();
    final today = await api.getPlanToday();
    return PlanReminderInput(
      mealTimes: prefs.mealTimes,
      exerciseTime: prefs.exerciseTime,
      exerciseDays: (today.exercise?.blocked ?? false) ? const [] : prefs.exerciseDays,
      exerciseLabel: today.exercise?.activity ?? prefs.exerciseKinds.first,
      bedtime: today.sleep.bedtime,
      loggedSlotsToday: {for (final m in today.meals) if (m.done) m.slot},
      viaWhatsapp: prefs.whatsapp ? {for (final e in prefs.reminders.entries) if (e.value) e.key} : const {},
    );
  }
}

final remindersProvider = NotifierProvider<RemindersController, ReminderSettings>(RemindersController.new);
