double? _d(Object? v) => v is num ? v.toDouble() : null;
List<double> _dl(Object? v) => (v as List? ?? const []).map((e) => (e as num).toDouble()).toList();

class Profile {
  const Profile({
    this.displayName,
    this.birthDate,
    this.sex,
    this.heightCm,
    this.weightKg,
    this.waistCm,
    this.familyHistoryDiabetes,
    this.mode = 'prevention',
    this.age,
  });

  final String? displayName;
  final String? birthDate;
  final String? sex;
  final double? heightCm;
  final double? weightKg;
  final double? waistCm;
  final String? familyHistoryDiabetes;
  final String mode;
  final int? age;

  bool get isComplete => birthDate != null && sex != null && heightCm != null && weightKg != null;
  bool get isManagement => mode == 'management';

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        displayName: j['display_name'] as String?,
        birthDate: j['birth_date'] as String?,
        sex: j['sex'] as String?,
        heightCm: _d(j['height_cm']),
        weightKg: _d(j['weight_kg']),
        waistCm: _d(j['waist_cm']),
        familyHistoryDiabetes: j['family_history_diabetes'] as String?,
        mode: (j['mode'] as String?) ?? 'prevention',
        age: (j['age'] as num?)?.toInt(),
      );
}

class FoodEntry {
  const FoodEntry({required this.name, this.portionText, this.portionG});
  final String name;
  final String? portionText;
  final double? portionG;
}

/// Hasil ekstraksi yang ditampilkan sebagai kartu yang bisa dikoreksi.
class ExtractionData {
  const ExtractionData({
    this.items = const [],
    this.drinks = const [],
    this.sleepBed,
    this.sleepWake,
    this.activities = const [],
    this.intent = 'log',
  });

  final List<FoodEntry> items;
  final List<String> drinks;
  final String? sleepBed;
  final String? sleepWake;
  final List<String> activities;
  final String intent;

  bool get isEmpty => items.isEmpty && drinks.isEmpty && sleepBed == null && sleepWake == null && activities.isEmpty;

  factory ExtractionData.fromJson(Map<String, dynamic> j) {
    final sleep = j['sleep'] as Map<String, dynamic>?;
    return ExtractionData(
      items: (j['items'] as List? ?? const [])
          .map((e) => FoodEntry(
                name: e['name'] as String,
                portionText: e['portion_text'] as String?,
                portionG: _d(e['portion_g_guess']),
              ))
          .toList(),
      drinks: (j['drinks'] as List? ?? const []).map((e) => e['name'] as String).toList(),
      sleepBed: sleep?['bed_time'] as String?,
      sleepWake: sleep?['wake_time'] as String?,
      activities: (j['activity'] as List? ?? const []).map((e) => '${e['kind']} ${e['minutes']} menit').toList(),
      intent: (j['intent'] as String?) ?? 'log',
    );
  }
}

class ChatReply {
  const ChatReply({
    required this.reply,
    this.extraction,
    this.redFlag,
    this.logIds = const [],
    this.toolNames = const [],
    this.transcript,
  });

  final String reply;
  final ExtractionData? extraction;
  final String? redFlag;
  final List<String> logIds;
  final List<String> toolNames;
  final String? transcript;

  factory ChatReply.fromJson(Map<String, dynamic> j) => ChatReply(
        reply: j['reply'] as String,
        extraction: j['extraction'] == null ? null : ExtractionData.fromJson(j['extraction'] as Map<String, dynamic>),
        redFlag: j['red_flag'] as String?,
        logIds: (j['log_ids'] as List? ?? const []).cast<String>(),
        toolNames: (j['tool_calls'] as List? ?? const []).map((e) => e['name'] as String).toList(),
        transcript: j['transcript'] as String?,
      );
}

class Projection {
  const Projection({
    required this.scoreLow,
    required this.scoreHigh,
    required this.categoryLow,
    required this.categoryHigh,
    required this.p10Low,
    required this.p10High,
    required this.curveLow,
    required this.curveHigh,
    required this.needsProfile,
    required this.mode,
    this.bpCategory,
    this.mostImpactful,
  });

  final int scoreLow, scoreHigh;
  final String categoryLow, categoryHigh;
  final double p10Low, p10High;
  final List<double> curveLow, curveHigh;
  final bool needsProfile;
  final String mode;
  final String? bpCategory;
  final String? mostImpactful;

  int get spread => scoreHigh - scoreLow;

  factory Projection.fromJson(Map<String, dynamic> j) => Projection(
        scoreLow: (j['score_low'] as num).toInt(),
        scoreHigh: (j['score_high'] as num).toInt(),
        categoryLow: j['category_low'] as String,
        categoryHigh: j['category_high'] as String,
        p10Low: (j['p10_low'] as num).toDouble(),
        p10High: (j['p10_high'] as num).toDouble(),
        curveLow: _dl(j['curve_low']),
        curveHigh: _dl(j['curve_high']),
        needsProfile: j['needs_profile'] as bool? ?? false,
        mode: (j['mode'] as String?) ?? 'prevention',
        bpCategory: j['bp_category'] as String?,
        mostImpactful: j['most_impactful'] as String?,
      );
}

class WhatIfChange {
  const WhatIfChange({
    this.active30min,
    this.dailyVegFruit,
    this.weightDeltaKg,
    this.sweetDrinksDeltaPerDay = 0,
  });

  final bool? active30min;
  final bool? dailyVegFruit;
  final double? weightDeltaKg;
  final double sweetDrinksDeltaPerDay;

  bool get isEmpty =>
      active30min == null && dailyVegFruit == null && (weightDeltaKg == null || weightDeltaKg == 0) && sweetDrinksDeltaPerDay == 0;

  Map<String, dynamic> toJson() => {
        if (active30min != null) 'active_30min': active30min,
        if (dailyVegFruit != null) 'daily_veg_fruit': dailyVegFruit,
        if (weightDeltaKg != null && weightDeltaKg != 0) 'weight_delta_kg': weightDeltaKg,
        'sweet_drinks_delta_per_day': sweetDrinksDeltaPerDay,
      };

  WhatIfChange copyWith({bool? active30min, bool? dailyVegFruit, double? weightDeltaKg, double? sweetDrinksDeltaPerDay}) =>
      WhatIfChange(
        active30min: active30min ?? this.active30min,
        dailyVegFruit: dailyVegFruit ?? this.dailyVegFruit,
        weightDeltaKg: weightDeltaKg ?? this.weightDeltaKg,
        sweetDrinksDeltaPerDay: sweetDrinksDeltaPerDay ?? this.sweetDrinksDeltaPerDay,
      );
}

class WhatIfResult {
  const WhatIfResult({
    required this.beforeLow,
    required this.beforeHigh,
    required this.afterLow,
    required this.afterHigh,
    required this.curveAfterLow,
    required this.curveAfterHigh,
    required this.sugarBefore,
    required this.sugarAfter,
    required this.mostImpactful,
  });

  final int beforeLow, beforeHigh, afterLow, afterHigh;
  final List<double> curveAfterLow, curveAfterHigh;
  final double sugarBefore, sugarAfter;
  final String mostImpactful;

  factory WhatIfResult.fromJson(Map<String, dynamic> j) => WhatIfResult(
        beforeLow: (j['before']['low'] as num).toInt(),
        beforeHigh: (j['before']['high'] as num).toInt(),
        afterLow: (j['after']['low'] as num).toInt(),
        afterHigh: (j['after']['high'] as num).toInt(),
        curveAfterLow: _dl(j['curve_after_low']),
        curveAfterHigh: _dl(j['curve_after_high']),
        sugarBefore: (j['sugar_g_before'] as num).toDouble(),
        sugarAfter: (j['sugar_g_after'] as num).toDouble(),
        mostImpactful: j['most_impactful'] as String,
      );
}

class CheckRecommendation {
  const CheckRecommendation({required this.id, required this.testKind, required this.reason});
  final String id, testKind, reason;

  String get label => testKind == 'fasting_glucose' ? 'Cek gula darah puasa' : 'Cek tekanan darah';

  factory CheckRecommendation.fromJson(Map<String, dynamic> j) => CheckRecommendation(
        id: j['id'] as String,
        testKind: j['test_kind'] as String,
        reason: j['reason'] as String,
      );
}

class Faskes {
  const Faskes({required this.name, required this.kind, required this.distanceKm, this.address});
  final String name, kind;
  final double distanceKm;
  final String? address;

  factory Faskes.fromJson(Map<String, dynamic> j) => Faskes(
        name: j['name'] as String,
        kind: j['kind'] as String,
        distanceKm: (j['distance_km'] as num).toDouble(),
        address: j['address'] as String?,
      );
}

class ResultOutcome {
  const ResultOutcome({required this.saved, this.redFlagMessage, this.bpCategory, this.projection});
  final bool saved;
  final String? redFlagMessage;
  final String? bpCategory;
  final Projection? projection;

  factory ResultOutcome.fromJson(Map<String, dynamic> j) => ResultOutcome(
        saved: j['saved'] as bool,
        redFlagMessage: (j['red_flag'] as Map<String, dynamic>?)?['message'] as String?,
        bpCategory: j['bp_category'] as String?,
        projection: j['projection'] == null ? null : Projection.fromJson(j['projection'] as Map<String, dynamic>),
      );
}
