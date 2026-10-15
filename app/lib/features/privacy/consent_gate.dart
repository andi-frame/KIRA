import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import 'consent_text.dart';

/// Akun yang dibuat sebelum ada persetujuan, atau saat teks persetujuan berubah, diminta menyetujui sebelum lanjut.
Future<void> showConsentGate(BuildContext context) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _ConsentGateDialog(),
    );

class _ConsentGateDialog extends ConsumerStatefulWidget {
  const _ConsentGateDialog();

  @override
  ConsumerState<_ConsentGateDialog> createState() => _ConsentGateDialogState();
}

class _ConsentGateDialogState extends ConsumerState<_ConsentGateDialog> {
  bool _busy = false;
  String? _error;

  Future<void> _agree() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).giveConsent();
      ref.invalidate(profileProvider);
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: AlertDialog(
        key: const Key('consent_gate'),
        title: const Text('Persetujuan data kesehatan'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const ConsentBody(),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ]),
        ),
        actions: [
          TextButton(
            key: const Key('consent_decline'),
            onPressed: _busy
                ? null
                : () async {
                    Navigator.pop(context);
                    await ref.read(authProvider.notifier).logout();
                  },
            child: const Text('Keluar'),
          ),
          FilledButton(key: const Key('consent_agree'), onPressed: _busy ? null : _agree, child: const Text('Saya setuju')),
        ],
      ),
    );
  }
}
