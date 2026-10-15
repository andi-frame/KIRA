import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../projection/projection_providers.dart';
import 'health_connect_source.dart';
import 'health_source.dart';

final healthSourceProvider = Provider<HealthSource>((ref) => kIsWeb ? const _UnsupportedSource() : HealthConnectSource());

class _UnsupportedSource implements HealthSource {
  const _UnsupportedSource();

  @override
  Future<HealthAvailability> availability() async => HealthAvailability.unsupported;

  @override
  Future<bool> requestAccess() async => false;

  @override
  Future<({List<RawStep> steps, List<RawSleep> sleep})> read({int days = 14}) async => (steps: const <RawStep>[], sleep: const <RawSleep>[]);
}

const _enabledKey = 'health_enabled';
const _lastSyncKey = 'health_last_sync';
const syncWindowDays = 14;
const autoSyncEvery = Duration(hours: 6);

class HealthSyncState {
  const HealthSyncState({
    this.loaded = false,
    this.enabled = false,
    this.busy = false,
    this.availability,
    this.lastSync,
    this.message,
    this.activityDays = 0,
    this.sleepNights = 0,
  });

  final bool loaded, enabled, busy;
  final HealthAvailability? availability;
  final DateTime? lastSync;
  final String? message;
  final int activityDays, sleepNights;

  HealthSyncState copyWith({
    bool? loaded,
    bool? enabled,
    bool? busy,
    HealthAvailability? availability,
    DateTime? lastSync,
    String? message,
    bool clearMessage = false,
    int? activityDays,
    int? sleepNights,
  }) =>
      HealthSyncState(
        loaded: loaded ?? this.loaded,
        enabled: enabled ?? this.enabled,
        busy: busy ?? this.busy,
        availability: availability ?? this.availability,
        lastSync: lastSync ?? this.lastSync,
        message: clearMessage ? null : (message ?? this.message),
        activityDays: activityDays ?? this.activityDays,
        sleepNights: sleepNights ?? this.sleepNights,
      );
}

/// Sinkronisasi langkah dan tidur dari Health Connect. Hanya jalan setelah pengguna menyalakannya sendiri,
/// dan mematikannya menghapus data tersebut dari server.
class HealthSyncController extends Notifier<HealthSyncState> {
  @override
  HealthSyncState build() => const HealthSyncState();

  PrefsStore get _prefs => ref.read(prefsStoreProvider);

  Future<void> load() async {
    final enabled = await _prefs.read(_enabledKey) == '1';
    final last = DateTime.tryParse(await _prefs.read(_lastSyncKey) ?? '');
    final availability = await ref.read(healthSourceProvider).availability();
    state = state.copyWith(loaded: true, enabled: enabled, lastSync: last, availability: availability);
  }

  Future<void> enable() async {
    if (state.busy) return;
    final source = ref.read(healthSourceProvider);
    final availability = await source.availability();
    state = state.copyWith(availability: availability, clearMessage: true);
    if (availability == HealthAvailability.unsupported) {
      state = state.copyWith(message: 'Health Connect hanya tersedia di aplikasi Android.');
      return;
    }
    if (availability == HealthAvailability.notInstalled) {
      state = state.copyWith(message: 'Health Connect belum terpasang atau perlu diperbarui. Pasang dari Play Store, lalu coba lagi.');
      return;
    }
    state = state.copyWith(busy: true);
    try {
      final granted = await source.requestAccess();
      if (!granted) {
        state = state.copyWith(
            busy: false, message: 'Izin belum diberikan, jadi KIRA tidak membaca apa pun. Kamu bisa mencobanya lagi kapan saja.');
        return;
      }
      await _prefs.write(_enabledKey, '1');
      state = state.copyWith(enabled: true, busy: false);
    } catch (_) {
      state = state.copyWith(busy: false, message: 'Izin tidak bisa diminta saat ini. Coba lagi sebentar lagi ya.');
      return;
    }
    await syncNow();
  }

  Future<void> syncNow() async {
    if (state.busy || !state.enabled) return;
    state = state.copyWith(busy: true, clearMessage: true);
    try {
      final raw = await ref.read(healthSourceProvider).read(days: syncWindowDays);
      final chunks = chunkByDays(buildBatch(raw.steps, raw.sleep));
      if (chunks.isEmpty) {
        state = state.copyWith(busy: false, message: 'Belum ada data langkah atau tidur di Health Connect untuk 14 hari terakhir.');
        return;
      }
      final api = ref.read(apiProvider);
      var activity = 0, nights = 0;
      for (final chunk in chunks) {
        final r = await api.syncPassive(chunk);
        activity += r.activityDays;
        nights += r.sleepNights;
      }
      final now = DateTime.now();
      await _prefs.write(_lastSyncKey, now.toIso8601String());
      state = state.copyWith(busy: false, lastSync: now, activityDays: activity, sleepNights: nights);
      ref.invalidate(projectionProvider); // aktivitas dan tidur baru mengubah proyeksi
    } on ApiException catch (e) {
      state = state.copyWith(busy: false, message: e.message);
    } catch (_) {
      state = state.copyWith(busy: false, message: 'Data dari Health Connect belum bisa dibaca. Coba lagi sebentar lagi ya.');
    }
  }

  /// Dipanggil saat aplikasi dibuka: sinkron otomatis bila sudah dinyalakan dan terakhir lebih dari 6 jam lalu.
  Future<void> syncIfDue() async {
    try {
      if (!state.loaded) await load();
      final last = state.lastSync;
      if (state.enabled && (last == null || DateTime.now().difference(last) >= autoSyncEvery)) await syncNow();
    } catch (_) {
      // Sinkron otomatis bersifat tambahan: kegagalannya tidak boleh mengganggu pembukaan aplikasi.
    }
  }

  Future<void> disable() async {
    if (state.busy) return;
    state = state.copyWith(busy: true, clearMessage: true);
    try {
      await ref.read(apiProvider).deletePassive();
    } on ApiException catch (e) {
      state = state.copyWith(busy: false, message: '${e.message} Data belum dihapus, jadi sinkronisasi masih menyala.');
      return;
    }
    await _prefs.write(_enabledKey, null);
    await _prefs.write(_lastSyncKey, null);
    state = HealthSyncState(loaded: true, availability: state.availability, message: 'Sinkronisasi dimatikan dan datanya dihapus dari KIRA.');
    ref.invalidate(projectionProvider);
  }
}

final healthSyncProvider = NotifierProvider<HealthSyncController, HealthSyncState>(HealthSyncController.new);
