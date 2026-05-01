import 'package:shared_preferences/shared_preferences.dart';

import 'package:foxel/core/models/session.dart';

class SessionStore {
  static const _baseUrlKey = 'foxel_base_url';
  static const _usernameKey = 'foxel_username';
  static const _tokenKey = 'foxel_token';
  static const _emailKey = 'foxel_email';
  static const _avatarUrlKey = 'foxel_avatar_url';

  Future<FoxelSession?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString(_baseUrlKey);
    final username = prefs.getString(_usernameKey);
    final token = prefs.getString(_tokenKey);

    if (baseUrl == null ||
        baseUrl.isEmpty ||
        username == null ||
        username.isEmpty ||
        token == null ||
        token.isEmpty) {
      return null;
    }

    return FoxelSession(
      baseUrl: baseUrl,
      username: username,
      token: token,
      email: prefs.getString(_emailKey) ?? '',
      avatarUrl: prefs.getString(_avatarUrlKey) ?? '',
    );
  }

  Future<void> save(FoxelSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_baseUrlKey, session.baseUrl);
    await prefs.setString(_usernameKey, session.username);
    await prefs.setString(_tokenKey, session.token);
    await prefs.setString(_emailKey, session.email);
    await prefs.setString(_avatarUrlKey, session.avatarUrl);
  }

  Future<void> clearToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  Future<void> clearAll() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_baseUrlKey);
    await prefs.remove(_usernameKey);
    await prefs.remove(_tokenKey);
    await prefs.remove(_emailKey);
    await prefs.remove(_avatarUrlKey);
  }
}
