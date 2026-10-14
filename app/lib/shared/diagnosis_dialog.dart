import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api_client.dart';
import '../core/providers.dart';
import '../features/check/check_providers.dart';
import '../features/projection/projection_providers.dart';

/// Menandai diagnosis yang sudah dipastikan dokter; mengalihkan KIRA ke mode pengelolaan.
Future<void> showDiagnosisDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _DiagnosisDialog());

class _DiagnosisDialog extends ConsumerStatefulWidget {
  const _DiagnosisDialog();

  @override
  ConsumerState<_DiagnosisDialog> createState() => _DiagnosisDialogState();
}

class _DiagnosisDialogState extends ConsumerState<_DiagnosisDialog> {
  String? _selected;
  bool _busy = false;
  String? _error;

  static const _options = {
    'prediabetes': 'Prediabetes',
    'diabetes': 'Diabetes',
    'hypertension': 'Hipertensi',
  };

  Future<void> _confirm() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(apiProvider).postDiagnosis(_selected!);
      ref
        ..invalidate(profileProvider)
        ..invalidate(projectionProvider)
        ..invalidate(checkProvider);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mode pengelolaan aktif. KIRA akan menemani langkah berikutnya bersama dokternya.')),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Sudah didiagnosis dokter?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Tandai hanya kalau dokter sudah memastikannya. KIRA tidak mendiagnosis.'),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: _selected,
            onChanged: (v) => setState(() => _selected = v),
            child: Column(children: [
              for (final entry in _options.entries)
                RadioListTile<String>(
                  key: Key('dx_${entry.key}'),
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.value),
                  value: entry.key,
                ),
            ]),
          ),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ],
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(
          key: const Key('dx_confirm'),
          onPressed: _selected == null || _busy ? null : _confirm,
          child: const Text('Tandai'),
        ),
      ],
    );
  }
}
