import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../shared/models.dart';
import 'jeda_bridge.dart';
import 'jeda_content.dart';
import 'jeda_models.dart';

const _prefsKey = 'jeda_v1';

class JedaState {
  const JedaState({
    this.settings = const JedaSettings(),
    this.permissions = const JedaPermissions(),
    this.installed = const [],
    this.loaded = false,
  });

  final JedaSettings settings;
  final JedaPermissions permissions;
  final List<JedaApp> installed;
  final bool loaded;

  /// Menyala dan semua izin ada: layanan benar-benar menjaga.
  bool get running => settings.enabled && permissions.ready && settings.apps.isNotEmpty;

  JedaState copyWith({JedaSettings? settings, JedaPermissions? permissions, List<JedaApp>? installed, bool? loaded}) =>
      JedaState(
        settings: settings ?? this.settings,
        permissions: permissions ?? this.permissions,
        installed: installed ?? this.installed,
        loaded: loaded ?? this.loaded,
      );
}

/// Pengaturan Jeda Sosmed + isi kartu yang dikirim ke Android. Isi kartu disusun ulang tiap aplikasi dibuka kembali,
/// tiap ada catatan baru, dan tiap pengaturan berubah. Dimiliki satu akun: keluar akun mematikan semuanya.
class JedaController extends Notifier<JedaState> {
  bool _loaded = false;

  JedaBridge get _bridge => ref.read(jedaBridgeProvider);

  @override
  JedaState build() {
    ref.listen(authProvider.select((s) => s.token), (prev, next) {
      if (prev != null && next != prev) unawaited(_reset());
    });
    return const JedaState();
  }

  Future<void> _reset() async {
    state = state.copyWith(settings: const JedaSettings());
    await ref.read(prefsStoreProvider).write(_prefsKey, null);
    await _bridge.stop();
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    final settings = JedaSettings.fromJson(await ref.read(prefsStoreProvider).read(_prefsKey));
    final permissions = await _bridge.permissions();
    final installed = await _bridge.installedApps();
    if (!ref.mounted) return;
    state = JedaState(settings: settings, permissions: permissions, installed: installed, loaded: true);
    await refresh();
  }

  Future<void> refreshPermissions() async {
    final permissions = await _bridge.permissions();
    if (!ref.mounted) return;
    final before = state.permissions.ready;
    state = state.copyWith(permissions: permissions);
    if (permissions.ready && !before) await refresh();
  }

  Future<void> update(JedaSettings next) async {
    var settings = next;
    if (settings.enabled && settings.apps.isEmpty && !state.settings.enabled) {
      // Pertama kali menyala: mulai dari aplikasi sosmed yang terpasang, pengguna boleh mengubahnya.
      // Fun fact ikut menyala di awal: kartu terjadwal hanya tampil di jam tertentu, sehingga tanpa itu Jeda tampak "tidak
      // bekerja" di sebagian besar hari. Pengguna bisa mematikannya di layar pengaturan.
      settings = settings.copyWith(
        funFact: true,
        apps: [
          for (final a in state.installed)
            if (defaultSocialApps.contains(a.package)) a.package,
        ],
      );
    }
    state = state.copyWith(settings: settings);
    await ref.read(prefsStoreProvider).write(_prefsKey, settings.enabled ? settings.toJson() : null);
    if (!settings.enabled) {
      await _bridge.stop();
      return;
    }
    await refresh();
  }

  /// Menyusun ulang isi kartu dari rencana terbaru dan mengirimkannya. Tanpa sinyal, pengaturan tetap dikirim dan isi
  /// kartu yang sudah ada di ponsel dipakai (kartu pagi sudah disiapkan beberapa hari ke depan).
  Future<void> refresh({DateTime? now}) async {
    if (!_bridge.supported || !state.settings.enabled) return;
    final api = ref.read(apiProvider);
    JedaPayload? payload;
    try {
      final today = await api.getPlanToday();
      var week = const <DayPlan>[];
      try {
        week = await api.getPlanWeek();
      } catch (_) {}
      final check = await _check(api);
      payload = buildJedaPayload(
        today: today,
        week: week,
        check: check,
        now: now ?? DateTime.now(),
      );
    } catch (_) {}
    await _bridge.apply(state.settings, payload);
  }

  Future<CheckRecommendation?> _check(KiraApi api) async {
    try {
      return await api.getCheck();
    } catch (_) {
      return null;
    }
  }

  /// Contoh kartu sekarang (dari layar pengaturan).
  Future<void> preview(String kind) async {
    await refresh();
    await _bridge.preview(kind);
  }
}

final jedaProvider = NotifierProvider<JedaController, JedaState>(JedaController.new);
