class LicenseInfo {
  const LicenseInfo({
    required this.licenseKey,
    required this.appAddress,
    required this.valid,
    required this.status,
    this.plan,
    this.expiresAt,
    this.verifiedAt,
    this.error,
  });

  factory LicenseInfo.fromJson(
    Map<String, dynamic> json, {
    required String licenseKey,
    required String appAddress,
  }) {
    return LicenseInfo(
      licenseKey: licenseKey,
      appAddress: appAddress,
      valid: json['valid'] as bool? ?? false,
      status: json['status'] as String? ?? 'unknown',
      plan: json['plan'] as String?,
      expiresAt: (json['expiresAt'] as num?)?.toInt(),
      verifiedAt: DateTime.now().millisecondsSinceEpoch,
    );
  }

  factory LicenseInfo.failed({
    required String licenseKey,
    required String appAddress,
    required String error,
  }) {
    return LicenseInfo(
      licenseKey: licenseKey,
      appAddress: appAddress,
      valid: false,
      status: 'verify_failed',
      verifiedAt: DateTime.now().millisecondsSinceEpoch,
      error: error,
    );
  }

  final String licenseKey;
  final String appAddress;
  final bool valid;
  final String status;
  final String? plan;
  final int? expiresAt;
  final int? verifiedAt;
  final String? error;

  bool get isPro {
    if (!valid || status != 'active') {
      return false;
    }
    final expires = expiresAt;
    return expires == null || expires > DateTime.now().millisecondsSinceEpoch;
  }
}
