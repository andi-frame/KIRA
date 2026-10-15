/// Sepasang token login: akses (singkat) dan penyegar (panjang, berputar tiap dipakai).
class AuthTokens {
  const AuthTokens(this.access, [this.refresh]);
  final String access;
  final String? refresh;

  factory AuthTokens.fromJson(Map<String, dynamic> j) =>
      AuthTokens(j['access_token'] as String, j['refresh_token'] as String?);
}

/// Satu catatan siapa yang membuka ringkasan pemilik data.
class AccessEntry {
  const AccessEntry({required this.kind, required this.viewer, required this.at, this.detail});
  final String kind; // family_status | share_link
  final String viewer;
  final String? detail;
  final DateTime at;

  bool get isShareLink => kind == 'share_link';

  factory AccessEntry.fromJson(Map<String, dynamic> j) => AccessEntry(
        kind: j['kind'] as String,
        viewer: j['viewer'] as String,
        detail: j['detail'] as String?,
        at: DateTime.parse(j['at'] as String).toLocal(),
      );
}

/// Tautan ringkasan untuk dokter. `url` hanya ada tepat setelah dibuat (token tidak disimpan di server).
class ShareLinkData {
  const ShareLinkData({
    required this.id,
    required this.days,
    required this.expiresAt,
    this.revoked = false,
    this.expired = false,
    this.openCount = 0,
    this.lastOpenedAt,
    this.url,
    this.pdfUrl,
  });

  final String id;
  final int days;
  final DateTime expiresAt;
  final bool revoked, expired;
  final int openCount;
  final DateTime? lastOpenedAt;
  final String? url, pdfUrl;

  bool get active => !revoked && !expired;

  factory ShareLinkData.fromJson(Map<String, dynamic> j) => ShareLinkData(
        id: j['id'] as String,
        days: (j['days'] as num).toInt(),
        expiresAt: DateTime.parse(j['expires_at'] as String).toLocal(),
        revoked: j['revoked'] as bool? ?? false,
        expired: j['expired'] as bool? ?? false,
        openCount: (j['open_count'] as num?)?.toInt() ?? 0,
        lastOpenedAt: j['last_opened_at'] == null ? null : DateTime.parse(j['last_opened_at'] as String).toLocal(),
        url: j['url'] as String?,
        pdfUrl: j['pdf_url'] as String?,
      );
}
