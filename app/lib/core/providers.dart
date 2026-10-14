import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../shared/models.dart';
import 'api_client.dart';

/// Penyimpanan token login. Hanya token yang disimpan di perangkat; semua data lain ada di server.
abstract class TokenStore {
  Future<String?> read();
  Future<void> write(String? token);
}

class SecureTokenStore implements TokenStore {
  static const _key = 'kira_token';
  final _storage = const FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String? token) =>
      token == null ? _storage.delete(key: _key) : _storage.write(key: _key, value: token);
}

class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([this._token]);
  String? _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String? token) async => _token = token;
}

final tokenStoreProvider = Provider<TokenStore>((ref) => SecureTokenStore());

class AuthState {
  const AuthState({this.loaded = false, this.token});
  final bool loaded;
  final String? token;
}

class AuthController extends Notifier<AuthState> {
  @override
  AuthState build() {
    Future.microtask(_load);
    return const AuthState();
  }

  Future<void> _load() async {
    final token = await ref.read(tokenStoreProvider).read();
    state = AuthState(loaded: true, token: token);
  }

  Future<void> setToken(String token) async {
    await ref.read(tokenStoreProvider).write(token);
    state = AuthState(loaded: true, token: token);
  }

  Future<void> logout() async {
    await ref.read(tokenStoreProvider).write(null);
    state = const AuthState(loaded: true);
  }
}

final authProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);

final apiProvider = Provider<KiraApi>(
  (ref) => DioKiraApi(
    baseUrl: kApiUrl,
    token: () => ref.read(authProvider).token,
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
  final auth = ref.watch(authProvider);
  if (!auth.loaded) return Gate.loading;
  if (auth.token == null) return Gate.loggedOut;
  return ref.watch(profileProvider).when(
        data: (p) => p.isComplete ? Gate.ready : Gate.needsOnboarding,
        loading: () => Gate.loading,
        error: (_, _) => Gate.ready,
      );
});
