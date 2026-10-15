import 'package:flutter/material.dart';

import '../../core/theme.dart';
import '../../shared/labels.dart';
import '../../shared/models.dart';

/// Satu baris jejak: apa yang dihitung KIRA dan dari mana angkanya.
class TraceEntry {
  const TraceEntry(this.title, this.lines);
  final String title;
  final List<String> lines;
}

String _n(Object? v, {int digits = 0}) {
  if (v is! num) return '?';
  final fixed = v.toStringAsFixed(digits);
  return digits > 0 && fixed.endsWith('.${'0' * digits}') ? v.round().toString() : fixed;
}

Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : const {};

/// Menerjemahkan pemanggilan tool menjadi kalimat yang bisa dibaca pengguna. Tool yang belum dikenal tetap tampil
/// dengan nama aslinya, supaya jejak tidak pernah menyembunyikan apa yang dipanggil.
TraceEntry describeToolCall(ToolCall call) {
  final r = call.resultMap;
  switch (call.name) {
    case 'cari_gizi':
      if (r['found'] != true) {
        return TraceEntry('Cek gizi: ${call.args['makanan'] ?? '-'}', [
          'Tidak ditemukan di database gizi, jadi KIRA tidak mengarang angkanya.',
        ]);
      }
      final source = (r['sumber'] ?? '').toString();
      return TraceEntry('Cek gizi: ${r['name'] ?? call.args['makanan']}', [
        '${_n(r['portion_g'])} g: gula ${_n(r['sugar_g'], digits: 1)} g, natrium ${_n(r['sodium_mg'])} mg, '
            'lemak ${_n(r['fat_g'], digits: 1)} g, ${_n(r['kcal'])} kkal',
        if (source.isNotEmpty) 'Sumber: $source',
        if (source.toLowerCase().contains('estimasi')) 'Bagian yang berstatus estimasi adalah perkiraan KIRA.',
      ]);
    case 'sisa_target_harian':
      final rem = _map(r['remaining']), lim = _map(r['limits']);
      return TraceEntry('Sisa target hari ini', [
        'Gula ${_n(rem['sugar_g'], digits: 1)} g dari batas ${_n(lim['sugar_g'])} g',
        'Natrium ${_n(rem['sodium_mg'])} mg dari batas ${_n(lim['sodium_mg'])} mg',
        'Lemak ${_n(rem['fat_g'], digits: 1)} g dari batas ${_n(lim['fat_g'])} g',
      ]);
    case 'hitung_risiko':
      return TraceEntry('Hitung risiko diabetes (FINDRISC)', [
        'Skor ${_n(r['score_low'])}-${_n(r['score_high'])}, '
            'kategori ${categoryLabel('${r['category_low']}')} sampai ${categoryLabel('${r['category_high']}')}',
      ]);
    case 'simulasi_whatif':
      final before = _map(r['before']), after = _map(r['after']);
      return TraceEntry('Simulasi kebiasaan', [
        'Skor ${_n(before['low'])}-${_n(before['high'])} menjadi ${_n(after['low'])}-${_n(after['high'])}',
      ]);
    case 'cari_faskes':
      final list = r['faskes'];
      return TraceEntry('Cari fasilitas kesehatan', [if (list is List) '${list.length} fasilitas ditemukan di sekitarmu']);
    default:
      return TraceEntry(call.name, ['Dipanggil dengan ${call.args}']);
  }
}

/// "Lihat cara KIRA menghitung": angka di balasan datang dari tool deterministik, bukan tebakan model.
class ToolTrace extends StatefulWidget {
  const ToolTrace({super.key, required this.calls});
  final List<ToolCall> calls;

  @override
  State<ToolTrace> createState() => _ToolTraceState();
}

class _ToolTraceState extends State<ToolTrace> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          key: const Key('trace_toggle'),
          onPressed: () => setState(() => _open = !_open),
          icon: Icon(_open ? Icons.expand_less : Icons.calculate_outlined, size: 18),
          label: Text(_open ? 'Sembunyikan perhitungan' : 'Lihat cara KIRA menghitung'),
        ),
        if (_open)
          Container(
            key: const Key('trace_panel'),
            width: double.infinity,
            padding: const EdgeInsets.all(KiraSpace.md),
            decoration: BoxDecoration(
              color: scheme.surfaceContainer,
              borderRadius: BorderRadius.circular(KiraRadius.field),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Angka berikut dihitung fungsi tetap, bukan ditebak model.', style: context.text.bodySmall),
                for (final call in widget.calls) ..._entry(context, describeToolCall(call)),
              ],
            ),
          ),
      ],
    );
  }

  List<Widget> _entry(BuildContext context, TraceEntry e) => [
        const SizedBox(height: KiraSpace.sm),
        Text(e.title, style: context.text.titleSmall),
        for (final line in e.lines) Text(line, style: context.text.bodyMedium),
      ];
}
