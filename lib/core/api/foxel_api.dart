import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:foxel/core/api/foxel_api_exception.dart';
import 'package:foxel/core/api/transfer_cancel.dart';
import 'package:foxel/core/models/adapter_usage.dart';
import 'package:foxel/core/models/compression.dart';
import 'package:foxel/core/models/file_entry.dart';
import 'package:foxel/core/models/server_task.dart';
import 'package:foxel/core/models/session.dart';
import 'package:foxel/core/models/user_profile.dart';
import 'package:foxel/core/utils/path_utils.dart' as path_utils;

class FoxelApi {
  FoxelApi({required String baseUrl, String? token})
    : baseUrl = normalizeBaseUrl(baseUrl),
      token = token ?? '',
      _client = http.Client();

  final String baseUrl;
  String token;
  final http.Client _client;

  /// 普通请求超时。
  ///
  /// `http.Client` 不提供应用层超时：半开连接、服务端不响应时请求会长时间
  /// 挂起（取决于系统 TCP 超时），界面表现为永久 loading，切账户的遮罩也退不掉。
  static const Duration _requestTimeout = Duration(seconds: 20);

  /// 上传 / 下载的宽松超时：大文件首包可能较慢，但不能无限等。
  static const Duration _transferTimeout = Duration(seconds: 60);

  /// 给任意请求加上超时，并把 [TimeoutException] 换成用户能看懂的错误。
  Future<T> _withTimeout<T>(Future<T> future, {Duration? timeout}) async {
    try {
      return await future.timeout(timeout ?? _requestTimeout);
    } on TimeoutException {
      throw const FoxelApiException('请求超时：服务器没有响应，请检查网络或服务器地址');
    }
  }

  static String normalizeBaseUrl(String value) {
    var cleaned = value.trim();
    if (cleaned.isEmpty) {
      throw const FoxelApiException('请输入后端地址');
    }
    if (!cleaned.startsWith('http://') && !cleaned.startsWith('https://')) {
      cleaned = 'http://$cleaned';
    }
    cleaned = cleaned.replaceAll(RegExp(r'/+$'), '');
    if (cleaned.endsWith('/api')) {
      return cleaned;
    }
    return '$cleaned/api';
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$baseUrl$normalizedPath').replace(queryParameters: query);
  }

  Map<String, String> _headers({bool json = false}) {
    return {
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      if (json) 'Content-Type': 'application/json',
    };
  }

  Map<String, String> authHeaders() => _headers();

  Future<FoxelSession> login({
    required String username,
    required String password,
  }) async {
    final response = await _withTimeout(
      _client.post(
        _uri('/auth/login'),
        headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'username': username, 'password': password},
      ),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwHttpError(response);
    }
    final data = _decodeAny(response);
    final accessToken = data['access_token'] as String?;
    if (accessToken == null || accessToken.isEmpty) {
      throw const FoxelApiException('登录响应缺少 token');
    }
    token = accessToken;
    final profile = await _fetchProfile();
    return FoxelSession(
      baseUrl: baseUrl,
      username: profile.username.isEmpty ? username : profile.username,
      token: token,
      email: profile.email,
      avatarUrl: profile.avatarUrl,
    );
  }

  Future<UserProfile> me() => _fetchProfile();

  Future<UserProfile> _fetchProfile() async {
    final data = await _getJson('/auth/me');
    return UserProfile.fromJson(data);
  }

  Future<DirectoryListing> listRecentFiles({int pageSize = 6}) async {
    final data = await _getJson('/fs/recent', {
      'page': '1',
      'page_size': '$pageSize',
      'sort_by': 'mtime',
      'sort_order': 'desc',
    });
    return DirectoryListing.fromJson(data);
  }

  Future<DirectoryListing> listDirectory(String path) async {
    final cleaned = path_utils.cleanPath(path);
    final endpoint = cleaned == '/'
        ? '/fs/'
        : '/fs/${path_utils.encodePath(cleaned)}';
    final data = await _getJson(endpoint, {
      'page': '1',
      'page_size': '200',
      'sort_by': 'name',
      'sort_order': 'asc',
    });
    return DirectoryListing.fromJson(data);
  }

  Future<List<AdapterUsage>> adapterUsages() async {
    final data = await _getJsonList('/adapters/usage');
    return data
        .whereType<Map<String, dynamic>>()
        .map(AdapterUsage.fromJson)
        .toList();
  }

  /// 预览类读取的硬上限：超过这个尺寸不再整体拉进内存。
  ///
  /// 图片查看器走 [readFile]，用户点开一个几百 MB 的 TIFF 时，
  /// 整文件读进内存会直接把进程拖垮。
  static const int maxInMemoryBytes = 32 * 1024 * 1024;

  Future<Uint8List> readFile(String path) async {
    final request = http.Request(
      'GET',
      _uri('/fs/file/${path_utils.encodePath(path)}'),
    );
    request.headers.addAll(_headers());
    final response = await _withTimeout(
      _client.send(request),
      timeout: _transferTimeout,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.toBytes();
      _throwHttpError(http.Response.bytes(body, response.statusCode));
    }
    // 先看 Content-Length 决定收不收：超限直接丢弃响应流，不浪费内存和带宽。
    final length = response.contentLength;
    if (length != null && length > maxInMemoryBytes) {
      await response.stream.listen(null).cancel();
      throw const FoxelApiException('文件超过 32 MB，暂不支持直接预览');
    }
    final bytes = await response.stream.toBytes();
    if (bytes.length > maxInMemoryBytes) {
      // 服务端没给 Content-Length 时的兜底。
      throw const FoxelApiException('文件超过 32 MB，暂不支持直接预览');
    }
    return bytes;
  }

  Future<void> uploadFile({
    required String remotePath,
    required String localPath,
    void Function(int sent, int total)? onProgress,
    TransferCancelToken? cancelToken,
  }) async {
    final file = File(localPath);
    final total = await file.length();
    var sent = 0;
    onProgress?.call(0, total);

    final request = http.MultipartRequest(
      'POST',
      _uri('/fs/upload/${path_utils.encodePath(remotePath)}', {
        'overwrite': 'true',
      }),
    );
    request.headers.addAll(_headers());
    request.files.add(
      http.MultipartFile(
        'file',
        file.openRead().map((chunk) {
          // 协作式取消：上传途中也能中断。抛出后 http 包会终止请求，
          // 不再往服务端继续灌数据。
          if (cancelToken?.isCancelled ?? false) {
            throw TransferCancelledException(cancelToken?.reason ?? '传输已中断');
          }
          sent += chunk.length;
          onProgress?.call(sent, total);
          return chunk;
        }),
        total,
        filename: remotePath.split('/').where((item) => item.isNotEmpty).last,
      ),
    );
    final streamed = await _withTimeout(
      request.send(),
      timeout: _transferTimeout,
    );
    final response = await http.Response.fromStream(streamed);
    _decodeWrapped(response);
    onProgress?.call(total, total);
  }

  Future<void> downloadFile({
    required String remotePath,
    required File outputFile,
    void Function(int received, int? total)? onProgress,
    TransferCancelToken? cancelToken,
  }) async {
    final request = http.Request(
      'GET',
      _uri('/fs/file/${path_utils.encodePath(remotePath)}'),
    );
    request.headers.addAll(_headers());
    final response = await _withTimeout(
      _client.send(request),
      timeout: _transferTimeout,
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = await response.stream.toBytes();
      _throwHttpError(http.Response.bytes(body, response.statusCode));
    }

    // 先写同目录下的 .part 临时文件，全部收完再改名覆盖：
    // 中途失败不会破坏本地已存在的同名文件（旧实现会把它截断成半截）。
    final partFile = File('${outputFile.path}.part');
    try {
      if (await partFile.exists()) {
        await partFile.delete();
      }
      await outputFile.parent.create(recursive: true);
    } catch (_) {
      // 清理或建目录失败不在这里处理，下面的 openWrite 会抛出更明确的错误。
    }
    final sink = partFile.openWrite();
    var received = 0;
    final total = response.contentLength;
    onProgress?.call(0, total);
    try {
      // 逐个 chunk 设空闲超时：下载大文件可能很慢，但「60 秒没有任何数据」
      // 基本可以判定连接已经死了，不能无限挂着。
      await for (final chunk in response.stream.timeout(_transferTimeout)) {
        // 取消时直接跳出：`await for` 会取消订阅，catch 分支再删掉半截的 .part。
        if (cancelToken?.isCancelled ?? false) {
          throw TransferCancelledException(cancelToken?.reason ?? '传输已中断');
        }
        received += chunk.length;
        sink.add(chunk);
        onProgress?.call(received, total);
      }
      await sink.close();
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {
        // 关闭失败无所谓，下面会清理掉残缺文件。
      }
      // 失败时清掉本次产生的残缺文件，避免用户误以为下载成功。
      try {
        if (await partFile.exists()) {
          await partFile.delete();
        }
      } catch (_) {
        // 清理失败不影响抛出原始错误。
      }
      rethrow;
    }
    try {
      await partFile.rename(outputFile.path);
    } on FileSystemException {
      // 个别文件系统不支持「改名覆盖」：退化为先删目标再改名。
      if (await outputFile.exists()) {
        await outputFile.delete();
      }
      await partFile.rename(outputFile.path);
    }
    onProgress?.call(received, total);
  }

  Future<void> mkdir(String path) async {
    await _postJson('/fs/mkdir', {'path': path_utils.cleanPath(path)});
  }

  Future<void> rename({required String src, required String dst}) async {
    await _postJson('/fs/rename', {
      'src': path_utils.cleanPath(src),
      'dst': path_utils.cleanPath(dst),
    });
  }

  Future<void> copy({required String src, required String dst}) async {
    await _postJson('/fs/copy', {
      'src': path_utils.cleanPath(src),
      'dst': path_utils.cleanPath(dst),
    });
  }

  Future<void> move({required String src, required String dst}) async {
    await _postJson('/fs/move', {
      'src': path_utils.cleanPath(src),
      'dst': path_utils.cleanPath(dst),
    });
  }

  Future<void> deletePath(String path) async {
    final response = await _withTimeout(
      _client.delete(
        _uri('/fs/${path_utils.encodePath(path)}'),
        headers: _headers(),
      ),
    );
    _decodeWrapped(response);
  }

  // ------------------------------------------------------------ 压缩 / 任务队列

  /// 查询某个目录路径的压缩能力。
  ///
  /// 服务端在路径不存在时返回 404，此时按「不支持」处理而不是抛错，
  /// 避免用户仅仅因为父目录缺失就看到一个报错弹窗。
  Future<CompressionCapability> compressionCapabilities(String path) async {
    try {
      final data = await _getJson('/fs/compression', {
        'path': path_utils.cleanPath(path),
      });
      return CompressionCapability.fromJson(data);
    } on FoxelApiException catch (error) {
      if (error.statusCode == 404) {
        return const CompressionCapability(
          formats: <String>[],
          native: false,
        );
      }
      rethrow;
    }
  }

  /// 创建 ZIP 压缩包。
  ///
  /// [dst] 必须是完整的目标文件路径且以 `.zip` 结尾（服务端强制校验）。
  Future<CompressResult> compress({
    required List<String> sources,
    required String dst,
  }) async {
    final data = await _postJsonData('/fs/compress', {
      'sources': <String>[
        for (final source in sources) path_utils.cleanPath(source),
      ],
      'dst': path_utils.cleanPath(dst),
    });
    if (data is Map<String, dynamic>) {
      return CompressResult.fromJson(data);
    }
    throw const FoxelApiException('压缩响应格式不正确');
  }

  /// 服务端任务队列全量列表。
  Future<List<ServerTask>> taskQueue() async {
    final data = await _getJsonList('/tasks/queue');
    return data
        .whereType<Map<String, dynamic>>()
        .map(ServerTask.fromJson)
        .toList();
  }

  /// 单个服务端任务的实时状态；任务不存在时返回 null。
  Future<ServerTask?> serverTask(String taskId) async {
    try {
      final data = await _getJson('/tasks/queue/$taskId');
      return ServerTask.fromJson(data);
    } on FoxelApiException catch (error) {
      if (error.statusCode == 404) {
        return null;
      }
      rethrow;
    }
  }

  Uri streamUri(String path) =>
      _uri('/fs/stream/${path_utils.encodePath(path)}');

  Uri thumbnailUri(
    String path, {
    int width = 320,
    int height = 320,
    String fit = 'cover',
  }) {
    return _uri('/fs/thumb/${path_utils.encodePath(path)}', {
      'w': '$width',
      'h': '$height',
      'fit': fit,
    });
  }

  static String cleanPath(String path) => path_utils.cleanPath(path);

  static String joinPath(String base, String name) =>
      path_utils.joinPath(base, name);

  static String parentPath(String path) => path_utils.parentPath(path);

  static String encodePath(String path) => path_utils.encodePath(path);

  static String appAddressFromBaseUrl(String baseUrl) {
    final uri = Uri.parse(normalizeBaseUrl(baseUrl));
    final host = uri.host;
    if (host.isEmpty) {
      return '';
    }
    if (uri.hasPort) {
      return '$host:${uri.port}';
    }
    return host;
  }

  Future<Map<String, dynamic>> _getJson(
    String path, [
    Map<String, String>? query,
  ]) async {
    final response = await _withTimeout(
      _client.get(_uri(path, query), headers: _headers()),
    );
    final data = _decodeWrapped(response);
    if (data is Map<String, dynamic>) {
      return data;
    }
    throw const FoxelApiException('后端响应格式不正确');
  }

  Future<List<dynamic>> _getJsonList(String path) async {
    final response = await _withTimeout(
      _client.get(_uri(path), headers: _headers()),
    );
    final data = _decodeWrapped(response);
    if (data is List<dynamic>) {
      return data;
    }
    throw const FoxelApiException('后端响应格式不正确');
  }

  Future<void> _postJson(String path, Map<String, dynamic> payload) async {
    final response = await _withTimeout(
      _client.post(
        _uri(path),
        headers: _headers(json: true),
        body: jsonEncode(payload),
      ),
    );
    _decodeWrapped(response);
  }

  /// 同 [_postJson]，但把 `data` 返回给调用方（压缩接口需要读结果）。
  Future<dynamic> _postJsonData(
    String path,
    Map<String, dynamic> payload,
  ) async {
    final response = await _withTimeout(
      _client.post(
        _uri(path),
        headers: _headers(json: true),
        body: jsonEncode(payload),
      ),
    );
    return _decodeWrapped(response);
  }

  dynamic _decodeWrapped(http.Response response) {
    final body = _decodeAny(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwDecodedError(body, response.statusCode);
    }
    if (body.containsKey('code')) {
      final code = body['code'];
      if (code != 0) {
        throw FoxelApiException(
          body['msg'] as String? ?? body['message'] as String? ?? '请求失败',
        );
      }
      return body['data'];
    }
    return body;
  }

  Map<String, dynamic> _decodeAny(http.Response response) {
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {};
      }
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwHttpError(response);
    }
    throw const FoxelApiException('后端响应格式不正确');
  }

  Never _throwHttpError(http.Response response) {
    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } catch (_) {
      decoded = null;
    }
    if (decoded is Map<String, dynamic>) {
      _throwDecodedError(decoded, response.statusCode);
    }
    throw FoxelApiException(
      '请求失败：${response.statusCode}',
      statusCode: response.statusCode,
    );
  }

  Never _throwDecodedError(Map<String, dynamic> body, int statusCode) {
    final detail = body['detail'];
    if (detail is String && detail.isNotEmpty) {
      throw FoxelApiException(detail, statusCode: statusCode);
    }
    if (detail is List) {
      throw FoxelApiException(
        detail.map((item) => '$item').join('; '),
        statusCode: statusCode,
      );
    }
    final message = body['msg'] as String? ?? body['message'] as String?;
    throw FoxelApiException(
      message ?? '请求失败：$statusCode',
      statusCode: statusCode,
    );
  }

  void close() {
    _client.close();
  }
}
