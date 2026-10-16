import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_screen.dart';
import '../features/barcode/barcode_screen.dart';
import '../features/bp/bp_protocol_screen.dart';
import '../features/auth/reset_pin_screen.dart';
import '../features/privacy/privacy_screen.dart';
import '../features/check/check_screen.dart';
import '../features/chat/chat_screen.dart';
import '../features/doctor/doctor_summary_screen.dart';
import '../features/family/family_screen.dart';
import '../features/goals/goals_screen.dart';
import '../features/health/health_screen.dart';
import '../features/history/history_screen.dart';
import '../features/trends/trends_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/plan/plan_preferences_screen.dart';
import '../features/plan/plan_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/jeda/jeda_screen.dart';
import '../features/reminders/reminders_screen.dart';
import '../features/home/home_screen.dart';
import '../shared/app_shell.dart';
import 'providers.dart';

const _gatedPaths = {'/splash', '/login', '/onboarding', '/reset-pin'};

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
          return location == '/login' || location == '/reset-pin' ? null : '/login';
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
      GoRoute(path: '/reminders', builder: (_, _) => const RemindersScreen()),
      GoRoute(path: '/jeda', builder: (_, _) => const JedaScreen()),
      GoRoute(path: '/goals', builder: (_, _) => const GoalsScreen()),
      GoRoute(path: '/bp-protocol', builder: (_, _) => const BpProtocolScreen()),
      GoRoute(path: '/barcode', builder: (_, _) => const BarcodeScreen()),
      GoRoute(path: '/reset-pin', builder: (_, _) => const ResetPinScreen()),
      GoRoute(path: '/privacy', builder: (_, _) => const PrivacyScreen()),
      GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
      GoRoute(path: '/family', builder: (_, _) => const FamilyScreen()),
      GoRoute(path: '/doctor', builder: (_, _) => const DoctorSummaryScreen()),
      GoRoute(path: '/health', builder: (_, _) => const HealthScreen()),
      GoRoute(path: '/trends', builder: (_, _) => const TrendsScreen()),
      GoRoute(path: '/plan', builder: (_, _) => const PlanScreen()),
      GoRoute(path: '/plan/preferences', builder: (_, _) => const PlanPreferencesScreen()),
      GoRoute(path: '/projection', redirect: (_, _) => '/home'), // tab lama "10 Tahun" kini bagian Beranda
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/chat', builder: (_, _) => const ChatScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/home', builder: (_, _) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/history', builder: (_, _) => const HistoryScreen())]),
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
