/// Jawaban server atas "sudah dicek?".
class CheckRespondResult {
  const CheckRespondResult({required this.status, required this.resultNeeded, required this.testKind});
  final String status; // open | done | dismissed
  final bool resultNeeded; // sudah dicek tapi hasilnya belum ada di KIRA
  final String testKind;

  factory CheckRespondResult.fromJson(Map<String, dynamic> j) => CheckRespondResult(
        status: j['status'] as String,
        resultNeeded: j['result_needed'] as bool? ?? false,
        testKind: j['test_kind'] as String? ?? '',
      );
}

/// Makanan atau minuman yang sering dicatat, untuk mencatat ulang dengan satu ketukan.
class FrequentFood {
  const FrequentFood({required this.name, required this.kind, required this.count, this.portionG});
  final String name;
  final String kind; // meal | drink
  final int count;
  final double? portionG;

  bool get isDrink => kind == 'drink';

  /// Kalimat yang dikirim ke chat saat chip diketuk.
  String get phrase => isDrink ? 'Tadi minum $name' : 'Tadi makan $name';

  factory FrequentFood.fromJson(Map<String, dynamic> j) => FrequentFood(
        name: j['name'] as String,
        kind: j['kind'] as String,
        count: (j['count'] as num).toInt(),
        portionG: (j['portion_g'] as num?)?.toDouble(),
      );
}

/// Gizi produk kemasan per 100 g/ml dari kode batang. Nilai yang tidak tertera di basis data tetap null.
class ProductInfo {
  const ProductInfo({
    required this.barcode,
    required this.name,
    required this.isDrink,
    required this.complete,
    required this.source,
    this.brand,
    this.servingG,
    this.sugarG,
    this.sodiumMg,
    this.fatG,
    this.kcal,
  });

  final String barcode, name, source;
  final String? brand;
  final double? servingG, sugarG, sodiumMg, fatG, kcal; // per 100 g/ml
  final bool isDrink, complete;

  factory ProductInfo.fromJson(Map<String, dynamic> j) {
    final per = (j['per100g'] as Map<String, dynamic>? ?? const {});
    double? n(String k) => (per[k] as num?)?.toDouble();
    return ProductInfo(
      barcode: j['barcode'] as String,
      name: j['name'] as String,
      brand: j['brand'] as String?,
      servingG: (j['serving_g'] as num?)?.toDouble(),
      isDrink: j['is_drink'] as bool? ?? false,
      complete: j['complete'] as bool? ?? false,
      source: j['source'] as String? ?? '',
      sugarG: n('sugar_g'),
      sodiumMg: n('sodium_mg'),
      fatG: n('fat_g'),
      kcal: n('kcal'),
    );
  }
}

/// Hasil mencatat produk dari kode batang: gizi total yang dimakan.
class BarcodeLogResult {
  const BarcodeLogResult({required this.logId, required this.name, this.portionG, this.sugarG, this.sodiumMg, this.kcal});
  final String logId, name;
  final double? portionG, sugarG, sodiumMg, kcal;

  factory BarcodeLogResult.fromJson(Map<String, dynamic> j) {
    final item = j['item'] as Map<String, dynamic>;
    double? n(String k) => (item[k] as num?)?.toDouble();
    return BarcodeLogResult(
      logId: j['log_id'] as String,
      name: item['name'] as String,
      portionG: n('portion_g'),
      sugarG: n('sugar_g'),
      sodiumMg: n('sodium_mg'),
      kcal: n('kcal'),
    );
  }
}

/// Satu hari dalam putaran ukur tensi di rumah.
class BpDay {
  const BpDay({required this.date, required this.morning, required this.evening, required this.discarded, required this.isToday});
  final DateTime date;
  final int morning, evening;
  final bool discarded; // hari pertama: dicatat tetapi tidak ikut rata-rata
  final bool isToday;

  factory BpDay.fromJson(Map<String, dynamic> j) => BpDay(
        date: DateTime.parse(j['date'] as String),
        morning: (j['morning'] as num).toInt(),
        evening: (j['evening'] as num).toInt(),
        discarded: j['discarded'] as bool? ?? false,
        isToday: j['is_today'] as bool? ?? false,
      );
}

class BpSummary {
  const BpSummary({required this.valid, required this.readingsUsed, required this.daysUsed, this.avgSys, this.avgDia, this.range, this.missing});
  final bool valid;
  final int readingsUsed, daysUsed;
  final double? avgSys, avgDia;
  final String? range; // hypertension_range | below_threshold
  final String? missing;

  factory BpSummary.fromJson(Map<String, dynamic> j) => BpSummary(
        valid: j['valid'] as bool? ?? false,
        readingsUsed: (j['readings_used'] as num?)?.toInt() ?? 0,
        daysUsed: (j['days_used'] as num?)?.toInt() ?? 0,
        avgSys: (j['avg_sys'] as num?)?.toDouble(),
        avgDia: (j['avg_dia'] as num?)?.toDouble(),
        range: j['range'] as String?,
        missing: j['missing'] as String?,
      );
}

class BpProtocolState {
  const BpProtocolState({
    required this.id,
    required this.status,
    required this.dayIndex,
    required this.days,
    required this.summary,
    required this.canFinish,
    required this.over,
    this.resultSys,
    this.resultDia,
    this.resultReadings,
    this.resultRange,
  });
  final String id, status; // active | completed
  final int dayIndex;
  final List<BpDay> days;
  final BpSummary summary;
  final bool canFinish, over;
  final double? resultSys, resultDia; // rata-rata final setelah selesai
  final int? resultReadings;
  final String? resultRange;

  bool get active => status == 'active';

  factory BpProtocolState.fromJson(Map<String, dynamic> j) {
    final r = j['result'] as Map<String, dynamic>?;
    return BpProtocolState(
      id: j['id'] as String,
      status: j['status'] as String,
      dayIndex: (j['day_index'] as num).toInt(),
      days: (j['days'] as List).map((e) => BpDay.fromJson(e as Map<String, dynamic>)).toList(),
      summary: BpSummary.fromJson(j['summary'] as Map<String, dynamic>),
      canFinish: j['can_finish'] as bool? ?? false,
      over: j['over'] as bool? ?? false,
      resultSys: (r?['avg_sys'] as num?)?.toDouble(),
      resultDia: (r?['avg_dia'] as num?)?.toDouble(),
      resultReadings: (r?['readings_used'] as num?)?.toInt(),
      resultRange: r?['range'] as String?,
    );
  }
}

/// Jawaban lengkap endpoint protokol: keadaan terkini + (bila ada) peringatan bahaya untuk bacaan yang barusan dikirim.
class BpProtocolView {
  const BpProtocolView({this.protocol, this.saved = true, this.redFlag, this.homeSys = 135, this.homeDia = 85});
  final BpProtocolState? protocol;
  final bool saved;
  final String? redFlag; // pesan darurat; bacaan berbahaya tidak disimpan
  final int homeSys, homeDia;

  factory BpProtocolView.fromJson(Map<String, dynamic> j) {
    final p = j['protocol'] as Map<String, dynamic>?;
    final t = (j['guide'] as Map<String, dynamic>?)?['home_threshold'] as Map<String, dynamic>?;
    return BpProtocolView(
      protocol: p == null ? null : BpProtocolState.fromJson(p),
      saved: j['saved'] as bool? ?? true,
      redFlag: (j['red_flag'] as Map<String, dynamic>?)?['message'] as String?,
      homeSys: (t?['sys'] as num?)?.toInt() ?? 135,
      homeDia: (t?['dia'] as num?)?.toInt() ?? 85,
    );
  }
}
