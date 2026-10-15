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
