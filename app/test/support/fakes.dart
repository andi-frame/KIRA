import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:kira/core/api_client.dart';
import 'package:kira/core/providers.dart';
import 'package:kira/core/theme.dart';
import 'package:kira/features/chat/media.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;
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

Projection sampleProjection({bool needsProfile = false, int low = 9, int high = 18, String? mostImpactful = 'activity'}) =>
    Projection(
      scoreLow: low,
      scoreHigh: high,
      categoryLow: 'slightly_elevated',
      categoryHigh: 'high',
      p10Low: 0.04,
      p10High: 0.33,
      curveLow: _curve(0.04),
      curveHigh: _curve(0.33),
      needsProfile: needsProfile,
      mode: 'prevention',
      mostImpactful: mostImpactful,
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
    return projection;
  }

  @override
  Future<WhatIfResult> whatIf(WhatIfChange change) async {
    whatIfRequests.add(change);
    return (onWhatIf ?? (_) => sampleWhatIf())(change);
  }

  @override
  Future<CheckRecommendation?> getCheck() async => recommendation;

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
}

/// Membungkus widget dengan tema, lokal, dan provider palsu.
Widget testApp(Widget child, {FakeApi? api, bool dark = false, List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: [
      apiProvider.overrideWithValue(api ?? FakeApi()),
      tokenStoreProvider.overrideWithValue(MemoryTokenStore()),
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
