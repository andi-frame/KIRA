// Model keluarga, ringkasan dokter, dan wawasan gula darah (Fase 2).

class FamilyPermissions {
  const FamilyPermissions({this.checkinStatus = true, this.checkReminders = true});
  final bool checkinStatus, checkReminders;

  factory FamilyPermissions.fromJson(Map<String, dynamic> j) => FamilyPermissions(
        checkinStatus: j['checkin_status'] as bool? ?? true,
        checkReminders: j['check_reminders'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {'checkin_status': checkinStatus, 'check_reminders': checkReminders};

  FamilyPermissions copyWith({bool? checkinStatus, bool? checkReminders}) => FamilyPermissions(
        checkinStatus: checkinStatus ?? this.checkinStatus,
        checkReminders: checkReminders ?? this.checkReminders,
      );
}

class FamilyMember {
  const FamilyMember({required this.id, required this.phone, required this.status, required this.permissions});
  final String id, phone, status;
  final FamilyPermissions permissions;

  bool get isActive => status == 'active';

  factory FamilyMember.fromJson(Map<String, dynamic> j) => FamilyMember(
        id: j['id'] as String,
        phone: j['member_phone'] as String,
        status: j['status'] as String,
        permissions: FamilyPermissions.fromJson(j['permissions'] as Map<String, dynamic>),
      );
}

class FamilyContact {
  const FamilyContact({required this.id, required this.ownerName, required this.permissions});
  final String id, ownerName;
  final FamilyPermissions permissions;

  factory FamilyContact.fromJson(Map<String, dynamic> j) => FamilyContact(
        id: j['id'] as String,
        ownerName: j['owner_name'] as String,
        permissions: FamilyPermissions.fromJson(j['permissions'] as Map<String, dynamic>),
      );
}

class FamilyOverview {
  const FamilyOverview({this.members = const [], this.invitesForMe = const [], this.watching = const []});
  final List<FamilyMember> members;
  final List<FamilyContact> invitesForMe, watching;

  factory FamilyOverview.fromJson(Map<String, dynamic> j) => FamilyOverview(
        members: (j['members'] as List).map((e) => FamilyMember.fromJson(e as Map<String, dynamic>)).toList(),
        invitesForMe:
            (j['invites_for_me'] as List).map((e) => FamilyContact.fromJson(e as Map<String, dynamic>)).toList(),
        watching: (j['watching'] as List).map((e) => FamilyContact.fromJson(e as Map<String, dynamic>)).toList(),
      );
}

/// Ringkasan yang dibagikan pemilik. Bagian yang tidak diizinkan tidak dibagikan (flag false).
class FamilyStatus {
  const FamilyStatus({
    required this.ownerName,
    this.checkinShared = false,
    this.daysAgo,
    this.suggestion,
    this.remindersShared = false,
    this.hasOpenCheck,
  });

  final String ownerName;
  final bool checkinShared, remindersShared;
  final int? daysAgo;
  final String? suggestion;
  final bool? hasOpenCheck;

  factory FamilyStatus.fromJson(Map<String, dynamic> j) {
    final c = j['checkin_status'] as Map<String, dynamic>?;
    final r = j['check_reminders'] as Map<String, dynamic>?;
    return FamilyStatus(
      ownerName: j['owner_name'] as String,
      checkinShared: c != null,
      daysAgo: (c?['last_checkin_days_ago'] as num?)?.toInt(),
      suggestion: c?['suggestion'] as String?,
      remindersShared: r != null,
      hasOpenCheck: r?['has_open_check'] as bool?,
    );
  }
}

class DoctorSummary {
  const DoctorSummary({required this.text, required this.periodDays, required this.daysLogged});
  final String text;
  final int periodDays, daysLogged;

  factory DoctorSummary.fromJson(Map<String, dynamic> j) => DoctorSummary(
        text: j['text'] as String,
        periodDays: (j['period_days'] as num).toInt(),
        daysLogged: ((j['habits'] as Map<String, dynamic>)['days_logged'] as num).toInt(),
      );
}

class FoodGlucoseEntry {
  const FoodGlucoseEntry({required this.name, required this.samples, required this.avgMgDl});
  final String name;
  final int samples, avgMgDl;
}

class FoodGlucose {
  const FoodGlucose({this.foods = const [], this.needsMoreData = true, this.totalReadings = 0, this.disclaimer = ''});
  final List<FoodGlucoseEntry> foods;
  final bool needsMoreData;
  final int totalReadings;
  final String disclaimer;

  factory FoodGlucose.fromJson(Map<String, dynamic> j) => FoodGlucose(
        foods: (j['foods'] as List)
            .map((e) => FoodGlucoseEntry(
                  name: e['name'] as String,
                  samples: (e['samples'] as num).toInt(),
                  avgMgDl: (e['avg_mg_dl'] as num).toInt(),
                ))
            .toList(),
        needsMoreData: j['needs_more_data'] as bool,
        totalReadings: (j['total_readings'] as num).toInt(),
        disclaimer: j['disclaimer'] as String,
      );
}
