import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:kira/core/api_client.dart';
import 'package:kira/core/providers.dart';
import 'package:kira/core/theme.dart';
import 'package:kira/features/chat/media.dart';
import 'package:kira/features/check/location.dart';
import 'package:kira/features/health/health_source.dart';
import 'package:kira/features/health/health_sync.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;
import 'package:kira/shared/family_models.dart';
import 'package:kira/shared/insight_models.dart';
import 'package:kira/shared/models.dart';

List<double> _curve(double p10) => [for (var t = 0; t <= 10; t++) 1 - _pow(1 - p10, t / 10)];
double _pow(double base, double exp) => base <= 0 ? 0 : (exp == 0 ? 1 : _exp(exp * _ln(base)));
double _ln(double x) => x <= 0 ? 0 : _lnImpl(x);
double _lnImpl(double x) {
  var n = 0.0, y = x;
  while (y > 1.5) {
    y /= 2.718281828459045;
    n += 1;
  }
  while (y < 0.5) {
    y *= 2.718281828459045;
    n -= 1;
  }
  final z = (y - 1) / (y + 1);
  var sum = 0.0, term = z;
  for (var k = 0; k < 40; k += 2) {
    sum += term / (k + 1);
    term *= z * z;
  }
  return n + 2 * sum;
}

double _exp(double x) {
  var sum = 1.0, term = 1.0;
  for (var k = 1; k < 40; k++) {
    term *= x / k;
    sum += term;
  }
  return sum;
}

Projection sampleProjection({
  bool needsProfile = false,
  int low = 9,
  int high = 18,
  String? mostImpactful = 'activity',
  double p10Low = 0.04,
  double p10High = 0.33,
  HypertensionRisk hypertension = const HypertensionRisk(status: 'needs_bp'),
}) =>
    Projection(
      scoreLow: low,
      scoreHigh: high,
      categoryLow: 'slightly_elevated',
      categoryHigh: 'high',
      p10Low: p10Low,
      p10High: p10High,
      curveLow: _curve(p10Low),
      curveHigh: _curve(p10High),
      needsProfile: needsProfile,
      mode: 'prevention',
      mostImpactful: mostImpactful,
      hypertension: hypertension,
    );

WhatIfResult sampleWhatIf({int afterLow = 9, int afterHigh = 16}) => WhatIfResult(
      beforeLow: 9,
      beforeHigh: 18,
      afterLow: afterLow,
      afterHigh: afterHigh,
      curveAfterLow: _curve(0.04),
      curveAfterHigh: _curve(0.17),
      sugarBefore: 40,
      sugarAfter: 20,
      mostImpactful: 'activity',
    );

/// API palsu: perilaku diatur lewat field; semua panggilan tercatat.
class FakeApi implements KiraApi {
  Profile profile = const Profile(birthDate: '1998-03-14', sex: 'male', heightCm: 170, weightKg: 78);
  Projection projection = sampleProjection();
  WhatIfResult Function(WhatIfChange)? onWhatIf;
  CheckRecommendation? recommendation;
  List<Faskes> faskes = const [
    Faskes(name: 'Puskesmas Coblong', kind: 'puskesmas', distanceKm: 0.4, address: 'Jl. Contoh No. 1'),
    Faskes(name: 'Posyandu Melati', kind: 'posyandu', distanceKm: 1.2),
  ];
  Future<ChatReply> Function(String text)? onMessage;
  Future<ChatReply> Function(String kind)? onPhoto;
  Future<ResultOutcome> Function(String kind, Map<String, num> value)? onResult;
  Object? loginError;
  Object? projectionError;
  Object? checkError;

  final List<String> messages = [];
  final List<WhatIfChange> whatIfRequests = [];
  final List<Map<String, dynamic>> profileUpdates = [];
  final List<String> diagnoses = [];
  final List<({String kind, Map<String, num> value})> results = [];
  final List<({String id, List<Map<String, dynamic>> items})> patches = [];
  int projectionCalls = 0;

  @override
  Future<String> register(String phone, String pin) async {
    if (loginError != null) throw loginError!;
    return 'token-baru';
  }

  @override
  Future<String> login(String phone, String pin) async {
    if (loginError != null) throw loginError!;
    return 'token';
  }

  @override
  Future<Profile> getProfile() async => profile;

  @override
  Future<Profile> putProfile(Map<String, dynamic> fields) async {
    profileUpdates.add(fields);
    profile = Profile(
      displayName: fields['display_name'] as String? ?? profile.displayName,
      birthDate: fields['birth_date'] as String? ?? profile.birthDate,
      sex: fields['sex'] as String? ?? profile.sex,
      heightCm: (fields['height_cm'] as num?)?.toDouble() ?? profile.heightCm,
      weightKg: (fields['weight_kg'] as num?)?.toDouble() ?? profile.weightKg,
      mode: profile.mode,
    );
    return profile;
  }

  @override
  Future<ChatReply> sendMessage(String text) {
    messages.add(text);
    return (onMessage ?? (t) async => const ChatReply(reply: 'Sip, sudah kucatat.'))(text);
  }

  @override
  Future<ChatReply> sendVoice(Uint8List audio, String filename) async =>
      const ChatReply(reply: 'Suara diterima.', transcript: 'tadi makan nasi padang');

  @override
  Future<ChatReply> sendPhoto(String kind, Uint8List image, String filename) =>
      (onPhoto ?? (k) async => const ChatReply(reply: 'Foto diterima.'))(kind);

  @override
  Future<void> patchLog(String logId, List<Map<String, dynamic>> items) async {
    patches.add((id: logId, items: items));
  }

  @override
  Future<Projection> getProjection() async {
    projectionCalls++;
    if (projectionError != null) throw projectionError!;
    return projection;
  }

  @override
  Future<WhatIfResult> whatIf(WhatIfChange change) async {
    whatIfRequests.add(change);
    return (onWhatIf ?? (_) => sampleWhatIf())(change);
  }

  @override
  Future<CheckRecommendation?> getCheck() async {
    if (checkError != null) throw checkError!;
    return recommendation;
  }

  @override
  Future<ResultOutcome> postResult(String kind, Map<String, num> value, {String source = 'self'}) {
    results.add((kind: kind, value: value));
    return (onResult ??
        (k, v) async => ResultOutcome(saved: true, projection: sampleProjection(low: 13, high: 17)))(kind, value);
  }

  @override
  Future<void> postDiagnosis(String condition) async => diagnoses.add(condition);

  @override
  Future<List<Faskes>> nearbyFaskes(double lat, double lng) async => faskes;

  FamilyOverview family = const FamilyOverview();
  final List<({String phone, FamilyPermissions permissions})> invites = [];
  final List<String> accepted = [];
  final List<String> ended = [];
  final List<({String id, FamilyPermissions permissions})> permissionChanges = [];
  Map<String, FamilyStatus> statuses = {};
  Object? familyError;

  @override
  Future<FamilyOverview> getFamily() async {
    if (familyError != null) throw familyError!;
    return family;
  }

  @override
  Future<void> inviteFamily(String phone, FamilyPermissions permissions) async {
    if (familyError != null) throw familyError!;
    invites.add((phone: phone, permissions: permissions));
  }

  @override
  Future<void> acceptFamily(String linkId) async => accepted.add(linkId);

  @override
  Future<void> endFamily(String linkId) async => ended.add(linkId);

  @override
  Future<void> setFamilyPermissions(String linkId, FamilyPermissions permissions) async =>
      permissionChanges.add((id: linkId, permissions: permissions));

  @override
  Future<FamilyStatus> getFamilyStatus(String linkId) async => statuses[linkId]!;

  DoctorSummary Function(int days)? onDoctorSummary;
  final List<int> doctorSummaryDays = [];
  FoodGlucose foodGlucose = const FoodGlucose();
  String linkCode = 'KIRA 4821';

  @override
  Future<DoctorSummary> getDoctorSummary(int days) async {
    doctorSummaryDays.add(days);
    return (onDoctorSummary ??
        (d) => DoctorSummary(text: 'Ringkasan KIRA $d hari untuk Raka. Bukan diagnosis.', periodDays: d, daysLogged: 12))(days);
  }

  @override
  Future<FoodGlucose> getFoodGlucose() async => foodGlucose;

  @override
  Future<String> whatsappLinkCode() async => linkCode;

  WeeklyRecap? weeklyRecap;
  Object? weeklyError;
  final List<PassiveBatch> passiveBatches = [];
  Object? passiveError;

  @override
  Future<WeeklyRecap?> getWeeklyRecap() async {
    if (weeklyError != null) throw weeklyError!;
    return weeklyRecap;
  }

  int deletedPassive = 0;

  @override
  Future<int> deletePassive() async {
    deletedPassive++;
    return 3;
  }

  @override
  Future<PassiveSyncResult> syncPassive(PassiveBatch batch) async {
    if (passiveError != null) throw passiveError!;
    passiveBatches.add(batch);
    return PassiveSyncResult(activityDays: batch.steps.length, sleepNights: batch.sleep.length);
  }
}

/// Membungkus widget dengan tema, lokal, dan provider palsu.
Widget testApp(Widget child,
    {FakeApi? api, bool dark = false, List<Override> overrides = const [], String? token, PrefsStore? prefs}) {
  return ProviderScope(
    overrides: [
      apiProvider.overrideWithValue(api ?? FakeApi()),
      tokenStoreProvider.overrideWithValue(MemoryTokenStore(token)),
      prefsStoreProvider.overrideWithValue(prefs ?? MemoryPrefsStore()),
      ...overrides,
    ],
    child: MaterialApp(
      theme: kiraLightTheme,
      darkTheme: kiraDarkTheme,
      themeMode: dark ? ThemeMode.dark : ThemeMode.light,
      home: child,
    ),
  );
}

class FakePhotoPicker implements PhotoPicker {
  FakePhotoPicker(this.bytes);
  final Uint8List bytes;

  @override
  Future<PickedMedia?> pick(ImageSource source) async => PickedMedia(bytes, 'foto.jpg');
}

Override photoPickerOverride(Uint8List bytes) => photoPickerProvider.overrideWithValue(FakePhotoPicker(bytes));


class FakeLocation implements LocationService {
  FakeLocation([this.position]);
  final ({double lat, double lng})? position;

  @override
  Future<({double lat, double lng})?> current() async => position;
}

Override locationOverride([({double lat, double lng})? position]) =>
    locationProvider.overrideWithValue(FakeLocation(position));

class FakeHealthSource implements HealthSource {
  FakeHealthSource({
    this.status = HealthAvailability.available,
    this.grant = true,
    List<RawStep>? steps,
    List<RawSleep>? sleep,
    this.readError,
  })  : steps = steps ?? [RawStep(sourceId: 'ponsel', start: _t(1, 7), end: _t(1, 7).add(const Duration(minutes: 10)), count: 1100)],
        sleep = sleep ?? [RawSleep(sourceId: 'ponsel', start: _t(1, 0), end: _t(1, 6))];

  static DateTime _t(int daysAgo, int hour) {
    final n = DateTime.now().subtract(Duration(days: daysAgo));
    return DateTime(n.year, n.month, n.day, hour);
  }

  HealthAvailability status;
  bool grant;
  List<RawStep> steps;
  List<RawSleep> sleep;
  Object? readError;
  int accessRequests = 0, reads = 0;

  @override
  Future<HealthAvailability> availability() async => status;

  @override
  Future<bool> requestAccess() async {
    accessRequests++;
    return grant;
  }

  @override
  Future<({List<RawStep> steps, List<RawSleep> sleep})> read({int days = 14}) async {
    reads++;
    if (readError != null) throw readError!;
    return (steps: steps, sleep: sleep);
  }
}

Override healthOverride(FakeHealthSource source) => healthSourceProvider.overrideWithValue(source);
