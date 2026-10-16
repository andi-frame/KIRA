import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../shared/record_models.dart';
import '../../shared/widgets.dart';
import 'records_providers.dart';

const _kindIcons = {
  'diagnosis': Icons.assignment_outlined,
  'lab': Icons.science_outlined,
  'medication': Icons.medication_outlined,
  'allergy': Icons.warning_amber_outlined,
  'procedure': Icons.healing_outlined,
  'vaccination': Icons.vaccines_outlined,
  'imaging': Icons.image_search_outlined,
  'visit': Icons.local_hospital_outlined,
  'other': Icons.description_outlined,
};

String recordDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

/// Rekam medis pribadi: diagnosis, hasil lab, obat yang dipakai, alergi, tindakan, vaksin, kunjungan. Ditambah lewat formulir
/// di sini atau lewat cerita di Ngobrol (KIRA menggolongkannya). KIRA hanya menyimpan; tidak menilai dan tidak menyarankan obat.
class RecordsScreen extends ConsumerStatefulWidget {
  const RecordsScreen({super.key});

  @override
  ConsumerState<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends ConsumerState<RecordsScreen> {
  String? _kind;

  Future<void> _edit([MedicalRecord? record]) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => RecordForm(record: record),
    );
    if (saved == true) ref.invalidate(recordsProvider);
  }

  Future<void> _delete(MedicalRecord record) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Hapus rekam medis ini?'),
        content: Text('"${record.title}" dihapus dari ponsel dan server. Ini tidak bisa dibatalkan.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialog, false), child: const Text('Batal')),
          FilledButton(key: const Key('record_delete_confirm'), onPressed: () => Navigator.pop(dialog, true), child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await ref.read(apiProvider).deleteRecord(record.id);
      ref.invalidate(recordsProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(recordsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Rekam medis')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('record_add'),
        onPressed: () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('Tambah'),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator.adaptive()),
        error: (e, _) => LoadError(message: friendlyError(e), onRetry: () => ref.invalidate(recordsProvider)),
        data: (records) {
          final shown = [for (final r in records) if (_kind == null || r.kind == _kind) r];
          final kinds = [for (final k in recordKinds) if (records.any((r) => r.kind == k)) k];
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(recordsProvider);
              await ref.read(recordsProvider.future);
            },
            child: ListView(
              key: const Key('records_list'),
              physics: const AlwaysScrollableScrollPhysics(),
              padding: context.pagePadding.copyWith(bottom: context.pagePadding.bottom + 72), // ruang untuk tombol Tambah
              children: [
                Text('Simpan riwayat kesehatanmu di satu tempat, lalu bawa ke dokter.', style: context.text.bodyLarge),
                const SizedBox(height: KiraSpace.sm),
                const SoftNote(
                  key: Key('records_note'),
                  icon: Icons.chat_bubble_outline,
                  text: 'Kamu juga bisa menceritakannya di Ngobrol, misalnya "dokter bilang kolesterolku 210". KIRA menggolongkan dan '
                      'menyimpannya. KIRA hanya menyimpan: tidak menilai isinya dan tidak menyarankan obat.',
                ),
                const SizedBox(height: KiraSpace.md),
                if (kinds.length > 1)
                  Wrap(spacing: KiraSpace.sm, runSpacing: KiraSpace.xs, children: [
                    ChoiceChip(
                      key: const Key('records_filter_all'),
                      label: const Text('Semua'),
                      selected: _kind == null,
                      onSelected: (_) => setState(() => _kind = null),
                    ),
                    for (final k in kinds)
                      ChoiceChip(
                        key: Key('records_filter_$k'),
                        label: Text(recordKindLabels[k]!),
                        selected: _kind == k,
                        onSelected: (_) => setState(() => _kind = k),
                      ),
                  ]),
                const SizedBox(height: KiraSpace.md),
                if (records.isEmpty)
                  Card(
                    key: const Key('records_empty'),
                    child: Padding(
                      padding: const EdgeInsets.all(KiraSpace.xl),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(Icons.folder_open_outlined, size: 36, color: context.scheme.primary),
                        const SizedBox(height: KiraSpace.md),
                        Text('Belum ada rekam medis', style: context.text.titleLarge),
                        const SizedBox(height: KiraSpace.xs),
                        Text('Mulai dari diagnosis dokter, hasil lab terakhir, obat yang kamu pakai, atau alergi.',
                            style: context.text.bodyLarge),
                        const SizedBox(height: KiraSpace.md),
                        OutlinedButton.icon(
                          key: const Key('records_tell_in_chat'),
                          onPressed: () => context.go('/chat'),
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: const Text('Ceritakan di Ngobrol'),
                        ),
                      ]),
                    ),
                  )
                else
                  for (final r in shown)
                    _RecordCard(record: r, onEdit: () => _edit(r), onDelete: () => _delete(r)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record, required this.onEdit, required this.onDelete});
  final MedicalRecord record;
  final VoidCallback onEdit, onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key('record_${record.id}'),
      margin: const EdgeInsets.only(bottom: KiraSpace.sm),
      child: Padding(
        padding: const EdgeInsets.all(KiraSpace.lg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(_kindIcons[record.kind] ?? Icons.description_outlined, color: context.scheme.primary),
            const SizedBox(width: KiraSpace.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(record.title, style: context.text.titleMedium),
                Text(
                  [record.kindLabel, recordDate(record.recordedOn), if (record.provider != null) record.provider!].join(' · '),
                  style: context.text.bodySmall,
                ),
              ]),
            ),
            PopupMenuButton<String>(
              key: Key('record_menu_${record.id}'),
              tooltip: 'Aksi rekam medis',
              onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Ubah')),
                PopupMenuItem(value: 'delete', child: Text('Hapus')),
              ],
            ),
          ]),
          if (record.details != null) ...[
            const SizedBox(height: KiraSpace.sm),
            Text(record.details!, style: context.text.bodyMedium),
          ],
          if (record.values.isNotEmpty) ...[
            const SizedBox(height: KiraSpace.sm),
            for (final v in record.values)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(children: [
                  Expanded(child: Text(v.name, style: context.text.bodyMedium)),
                  Text('${v.value}${v.unit == null ? '' : ' ${v.unit}'}',
                      style: context.text.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                ]),
              ),
          ],
          if (record.source == 'chat')
            Padding(
              padding: const EdgeInsets.only(top: KiraSpace.sm),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.chat_bubble_outline, size: 14, color: context.scheme.onSurfaceVariant),
                const SizedBox(width: KiraSpace.xs),
                Text('Dicatat dari cerita di Ngobrol', style: context.text.bodySmall),
              ]),
            ),
        ]),
      ),
    );
  }
}

/// Formulir tambah atau ubah rekam medis.
class RecordForm extends ConsumerStatefulWidget {
  const RecordForm({super.key, this.record});
  final MedicalRecord? record;

  @override
  ConsumerState<RecordForm> createState() => _RecordFormState();
}

class _RecordFormState extends ConsumerState<RecordForm> {
  late String _kind = widget.record?.kind ?? 'diagnosis';
  late final _title = TextEditingController(text: widget.record?.title ?? '');
  late final _provider = TextEditingController(text: widget.record?.provider ?? '');
  late final _details = TextEditingController(text: widget.record?.details ?? '');
  late DateTime _date = widget.record?.recordedOn ?? ref.read(clockProvider)();
  late final List<({TextEditingController name, TextEditingController value, TextEditingController unit})> _values = [
    for (final v in widget.record?.values ?? const <RecordValue>[])
      (name: TextEditingController(text: v.name), value: TextEditingController(text: v.value), unit: TextEditingController(text: v.unit ?? '')),
  ];
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _provider.dispose();
    _details.dispose();
    for (final v in _values) {
      v.name.dispose();
      v.value.dispose();
      v.unit.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final today = ref.read(clockProvider)();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isAfter(today) ? today : _date,
      firstDate: DateTime(1950),
      lastDate: DateTime(today.year, today.month, today.day),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      setState(() => _error = 'Isi judul singkat, misalnya "Panel lipid" atau "Metformin 500 mg".');
      return;
    }
    final values = [
      for (final v in _values)
        if (v.name.text.trim().isNotEmpty && v.value.text.trim().isNotEmpty)
          RecordValue(name: v.name.text.trim(), value: v.value.text.trim(), unit: v.unit.text.trim().isEmpty ? null : v.unit.text.trim()),
    ];
    final fields = <String, dynamic>{
      'kind': _kind,
      'title': _title.text.trim(),
      'recorded_on': _date.toIso8601String().substring(0, 10),
      'provider': _provider.text.trim().isEmpty ? null : _provider.text.trim(),
      'details': _details.text.trim().isEmpty ? null : _details.text.trim(),
      'values': [for (final v in values) v.toJson()],
    };
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(apiProvider);
      if (widget.record == null) {
        await api.createRecord(fields);
      } else {
        await api.updateRecord(widget.record!.id, fields);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(KiraSpace.xl, 0, KiraSpace.xl, KiraSpace.xl + inset + MediaQuery.paddingOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.record == null ? 'Tambah rekam medis' : 'Ubah rekam medis', style: context.text.titleLarge),
          const SizedBox(height: KiraSpace.md),
          Wrap(spacing: KiraSpace.sm, runSpacing: KiraSpace.xs, children: [
            for (final k in recordKinds)
              ChoiceChip(
                key: Key('record_kind_$k'),
                label: Text(recordKindLabels[k]!),
                selected: _kind == k,
                onSelected: (_) => setState(() => _kind = k),
              ),
          ]),
          const SizedBox(height: KiraSpace.md),
          TextField(
            key: const Key('record_title'),
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Judul', hintText: 'mis. Panel lipid, Metformin 500 mg, Alergi udang'),
          ),
          const SizedBox(height: KiraSpace.sm),
          OutlinedButton.icon(
            key: const Key('record_date'),
            onPressed: _pickDate,
            icon: const Icon(Icons.event_outlined),
            label: Text('Tanggal ${recordDate(_date)}'),
          ),
          const SizedBox(height: KiraSpace.sm),
          TextField(
            key: const Key('record_provider'),
            controller: _provider,
            decoration: const InputDecoration(labelText: 'Dokter / fasilitas (boleh kosong)'),
          ),
          const SizedBox(height: KiraSpace.sm),
          TextField(
            key: const Key('record_details'),
            controller: _details,
            minLines: 2,
            maxLines: 5,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Catatan (boleh kosong)'),
          ),
          if (_kind == 'lab' || _values.isNotEmpty) ...[
            const SizedBox(height: KiraSpace.md),
            Text('Nilai hasil', style: context.text.titleSmall),
            for (var i = 0; i < _values.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: KiraSpace.xs),
                child: Row(children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      key: Key('record_value_name_$i'),
                      controller: _values[i].name,
                      decoration: const InputDecoration(labelText: 'Nama', isDense: true),
                    ),
                  ),
                  const SizedBox(width: KiraSpace.xs),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      key: Key('record_value_value_$i'),
                      controller: _values[i].value,
                      decoration: const InputDecoration(labelText: 'Nilai', isDense: true),
                    ),
                  ),
                  const SizedBox(width: KiraSpace.xs),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      key: Key('record_value_unit_$i'),
                      controller: _values[i].unit,
                      decoration: const InputDecoration(labelText: 'Satuan', isDense: true),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Hapus baris',
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => setState(() {
                      final removed = _values.removeAt(i);
                      removed.name.dispose();
                      removed.value.dispose();
                      removed.unit.dispose();
                    }),
                  ),
                ]),
              ),
            TextButton.icon(
              key: const Key('record_add_value'),
              onPressed: () => setState(() => _values.add((
                    name: TextEditingController(),
                    value: TextEditingController(),
                    unit: TextEditingController(),
                  ))),
              icon: const Icon(Icons.add),
              label: const Text('Tambah nilai'),
            ),
          ] else
            TextButton.icon(
              key: const Key('record_add_value'),
              onPressed: () => setState(() => _values.add((
                    name: TextEditingController(),
                    value: TextEditingController(),
                    unit: TextEditingController(),
                  ))),
              icon: const Icon(Icons.add),
              label: const Text('Tambah nilai hasil (opsional)'),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: KiraSpace.sm),
              child: Semantics(
                liveRegion: true,
                child: Text(_error!, key: const Key('record_error'), style: context.text.bodyMedium?.copyWith(color: context.scheme.error)),
              ),
            ),
          const SizedBox(height: KiraSpace.lg),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              key: const Key('record_save'),
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Text('Simpan'),
            ),
          ),
        ]),
      ),
    );
  }
}
