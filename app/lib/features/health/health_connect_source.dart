import 'package:health/health.dart';

import 'health_source.dart';

/// Health Connect (Android) lewat paket `health`. Hanya membaca langkah dan sesi tidur; tidak pernah menulis.
class HealthConnectSource implements HealthSource {
  static const _types = [HealthDataType.STEPS, HealthDataType.SLEEP_SESSION];
  static const _access = [HealthDataAccess.READ, HealthDataAccess.READ];
  final Health _health = Health();
  bool _configured = false;

  Future<void> _configure() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  @override
  Future<HealthAvailability> availability() async {
    try {
      await _configure();
      final status = await _health.getHealthConnectSdkStatus();
      return switch (status) {
        HealthConnectSdkStatus.sdkAvailable => HealthAvailability.available,
        HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired => HealthAvailability.notInstalled,
        _ => HealthAvailability.unsupported,
      };
    } catch (_) {
      return HealthAvailability.unsupported;
    }
  }

  @override
  Future<bool> requestAccess() async {
    await _configure();
    return _health.requestAuthorization(_types, permissions: _access);
  }

  @override
  Future<({List<RawStep> steps, List<RawSleep> sleep})> read({int days = 14}) async {
    await _configure();
    final end = DateTime.now();
    final start = DateTime(end.year, end.month, end.day).subtract(Duration(days: days - 1));
    final points = await _health.getHealthDataFromTypes(types: _types, startTime: start, endTime: end);
    final steps = <RawStep>[], sleep = <RawSleep>[];
    for (final p in points) {
      if (p.type == HealthDataType.STEPS && p.value is NumericHealthValue) {
        steps.add(RawStep(
          sourceId: p.sourceId,
          start: p.dateFrom,
          end: p.dateTo,
          count: (p.value as NumericHealthValue).numericValue.round(),
        ));
      } else if (p.type == HealthDataType.SLEEP_SESSION) {
        sleep.add(RawSleep(sourceId: p.sourceId, start: p.dateFrom, end: p.dateTo));
      }
    }
    return (steps: steps, sleep: sleep);
  }
}
