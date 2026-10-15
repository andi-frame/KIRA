import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../shared/account_models.dart';
import '../shared/models.dart';
import 'api_client.dart';

/// Penyimpanan token login. Hanya token yang disimpan di perangkat; semua data lain ada di server.
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String? token);
  Future<String?> readRefresh();
  Future<void> writeRefresh(String? token);
}

class SecureTokenStore implements TokenStore {
  static const _key = 'kira_token';
  static const _refreshKey = 'kira_refresh_token';
  final _storage = const FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String? token) =>
      token == null ? _storage.delete(key: _key) : _storage.write(key: _key, value: token);

  @override
  Future<String?> readRefresh() => _storage.read(key: _refreshKey);

  @override
  Future<void> writeRefresh(String? token) =>
      token == null ? _storage.delete(key: _refreshKey) : _storage.write(key: _refreshKey, value: token);
}

class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this._token, this._refresh]);
  String? _token, _refresh;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String? token) async => _token = token;

  @override
  Future<String?> readRefresh() async => _refresh;

  @override
  Future<void> writeRefresh(String? token) async => _refresh = token;
}

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

/// Pengaturan kecil di perangkat (bukan data kesehatan), mis. apakah sinkronisasi Health Connect dinyalakan.
abstract class PrefsStore {
  Future<String?> read(String key);
  Future<void> write(String key, String? value);
}

class SecurePrefsStore implements PrefsStore {
  final _storage = const FlutterSecureStorage();

  @override
  Future<String?> read(String key) => _storage.read(key: 'pref_$key');

  @override
  Future<void> write(String key, String? value) =>
      value == null ? _storage.delete(key: 'pref_$key') : _storage.write(key: 'pref_$key', value: value);
}

class MemoryPrefsStore implements PrefsStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String? value) async =>
      value == null ? _values.remove(key) : _values[key] = value;
}

final prefsStoreProvider = Provider<PrefsStore>((ref) => SecurePrefsStore());

/// `token` adalah penanda sesi: tetap sama selama sesi berjalan, sehingga layar yang memantaunya tidak memuat
/// ulang saat token akses diperbarui diam-diam. `access` adalah token akses terkini yang dikirim ke server.
class AuthState {
  const AuthState({this.loaded = false, this.token, this.access, this.refreshToken});
  final bool loaded;
  final String? token;
  final String? access;
  final String? refreshToken;

  String? get currentAccess => access ?? token;
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    Future.microtask(_load);
    return const AuthState();
  }

  Future<void> _load() async {
    final store = ref.read(tokenStoreProvider);
    final token = await store.read();
    final refresh = await store.readRefresh();
    if (!ref.mounted) return;
    state = AuthState(loaded: true, token: token, refreshToken: refresh);
  }

  Future<void> setTokens(AuthTokens tokens) async {
    final store = ref.read(tokenStoreProvider);
    await store.write(tokens.access);
    await store.writeRefresh(tokens.refresh);
    state = AuthState(loaded: true, token: tokens.access, refreshToken: tokens.refresh);
  }

  /// Hasil penukaran token disimpan tanpa mengganti penanda sesi.
  Future<void> storeRefreshed(AuthTokens tokens) async {
    final store = ref.read(tokenStoreProvider);
    await store.write(tokens.access);
    await store.writeRefresh(tokens.refresh);
    state = AuthState(loaded: true, token: state.token, access: tokens.access, refreshToken: tokens.refresh);
  }

  Future<void> logout() async {
    final store = ref.read(tokenStoreProvider);
    final refresh = state.refreshToken ?? await store.readRefresh();
    final access = state.currentAccess;
    await store.write(null);
    await store.writeRefresh(null);
    state = const AuthState(loaded: true);
    if (refresh != null && access != null) {
      // Akhiri sesi di server; gagal (offline) tidak boleh menahan pengguna keluar.
      try {
        await ref.read(apiProvider).logout(refresh);
      } catch (_) {}
    }
  }
}

final authProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

final apiProvider = Provider<KiraApi>(
  (ref) => DioKiraApi(
    baseUrl: kApiUrl,
    token: () => ref.read(authProvider).currentAccess,
    refreshToken: () => ref.read(authProvider).refreshToken,
    onTokens: (tokens) => ref.read(authProvider.notifier).storeRefreshed(tokens),
    onUnauthorized: () => ref.read(authProvider.notifier).logout(),
  ),
);

final profileProvider = FutureProvider<Profile>((ref) async {
  final token = ref.watch(authProvider.select((s) => s.token));
  if (token == null) throw StateError('belum login');
  return ref.read(apiProvider).getProfile();
});

enum Gate { loading, loggedOut, needsOnboarding, ready }

final gateProvider = Provider<Gate>((ref) {
  final loaded = ref.watch(authProvider.select((s) => s.loaded));
  final token = ref.watch(authProvider.select((s) => s.token));
  if (!loaded) return Gate.loading;
  if (token == null) return Gate.loggedOut;
  return ref.watch(profileProvider).when(
        data: (p) => p.isComplete ? Gate.ready : Gate.needsOnboarding,
        loading: () => Gate.loading,
        error: (_, _) => Gate.ready,
      );
});
