import 'dart:typed_data';

import 'package:dio/dio.dart';

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
  @override
  String toString() => message;
}

/// Kontrak API KIRA. Layar hanya bergantung pada antarmuka ini sehingga mudah diuji dengan fake.
abstract class KiraApi {
  Future<String> register(String phone, String pin);
  Future<String> login(String phone, String pin);
  Future<Profile> getProfile();
  Future<Profile> putProfile(Map<String, dynamic> fields);
  Future<ChatReply> sendMessage(String text);
  Future<ChatReply> sendVoice(Uint8List audio, String filename);
  Future<ChatReply> sendPhoto(String kind, Uint8List image, String filename);
  Future<void> patchLog(String logId, List<Map<String, dynamic>> items);
  Future<Projection> getProjection();
  Future<WhatIfResult> whatIf(WhatIfChange change);
  Future<CheckRecommendation?> getCheck();
  Future<ResultOutcome> postResult(String kind, Map<String, num> value, {String source = 'self'});
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
}

class DioKiraApi implements KiraApi {
  DioKiraApi({required String baseUrl, required String? Function() token, void Function()? onUnauthorized})
      : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 60),
        )) {
    _dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      final t = token();
      if (t != null) options.headers['Authorization'] = 'Bearer $t';
      handler.next(options);
    }, onError: (e, handler) {
      if (e.response?.statusCode == 401 && onUnauthorized != null) onUnauthorized();
      handler.next(e);
    }));
  }

  final Dio _dio;

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
  Future<String> register(String phone, String pin) =>
      _run(() => _dio.post('/auth/register', data: {'phone': phone, 'pin': pin}), (d) => d['access_token'] as String);

  @override
  Future<String> login(String phone, String pin) =>
      _run(() => _dio.post('/auth/login', data: {'phone': phone, 'pin': pin}), (d) => d['access_token'] as String);

  @override
  Future<Profile> getProfile() => _run(() => _dio.get('/profile'), (d) => Profile.fromJson(d as Map<String, dynamic>));

  @override
  Future<Profile> putProfile(Map<String, dynamic> fields) =>
      _run(() => _dio.put('/profile', data: fields), (d) => Profile.fromJson(d as Map<String, dynamic>));

  @override
  Future<ChatReply> sendMessage(String text) =>
      _run(() => _dio.post('/chat/message', data: {'text': text}), (d) => ChatReply.fromJson(d as Map<String, dynamic>));

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
  Future<ResultOutcome> postResult(String kind, Map<String, num> value, {String source = 'self'}) => _run(
        () => _dio.post('/results', data: {'kind': kind, 'value': value, 'source': source}),
        (d) => ResultOutcome.fromJson(d as Map<String, dynamic>),
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
}
