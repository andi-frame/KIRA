import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../shared/engagement_models.dart';
import '../../shared/widgets.dart';
import '../chat/frequent_foods.dart';
import '../projection/projection_providers.dart';
import 'barcode_scanner.dart';

String _n(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1).replaceAll('.', ',');

/// Pindai kode batang kemasan, lihat gizinya, lalu catat sesuai porsi yang dimakan. Alternatif cepat dari foto label.
class BarcodeScreen extends ConsumerStatefulWidget {
  const BarcodeScreen({super.key});

  @override
  ConsumerState<BarcodeScreen> createState() => _BarcodeScreenState();
}

class _BarcodeScreenState extends ConsumerState<BarcodeScreen> {
  final _manual = TextEditingController();
  final _grams = TextEditingController();
  ProductInfo? _product;
  BarcodeLogResult? _logged;
  String? _error;
  String? _lastCode;
  bool _busy = false;
  bool _byServing = false;
  double _servings = 1;

  @override
  void dispose() {
    _manual.dispose();
    _grams.dispose();
    super.dispose();
  }

  Future<void> _lookup(String code) async {
    final clean = code.trim();
    if (_busy || clean == _lastCode) return; // kamera memanggil berulang untuk kode yang sama
    if (!RegExp(r'^\d{8,14}$').hasMatch(clean)) {
      setState(() => _error = 'Nomor kode batang berisi 8 sampai 14 angka.');
      return;
    }
    _lastCode = clean;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final product = await ref.read(apiProvider).getProduct(clean);
      if (!mounted) return;
      setState(() {
        _product = product;
        _byServing = product.servingG != null;
        _grams.text = (product.servingG ?? 100).round().toString();
        _servings = 1;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
      _lastCode = null; // izinkan mencoba kode yang sama lagi setelah gagal
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _log() async {
    final product = _product!;
    double? grams;
    if (!_byServing) {
      grams = double.tryParse(_grams.text.trim().replaceAll(',', '.'));
      if (grams == null || grams <= 0 || grams > 5000) {
        setState(() => _error = 'Isi gram antara 1 dan 5000.');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(apiProvider)
          .logBarcode(product.barcode, grams: grams, servings: _byServing ? _servings : null);
      ref
        ..invalidate(projectionProvider)
        ..invalidate(frequentFoodsProvider);
      if (mounted) setState(() => _logged = result);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _reset() => setState(() {
        _product = null;
        _logged = null;
        _error = null;
        _lastCode = null;
        _manual.clear();
      });

  @override
  Widget build(BuildContext context) {
    final product = _product;
    return Scaffold(
      appBar: AppBar(title: const Text('Pindai kode batang')),
      body: ListView(
        padding: const EdgeInsets.all(KiraSpace.lg),
        children: [
          if (_logged != null)
            _Logged(result: _logged!, onAnother: _reset)
          else if (product == null) ...[
            SizedBox(
              height: 240,
              child: ref.read(barcodeScannerProvider).view(context, _lookup),
            ),
            const SizedBox(height: KiraSpace.lg),
            Text('Atau ketik nomor di bawah kode batang', style: context.text.titleSmall),
            const SizedBox(height: KiraSpace.sm),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: TextField(
                  key: const Key('barcode_manual'),
                  controller: _manual,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(14)],
                  onSubmitted: _lookup,
                  decoration: const InputDecoration(labelText: 'Nomor kode batang', hintText: '8 sampai 14 angka'),
                ),
              ),
              const SizedBox(width: KiraSpace.sm),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: FilledButton(
                  key: const Key('barcode_lookup'),
                  style: FilledButton.styleFrom(minimumSize: const Size(72, 56)),
                  onPressed: _busy ? null : () => _lookup(_manual.text),
                  child: _busy
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                      : const Text('Cari'),
                ),
              ),
            ]),
          ] else
            _ProductCard(
              product: product,
              grams: _grams,
              byServing: _byServing,
              servings: _servings,
              busy: _busy,
              onMode: (v) => setState(() => _byServing = v),
              onServings: (v) => setState(() => _servings = v),
              onLog: _log,
              onBack: _reset,
            ),
          if (_error != null) ...[
            const SizedBox(height: KiraSpace.md),
            Semantics(
              liveRegion: true,
              child: SoftNote(key: const Key('barcode_error'), icon: Icons.info_outline, text: _error!),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.grams,
    required this.byServing,
    required this.servings,
    required this.busy,
    required this.onMode,
    required this.onServings,
    required this.onLog,
    required this.onBack,
  });

  final ProductInfo product;
  final TextEditingController grams;
  final bool byServing, busy;
  final double servings;
  final ValueChanged<bool> onMode;
  final ValueChanged<double> onServings;
  final VoidCallback onLog, onBack;

  String _fact(String label, double? v, String unit) => '$label ${v == null ? 'tidak tertera' : '${_n(v)} $unit'}';

  @override
  Widget build(BuildContext context) {
    final p = product;
    final base = p.isDrink ? '100 ml' : '100 g';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Card(
        key: const Key('product_card'),
        child: Padding(
          padding: const EdgeInsets.all(KiraSpace.lg),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(p.name, style: context.text.titleLarge),
            if (p.brand != null) Text(p.brand!, style: context.text.bodyMedium?.copyWith(color: context.scheme.onSurfaceVariant)),
            const SizedBox(height: KiraSpace.md),
            Text('Per $base', style: context.text.labelLarge),
            const SizedBox(height: KiraSpace.xs),
            Text(_fact('Gula', p.sugarG, 'g'), style: context.text.bodyLarge),
            Text(_fact('Natrium', p.sodiumMg, 'mg'), style: context.text.bodyLarge),
            Text(_fact('Lemak', p.fatG, 'g'), style: context.text.bodyLarge),
            Text(_fact('Energi', p.kcal, 'kkal'), style: context.text.bodyLarge),
            const SizedBox(height: KiraSpace.sm),
            Text('Sumber: ${p.source}. Data disumbangkan pengguna dan bisa keliru.', style: context.text.bodySmall),
          ]),
        ),
      ),
      const SizedBox(height: KiraSpace.lg),
      if (!p.complete)
        const SoftNote(
          key: Key('product_incomplete'),
          icon: Icons.fact_check_outlined,
          title: 'Data gizinya belum lengkap',
          text: 'Gula atau energi produk ini belum ada di basis data. Foto tabel nilai gizi di kemasannya, KIRA bacakan.',
        )
      else ...[
        if (p.servingG != null)
          SegmentedButton<bool>(
            key: const Key('amount_mode'),
            segments: [
              ButtonSegment(value: true, label: Text('Sajian (${_n(p.servingG!)} g)')),
              const ButtonSegment(value: false, label: Text('Gram')),
            ],
            selected: {byServing},
            onSelectionChanged: (s) => onMode(s.first),
          ),
        const SizedBox(height: KiraSpace.md),
        if (byServing)
          Row(children: [
            IconButton.outlined(
              key: const Key('servings_minus'),
              tooltip: 'Kurangi setengah sajian',
              onPressed: servings > 0.5 ? () => onServings(servings - 0.5) : null,
              icon: const Icon(Icons.remove),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: KiraSpace.lg),
              child: Text('${_n(servings)} sajian', key: const Key('servings_value'), style: context.text.titleMedium),
            ),
            IconButton.outlined(
              key: const Key('servings_plus'),
              tooltip: 'Tambah setengah sajian',
              onPressed: servings < 10 ? () => onServings(servings + 0.5) : null,
              icon: const Icon(Icons.add),
            ),
          ])
        else
          TextField(
            key: const Key('barcode_grams'),
            controller: grams,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: p.isDrink ? 'Berapa ml?' : 'Berapa gram?', suffixText: p.isDrink ? 'ml' : 'g'),
          ),
        const SizedBox(height: KiraSpace.lg),
        FilledButton.icon(
          key: const Key('barcode_log'),
          icon: busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.add_task),
          label: const Text('Catat'),
          onPressed: busy ? null : onLog,
        ),
      ],
      TextButton(key: const Key('barcode_back'), onPressed: onBack, child: const Text('Pindai produk lain')),
    ]);
  }
}

class _Logged extends StatelessWidget {
  const _Logged({required this.result, required this.onAnother});
  final BarcodeLogResult result;
  final VoidCallback onAnother;

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (result.portionG != null) '${_n(result.portionG!)} g',
      if (result.sugarG != null) 'gula ${_n(result.sugarG!)} g',
      if (result.sodiumMg != null) 'natrium ${_n(result.sodiumMg!)} mg',
      if (result.kcal != null) '${_n(result.kcal!)} kkal',
    ].join(' · ');
    return Card(
      key: const Key('barcode_logged'),
      child: Padding(
        padding: const EdgeInsets.all(KiraSpace.xl),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.check_circle_outline, size: 36, color: context.kira.improve),
          const SizedBox(height: KiraSpace.md),
          Text('Tercatat: ${result.name}', style: context.text.titleLarge),
          if (parts.isNotEmpty) ...[
            const SizedBox(height: KiraSpace.xs),
            Text(parts, style: context.text.bodyLarge),
          ],
          const SizedBox(height: KiraSpace.lg),
          Wrap(spacing: KiraSpace.sm, children: [
            FilledButton(key: const Key('barcode_done'), onPressed: () => Navigator.of(context).maybePop(), child: const Text('Selesai')),
            OutlinedButton(key: const Key('barcode_another'), onPressed: onAnother, child: const Text('Pindai lagi')),
          ]),
        ]),
      ),
    );
  }
}
