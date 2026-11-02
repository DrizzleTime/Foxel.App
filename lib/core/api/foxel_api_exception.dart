/// 服务端 / 网络错误。
///
/// [statusCode] 为 null 表示非 HTTP 错误（如连接失败、超时）。
class FoxelApiException implements Exception {
  const FoxelApiException(this.message, {this.statusCode});

  final String message;

  /// HTTP 状态码；非 HTTP 错误（连不上、超时等）为 null。
  final int? statusCode;

  /// 是否为凭证类错误（未授权 / 禁止访问）。
  bool get isUnauthorized => statusCode == 401 || statusCode == 403;

  @override
  String toString() => message;
}
