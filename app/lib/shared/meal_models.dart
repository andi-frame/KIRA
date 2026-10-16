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

/// Waktu makan dan labelnya. Urutan = urutan di sepanjang hari.
const mealSlots = ['breakfast', 'lunch', 'snack', 'dinner'];
const mealSlotLabels = {'breakfast': 'Sarapan', 'lunch': 'Makan siang', 'snack': 'Selingan', 'dinner': 'Makan malam'};

class MealLog {
  const MealLog({
    required this.id,
    this.kind = 'meal',
    this.source = 'text',
    this.occurredAt,
    this.corrected = false,
    this.items = const [],
    this.mealSlot,
    this.slotConfirmed = true,
    this.halvedGroups = const [],
  });

  final String id;
  final String kind;
  final String source;
  final DateTime? occurredAt;
  final bool corrected;
  final List<LoggedItem> items;

  /// breakfast | lunch | snack | dinner untuk catatan makan; null pada minuman dan catatan lama.
  final String? mealSlot;

  /// false: waktu makan hanya ditebak dari jam, jadi pengguna diminta memastikan.
  final bool slotConfirmed;

  /// Hidangan yang sedang "setengah porsi": tombolnya berubah menjadi "Porsi biasa" (saklar, bukan pengurang berulang).
  final List<String> halvedGroups;

  bool isHalved(String group) => halvedGroups.contains(group);
  bool get needsSlotConfirmation => kind == 'meal' && !slotConfirmed;

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
        mealSlot: j['meal_slot'] as String?,
        slotConfirmed: (j['slot_confirmed'] as bool?) ?? true,
        halvedGroups: (j['halved_groups'] as List? ?? const []).cast<String>(),
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

/// Batas harian gula/natrium/lemak sesuai mode pengguna (pencegahan atau pengelolaan).
class DailyLimits {
  const DailyLimits({this.sugarG = 50, this.sodiumMg = 2000, this.fatG = 67});
  final double sugarG;
  final double sodiumMg;
  final double fatG;

  factory DailyLimits.fromJson(Map<String, dynamic> j) => DailyLimits(
        sugarG: _d(j['sugar_g']) ?? 50,
        sodiumMg: _d(j['sodium_mg']) ?? 2000,
        fatG: _d(j['fat_g']) ?? 67,
      );
}

/// Satu catatan makan/minum di Riwayat.
class HistoryEntry {
  const HistoryEntry({
    required this.logId,
    required this.kind,
    required this.time,
    required this.source,
    required this.title,
    this.items = const [],
    this.totals = const NutrientTotals(),
    this.uncounted = 0,
    this.corrected = false,
    this.mealSlot,
    this.slotConfirmed = true,
    this.halvedGroups = const [],
  });

  final String logId;
  final String kind; // meal | drink
  final DateTime time;
  final String source;
  final String title;
  final List<LoggedItem> items;
  final NutrientTotals totals;
  final int uncounted;
  final bool corrected;
  final String? mealSlot;
  final bool slotConfirmed;
  final List<String> halvedGroups;

  MealLog get asMeal => MealLog(
        id: logId,
        kind: kind,
        source: source,
        occurredAt: time,
        corrected: corrected,
        items: items,
        mealSlot: mealSlot,
        slotConfirmed: slotConfirmed,
        halvedGroups: halvedGroups,
      );

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        logId: j['log_id'] as String,
        kind: j['kind'] as String,
        time: DateTime.parse(j['time'] as String),
        source: j['source'] as String,
        title: j['title'] as String,
        items: (j['items'] as List? ?? const []).map((e) => LoggedItem.fromJson(e as Map<String, dynamic>)).toList(),
        totals: NutrientTotals.fromJson(j['totals'] as Map<String, dynamic>),
        uncounted: (j['uncounted'] as int?) ?? 0,
        corrected: (j['corrected'] as bool?) ?? false,
        mealSlot: j['meal_slot'] as String?,
        slotConfirmed: (j['slot_confirmed'] as bool?) ?? true,
        halvedGroups: (j['halved_groups'] as List? ?? const []).cast<String>(),
      );
}

/// Satu catatan olahraga/aktivitas di Riwayat (bisa diubah atau dihapus).
class HistoryActivity {
  const HistoryActivity({required this.logId, required this.kind, required this.minutes, required this.time, this.source = 'text'});
  final String logId;
  final String kind;
  final double minutes;
  final DateTime time;
  final String source;

  factory HistoryActivity.fromJson(Map<String, dynamic> j) => HistoryActivity(
        logId: j['log_id'] as String,
        kind: (j['kind'] as String?) ?? 'aktivitas',
        minutes: (_d(j['minutes']) ?? 0),
        time: DateTime.parse(j['time'] as String),
        source: (j['source'] as String?) ?? 'text',
      );
}

/// Satu catatan tidur di Riwayat (bisa diubah atau dihapus).
class HistorySleep {
  const HistorySleep({required this.logId, required this.time, this.hours, this.bedTime, this.wakeTime, this.source = 'text'});
  final String logId;
  final DateTime time;
  final double? hours;
  final String? bedTime;
  final String? wakeTime;
  final String source;

  factory HistorySleep.fromJson(Map<String, dynamic> j) => HistorySleep(
        logId: j['log_id'] as String,
        time: DateTime.parse(j['time'] as String),
        hours: _d(j['hours']),
        bedTime: j['bed_time'] as String?,
        wakeTime: j['wake_time'] as String?,
        source: (j['source'] as String?) ?? 'text',
      );
}

class HistoryDay {
  const HistoryDay({
    required this.date,
    required this.logged,
    this.totals = const NutrientTotals(),
    this.limits = const DailyLimits(),
    this.meals = const [],
    this.drinks = const [],
    this.activityMinutes,
    this.sleepHours,
    this.activities = const [],
    this.sleeps = const [],
  });

  final DateTime date;
  final bool logged;
  final NutrientTotals totals;
  final DailyLimits limits;
  final List<HistoryEntry> meals;
  final List<HistoryEntry> drinks;
  final double? activityMinutes;
  final double? sleepHours;
  final List<HistoryActivity> activities;
  final List<HistorySleep> sleeps;

  /// Makan dan minum hari ini, urut waktu.
  List<HistoryEntry> get entries => [...meals, ...drinks]..sort((a, b) => a.time.compareTo(b.time));

  factory HistoryDay.fromJson(Map<String, dynamic> j) => HistoryDay(
        date: DateTime.parse(j['date'] as String),
        logged: j['logged'] as bool,
        totals: NutrientTotals.fromJson(j['totals'] as Map<String, dynamic>),
        limits: DailyLimits.fromJson(j['limits'] as Map<String, dynamic>),
        meals: (j['meals'] as List? ?? const []).map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>)).toList(),
        drinks: (j['drinks'] as List? ?? const []).map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>)).toList(),
        activityMinutes: _d(j['activity_minutes']),
        sleepHours: _d(j['sleep_hours']),
        activities:
            (j['activities'] as List? ?? const []).map((e) => HistoryActivity.fromJson(e as Map<String, dynamic>)).toList(),
        sleeps: (j['sleeps'] as List? ?? const []).map((e) => HistorySleep.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

class HistoryPage {
  const HistoryPage({required this.days, required this.nextBefore});
  final List<HistoryDay> days; // terbaru dulu
  final String nextBefore;

  factory HistoryPage.fromJson(Map<String, dynamic> j) => HistoryPage(
        days: (j['days'] as List).map((e) => HistoryDay.fromJson(e as Map<String, dynamic>)).toList(),
        nextBefore: j['next_before'] as String,
      );
}
