import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/providers.dart';
import '../../core/theme.dart';
import '../../shared/widgets.dart';

enum _Step { name, birth, sex, body, waist, family, habits, smoker, saving }

class _Msg {
  const _Msg(this.text, {this.mine = false});
  final String text;
  final bool mine;
}

/// Percakapan kenalan 8 pertanyaan. Jawaban dikumpulkan lalu disimpan sekali lewat PUT /profile.
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _input = TextEditingController();
  final _height = TextEditingController();
  final _weight = TextEditingController();
  final _answers = <String, dynamic>{};
  final _messages = <_Msg>[
    const _Msg('Hai, aku KIRA. Yuk kenalan dulu, cuma 8 pertanyaan singkat. Datamu hanya dipakai untuk menghitung proyeksimu.'),
    const _Msg('Biasanya kamu dipanggil siapa?'),
  ];
  _Step _step = _Step.name;
  String? _error;
  bool? _active, _veg;

  @override
  void dispose() {
    _input.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  void _ask(String question) => _messages.add(_Msg(question));

  void _advance(_Step next, String answerShown, String nextQuestion) {
    setState(() {
      _messages.add(_Msg(answerShown, mine: true));
      _error = null;
      _step = next;
      _input.clear();
      _ask(nextQuestion);
    });
  }

  void _fail(String message) => setState(() => _error = message);

  void _submitName() {
    final name = _input.text.trim();
    if (name.isEmpty || name.length > 60) return _fail('Tulis panggilanmu dulu ya (maksimal 60 huruf).');
    _answers['display_name'] = name;
    _advance(_Step.birth, name, 'Senang kenal, $name! Tahun berapa kamu lahir?');
  }

  void _submitBirth() {
    final year = int.tryParse(_input.text.trim());
    final maxYear = DateTime.now().year - 15;
    if (year == null || year < 1930 || year > maxYear) {
      return _fail('Cek lagi tahun lahirnya ya (antara 1930 dan $maxYear).');
    }
    _answers['birth_date'] = '$year-07-01';
    _advance(_Step.sex, '$year', 'Jenis kelamin? Ini dipakai karena batas lingkar perut berbeda.');
  }

  void _pickSex(String value, String label) {
    _answers['sex'] = value;
    _advance(_Step.body, label, 'Berapa tinggi dan berat badanmu sekarang?');
  }

  void _submitBody() {
    final height = double.tryParse(_height.text.trim().replaceAll(',', '.'));
    final weight = double.tryParse(_weight.text.trim().replaceAll(',', '.'));
    if (height == null || height < 100 || height > 230) return _fail('Tinggi badan antara 100 dan 230 cm ya.');
    if (weight == null || weight < 25 || weight > 300) return _fail('Berat badan antara 25 dan 300 kg ya.');
    _answers['height_cm'] = height;
    _answers['weight_kg'] = weight;
    _advance(_Step.waist, '${height.round()} cm, ${weight.round()} kg',
        'Lingkar perutmu (diukur sejajar pusar)? Kalau belum pernah mengukur, lewati saja.');
  }

  void _submitWaist() {
    final waist = double.tryParse(_input.text.trim().replaceAll(',', '.'));
    if (waist == null || waist < 40 || waist > 200) return _fail('Lingkar perut antara 40 dan 200 cm, atau lewati saja.');
    _answers['waist_cm'] = waist;
    _advance(_Step.family, '${waist.round()} cm', 'Ada keluarga yang punya diabetes?');
  }

  void _skipWaist() => _advance(_Step.family, 'Dilewati', 'Ada keluarga yang punya diabetes?');

  void _pickFamily(String? value, String label) {
    if (value != null) _answers['family_history_diabetes'] = value;
    _advance(_Step.habits, label, 'Soal kebiasaan sehari-hari, jawab seadanya saja ya.');
  }

  void _submitHabits() {
    if (_active == null || _veg == null) return;
    _answers['usual_active_30min'] = _active;
    _answers['usual_veg_fruit'] = _veg;
    _advance(_Step.smoker, '${_active! ? 'Aktif' : 'Jarang aktif'}, ${_veg! ? 'sayur/buah tiap hari' : 'jarang sayur/buah'}',
        'Terakhir: apakah kamu merokok?');
  }

  Future<void> _pickSmoker(bool smoker, String label) async {
    _answers['smoker'] = smoker;
    setState(() {
      _messages.add(_Msg(label, mine: true));
      _step = _Step.saving;
      _error = null;
    });
    await _save();
  }

  Future<void> _save() async {
    setState(() => _error = null);
    try {
      await ref.read(apiProvider).putProfile(Map<String, dynamic>.of(_answers));
      if (!mounted) return;
      ref.invalidate(profileProvider);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yuk kenalan')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                reverse: true,
                padding: const EdgeInsets.all(KiraSpace.lg),
                itemCount: _messages.length,
                itemBuilder: (_, i) {
                  final m = _messages[_messages.length - 1 - i];
                  return Padding(
                    padding: const EdgeInsets.only(top: KiraSpace.md),
                    child: ChatBubble(text: m.text, mine: m.mine),
                  );
                },
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(KiraSpace.lg),
              decoration: BoxDecoration(
                color: context.scheme.surfaceContainerLowest,
                border: Border(top: BorderSide(color: context.scheme.outlineVariant)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: KiraSpace.md),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(_error!, key: const Key('onb_error'),
                            style: context.text.bodyMedium?.copyWith(color: context.scheme.error)),
                      ),
                    ),
                  _panel(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _next(VoidCallback onPressed) => SizedBox(
        width: double.infinity,
        child: FilledButton(key: const Key('onb_next'), onPressed: onPressed, child: const Text('Lanjut')),
      );

  Widget _textField({required String label, TextInputType? type, String? suffix, List<TextInputFormatter>? formatters, VoidCallback? onSubmit}) =>
      TextField(
        key: const Key('onb_input'),
        controller: _input,
        keyboardType: type,
        inputFormatters: formatters,
        autofocus: true,
        onSubmitted: onSubmit == null ? null : (_) => onSubmit(),
        decoration: InputDecoration(labelText: label, suffixText: suffix),
      );

  Widget _options(List<(String label, VoidCallback onTap)> options) => Wrap(
        spacing: KiraSpace.sm,
        runSpacing: KiraSpace.sm,
        children: [
          for (final (label, onTap) in options) ActionChip(label: Text(label), onPressed: onTap),
        ],
      );

  Widget _yesNo(String question, bool? value, String keyBase, ValueChanged<bool> onChanged) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(question, style: context.text.bodyLarge),
          const SizedBox(height: KiraSpace.sm),
          Wrap(spacing: KiraSpace.sm, children: [
            ChoiceChip(key: Key('${keyBase}_yes'), label: const Text('Ya'), selected: value == true, onSelected: (_) => onChanged(true)),
            ChoiceChip(key: Key('${keyBase}_no'), label: const Text('Tidak'), selected: value == false, onSelected: (_) => onChanged(false)),
          ]),
          const SizedBox(height: KiraSpace.md),
        ],
      );

  Widget _panel(BuildContext context) {
    switch (_step) {
      case _Step.name:
        return Column(children: [_textField(label: 'Panggilanmu', onSubmit: _submitName), const SizedBox(height: KiraSpace.md), _next(_submitName)]);
      case _Step.birth:
        return Column(children: [
          _textField(
            label: 'Tahun lahir, misalnya 1998',
            type: TextInputType.number,
            formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(4)],
            onSubmit: _submitBirth,
          ),
          const SizedBox(height: KiraSpace.md),
          _next(_submitBirth),
        ]);
      case _Step.sex:
        return _options([('Laki-laki', () => _pickSex('male', 'Laki-laki')), ('Perempuan', () => _pickSex('female', 'Perempuan'))]);
      case _Step.body:
        return Column(children: [
          Row(children: [
            Expanded(
              child: TextField(
                key: const Key('onb_height'),
                controller: _height,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Tinggi', suffixText: 'cm'),
              ),
            ),
            const SizedBox(width: KiraSpace.md),
            Expanded(
              child: TextField(
                key: const Key('onb_weight'),
                controller: _weight,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Berat', suffixText: 'kg'),
              ),
            ),
          ]),
          const SizedBox(height: KiraSpace.md),
          _next(_submitBody),
        ]);
      case _Step.waist:
        return Column(children: [
          _textField(label: 'Lingkar perut', type: const TextInputType.numberWithOptions(decimal: true), suffix: 'cm', onSubmit: _submitWaist),
          const SizedBox(height: KiraSpace.md),
          Row(children: [
            TextButton(key: const Key('onb_skip'), onPressed: _skipWaist, child: const Text('Lewati')),
            const Spacer(),
            FilledButton(key: const Key('onb_next'), onPressed: _submitWaist, child: const Text('Lanjut')),
          ]),
        ]);
      case _Step.family:
        return _options([
          ('Orang tua atau saudara kandung', () => _pickFamily('first_degree', 'Orang tua atau saudara kandung')),
          ('Kakek-nenek, paman, atau bibi', () => _pickFamily('second_degree', 'Kakek-nenek, paman, atau bibi')),
          ('Tidak ada', () => _pickFamily('none', 'Tidak ada')),
          ('Belum tahu', () => _pickFamily(null, 'Belum tahu')),
        ]);
      case _Step.habits:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _yesNo('Biasanya aktif bergerak minimal 30 menit sehari?', _active, 'onb_active', (v) => setState(() => _active = v)),
          _yesNo('Makan sayur atau buah setiap hari?', _veg, 'onb_veg', (v) => setState(() => _veg = v)),
          _next(_submitHabits),
        ]);
      case _Step.smoker:
        return _options([('Tidak merokok', () => _pickSmoker(false, 'Tidak merokok')), ('Merokok', () => _pickSmoker(true, 'Merokok'))]);
      case _Step.saving:
        return _error == null
            ? const Row(children: [SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5)), SizedBox(width: 12), Text('Menyimpan...')])
            : SizedBox(width: double.infinity, child: FilledButton(key: const Key('onb_retry'), onPressed: _save, child: const Text('Coba simpan lagi')));
    }
  }
}
