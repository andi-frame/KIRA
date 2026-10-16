import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/outbox.dart';
import '../core/providers.dart';
import '../features/health/health_sync.dart';
import '../features/home/home_screen.dart';
import '../features/privacy/consent_gate.dart';
import '../features/reminders/reminders_controller.dart';

/// Kerangka dengan bilah navigasi bawah (4 tujuan, Material 3). Profil dibuka dari bilah atas.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> with WidgetsBindingObserver {
  bool _askedConsent = false;
  Timer? _retry;

  /// Kirim ulang yang tertunda karena tidak ada sinyal: saat dibuka, saat kembali ke aplikasi, dan tiap 30 detik
  /// selama masih ada yang menunggu.
  Future<void> _flushOutbox() async {
    final outbox = ref.read(outboxProvider.notifier);
    await outbox.load();
    await outbox.flush();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(dashboardProvider); // kondisi hari ini bisa berubah selama aplikasi tertutup
      unawaited(_flushOutbox());
      unawaited(ref.read(remindersProvider.notifier).reschedule());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retry?.cancel();
    super.dispose();
  }


  void _maybeAskConsent(bool? consented) {
    if (consented != false || _askedConsent) return;
    _askedConsent = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showConsentGate(context); // tetap terbuka sampai disetujui atau pengguna keluar
    });
  }

  @override
  void initState() {
    super.initState();
    _maybeAskConsent(ref.read(profileProvider).asData?.value.consented);
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(_flushOutbox);
    Future.microtask(() => ref.read(remindersProvider.notifier).load());
    _retry = Timer.periodic(const Duration(seconds: 30), (_) {
      if (ref.read(outboxProvider).isNotEmpty) unawaited(_flushOutbox());
    });
    // Bila pengguna sudah menyalakan sinkronisasi Health Connect, perbarui saat aplikasi dibuka (paling sering tiap 6 jam).
    Future.microtask(() => ref.read(healthSyncProvider.notifier).syncIfDue());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(profileProvider, (_, next) => _maybeAskConsent(next.asData?.value.consented));
    final shell = widget.shell;
    return Scaffold(
      body: shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Ngobrol',
          ),
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Beranda',
          ),
          NavigationDestination(
            icon: Icon(Icons.restaurant_menu_outlined),
            selectedIcon: Icon(Icons.restaurant_menu),
            label: 'Riwayat',
          ),
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(Icons.fact_check),
            label: 'Cek',
          ),
        ],
      ),
    );
  }
}

/// Tombol profil standar untuk bilah atas setiap tujuan.
class ProfileAction extends StatelessWidget {
  const ProfileAction({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Profil',
        icon: const Icon(Icons.account_circle_outlined),
        onPressed: () => context.push('/profile'),
      );
}
