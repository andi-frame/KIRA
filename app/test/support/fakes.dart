import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:kira/core/api_client.dart';
import 'package:kira/core/link_opener.dart';
import 'package:kira/core/share_service.dart';
import 'package:kira/core/providers.dart';
import 'package:kira/core/theme.dart';
import 'package:kira/features/barcode/barcode_scanner.dart';
import 'package:kira/features/chat/media.dart';
import 'package:kira/features/check/location.dart';
import 'package:kira/features/health/health_source.dart';
import 'package:kira/features/reminders/notification_service.dart';
import 'package:kira/features/reminders/reminder_plan.dart';
import 'package:kira/features/health/health_sync.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;
import 'package:kira/shared/account_models.dart';
import 'package:kira/shared/clinical_extras_models.dart';
import 'package:kira/shared/engagement_models.dart';
import 'package:kira/shared/family_models.dart';
import 'package:kira/shared/goal_models.dart';
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
    Faskes(name: 'Puskesmas Coblong', kind: 'puskesmas', distanceKm: 0.4, address: 'Jl. Contoh No. 1', lat: -6.893, lng: 107.613),
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
  final List<({double? scale, String? group})> patchScales = [];
  MealLog? patchResult;
  Object? patchError;
  final List<String> searches = [];
  List<FoodSuggestion> foodSuggestions = const [];
  int projectionCalls = 0;

  final List<({String phone, String username, String pin, bool consent})> registrations = [];
  final List<({String identifier, String pin})> logins = [];
  final List<String> usernameChanges = [];
  Object? usernameError;

  @override
  Future<AuthTokens> register(String phone, String username, String pin, {required bool consent}) async {
    registrations.add((phone: phone, username: username, pin: pin, consent: consent));
    if (loginError != null) throw loginError!;
    return const AuthTokens('token-baru', 'refresh-baru');
  }

  @override
  Future<AuthTokens> login(String identifier, String pin) async {
    logins.add((identifier: identifier, pin: pin));
    if (loginError != null) throw loginError!;
    return const AuthTokens('token', 'refresh');
  }

  final List<String> loggedOutRefresh = [];
  final List<String> pinResetRequests = [];
  final List<({String identifier, String code, String newPin})> pinResets = [];
  final List<({String current, String next})> pinChanges = [];
  final List<String> deletedAccounts = [];
  int consents = 0, exports = 0;
  Object? pinResetError, pinChangeError, deleteError, exportError, consentError;
  Map<String, dynamic> exportData = {'format': 1, 'logs': <dynamic>[]};
  List<AccessEntry> accessLog = const [];
  List<ShareLinkData> shareLinks = [];
  final List<({int days, int validDays})> createdLinks = [];
  final List<String> revokedLinks = [];
  Object? shareLinkError;

  @override
  Future<void> logout(String refreshToken) async => loggedOutRefresh.add(refreshToken);

  @override
  Future<void> requestPinReset(String identifier) async {
    if (pinResetError != null) throw pinResetError!;
    pinResetRequests.add(identifier);
  }

  @override
  Future<void> confirmPinReset(String identifier, String code, String newPin) async {
    if (pinResetError != null) throw pinResetError!;
    pinResets.add((identifier: identifier, code: code, newPin: newPin));
  }

  @override
  Future<AuthTokens> changePin(String currentPin, String newPin) async {
    if (pinChangeError != null) throw pinChangeError!;
    pinChanges.add((current: currentPin, next: newPin));
    return const AuthTokens('token-pin-baru', 'refresh-pin-baru');
  }

  @override
  Future<void> giveConsent() async {
    if (consentError != null) throw consentError!;
    consents++;
    profile = Profile(
      displayName: profile.displayName,
      username: profile.username,
      birthDate: profile.birthDate,
      sex: profile.sex,
      heightCm: profile.heightCm,
      weightKg: profile.weightKg,
      mode: profile.mode,
    );
  }

  @override
  Future<Map<String, dynamic>> exportAccount() async {
    if (exportError != null) throw exportError!;
    exports++;
    return exportData;
  }

  @override
  Future<void> deleteAccount(String pin) async {
    if (deleteError != null) throw deleteError!;
    deletedAccounts.add(pin);
  }

  @override
  Future<List<AccessEntry>> getAccessLog() async => accessLog;

  @override
  Future<ShareLinkData> createShareLink({required int days, required int validDays}) async {
    if (shareLinkError != null) throw shareLinkError!;
    createdLinks.add((days: days, validDays: validDays));
    final link = ShareLinkData(
      id: 'link-${createdLinks.length}',
      days: days,
      expiresAt: DateTime.now().add(Duration(days: validDays)),
      url: 'https://api.kira.example/s/token-rahasia-${createdLinks.length}',
    );
    shareLinks = [ShareLinkData(id: link.id, days: days, expiresAt: link.expiresAt), ...shareLinks];
    return link;
  }

  @override
  Future<List<ShareLinkData>> listShareLinks() async => shareLinks;

  @override
  Future<void> revokeShareLink(String id) async {
    revokedLinks.add(id);
    shareLinks = [
      for (final l in shareLinks)
        if (l.id != id) l,
    ];
  }

  @override
  Future<String> setUsername(String username) async {
    if (usernameError != null) throw usernameError!;
    usernameChanges.add(username);
    profile = Profile(
      displayName: profile.displayName,
      username: username,
      birthDate: profile.birthDate,
      sex: profile.sex,
      heightCm: profile.heightCm,
      weightKg: profile.weightKg,
      mode: profile.mode,
    );
    return username;
  }

  @override
  Future<Profile> getProfile() async => profile;

  @override
  Future<Profile> putProfile(Map<String, dynamic> fields) async {
    profileUpdates.add(fields);
    profile = Profile(
      displayName: fields['display_name'] as String? ?? profile.displayName,
      username: profile.username,
      birthDate: fields['birth_date'] as String? ?? profile.birthDate,
      sex: fields['sex'] as String? ?? profile.sex,
      heightCm: (fields['height_cm'] as num?)?.toDouble() ?? profile.heightCm,
      weightKg: (fields['weight_kg'] as num?)?.toDouble() ?? profile.weightKg,
      mode: profile.mode,
    );
    return profile;
  }

  final List<String?> messageKeys = [];
  Object? networkError; // bila diisi, kiriman teks dan hasil gagal seolah tanpa sinyal

  @override
  Future<ChatReply> sendMessage(String text, {String? idempotencyKey}) {
    if (networkError != null) throw networkError!;
    messages.add(text);
    messageKeys.add(idempotencyKey);
    return (onMessage ?? (t) async => const ChatReply(reply: 'Sip, sudah kucatat.'))(text);
  }

  @override
  Future<ChatReply> sendVoice(Uint8List audio, String filename) async =>
      const ChatReply(reply: 'Suara diterima.', transcript: 'tadi makan nasi padang');

  @override
  Future<ChatReply> sendPhoto(String kind, Uint8List image, String filename) =>
      (onPhoto ?? (k) async => const ChatReply(reply: 'Foto diterima.'))(kind);

  @override
  Future<MealLog> patchLog(String logId, {List<Map<String, dynamic>>? items, double? scale, String? group}) async {
    patches.add((id: logId, items: items ?? const []));
    patchScales.add((scale: scale, group: group));
    if (patchError != null) throw patchError!;
    return patchResult ?? MealLog(id: logId, corrected: true);
  }

  @override
  Future<List<FoodSuggestion>> searchFoods(String query) async {
    searches.add(query);
    return foodSuggestions;
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

  final List<String?> resultKeys = [];

  @override
  Future<ResultOutcome> postResult(String kind, Map<String, num> value,
      {String source = 'self', String? idempotencyKey}) {
    if (networkError != null) throw networkError!;
    results.add((kind: kind, value: value));
    resultKeys.add(idempotencyKey);
    return (onResult ??
        (k, v) async => ResultOutcome(saved: true, projection: sampleProjection(low: 13, high: 17)))(kind, value);
  }

  final List<({String id, String action})> checkResponses = [];
  CheckRespondResult Function(String id, String action)? onRespondCheck;
  List<FrequentFood> frequentFoods = const [];
  Object? productError;
  ProductInfo? product;
  final List<String> productLookups = [];
  final List<({String barcode, double? grams, double? servings})> barcodeLogs = [];
  Object? barcodeLogError;

  @override
  Future<CheckRespondResult> respondCheck(String id, String action) async {
    checkResponses.add((id: id, action: action));
    return (onRespondCheck ??
        (i, a) => CheckRespondResult(
            status: a == 'done' ? 'done' : (a == 'dismiss' ? 'dismissed' : 'open'),
            resultNeeded: a == 'done',
            testKind: 'fasting_glucose'))(id, action);
  }

  bool loggedToday = false;
  GoalsData goalsData = const GoalsData(kinds: sampleGoalKinds, daysLeft: 3);
  final List<({String kind, double target})> createdGoals = [];
  final List<({String id, double target})> updatedGoals = [];
  final List<String> deletedGoals = [];
  Object? goalError;

  @override
  Future<GoalsData> getGoals() async => goalsData;

  @override
  Future<void> createGoal(String kind, double target) async {
    if (goalError != null) throw goalError!;
    createdGoals.add((kind: kind, target: target));
    final spec = goalsData.kinds.firstWhere((k) => k.kind == kind);
    goalsData = GoalsData(
      kinds: goalsData.kinds,
      daysLeft: goalsData.daysLeft,
      goals: [
        ...goalsData.goals,
        sampleGoal(kind: kind, label: spec.label, unit: spec.unit, target: target, isMax: spec.isMax),
      ],
    );
  }

  @override
  Future<void> updateGoal(String id, double target) async {
    updatedGoals.add((id: id, target: target));
  }

  @override
  Future<void> deleteGoal(String id) async {
    deletedGoals.add(id);
    goalsData = GoalsData(kinds: goalsData.kinds, daysLeft: goalsData.daysLeft, goals: [
      for (final g in goalsData.goals)
        if (g.id != id) g,
    ]);
  }
  RiskHistory riskHistory = const RiskHistory(boundaries: [7, 12, 15, 21]);
  SleepPatterns patterns = const SleepPatterns();
  List<SavedScenario> scenarios = [];
  final List<({String name, WhatIfChange change})> savedScenarios = [];
  final List<String> deletedScenarios = [];
  Object? scenarioError;

  @override
  Future<RiskHistory> getRiskHistory(int days) async => riskHistory;

  @override
  Future<SleepPatterns> getPatterns(int days) async => patterns;

  @override
  Future<List<SavedScenario>> listScenarios() async => scenarios;

  @override
  Future<SavedScenario> saveScenario(String name, WhatIfChange change) async {
    if (scenarioError != null) throw scenarioError!;
    savedScenarios.add((name: name, change: change));
    final s = SavedScenario(
      id: 'sc-${savedScenarios.length}',
      name: name,
      params: change.toJson(),
      savedBefore: const ScoreSpan(9, 18),
      savedAfter: const ScoreSpan(9, 16),
      nowBefore: const ScoreSpan(9, 18),
      nowAfter: const ScoreSpan(9, 16),
    );
    scenarios = [s, ...scenarios];
    return s;
  }

  @override
  Future<void> deleteScenario(String id) async {
    deletedScenarios.add(id);
    scenarios = [
      for (final s in scenarios)
        if (s.id != id) s,
    ];
  }
  BpProtocolView bpView = const BpProtocolView();
  Object? bpError;
  final List<({int sys, int dia, String session})> bpReadings = [];
  int bpStarts = 0, bpFinishes = 0, bpCancels = 0;
  BpProtocolView Function(int sys, int dia, String session)? onBpReading;

  @override
  Future<BpProtocolView> getBpProtocol() async {
    if (bpError != null) throw bpError!;
    return bpView;
  }

  @override
  Future<BpProtocolView> startBpProtocol() async {
    if (bpError != null) throw bpError!;
    bpStarts++;
    return bpView = BpProtocolView(protocol: sampleBpState());
  }

  @override
  Future<BpProtocolView> addBpReading(int sys, int dia, String session) async {
    if (bpError != null) throw bpError!;
    bpReadings.add((sys: sys, dia: dia, session: session));
    return bpView = (onBpReading ?? (a, b, c) => bpView)(sys, dia, session);
  }

  @override
  Future<BpProtocolView> finishBpProtocol() async {
    if (bpError != null) throw bpError!;
    bpFinishes++;
    return bpView;
  }

  @override
  Future<void> cancelBpProtocol() async {
    bpCancels++;
    bpView = const BpProtocolView();
  }

  @override
  Future<bool> hasLoggedToday() async => loggedToday;

  @override
  Future<List<FrequentFood>> getFrequentFoods() async => frequentFoods;

  @override
  Future<ProductInfo> getProduct(String barcode) async {
    productLookups.add(barcode);
    if (productError != null) throw productError!;
    return product!;
  }

  @override
  Future<BarcodeLogResult> logBarcode(String barcode, {double? grams, double? servings}) async {
    if (barcodeLogError != null) throw barcodeLogError!;
    barcodeLogs.add((barcode: barcode, grams: grams, servings: servings));
    return BarcodeLogResult(logId: 'log-1', name: product?.name ?? 'Produk', portionG: grams, sugarG: 7);
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
  TrendsData trends = const TrendsData();
  Object? trendsError;
  final List<int> trendsDays = [];
  final List<int> pdfDays = [];
  Object? pdfError;

  @override
  Future<TrendsData> getTrends(int days) async {
    trendsDays.add(days);
    if (trendsError != null) throw trendsError!;
    return trends;
  }

  @override
  Future<Uint8List> getDoctorPdf(int days) async {
    pdfDays.add(days);
    if (pdfError != null) throw pdfError!;
    return Uint8List.fromList([0x25, 0x50, 0x44, 0x46]); // %PDF
  }

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

/// Sama seperti [testApp] tetapi dengan router, untuk layar yang berpindah halaman atau memakai AppShell.
Widget testAppRouter(GoRouter router,
    {FakeApi? api, List<Override> overrides = const [], String? token, PrefsStore? prefs}) {
  return ProviderScope(
    overrides: [
      apiProvider.overrideWithValue(api ?? FakeApi()),
      tokenStoreProvider.overrideWithValue(MemoryTokenStore(token ?? 'token')),
      prefsStoreProvider.overrideWithValue(prefs ?? MemoryPrefsStore()),
      ...overrides,
    ],
    child: MaterialApp.router(theme: kiraLightTheme, darkTheme: kiraDarkTheme, routerConfig: router),
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


class FakeShare implements ShareService {
  final List<({int bytes, String filename, String? message})> shared = [];
  final List<({String filename, String mime, String content})> files = [];
  final List<String> texts = [];
  Object? error;

  @override
  Future<void> sharePdf(Uint8List bytes, String filename, {String? message}) async {
    if (error != null) throw error!;
    shared.add((bytes: bytes.length, filename: filename, message: message));
  }

  @override
  Future<void> shareFile(Uint8List bytes, String filename, String mimeType, {String? subject, String? message}) async {
    if (error != null) throw error!;
    files.add((filename: filename, mime: mimeType, content: String.fromCharCodes(bytes)));
  }

  @override
  Future<void> shareText(String text, {String? subject}) async {
    if (error != null) throw error!;
    texts.add(text);
  }
}

Override shareOverride(FakeShare share) => shareServiceProvider.overrideWithValue(share);

DailyPoint day(int offset, {bool logged = true, double? sugar, double? sleep, double? active}) => DailyPoint(
      date: DateTime(2026, 10, 1).add(Duration(days: offset)).toIso8601String().substring(0, 10),
      logged: logged,
      sugarG: logged ? (sugar ?? 40) : null,
      sleepHours: logged ? sleep : null,
      activeMinutes: logged ? (active ?? 0) : null,
    );

TrendsData sampleTrends({bool withClinical = true, List<TriageFlag>? triage}) => TrendsData(
      periodDays: 30,
      clinical: withClinical
          ? {
              'blood_pressure': const ClinicalSeries(
                points: [
                  ClinicalPoint(date: '2026-09-20', source: 'self', sys: 132, dia: 86, band: 'prehypertension'),
                  ClinicalPoint(date: '2026-10-12', source: 'lab', sys: 146, dia: 94, band: 'hypertension'),
                ],
                trend: 'naik',
                references: [RefLine('Hipertensi (sistolik)', 140), RefLine('Hipertensi (diastolik)', 90)],
              ),
              'fasting_glucose': const ClinicalSeries(
                points: [
                  ClinicalPoint(date: '2026-09-15', source: 'lab', value: 104, band: 'prediabetes'),
                  ClinicalPoint(date: '2026-10-13', source: 'lab', value: 128, band: 'diabetes_range'),
                ],
                trend: 'naik',
                references: [RefLine('Prediabetes mulai', 100), RefLine('Rentang diabetes mulai', 126)],
              ),
            }
          : const {},
      daily: [
        day(0, sugar: 38, sleep: 5, active: 0),
        day(1, logged: false),
        day(2, sugar: 72, sleep: 6.5, active: 35),
      ],
      triage: triage ??
          const [
            TriageFlag(level: 'perhatian', kind: 'blood_pressure', text: 'Tekanan darah terakhir 146/94 mmHg berada di rentang hipertensi. Satu pembacaan bukan diagnosis.'),
            TriageFlag(level: 'pantau', kind: 'findrisc', text: 'Skrining FINDRISC berada di kategori tinggi pada batas atas rentang.'),
          ],
    );


/// Pemindai palsu: tombol "pindai" menyerahkan kode yang sudah ditentukan, seolah kamera membacanya.
class FakeScanner implements BarcodeScanner {
  FakeScanner(this.code);
  final String code;

  @override
  Widget view(BuildContext context, void Function(String code) onCode) =>
      Center(child: ElevatedButton(key: const Key('fake_scan'), onPressed: () => onCode(code), child: const Text('pindai')));
}

Override scannerOverride(String code) => barcodeScannerProvider.overrideWithValue(FakeScanner(code));

ProductInfo sampleProduct({bool complete = true, double? servingG = 85, bool drink = false}) => ProductInfo(
      barcode: '089686010947',
      name: 'Indomie Mi Goreng Original',
      brand: 'Indofood',
      servingG: servingG,
      isDrink: drink,
      complete: complete,
      source: 'Open Food Facts (ODbL)',
      sugarG: complete ? 7.06 : null,
      sodiumMg: 397.6,
      fatG: 18.8,
      kcal: complete ? 470.6 : null,
    );


/// Notifikasi palsu: mencatat jadwal terakhir yang diterapkan.
class FakeNotifications implements NotificationService {
  FakeNotifications({this.grant = true});
  bool grant;
  int permissionRequests = 0, cancels = 0;
  List<PlannedReminder> scheduled = [];

  @override
  Future<bool> ensurePermission() async {
    permissionRequests++;
    return grant;
  }

  @override
  Future<void> apply(List<PlannedReminder> reminders) async => scheduled = reminders;

  @override
  Future<void> cancelAll() async {
    cancels++;
    scheduled = [];
  }
}

Override notificationsOverride(FakeNotifications n) => notificationServiceProvider.overrideWithValue(n);


BpProtocolState sampleBpState({
  int dayIndex = 1,
  int morning = 0,
  int evening = 0,
  bool canFinish = false,
  bool over = false,
  String status = 'active',
  BpSummary? summary,
}) =>
    BpProtocolState(
      id: 'p1',
      status: status,
      dayIndex: dayIndex,
      days: [
        for (var i = 0; i < 7; i++)
          BpDay(
            date: DateTime(2026, 10, 12).add(Duration(days: i)),
            morning: i == 0 ? morning : 0,
            evening: i == 0 ? evening : 0,
            discarded: i == 0 && (morning + evening) > 0,
            isToday: i == dayIndex - 1,
          ),
      ],
      summary: summary ??
          const BpSummary(
            valid: false, readingsUsed: 0, daysUsed: 0,
            missing: 'Belum cukup untuk dihitung: butuh 3 hari lagi dan 12 bacaan lagi (hari pertama dibuang; minimal 3 hari dan 12 bacaan).',
          ),
      canFinish: canFinish,
      over: over,
    );


class FakeLinks implements LinkOpener {
  FakeLinks({this.canOpen = true});
  final bool canOpen;
  final List<Uri> opened = [];

  @override
  Future<bool> open(Uri uri) async {
    opened.add(uri);
    return canOpen;
  }
}

Override linksOverride(FakeLinks links) => linkOpenerProvider.overrideWithValue(links);


const sampleGoalKinds = [
  GoalKind(kind: 'active_minutes_week', label: 'Bergerak minggu ini', unit: 'menit', isMax: false, defaultTarget: 150, min: 30, max: 600),
  GoalKind(kind: 'sweet_drinks_week', label: 'Minuman manis minggu ini', unit: 'gelas', isMax: true, defaultTarget: 7, min: 0, max: 28),
  GoalKind(kind: 'sleep_nights', label: 'Malam tidur 7 jam atau lebih', unit: 'malam', isMax: false, defaultTarget: 5, min: 1, max: 7),
];

Goal sampleGoal({
  String kind = 'active_minutes_week',
  String label = 'Bergerak minggu ini',
  String unit = 'menit',
  double current = 70,
  double target = 150,
  bool isMax = false,
  List<WeekResult> history = const [],
  int metWeeks = 0,
  int weeksWithData = 0,
}) {
  final met = isMax ? current <= target : current >= target;
  return Goal(
    id: 'g-$kind',
    kind: kind,
    label: label,
    unit: unit,
    current: current,
    target: target,
    isMax: isMax,
    met: met,
    fraction: target <= 0 ? 1 : (current / target).clamp(0, 1).toDouble(),
    remaining: met ? 0 : (isMax ? 0 : target - current),
    history: history,
    metWeeks: metWeeks,
    weeksWithData: weeksWithData,
  );
}
