import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:foxel/core/models/license_info.dart';

class LicenseApi {
  static final _verifyUri = Uri.parse('https://foxel.cc/api/license/verify');

  Future<LicenseInfo> verify({
    required String appAddress,
    required String licenseKey,
  }) async {
    try {
      final response = await http
          .post(
            _verifyUri,
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'appAddress': appAddress,
              'licenseKey': licenseKey,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        return LicenseInfo.failed(
          licenseKey: licenseKey,
          appAddress: appAddress,
          error: '验证请求失败：${response.statusCode}',
        );
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        return LicenseInfo.failed(
          licenseKey: licenseKey,
          appAddress: appAddress,
          error: '验证响应格式不正确',
        );
      }
      return LicenseInfo.fromJson(
        decoded,
        licenseKey: licenseKey,
        appAddress: appAddress,
      );
    } catch (error) {
      return LicenseInfo.failed(
        licenseKey: licenseKey,
        appAddress: appAddress,
        error: error.toString(),
      );
    }
  }
}
