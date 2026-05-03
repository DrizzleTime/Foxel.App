import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:foxel/core/api/foxel_api.dart';

class VideoPlaybackStore {
  static const _prefix = 'video_position_';

  Future<Duration?> load({
    required FoxelApi api,
    required String path,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_key(api, path));
    if (value == null || value <= 0) {
      return null;
    }
    return Duration(milliseconds: value);
  }

  Future<void> save({
    required FoxelApi api,
    required String path,
    required Duration position,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key(api, path), position.inMilliseconds);
  }

  Future<void> clear({
    required FoxelApi api,
    required String path,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(api, path));
  }

  String _key(FoxelApi api, String path) {
    return '$_prefix${_fnv1a64(utf8.encode('${api.baseUrl}|$path'))}';
  }

  String _fnv1a64(List<int> bytes) {
    const mask = 0xFFFFFFFFFFFFFFFF;
    var hash = 0xcbf29ce484222325;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & mask;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }
}
