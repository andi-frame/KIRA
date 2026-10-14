import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_screen.dart';
import '../features/check/check_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/projection/projection_screen.dart';
import '../shared/app_shell.dart';
import 'providers.dart';

const _gatedPaths = {'/splash', '/login', '/onboarding'};

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(gateProvider, (_, __) => refresh.value++);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final location = state.matchedLocation;
      switch (ref.read(gateProvider)) {
        case Gate.loading:
          return location == '/splash' ? null : '/splash';
        case Gate.loggedOut:
          return location == '/login' ? null : '/login';
        case Gate.needsOnboarding:
          return location == '/onboarding' ? null : '/onboarding';
        case Gate.ready:
          return _gatedPaths.contains(location) ? '/chat' : null;
      }
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const _Splash()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/chat', builder: (_, __) => const ChatScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/projection', builder: (_, __) => const ProjectionScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/check', builder: (_, __) => const CheckScreen())]),
        ],
      ),
    ],
  );
});

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator.adaptive()));
}
