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

    // 字段类型必须显式校验：直接 as String? 遇到数字/对象会抛 TypeError，
    // 登录页只能把「type 'int' is not a subtype of type 'String?'」原样丢给用户。
    final rawBaseUrl = decoded['base_url'];
    final rawToken = decoded['token'];
    if (rawBaseUrl is! String || rawBaseUrl.trim().isEmpty) {
      throw const FoxelApiException('二维码缺少 base_url');
    }
    if (rawToken is! String || rawToken.trim().isEmpty) {
      throw const FoxelApiException('二维码缺少 token');
    }

    return QrLoginPayload(
      baseUrl: rawBaseUrl.trim(),
      token: rawToken.trim(),
    );
  }
}
