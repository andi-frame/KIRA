/// Rekam medis pribadi (dicatat sendiri oleh pengguna atau dari cerita di chat) dan riwayat obrolan hari ini.
library;

import 'models.dart';

/// Jenis rekam medis, urut sesuai tampilan. Label dari server mengikuti urutan ini.
const recordKinds = ['diagnosis', 'lab', 'medication', 'allergy', 'procedure', 'vaccination', 'imaging', 'visit', 'other'];
const recordKindLabels = {
  'diagnosis': 'Diagnosis',
  'lab': 'Hasil laboratorium',
  'medication': 'Obat yang dipakai',
  'allergy': 'Alergi',
  'procedure': 'Tindakan/operasi',
  'vaccination': 'Vaksinasi',
  'imaging': 'Radiologi/penunjang',
  'visit': 'Kunjungan/konsultasi',
  'other': 'Lainnya',
};

class RecordValue {
  const RecordValue({required this.name, required this.value, this.unit});
  final String name;
  final String value;
  final String? unit;

  factory RecordValue.fromJson(Map<String, dynamic> j) =>
      RecordValue(name: j['name'] as String, value: '${j['value']}', unit: j['unit'] as String?);

  Map<String, dynamic> toJson() => {'name': name, 'value': value, if (unit != null && unit!.isNotEmpty) 'unit': unit};
}

class MedicalRecord {
  const MedicalRecord({
    required this.id,
    required this.kind,
    required this.title,
    required this.recordedOn,
    this.provider,
    this.details,
    this.values = const [],
    this.source = 'manual',
  });

  final String id;
  final String kind;
  final String title;
  final DateTime recordedOn;
  final String? provider;
  final String? details;
  final List<RecordValue> values;

  /// manual | chat
  final String source;

  String get kindLabel => recordKindLabels[kind] ?? kind;

  factory MedicalRecord.fromJson(Map<String, dynamic> j) => MedicalRecord(
        id: j['id'] as String,
        kind: j['kind'] as String,
        title: j['title'] as String,
        recordedOn: DateTime.parse(j['recorded_on'] as String),
        provider: j['provider'] as String?,
        details: j['details'] as String?,
        values: (j['values'] as List? ?? const []).map((e) => RecordValue.fromJson(e as Map<String, dynamic>)).toList(),
        source: (j['source'] as String?) ?? 'manual',
      );
}

/// Satu pesan di obrolan hari ini (dari server), beserta kartu catatan makan yang dibuat darinya.
class ChatHistoryMessage {
  const ChatHistoryMessage({
    required this.id,
    required this.role,
    required this.text,
    required this.at,
    this.redFlag,
    this.toolCalls = const [],
    this.meals = const [],
    this.channel = 'app',
  });

  final String id;
  final String role; // user | assistant
  final String text;
  final DateTime at;
  final String? redFlag;
  final List<ToolCall> toolCalls;
  final List<MealLog> meals;
  final String channel;

  factory ChatHistoryMessage.fromJson(Map<String, dynamic> j) => ChatHistoryMessage(
        id: j['id'] as String,
        role: j['role'] as String,
        text: (j['text'] as String?) ?? '',
        at: DateTime.parse(j['at'] as String),
        redFlag: j['red_flag'] as String?,
        toolCalls: (j['tool_calls'] as List? ?? const []).map((e) => ToolCall.fromJson(e as Map<String, dynamic>)).toList(),
        meals: (j['meals'] as List? ?? const []).map((e) => MealLog.fromJson(e as Map<String, dynamic>)).toList(),
        channel: (j['channel'] as String?) ?? 'app',
      );
}
