import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../shared/account_models.dart';
import '../shared/engagement_models.dart';
import '../shared/family_models.dart';
import '../shared/insight_models.dart';
import '../shared/models.dart';

const String kApiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:8000');

/// Error ramah pengguna dari API atau jaringan.
class ApiException implements Exception {
  ApiException(this.message, {this.status});
  final String message;
  final int? status;
  bool get isUnauthorized => status == 401;

  /// Tidak ada jawaban dari server sama sekali (tanpa sinyal, atau waktu habis).
  bool get isNetwork => status == null;
  @override
  String toString() => message;
}

/// Kontrak API KIRA. Layar hanya bergantung pada antarmuka ini sehingga mudah diuji dengan fake.
abstract class KiraApi {
  Future<AuthTokens> register(String phone, String username, String pin, {required bool consent});
  Future<AuthTokens> login(String identifier, String pin);
  Future<void> logout(String refreshToken);
  Future<void> requestPinReset(String identifier);
  Future<void> confirmPinReset(String identifier, String code, String newPin);
  Future<AuthTokens> changePin(String currentPin, String newPin);
  Future<void> giveConsent();
  Future<Map<String, dynamic>> exportAccount();
  Future<void> deleteAccount(String pin);
  Future<List<AccessEntry>> getAccessLog();
  Future<ShareLinkData> createShareLink({required int days, required int validDays});
  Future<List<ShareLinkData>> listShareLinks();
  Future<void> revokeShareLink(String id);
  Future<String> setUsername(String username);
  Future<Profile> getProfile();
  Future<Profile> putProfile(Map<String, dynamic> fields);
  Future<ChatReply> sendMessage(String text, {String? idempotencyKey});
  Future<ChatReply> sendVoice(Uint8List audio, String filename);
  Future<ChatReply> sendPhoto(String kind, Uint8List image, String filename);
  Future<void> patchLog(String logId, List<Map<String, dynamic>> items);
  Future<Projection> getProjection();
  Future<WhatIfResult> whatIf(WhatIfChange change);
  Future<CheckRecommendation?> getCheck();
  Future<ResultOutcome> postResult(String kind, Map<String, num> value, {String source = 'self', String? idempotencyKey});
  Future<CheckRespondResult> respondCheck(String id, String action);
  Future<List<FrequentFood>> getFrequentFoods();
  Future<bool> hasLoggedToday();
  Future<BpProtocolView> getBpProtocol();
  Future<BpProtocolView> startBpProtocol();
  Future<BpProtocolView> addBpReading(int sys, int dia, String session);
  Future<BpProtocolView> finishBpProtocol();
  Future<void> cancelBpProtocol();
  Future<ProductInfo> getProduct(String barcode);
  Future<BarcodeLogResult> logBarcode(String barcode, {double? grams, double? servings});
  Future<void> postDiagnosis(String condition);
  Future<List<Faskes>> nearbyFaskes(double lat, double lng);
  Future<FamilyOverview> getFamily();
  Future<void> inviteFamily(String phone, FamilyPermissions permissions);
  Future<void> acceptFamily(String linkId);
  Future<void> endFamily(String linkId);
  Future<void> setFamilyPermissions(String linkId, FamilyPermissions permissions);
  Future<FamilyStatus> getFamilyStatus(String linkId);
  Future<DoctorSummary> getDoctorSummary(int days);
  Future<FoodGlucose> getFoodGlucose();
  Future<String> whatsappLinkCode();
  Future<WeeklyRecap?> getWeeklyRecap();
  Future<PassiveSyncResult> syncPassive(PassiveBatch batch);
  Future<int> deletePassive();
  Future<TrendsData> getTrends(int days);
  Future<Uint8List> getDoctorPdf(int days);
}

class DioKiraApi implements KiraApi {
  DioKiraApi({
    required String baseUrl,
    required String? Function() token,
    String? Function()? refreshToken,
    Future<void> Function(AuthTokens)? onTokens,
    void Function()? onUnauthorized,
    HttpClientAdapter? adapter, // untuk pengujian
  })  : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 60),
        )),
        _plain = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 30),
        )) {
    if (adapter != null) {
      _dio.httpClientAdapter = adapter;
      _plain.httpClientAdapter = adapter;
    }
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      final t = token();
      if (t != null && options.headers['Authorization'] == null) options.headers['Authorization'] = 'Bearer $t';
      handler.next(options);
    }, onError: (e, handler) async {
      final request = e.requestOptions;
      final isAuthCall = request.path.startsWith('/auth/');
      if (e.response?.statusCode == 401 && !isAuthCall && request.extra['retried'] != true) {
        // Token akses habis: tukar token penyegar sekali, lalu ulangi permintaan yang tadi gagal.
        final fresh = await _refresh(refreshToken?.call(), onTokens);
        if (fresh != null) {
          try {
            request.extra['retried'] = true;
            request.headers['Authorization'] = 'Bearer ${fresh.access}';
            return handler.resolve(await _dio.fetch<dynamic>(request));
          } on DioException catch (retryError) {
            return handler.next(retryError);
          }
        }
      }
      if (e.response?.statusCode == 401 && !isAuthCall && onUnauthorized != null) onUnauthorized();
      handler.next(e);
    }));
  }

  final Dio _dio;
  final Dio _plain; // tanpa pencegat, khusus untuk menukar token

  /// Satu penukaran pada satu waktu: permintaan lain yang gagal bersamaan menunggu hasil yang sama,
  /// sebab token penyegar berputar dan hanya boleh dipakai sekali.
  Future<AuthTokens?>? _inflight;

  Future<AuthTokens?> _refresh(String? refresh, Future<void> Function(AuthTokens)? onTokens) {
    if (refresh == null || onTokens == null) return Future.value(null);
    return _inflight ??= () async {
      try {
        final res = await _plain.post<dynamic>('/auth/refresh', data: {'refresh_token': refresh});
        final tokens = AuthTokens.fromJson(res.data as Map<String, dynamic>);
        await onTokens(tokens);
        return tokens;
      } on DioException {
        return null;
      } finally {
        _inflight = null;
      }
    }();
  }

  Future<T> _run<T>(Future<Response<dynamic>> Function() call, T Function(dynamic data) parse) async {
    try {
      final res = await call();
      return parse(res.data);
    } on DioException catch (e) {
      throw _toApiException(e);
    }
  }

  ApiException _toApiException(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    if (data is Map && data['detail'] is String) return ApiException(data['detail'] as String, status: status);
    if (data is Map && data['detail'] is List) {
      return ApiException('Isian belum sesuai. Coba periksa lagi ya.', status: status);
    }
    if (status == null) {
      return ApiException('Tidak bisa terhubung ke server. Cek koneksimu lalu coba lagi.');
    }
    return ApiException('Ada kendala di server. Coba lagi sebentar lagi ya.', status: status);
  }

  @override
  Future<AuthTokens> register(String phone, String username, String pin, {required bool consent}) => _run(
        () => _dio.post('/auth/register',
            data: {'phone': phone, 'username': username, 'pin': pin, 'consent': consent}),
        (d) => AuthTokens.fromJson(d as Map<String, dynamic>),
      );

  @override
  Future<AuthTokens> login(String identifier, String pin) => _run(
        () => _dio.post('/auth/login', data: {'identifier': identifier, 'pin': pin}),
        (d) => AuthTokens.fromJson(d as Map<String, dynamic>),
      );

  @override
  Future<void> logout(String refreshToken) =>
      _run(() => _dio.post('/auth/logout', data: {'refresh_token': refreshToken}), (_) {});

  @override
  Future<void> requestPinReset(String identifier) =>
      _run(() => _dio.post('/auth/pin-reset/request', data: {'identifier': identifier}), (_) {});

  @override
  Future<void> confirmPinReset(String identifier, String code, String newPin) => _run(
        () => _dio.post('/auth/pin-reset/confirm',
            data: {'identifier': identifier, 'code': code, 'new_pin': newPin}),
        (_) {},
      );

  @override
  Future<AuthTokens> changePin(String currentPin, String newPin) => _run(
        () => _dio.put('/auth/pin', data: {'current_pin': currentPin, 'new_pin': newPin}),
        (d) => AuthTokens.fromJson(d as Map<String, dynamic>),
      );

  @override
  Future<void> giveConsent() => _run(() => _dio.post('/account/consent'), (_) {});

  @override
  Future<Map<String, dynamic>> exportAccount() =>
      _run(() => _dio.get('/account/export'), (d) => d as Map<String, dynamic>);

  @override
  Future<void> deleteAccount(String pin) => _run(() => _dio.post('/account/delete', data: {'pin': pin}), (_) {});

  @override
  Future<List<AccessEntry>> getAccessLog() => _run(
        () => _dio.get('/account/access-log'),
        (d) => (d['entries'] as List).map((e) => AccessEntry.fromJson(e as Map<String, dynamic>)).toList(),
      );

  @override
  Future<ShareLinkData> createShareLink({required int days, required int validDays}) => _run(
        () => _dio.post('/summary/share', data: {'days': days, 'valid_days': validDays}),
        (d) => ShareLinkData.fromJson(d as Map<String, dynamic>),
      );

  @override
  Future<List<ShareLinkData>> listShareLinks() => _run(
        () => _dio.get('/summary/share'),
        (d) => (d['links'] as List).map((e) => ShareLinkData.fromJson(e as Map<String, dynamic>)).toList(),
      );

  @override
  Future<void> revokeShareLink(String id) => _run(() => _dio.delete('/summary/share/$id'), (_) {});

  @override
  Future<String> setUsername(String username) =>
      _run(() => _dio.put('/auth/username', data: {'username': username}), (d) => d['username'] as String);

  @override
  Future<Profile> getProfile() => _run(() => _dio.get('/profile'), (d) => Profile.fromJson(d as Map<String, dynamic>));

  @override
  Future<Profile> putProfile(Map<String, dynamic> fields) =>
      _run(() => _dio.put('/profile', data: fields), (d) => Profile.fromJson(d as Map<String, dynamic>));

  @override
  Future<ChatReply> sendMessage(String text, {String? idempotencyKey}) => _run(
        () => _dio.post('/chat/message', data: {'text': text}, options: _idempotent(idempotencyKey)),
        (d) => ChatReply.fromJson(d as Map<String, dynamic>),
      );

  /// Kunci unik per kiriman: bila jaringan putus setelah server mencatat, kiriman ulang tidak tercatat dua kali.
  Options? _idempotent(String? key) => key == null ? null : Options(headers: {'Idempotency-Key': key});

  @override
  Future<ChatReply> sendVoice(Uint8List audio, String filename) => _run(
        () => _dio.post('/chat/voice',
            data: FormData.fromMap({'audio': MultipartFile.fromBytes(audio, filename: filename)})),
        (d) => ChatReply.fromJson(d as Map<String, dynamic>),
      );

  @override
  Future<ChatReply> sendPhoto(String kind, Uint8List image, String filename) => _run(
        () => _dio.post('/chat/photo',
            queryParameters: {'kind': kind},
            data: FormData.fromMap({'image': MultipartFile.fromBytes(image, filename: filename)})),
        (d) => ChatReply.fromJson(d as Map<String, dynamic>),
      );

  @override
  Future<void> patchLog(String logId, List<Map<String, dynamic>> items) =>
      _run(() => _dio.patch('/logs/$logId', data: {'items': items}), (_) {});

  @override
  Future<Projection> getProjection() =>
      _run(() => _dio.get('/projection'), (d) => Projection.fromJson(d as Map<String, dynamic>));

  @override
  Future<WhatIfResult> whatIf(WhatIfChange change) => _run(
        () => _dio.post('/projection/whatif', data: change.toJson()),
        (d) => WhatIfResult.fromJson(d as Map<String, dynamic>),
      );

  @override
  Future<CheckRecommendation?> getCheck() => _run(
        () => _dio.get('/recommendations/check'),
        (d) => d == null || (d is String && d.isEmpty) ? null : CheckRecommendation.fromJson(d as Map<String, dynamic>),
      );

  @override
  Future<ResultOutcome> postResult(String kind, Map<String, num> value,
          {String source = 'self', String? idempotencyKey}) =>
      _run(
        () => _dio.post('/results',
            data: {'kind': kind, 'value': value, 'source': source}, options: _idempotent(idempotencyKey)),
        (d) => ResultOutcome.fromJson(d as Map<String, dynamic>),
      );

  @override
  Future<CheckRespondResult> respondCheck(String id, String action) => _run(
        () => _dio.post('/recommendations/$id/respond', data: {'action': action}),
        (d) => CheckRespondResult.fromJson(d as Map<String, dynamic>),
      );

  @override
  Future<BpProtocolView> getBpProtocol() =>
      _run(() => _dio.get('/bp-protocol'), (d) => BpProtocolView.fromJson(d as Map<String, dynamic>));

  @override
  Future<BpProtocolView> startBpProtocol() =>
      _run(() => _dio.post('/bp-protocol'), (d) => BpProtocolView.fromJson(d as Map<String, dynamic>));

  @override
  Future<BpProtocolView> addBpReading(int sys, int dia, String session) => _run(
        () => _dio.post('/bp-protocol/readings', data: {'sys': sys, 'dia': dia, 'session': session}),
        (d) => BpProtocolView.fromJson(d as Map<String, dynamic>),
      );

  @override
  Future<BpProtocolView> finishBpProtocol() =>
      _run(() => _dio.post('/bp-protocol/finish'), (d) => BpProtocolView.fromJson(d as Map<String, dynamic>));

  @override
  Future<void> cancelBpProtocol() => _run(() => _dio.delete('/bp-protocol'), (_) {});

  @override
  Future<bool> hasLoggedToday() => _run(() => _dio.get('/logs'), (d) => (d['logs'] as List).isNotEmpty);

  @override
  Future<List<FrequentFood>> getFrequentFoods() => _run(
        () => _dio.get('/logs/frequent'),
        (d) => (d['foods'] as List).map((e) => FrequentFood.fromJson(e as Map<String, dynamic>)).toList(),
      );

  @override
  Future<ProductInfo> getProduct(String barcode) =>
      _run(() => _dio.get('/products/$barcode'), (d) => ProductInfo.fromJson(d as Map<String, dynamic>));

  @override
  Future<BarcodeLogResult> logBarcode(String barcode, {double? grams, double? servings}) => _run(
        () => _dio.post('/logs/barcode', data: {
          'barcode': barcode,
          'grams': ?grams,
          'servings': ?servings,
        }),
        (d) => BarcodeLogResult.fromJson(d as Map<String, dynamic>),
      );

  @override
  Future<void> postDiagnosis(String condition) =>
      _run(() => _dio.post('/diagnoses', data: {'condition': condition}), (_) {});

  @override
  Future<List<Faskes>> nearbyFaskes(double lat, double lng) => _run(
        () => _dio.get('/faskes/nearby', queryParameters: {'lat': lat, 'lng': lng}),
        (d) => (d['faskes'] as List).map((e) => Faskes.fromJson(e as Map<String, dynamic>)).toList(),
      );

  @override
  Future<FamilyOverview> getFamily() =>
      _run(() => _dio.get('/family'), (d) => FamilyOverview.fromJson(d as Map<String, dynamic>));

  @override
  Future<void> inviteFamily(String phone, FamilyPermissions permissions) => _run(
        () => _dio.post('/family/invite', data: {'phone': phone, 'permissions': permissions.toJson()}),
        (_) {},
      );

  @override
  Future<void> acceptFamily(String linkId) => _run(() => _dio.post('/family/$linkId/accept'), (_) {});

  @override
  Future<void> endFamily(String linkId) => _run(() => _dio.delete('/family/$linkId'), (_) {});

  @override
  Future<void> setFamilyPermissions(String linkId, FamilyPermissions permissions) =>
      _run(() => _dio.patch('/family/$linkId/permissions', data: permissions.toJson()), (_) {});

  @override
  Future<FamilyStatus> getFamilyStatus(String linkId) =>
      _run(() => _dio.get('/family/$linkId/status'), (d) => FamilyStatus.fromJson(d as Map<String, dynamic>));

  @override
  Future<DoctorSummary> getDoctorSummary(int days) => _run(
        () => _dio.get('/summary/doctor', queryParameters: {'days': days}),
        (d) => DoctorSummary.fromJson(d as Map<String, dynamic>),
      );

  @override
  Future<FoodGlucose> getFoodGlucose() =>
      _run(() => _dio.get('/insights/food-glucose'), (d) => FoodGlucose.fromJson(d as Map<String, dynamic>));

  @override
  Future<String> whatsappLinkCode() => _run(() => _dio.post('/whatsapp/link-code'), (d) => d['code'] as String);

  @override
  Future<WeeklyRecap?> getWeeklyRecap() => _run(
        () => _dio.get('/summary/weekly'),
        (d) => (d as Map<String, dynamic>)['week'] == null ? null : WeeklyRecap.fromJson(d['week'] as Map<String, dynamic>),
      );

  @override
  Future<PassiveSyncResult> syncPassive(PassiveBatch batch) => _run(
        () => _dio.post('/sync/passive', data: batch.toJson()),
        (d) => PassiveSyncResult.fromJson(d as Map<String, dynamic>),
      );

  @override
  Future<int> deletePassive() => _run(() => _dio.delete('/sync/passive'), (d) => (d['deleted'] as num).toInt());

  @override
  Future<TrendsData> getTrends(int days) => _run(
        () => _dio.get('/insights/trends', queryParameters: {'days': days}),
        (d) => TrendsData.fromJson(d as Map<String, dynamic>),
      );

  @override
  Future<Uint8List> getDoctorPdf(int days) => _run(
        () => _dio.get('/summary/doctor.pdf',
            queryParameters: {'days': days}, options: Options(responseType: ResponseType.bytes)),
        (d) => Uint8List.fromList((d as List).cast<int>()),
      );
}
