import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'package:foxel/core/api/foxel_api_exception.dart';
import 'package:foxel/core/models/file_entry.dart';
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
    final response = await _client.post(
      _uri('/auth/login'),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'username': username, 'password': password},
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

  Future<Uint8List> readFile(String path) async {
    final response = await _client.get(
      _uri('/fs/file/${path_utils.encodePath(path)}'),
      headers: _headers(),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwHttpError(response);
    }
    return response.bodyBytes;
  }

  Future<void> uploadFile({
    required String remotePath,
    required String localPath,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      _uri('/fs/upload/${path_utils.encodePath(remotePath)}', {
        'overwrite': 'true',
      }),
    );
    request.headers.addAll(_headers());
    request.files.add(await http.MultipartFile.fromPath('file', localPath));
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    _decodeWrapped(response);
  }

  Future<void> downloadFile({
    required String remotePath,
    required File outputFile,
  }) async {
    final response = await _client.get(
      _uri('/fs/file/${path_utils.encodePath(remotePath)}'),
      headers: _headers(),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwHttpError(response);
    }
    await outputFile.writeAsBytes(response.bodyBytes);
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
    final response = await _client.delete(
      _uri('/fs/${path_utils.encodePath(path)}'),
      headers: _headers(),
    );
    _decodeWrapped(response);
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

  Future<Map<String, dynamic>> _getJson(
    String path, [
    Map<String, String>? query,
  ]) async {
    final response = await _client.get(_uri(path, query), headers: _headers());
    final data = _decodeWrapped(response);
    if (data is Map<String, dynamic>) {
      return data;
    }
    throw const FoxelApiException('后端响应格式不正确');
  }

  Future<void> _postJson(String path, Map<String, dynamic> payload) async {
    final response = await _client.post(
      _uri(path),
      headers: _headers(json: true),
      body: jsonEncode(payload),
    );
    _decodeWrapped(response);
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
    throw FoxelApiException('请求失败：${response.statusCode}');
  }

  Never _throwDecodedError(Map<String, dynamic> body, int statusCode) {
    final detail = body['detail'];
    if (detail is String && detail.isNotEmpty) {
      throw FoxelApiException(detail);
    }
    if (detail is List) {
      throw FoxelApiException(detail.map((item) => '$item').join('; '));
    }
    final message = body['msg'] as String? ?? body['message'] as String?;
    throw FoxelApiException(message ?? '请求失败：$statusCode');
  }

  void close() {
    _client.close();
  }
}
