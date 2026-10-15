import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_screen.dart';
import '../features/check/check_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/doctor/doctor_summary_screen.dart';
import '../features/family/family_screen.dart';
import '../features/health/health_screen.dart';
import '../features/trends/trends_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/projection/projection_screen.dart';
import '../shared/app_shell.dart';
import 'providers.dart';

const _gatedPaths = {'/splash', '/login', '/onboarding'};

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ValueNotifier<int>(0);
  ref.listen(gateProvider, (_, _) => refresh.value++);
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
      GoRoute(path: '/splash', builder: (_, _) => const _Splash()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
      GoRoute(path: '/family', builder: (_, _) => const FamilyScreen()),
      GoRoute(path: '/doctor', builder: (_, _) => const DoctorSummaryScreen()),
      GoRoute(path: '/health', builder: (_, _) => const HealthScreen()),
      GoRoute(path: '/trends', builder: (_, _) => const TrendsScreen()),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/chat', builder: (_, _) => const ChatScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/projection', builder: (_, _) => const ProjectionScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/check', builder: (_, _) => const CheckScreen())]),
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
