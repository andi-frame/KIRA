import 'meal_models.dart';

export 'dashboard_models.dart';
export 'meal_models.dart';
export 'plan_models.dart';

double? _d(Object? v) => v is num ? v.toDouble() : null;
List<double> _dl(Object? v) => (v as List? ?? const []).map((e) => (e as num).toDouble()).toList();

class Profile {
  const Profile({
    this.displayName,
    this.username,
    this.birthDate,
    this.sex,
    this.heightCm,
    this.weightKg,
    this.waistCm,
    this.familyHistoryDiabetes,
    this.mode = 'prevention',
    this.age,
    this.consented = true,
  });

  final String? displayName;
  final String? username;
  final String? birthDate;
  final String? sex;
  final double? heightCm;
  final double? weightKg;
  final double? waistCm;
  final String? familyHistoryDiabetes;
  final String mode;
  final int? age;
  final bool consented; // sudah menyetujui teks persetujuan versi yang berlaku

  bool get isComplete => birthDate != null && sex != null && heightCm != null && weightKg != null;
  bool get isManagement => mode == 'management';

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        displayName: j['display_name'] as String?,
        username: j['username'] as String?,
        birthDate: j['birth_date'] as String?,
        sex: j['sex'] as String?,
        heightCm: _d(j['height_cm']),
        weightKg: _d(j['weight_kg']),
        waistCm: _d(j['waist_cm']),
        familyHistoryDiabetes: j['family_history_diabetes'] as String?,
        mode: (j['mode'] as String?) ?? 'prevention',
        age: (j['age'] as num?)?.toInt(),
        consented: j['consented'] as bool? ?? true,
      );
}

class FoodEntry {
  const FoodEntry({required this.name, this.portionText, this.portionG});
  final String name;
  final String? portionText;
  final double? portionG;
}

/// Isi tabel informasi nilai gizi di kemasan, sebagaimana terbaca dari foto (angka tercetak, bukan estimasi).
class LabelEntry {
  const LabelEntry({
    required this.productName,
    this.isDrink = false,
    this.perServing = true,
    this.servingG,
    this.servings = 1,
    this.sugarG,
    this.sodiumMg,
    this.fatG,
    this.kcal,
  });

  final String productName;
  final bool isDrink, perServing;
  final double? servingG, sugarG, sodiumMg, fatG, kcal;
  final double servings;

  factory LabelEntry.fromJson(Map<String, dynamic> j) => LabelEntry(
        productName: j['product_name'] as String,
        isDrink: j['is_drink'] as bool? ?? false,
        perServing: (j['basis'] as String?) != 'per_100g',
        servingG: _d(j['serving_g']),
        servings: _d(j['servings_consumed']) ?? 1,
        sugarG: _d(j['sugar_g']),
        sodiumMg: _d(j['sodium_mg']),
        fatG: _d(j['fat_g']),
        kcal: _d(j['kcal']),
      );
}

/// Hasil ekstraksi yang ditampilkan sebagai kartu yang bisa dikoreksi.
class ExtractionData {
  const ExtractionData({
    this.items = const [],
    this.drinks = const [],
    this.sleepBed,
    this.sleepWake,
    this.activities = const [],
    this.label,
    this.intent = 'log',
  });

  final LabelEntry? label;
  final List<FoodEntry> items;
  final List<String> drinks;
  final String? sleepBed;
  final String? sleepWake;
  final List<String> activities;
  final String intent;

  bool get isEmpty =>
      items.isEmpty && drinks.isEmpty && sleepBed == null && sleepWake == null && activities.isEmpty && label == null;

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
      label: j['label'] == null ? null : LabelEntry.fromJson(j['label'] as Map<String, dynamic>),
      intent: (j['intent'] as String?) ?? 'log',
    );
  }
}

/// Satu pemanggilan tool oleh KIRA: nama, argumen, dan hasil yang dikembalikan fungsi deterministik.
class ToolCall {
  const ToolCall({required this.name, this.args = const {}, this.result});
  final String name;
  final Map<String, dynamic> args;
  final Object? result;

  Map<String, dynamic> get resultMap => result is Map ? Map<String, dynamic>.from(result as Map) : const {};

  factory ToolCall.fromJson(Map<String, dynamic> j) => ToolCall(
        name: j['name'] as String,
        args: Map<String, dynamic>.from(j['args'] as Map? ?? const {}),
        result: j['result'],
      );
}

class ChatReply {
  const ChatReply({
    required this.reply,
    this.extraction,
    this.redFlag,
    this.logIds = const [],
    this.toolCalls = const [],
    this.transcript,
    this.meals = const [],
  });

  final String reply;
  final ExtractionData? extraction;
  final String? redFlag;
  final List<String> logIds;
  final List<ToolCall> toolCalls;
  final String? transcript;

  /// Catatan makan dari pesan ini beserta item dan gizinya (kartu "Yang kucatat").
  final List<MealLog> meals;

  factory ChatReply.fromJson(Map<String, dynamic> j) => ChatReply(
        reply: j['reply'] as String,
        extraction: j['extraction'] == null ? null : ExtractionData.fromJson(j['extraction'] as Map<String, dynamic>),
        redFlag: j['red_flag'] as String?,
        logIds: (j['log_ids'] as List? ?? const []).cast<String>(),
        toolCalls: (j['tool_calls'] as List? ?? const []).map((e) => ToolCall.fromJson(e as Map<String, dynamic>)).toList(),
        transcript: j['transcript'] as String?,
        meals: (j['meals'] as List? ?? const []).map((e) => MealLog.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

/// Risiko hipertensi 4 tahun (skor Framingham). status: ok, needs_bp, needs_profile, already_hypertensive,
/// out_of_age_range, has_diabetes.
class HypertensionRisk {
  const HypertensionRisk({
    required this.status,
    this.riskLow,
    this.riskHigh,
    this.categoryLow,
    this.categoryHigh,
    this.sys,
    this.dia,
  });

  final String status;
  final double? riskLow, riskHigh;
  final String? categoryLow, categoryHigh;
  final int? sys, dia;

  factory HypertensionRisk.fromJson(Map<String, dynamic>? j) {
    if (j == null) return const HypertensionRisk(status: 'needs_bp');
    final bp = j['last_bp'] as Map<String, dynamic>?;
    return HypertensionRisk(
      status: j['status'] as String,
      riskLow: _d(j['risk_low']),
      riskHigh: _d(j['risk_high']),
      categoryLow: j['category_low'] as String?,
      categoryHigh: j['category_high'] as String?,
      sys: (bp?['sys'] as num?)?.toInt(),
      dia: (bp?['dia'] as num?)?.toInt(),
    );
  }
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
    this.hypertension = const HypertensionRisk(status: 'needs_bp'),
  });

  final HypertensionRisk hypertension;
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
        hypertension: HypertensionRisk.fromJson(j['hypertension'] as Map<String, dynamic>?),
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
  const CheckRecommendation({
    required this.id,
    required this.testKind,
    required this.reason,
    this.followUp = false,
    this.ageDays = 0,
  });
  final String id, testKind, reason;

  /// Sudah beberapa hari sejak rekomendasi muncul: saatnya bertanya "sudah dicek?".
  final bool followUp;
  final int ageDays;

  String get label => testKind == 'fasting_glucose' ? 'Cek gula darah puasa' : 'Cek tekanan darah';

  factory CheckRecommendation.fromJson(Map<String, dynamic> j) => CheckRecommendation(
        id: j['id'] as String,
        testKind: j['test_kind'] as String,
        reason: j['reason'] as String,
        followUp: j['follow_up'] as bool? ?? false,
        ageDays: (j['age_days'] as num?)?.toInt() ?? 0,
      );
}

class Faskes {
  const Faskes({
    required this.name,
    required this.kind,
    required this.distanceKm,
    this.address,
    this.lat,
    this.lng,
    this.source = 'seed',
    this.phone,
    this.openingHours,
    this.directionsUrl,
    this.mapsUrl,
  });
  final String name, kind;
  final double distanceKm;
  final String? address;
  final double? lat, lng;

  /// google | osm | seed (data contoh). Menentukan keterangan sumber di bawah daftar.
  final String source;
  final String? phone, openingHours;

  /// Tautan Google Maps: rute ke tempat itu, dan tempatnya.
  final String? directionsUrl, mapsUrl;

  /// Rute di Google Maps; dibuat dari koordinat bila server tidak mengirim tautan.
  String? get routeUrl => directionsUrl ??
      (lat == null || lng == null ? null : 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving');

  factory Faskes.fromJson(Map<String, dynamic> j) => Faskes(
        name: j['name'] as String,
        kind: j['kind'] as String,
        distanceKm: (j['distance_km'] as num).toDouble(),
        address: j['address'] as String?,
        lat: (j['lat'] as num?)?.toDouble(),
        lng: (j['lng'] as num?)?.toDouble(),
        source: (j['source'] as String?) ?? 'seed',
        phone: j['phone'] as String?,
        openingHours: j['opening_hours'] as String?,
        directionsUrl: j['directions_url'] as String?,
        mapsUrl: j['maps_url'] as String?,
      );
}

class ResultOutcome {
  const ResultOutcome({required this.saved, this.redFlagMessage, this.bpCategory, this.hrRange, this.projection});
  final bool saved;
  final String? redFlagMessage;
  final String? bpCategory;

  /// Untuk detak jantung istirahat: below_range (< 60) | normal_range (60-100) | above_range (> 100).
  final String? hrRange;
  final Projection? projection;

  factory ResultOutcome.fromJson(Map<String, dynamic> j) => ResultOutcome(
        saved: j['saved'] as bool,
        redFlagMessage: (j['red_flag'] as Map<String, dynamic>?)?['message'] as String?,
        bpCategory: j['bp_category'] as String?,
        hrRange: j['hr_range'] as String?,
        projection: j['projection'] == null ? null : Projection.fromJson(j['projection'] as Map<String, dynamic>),
      );
}
