import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:foxel/core/models/isolation_policy.dart';

/// 视频播放进度，按账户沙箱存储（随账户一起清理）。
class VideoPlaybackStore {
  static const _prefix = 'foxel_acc_';
  static const _midfix = '_vp_';

  Future<Duration?> load({
    required String accountId,
    required String path,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getInt(_key(accountId, path));
    if (value == null || value <= 0) {
      return null;
    }
    return Duration(milliseconds: value);
  }

  Future<void> save({
    required String accountId,
    required String path,
    required Duration position,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key(accountId, path), position.inMilliseconds);
  }

  Future<void> clear({required String accountId, required String path}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(accountId, path));
  }

  String _key(String accountId, String path) {
    // 「独立媒体缓存」关闭时改用共享分区。
    final scope = IsolationPolicy.cacheScope(accountId);
    return '$_prefix$scope$_midfix${_fnv1a64(utf8.encode(path))}';
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
