import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../shared/app_shell.dart';
import '../../shared/models.dart';
import '../../shared/widgets.dart';
import 'chat_controller.dart';
import 'frequent_foods.dart';
import 'meal_card.dart';
import 'media.dart';
import 'tool_trace.dart';

const _suggestions = [
  'Tadi siang nasi padang rendang, es teh manis',
  'Semalam tidur jam 1, bangun jam 6',
  'Nanti malam mau makan rendang lagi, boleh berapa?',
];

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  bool _recording = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    setState(() {});
    await ref.read(chatProvider.notifier).send(text);
  }

  Future<void> _pickPhoto() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _KindSheet(),
    );
    if (kind == null || !mounted) return;
    if (kind == 'barcode') {
      await context.push('/barcode');
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _SourceSheet(),
    );
    if (source == null || !mounted) return;
    final media = await ref.read(photoPickerProvider).pick(source);
    if (media == null) return;
    await ref.read(chatProvider.notifier).sendPhoto(kind, media.bytes, media.name);
  }

  Future<void> _startRecording() async {
    final ok = await ref.read(voiceRecorderProvider).start();
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Izin mikrofon belum diberikan. Kamu tetap bisa mengetik atau kirim foto.')),
      );
      return;
    }
    setState(() => _recording = true);
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    setState(() => _recording = false);
    final media = await ref.read(voiceRecorderProvider).stop();
    if (media == null) return;
    await ref.read(chatProvider.notifier).sendVoice(media.bytes, media.name);
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatProvider);
    final profile = ref.watch(profileProvider).value;
    final items = chat.items.reversed.toList();
    final hasText = _input.text.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('KIRA'),
        actions: [
          if (profile?.isManagement ?? false)
            Padding(
              padding: const EdgeInsets.only(right: KiraSpace.xs),
              child: Chip(
                label: const Text('Mode pengelolaan'),
                avatar: Icon(Icons.favorite_outline, size: 18, color: context.scheme.primary),
              ),
            ),
          const ProfileAction(),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                reverse: true,
                padding: const EdgeInsets.fromLTRB(KiraSpace.lg, KiraSpace.sm, KiraSpace.lg, KiraSpace.lg),
                itemCount: items.length + (chat.busy ? 1 : 0),
                itemBuilder: (context, index) {
                  if (chat.busy && index == 0) return const _TypingBubble();
                  final item = items[chat.busy ? index - 1 : index];
                  return Padding(
                    padding: const EdgeInsets.only(top: KiraSpace.md),
                    child: _ItemView(item: item),
                  );
                },
              ),
            ),
            if (chat.isFresh)
              SizedBox(
                height: 56,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: KiraSpace.lg, vertical: KiraSpace.sm),
                  itemCount: _suggestions.length,
                  separatorBuilder: (_, _) => const SizedBox(width: KiraSpace.sm),
                  itemBuilder: (_, i) => ActionChip(
                    key: Key('suggestion_$i'),
                    label: Text(_suggestions[i]),
                    onPressed: () => ref.read(chatProvider.notifier).send(_suggestions[i]),
                  ),
                ),
              ),
            if (!chat.isFresh && !hasText) const FrequentFoodChips(),
            _InputBar(
              controller: _input,
              hasText: hasText,
              recording: _recording,
              onChanged: () => setState(() {}),
              onSend: _send,
              onCamera: _pickPhoto,
              onRecordStart: _startRecording,
              onRecordEnd: _stopRecording,
            ),
          ],
        ),
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.hasText,
    required this.recording,
    required this.onChanged,
    required this.onSend,
    required this.onCamera,
    required this.onRecordStart,
    required this.onRecordEnd,
  });

  final TextEditingController controller;
  final bool hasText, recording;
  final VoidCallback onChanged, onSend, onCamera;
  final Future<void> Function() onRecordStart, onRecordEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = context.scheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(KiraSpace.sm, KiraSpace.sm, KiraSpace.sm, KiraSpace.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: recording
          ? Row(
              children: [
                const SizedBox(width: KiraSpace.md),
                Icon(Icons.mic, color: scheme.primary),
                const SizedBox(width: KiraSpace.sm),
                Expanded(child: Text('Merekam... lepas untuk mengirim', style: context.text.bodyLarge)),
                _MicButton(recording: true, onStart: onRecordStart, onEnd: onRecordEnd),
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                IconButton(
                  key: const Key('camera_button'),
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                  tooltip: 'Kirim foto makanan, struk, label gizi, atau hasil cek',
                  icon: const Icon(Icons.photo_camera_outlined),
                  onPressed: onCamera,
                ),
                Expanded(
                  child: TextField(
                    key: const Key('chat_input'),
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    onChanged: (_) => onChanged(),
                    decoration: const InputDecoration(hintText: 'Ceritakan harimu...', isDense: true),
                  ),
                ),
                const SizedBox(width: KiraSpace.xs),
                _MicButton(recording: false, onStart: onRecordStart, onEnd: onRecordEnd),
                IconButton.filled(
                  key: const Key('send_button'),
                  style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
                  tooltip: 'Kirim',
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: hasText ? onSend : null,
                ),
              ],
            ),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({required this.recording, required this.onStart, required this.onEnd});
  final bool recording;
  final Future<void> Function() onStart, onEnd;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (_) => onStart(),
      onLongPressEnd: (_) => onEnd(),
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tahan tombol mikrofon sambil bicara, lepas untuk mengirim.')),
      ),
      child: Semantics(
        button: true,
        label: 'Tahan untuk bicara',
        child: Container(
          key: const Key('mic_button'),
          width: 48,
          height: 48,
          alignment: Alignment.center,
          decoration: recording
              ? BoxDecoration(color: context.scheme.primaryContainer, shape: BoxShape.circle)
              : null,
          child: Icon(Icons.mic_none, color: recording ? context.scheme.primary : context.scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _ItemView extends ConsumerWidget {
  const _ItemView({required this.item});
  final ChatItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    switch (item.kind) {
      case ChatKind.user:
        return ChatBubble(text: item.text, mine: true);
      case ChatKind.pending:
        return Column(
          key: Key('pending_${item.id}'),
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            ChatBubble(text: item.text, mine: true),
            Padding(
              padding: const EdgeInsets.only(top: KiraSpace.xs, right: KiraSpace.sm),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.schedule, size: 14, color: context.scheme.onSurfaceVariant),
                const SizedBox(width: KiraSpace.xs),
                Text('Menunggu sinyal, dikirim otomatis', style: context.text.bodySmall),
              ]),
            ),
          ],
        );
      case ChatKind.kira:
        if (item.calls.isEmpty) return ChatBubble(text: item.text, mine: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [ChatBubble(text: item.text, mine: false), ToolTrace(calls: item.calls)],
        );
      case ChatKind.emergency:
        return EmergencyCard(message: item.text);
      case ChatKind.extraction:
        final chat = ref.read(chatProvider.notifier);
        return ExtractionCard(
          item: item,
          onEdit: (index, grams) => chat.correctPortion(item, index, grams),
          mealActions: MealCardActions(
            correct: (food, grams) => chat.correctItem(item, food, grams),
            halve: (group) => chat.halveGroup(item, group),
            remove: (food) => chat.removeItem(item, food),
            replace: (food, found) => chat.replaceItem(item, food, found),
            search: chat.searchFoods,
          ),
        );
      case ChatKind.error:
        return _ErrorBubble(item: item);
    }
  }
}

class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: KiraSpace.md),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          label: 'KIRA sedang mengetik',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: KiraSpace.lg, vertical: KiraSpace.md),
            decoration: BoxDecoration(
              color: context.scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(KiraRadius.card),
              border: Border.all(color: context.scheme.outlineVariant),
            ),
            child: const SizedBox(width: 24, height: 16, child: LinearProgressIndicator()),
          ),
        ),
      ),
    );
  }
}

class _ErrorBubble extends StatelessWidget {
  const _ErrorBubble({required this.item});
  final ChatItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(KiraSpace.lg),
      decoration: BoxDecoration(
        color: context.scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(KiraRadius.card),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, color: context.scheme.onSurfaceVariant),
          const SizedBox(width: KiraSpace.md),
          Expanded(child: Text(item.text, style: context.text.bodyMedium)),
          TextButton(key: const Key('retry_button'), onPressed: item.retry, child: const Text('Coba lagi')),
        ],
      ),
    );
  }
}

/// Kartu hasil ekstraksi: apa yang dicatat KIRA, dengan porsi yang bisa dikoreksi.
class ExtractionCard extends StatelessWidget {
  const ExtractionCard({super.key, required this.item, required this.onEdit, this.mealActions});
  final ChatItem item;
  final Future<void> Function(int index, double grams) onEdit;

  /// Koreksi per komponen; dipakai bila balasan membawa rincian catatan makan (item.meal).
  final MealCardActions? mealActions;

  Future<void> _edit(BuildContext context, int index, FoodEntry entry) async {
    final grams = await showDialog<double>(context: context, builder: (_) => _PortionDialog(entry: entry));
    if (grams != null) await onEdit(index, grams);
  }

  @override
  Widget build(BuildContext context) {
    final data = item.data!;
    final scheme = context.scheme;
    return Container(
      key: const Key('extraction_card'),
      padding: const EdgeInsets.all(KiraSpace.lg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(KiraRadius.card),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.check_circle_outline, size: 20, color: context.kira.improve),
            const SizedBox(width: KiraSpace.sm),
            Text('Yang kucatat', style: context.text.titleSmall),
          ]),
          const SizedBox(height: KiraSpace.sm),
          if (item.meal != null && item.meal!.items.isNotEmpty && mealActions != null)
            MealGroupsView(meal: item.meal!, actions: mealActions!)
          else
          for (var i = 0; i < data.items.length; i++)
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: KiraSpace.sm,
                    children: [
                      Text(data.items[i].name, style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
                      if (data.items[i].portionText != null)
                        Text(data.items[i].portionText!, style: context.text.bodyMedium),
                    ],
                  ),
                ),
                IconButton(
                  key: Key('edit_item_$i'),
                  tooltip: 'Ubah porsi ${data.items[i].name}',
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  onPressed: () => _edit(context, i, data.items[i]),
                ),
              ],
            ),
          if (data.label != null) _LabelRows(label: data.label!),
          for (final d in data.drinks)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: KiraSpace.xs),
              child: Row(children: [
                Icon(Icons.local_cafe_outlined, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: KiraSpace.sm),
                Text(d, style: context.text.bodyLarge),
              ]),
            ),
          if (data.sleepBed != null || data.sleepWake != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: KiraSpace.xs),
              child: Row(children: [
                Icon(Icons.bedtime_outlined, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: KiraSpace.sm),
                Text(
                  [
                    if (data.sleepBed != null) 'tidur ${data.sleepBed}',
                    if (data.sleepWake != null) 'bangun ${data.sleepWake}',
                  ].join(', '),
                  style: context.text.bodyLarge,
                ),
              ]),
            ),
          for (final a in data.activities)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: KiraSpace.xs),
              child: Row(children: [
                Icon(Icons.directions_walk, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: KiraSpace.sm),
                Text(a, style: context.text.bodyLarge),
              ]),
            ),
        ],
      ),
    );
  }
}

String _num(double v) => v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

/// Angka dari tabel informasi nilai gizi di kemasan: tercetak, bukan estimasi. Yang tidak tertera tidak ditampilkan.
class _LabelRows extends StatelessWidget {
  const _LabelRows({required this.label});
  final LabelEntry label;

  @override
  Widget build(BuildContext context) {
    final values = [
      if (label.sugarG != null) 'gula ${_num(label.sugarG!)} g',
      if (label.sodiumMg != null) 'natrium ${_num(label.sodiumMg!)} mg',
      if (label.fatG != null) 'lemak ${_num(label.fatG!)} g',
      if (label.kcal != null) '${_num(label.kcal!)} kkal',
    ].join(', ');
    final basis = label.perServing
        ? 'per sajian${label.servingG != null ? ' (${_num(label.servingG!)} g)' : ''}'
        : 'per 100 g';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: KiraSpace.xs),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(label.isDrink ? Icons.local_cafe_outlined : Icons.fact_check_outlined,
                size: 18, color: context.scheme.onSurfaceVariant),
            const SizedBox(width: KiraSpace.sm),
            Expanded(
              child: Text(label.productName, style: context.text.bodyLarge?.copyWith(fontWeight: FontWeight.w700)),
            ),
          ]),
          Text(
            'Dari label kemasan${label.servings != 1 ? ' · ${_num(label.servings)} sajian' : ''}',
            style: context.text.bodySmall,
          ),
          if (values.isNotEmpty) Text('$values $basis', style: context.text.bodyMedium),
        ],
      ),
    );
  }
}

class _KindSheet extends StatelessWidget {
  const _KindSheet();

  @override
  Widget build(BuildContext context) {
    Widget tile(String key, String kind, IconData icon, String title, String subtitle) => ListTile(
          key: Key(key),
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(subtitle),
          onTap: () => Navigator.pop(context, kind),
        );
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
        tile('photo_kind_food', 'food', Icons.restaurant_outlined, 'Foto makanan', 'KIRA mengenali menu dan porsinya'),
        tile('photo_kind_receipt', 'receipt', Icons.receipt_long_outlined, 'Foto struk belanja', 'Daftar item dibaca dari struk'),
        tile('photo_kind_label', 'label', Icons.fact_check_outlined, 'Foto label gizi kemasan',
            'Gula dan natrium dibaca dari tabel informasi nilai gizi'),
        tile('photo_kind_barcode', 'barcode', Icons.qr_code_scanner, 'Pindai kode batang kemasan',
            'Gizi produk dicari di Open Food Facts, tinggal pilih porsinya'),
        tile('photo_kind_result', 'result', Icons.biotech_outlined, 'Foto hasil cek', 'Hasil lab, CKG, atau layar tensimeter'),
        ]),
      ),
    );
  }
}

class _SourceSheet extends StatelessWidget {
  const _SourceSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          key: const Key('photo_source_camera'),
          leading: const Icon(Icons.photo_camera_outlined),
          title: const Text('Ambil dengan kamera'),
          onTap: () => Navigator.pop(context, ImageSource.camera),
        ),
        ListTile(
          key: const Key('photo_source_gallery'),
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('Pilih dari galeri'),
          onTap: () => Navigator.pop(context, ImageSource.gallery),
        ),
      ]),
    );
  }
}


class _PortionDialog extends StatefulWidget {
  const _PortionDialog({required this.entry});
  final FoodEntry entry;

  @override
  State<_PortionDialog> createState() => _PortionDialogState();
}

class _PortionDialogState extends State<_PortionDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.entry.portionG?.round().toString() ?? '');
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = double.tryParse(_controller.text.trim().replaceAll(',', '.'));
    if (value == null || value <= 0 || value > 5000) {
      setState(() => _error = 'Isi angka gram antara 1 dan 5000.');
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Porsi ${widget.entry.name}'),
      content: TextField(
        key: const Key('portion_input'),
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(labelText: 'Berapa gram?', suffixText: 'g', errorText: _error),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal')),
        FilledButton(key: const Key('portion_save'), onPressed: _save, child: const Text('Simpan')),
      ],
    );
  }
}
