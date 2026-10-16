/// Catatan makan beserta item dan gizinya (dari tabel pangan server, bukan dari model bahasa).
library;

double? _d(Object? v) => v == null ? null : (v as num).toDouble();

/// Jumlah gizi beberapa item. Item yang belum terhitung (tidak ada di database gizi) tidak ikut dijumlah.
class NutrientTotals {
  const NutrientTotals({this.kcal = 0, this.sugarG = 0, this.sodiumMg = 0, this.fatG = 0});
  final double kcal;
  final double sugarG;
  final double sodiumMg;
  final double fatG;

  factory NutrientTotals.of(Iterable<LoggedItem> items) {
    var kcal = 0.0, sugar = 0.0, sodium = 0.0, fat = 0.0;
    for (final i in items) {
      kcal += i.kcal ?? 0;
      sugar += i.sugarG ?? 0;
      sodium += i.sodiumMg ?? 0;
      fat += i.fatG ?? 0;
    }
    return NutrientTotals(kcal: kcal, sugarG: sugar, sodiumMg: sodium, fatG: fat);
  }

  factory NutrientTotals.fromJson(Map<String, dynamic> j) => NutrientTotals(
        kcal: _d(j['kcal']) ?? 0,
        sugarG: _d(j['sugar_g']) ?? 0,
        sodiumMg: _d(j['sodium_mg']) ?? 0,
        fatG: _d(j['fat_g']) ?? 0,
      );
}

class LoggedItem {
  const LoggedItem({
    required this.id,
    required this.name,
    this.portionG,
    this.kcal,
    this.sugarG,
    this.sodiumMg,
    this.fatG,
    this.foodId,
    this.group,
  });

  final String id;
  final String name;
  final double? portionG;
  final double? kcal;
  final double? sugarG;
  final double? sodiumMg;
  final double? fatG;
  final String? foodId;

  /// Hidangan induk bila item ini komponen sebuah hidangan ("Ayam geprek").
  final String? group;

  /// Ada di database gizi. Yang belum terhitung tidak punya angka (bukan nol).
  bool get counted => kcal != null;

  factory LoggedItem.fromJson(Map<String, dynamic> j) => LoggedItem(
        id: j['id'] as String,
        name: j['name'] as String,
        portionG: _d(j['portion_g']),
        kcal: _d(j['kcal']),
        sugarG: _d(j['sugar_g']),
        sodiumMg: _d(j['sodium_mg']),
        fatG: _d(j['fat_g']),
        foodId: j['food_id'] as String?,
        group: j['group'] as String?,
      );

  /// Bentuk untuk PATCH /logs/{id}: komponen tetap dikenali lewat food_id dan tetap terkelompok.
  Map<String, dynamic> toPatch({double? portionG, String? name, String? foodId}) => {
        'name': name ?? this.name,
        'portion_g': portionG ?? this.portionG,
        if ((foodId ?? this.foodId) != null) 'food_id': foodId ?? this.foodId,
        if (group != null) 'group': group,
      };
}

/// Satu kelompok di kartu: hidangan beserta komponennya, atau satu makanan tunggal.
class MealGroup {
  const MealGroup({required this.title, required this.isDish, required this.items});
  final String title;
  final bool isDish;
  final List<LoggedItem> items;

  NutrientTotals get totals => NutrientTotals.of(items);
  bool get hasUncounted => items.any((i) => !i.counted);
}

class MealLog {
  const MealLog({
    required this.id,
    this.kind = 'meal',
    this.source = 'text',
    this.occurredAt,
    this.corrected = false,
    this.items = const [],
  });

  final String id;
  final String kind;
  final String source;
  final DateTime? occurredAt;
  final bool corrected;
  final List<LoggedItem> items;

  NutrientTotals get totals => NutrientTotals.of(items);

  /// Item dikelompokkan per hidangan sesuai urutan kemunculan; makanan tunggal menjadi kelompoknya sendiri.
  List<MealGroup> get groups {
    final out = <MealGroup>[];
    final byGroup = <String, List<LoggedItem>>{};
    for (final item in items) {
      final g = item.group;
      if (g == null) {
        out.add(MealGroup(title: item.name, isDish: false, items: [item]));
      } else if (byGroup.containsKey(g)) {
        byGroup[g]!.add(item);
      } else {
        final list = [item];
        byGroup[g] = list;
        out.add(MealGroup(title: g, isDish: true, items: list));
      }
    }
    return out;
  }

  factory MealLog.fromJson(Map<String, dynamic> j) => MealLog(
        id: j['id'] as String,
        kind: (j['kind'] as String?) ?? 'meal',
        source: (j['source'] as String?) ?? 'text',
        occurredAt: j['occurred_at'] == null ? null : DateTime.parse(j['occurred_at'] as String),
        corrected: (j['corrected'] as bool?) ?? false,
        items: (j['items'] as List? ?? const []).map((e) => LoggedItem.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

/// Saran dari GET /foods/search untuk mengganti komponen yang belum terhitung.
class FoodSuggestion {
  const FoodSuggestion({required this.kind, required this.id, required this.name, this.portionG});
  final String kind; // food | dish
  final String id;
  final String name;
  final double? portionG;

  factory FoodSuggestion.fromJson(Map<String, dynamic> j) => FoodSuggestion(
        kind: j['kind'] as String,
        id: j['id'] as String,
        name: j['name'] as String,
        portionG: _d(j['portion_g']),
      );
}
