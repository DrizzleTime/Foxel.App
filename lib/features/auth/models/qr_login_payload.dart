import 'dart:convert';

import 'package:foxel/core/api/foxel_api_exception.dart';

class QrLoginPayload {
  const QrLoginPayload({required this.baseUrl, required this.token});

  final String baseUrl;
  final String token;

  factory QrLoginPayload.parse(String rawValue) {
    final dynamic decoded;
    try {
      decoded = jsonDecode(rawValue);
    } catch (_) {
      throw const FoxelApiException('二维码内容不是合法 JSON');
    }
    if (decoded is! Map<String, dynamic>) {
      throw const FoxelApiException('二维码内容格式不正确');
    }

    final baseUrl = decoded['base_url'] as String?;
    final token = decoded['token'] as String?;
    if (baseUrl == null || baseUrl.trim().isEmpty) {
      throw const FoxelApiException('二维码缺少 base_url');
    }
    if (token == null || token.trim().isEmpty) {
      throw const FoxelApiException('二维码缺少 token');
    }

    return QrLoginPayload(baseUrl: baseUrl.trim(), token: token.trim());
  }
}
