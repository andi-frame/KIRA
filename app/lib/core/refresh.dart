import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import '../features/chat/frequent_foods.dart';
import '../features/check/check_providers.dart';
import '../features/doctor/doctor_summary_screen.dart';
import '../features/goals/goals_screen.dart';
import '../features/history/history_controller.dart';
import '../features/home/home_screen.dart';
import '../features/plan/plan_screen.dart';
import '../features/projection/projection_providers.dart';
import '../features/trends/insight_cards.dart';
import '../features/trends/trends_screen.dart';

/// Dipanggil setiap kali catatan atau hasil berubah (dicatat, diubah, dihapus; hasil cek; rekam medis): semua tampilan yang
/// diturunkan dari data itu dimuat ulang dari server, sehingga tidak ada layar yang tertahan pada versi sebelum perubahan
/// (proyeksi, Beranda, Riwayat, Tren dan Penanda, rencana, target, ringkasan dokter).
///
/// Dipakai dengan `refreshHealthData(ref.invalidate)`, baik dari `Ref` (pengontrol) maupun `WidgetRef` (layar).
/// `includeHistory: false` bagi pemanggil yang memuat ulang Riwayat sendiri (mempertahankan halaman yang sudah dibuka).
void refreshHealthData(void Function(ProviderOrFamily provider) invalidate, {bool includeHistory = true}) {
  invalidate(projectionProvider);
  invalidate(weeklyRecapProvider);
  invalidate(dashboardProvider);
  invalidate(frequentFoodsProvider);
  invalidate(trendsProvider);
  invalidate(riskHistoryProvider);
  invalidate(sleepPatternsProvider);
  invalidate(checkProvider);
  invalidate(planTodayProvider);
  invalidate(planWeekProvider);
  invalidate(goalsProvider);
  invalidate(doctorSummaryProvider);
  invalidate(foodGlucoseProvider);
  if (includeHistory) invalidate(historyProvider);
}
