import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kira/core/api_client.dart';
import 'package:kira/shared/account_models.dart';

/// Server palsu: token akses "lama" ditolak 401, penukaran token menghasilkan "baru".
class _Server implements HttpClientAdapter {
  _Server({this.refreshWorks = true});
  final bool refreshWorks;
  final List<String> calls = [];
  final List<String?> authHeaders = [];
  int refreshCalls = 0;

  ResponseBody _json(int status, Object body) => ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    calls.add('${options.method} ${options.path}');
    authHeaders.add(options.headers['Authorization'] as String?);
    if (options.path == '/auth/refresh') {
      refreshCalls++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      return refreshWorks
          ? _json(200, {'access_token': 'baru', 'refresh_token': 'penyegar-2', 'token_type': 'bearer'})
          : _json(401, {'detail': 'Sesi berakhir. Silakan masuk lagi.'});
    }
    if (options.path == '/auth/login') return _json(401, {'detail': 'Nama pengguna, nomor, atau PIN salah'});
    if (options.headers['Authorization'] == 'Bearer baru') return _json(200, {'display_name': 'Raka', 'mode': 'prevention'});
    return _json(401, {'detail': 'Token tidak valid atau kedaluwarsa'});
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late List<AuthTokens> stored;
  late int unauthorized;

  DioKiraApi build(_Server server, {String? refresh = 'penyegar-1'}) {
    stored = [];
    unauthorized = 0;
    var access = 'lama';
    return DioKiraApi(
      baseUrl: 'http://test',
      token: () => access,
      refreshToken: () => refresh,
      onTokens: (t) async {
        access = t.access;
        stored.add(t);
      },
      onUnauthorized: () => unauthorized++,
      adapter: server,
    );
  }

  test('401 → token ditukar sekali, permintaan diulang dengan token baru, pengguna tidak terganggu', () async {
    final server = _Server();
    final profile = await build(server).getProfile();
    expect(profile.displayName, 'Raka');
    expect(server.calls, ['GET /profile', 'POST /auth/refresh', 'GET /profile']);
    expect(server.authHeaders.last, 'Bearer baru');
    expect(stored.single.refresh, 'penyegar-2');
    expect(unauthorized, 0);
  });

  test('beberapa permintaan gagal bersamaan memakai satu penukaran (token penyegar berputar)', () async {
    final server = _Server();
    final api = build(server);
    final results = await Future.wait([api.getProfile(), api.getProfile(), api.getProfile()]);
    expect(results.every((p) => p.displayName == 'Raka'), isTrue);
    expect(server.refreshCalls, 1);
  });

  test('penukaran gagal → keluar (onUnauthorized) dan pesan server diteruskan', () async {
    final server = _Server(refreshWorks: false);
    final api = build(server);
    await expectLater(api.getProfile(), throwsA(isA<ApiException>().having((e) => e.isUnauthorized, 'status 401', true)));
    expect(unauthorized, 1);
    expect(server.refreshCalls, 1);
  });

  test('tanpa token penyegar langsung keluar, tanpa memanggil /auth/refresh', () async {
    final server = _Server();
    final api = build(server, refresh: null);
    await expectLater(api.getProfile(), throwsA(isA<ApiException>()));
    expect(server.refreshCalls, 0);
    expect(unauthorized, 1);
  });

  test('401 dari /auth/login (PIN salah) bukan sesi habis: tidak menukar token dan tidak keluar', () async {
    final server = _Server();
    final api = build(server);
    await expectLater(api.login('raka', '000000'), throwsA(isA<ApiException>().having((e) => e.message, 'pesan', contains('PIN salah'))));
    expect(server.refreshCalls, 0);
    expect(unauthorized, 0);
  });
}
