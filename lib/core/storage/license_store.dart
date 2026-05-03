import 'package:shared_preferences/shared_preferences.dart';

import 'package:foxel/core/models/license_info.dart';

class LicenseStore {
  static const _licenseKeyKey = 'foxel_license_key';
  static const _appAddressKey = 'foxel_license_app_address';
  static const _validKey = 'foxel_license_valid';
  static const _statusKey = 'foxel_license_status';
  static const _planKey = 'foxel_license_plan';
  static const _expiresAtKey = 'foxel_license_expires_at';
  static const _verifiedAtKey = 'foxel_license_verified_at';
  static const _errorKey = 'foxel_license_error';

  Future<LicenseInfo?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final licenseKey = prefs.getString(_licenseKeyKey);
    if (licenseKey == null || licenseKey.isEmpty) {
      return null;
    }
    return LicenseInfo(
      licenseKey: licenseKey,
      appAddress: prefs.getString(_appAddressKey) ?? '',
      valid: prefs.getBool(_validKey) ?? false,
      status: prefs.getString(_statusKey) ?? 'unverified',
      plan: prefs.getString(_planKey),
      expiresAt: prefs.getInt(_expiresAtKey),
      verifiedAt: prefs.getInt(_verifiedAtKey),
      error: prefs.getString(_errorKey),
    );
  }

  Future<void> save(LicenseInfo info) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_licenseKeyKey, info.licenseKey);
    await prefs.setString(_appAddressKey, info.appAddress);
    await prefs.setBool(_validKey, info.valid);
    await prefs.setString(_statusKey, info.status);
    await _setNullableString(prefs, _planKey, info.plan);
    await _setNullableInt(prefs, _expiresAtKey, info.expiresAt);
    await _setNullableInt(prefs, _verifiedAtKey, info.verifiedAt);
    await _setNullableString(prefs, _errorKey, info.error);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_licenseKeyKey);
    await prefs.remove(_appAddressKey);
    await prefs.remove(_validKey);
    await prefs.remove(_statusKey);
    await prefs.remove(_planKey);
    await prefs.remove(_expiresAtKey);
    await prefs.remove(_verifiedAtKey);
    await prefs.remove(_errorKey);
  }

  Future<void> _setNullableString(
    SharedPreferences prefs,
    String key,
    String? value,
  ) async {
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }

  Future<void> _setNullableInt(
    SharedPreferences prefs,
    String key,
    int? value,
  ) async {
    if (value == null) {
      await prefs.remove(key);
    } else {
      await prefs.setInt(key, value);
    }
  }
}
