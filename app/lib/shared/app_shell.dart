import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Kerangka dengan bilah navigasi bawah (3 tujuan, Material 3). Profil dibuka dari bilah atas.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
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
            icon: Icon(Icons.show_chart),
            selectedIcon: Icon(Icons.auto_graph),
            label: '10 Tahun',
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
