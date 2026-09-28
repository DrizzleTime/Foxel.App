import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 下载目录配置。
///
/// Android 端默认目录固定为 /storage/emulated/0/Download/Foxel，
/// 用户可以在「设置 → 下载目录」中修改。
class DownloadDirStore {
  static const _prefsKey = 'foxel_download_dir';
  static const _channel = MethodChannel('foxel/storage');

  /// Android 端固定默认下载目录。
  static const String androidDefaultDir = '/storage/emulated/0/Download/Foxel';

  /// 读取当前配置的下载目录，未配置时返回平台默认值。
  static Future<String> currentDir() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved != null && saved.trim().isNotEmpty) {
      return saved.trim();
    }
    return defaultDir();
  }

  /// 平台默认下载目录。Android 固定为 [androidDefaultDir]，
  /// 其他平台优先使用系统下载目录。
  static Future<String> defaultDir() async {
    if (kIsWeb) {
      return '';
    }
    if (Platform.isAndroid) {
      return androidDefaultDir;
    }
    try {
      final downloads = await getDownloadsDirectory();
      if (downloads != null) {
        return downloads.path;
      }
      final docs = await getApplicationDocumentsDirectory();
      return docs.path;
    } catch (_) {
      return '';
    }
  }

  /// 当前是否配置了自定义下载目录。
  static Future<bool> isCustomDir() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved == null || saved.trim().isEmpty) {
      return false;
    }
    return saved.trim() != await defaultDir();
  }

  /// 保存自定义下载目录。
  static Future<void> setDir(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, path.trim());
  }

  /// 恢复默认下载目录。
  static Future<void> resetDir() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsKey);
  }

  /// 解析实际下载目录，并确保目录存在。
  static Future<Directory> resolve() async {
    final dir = Directory(await currentDir());
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 通过写入探测文件检查目录是否可写。
  static Future<bool> isWritable(String path) async {
    try {
      final dir = Directory(path.trim());
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final probe = File('${dir.path}/.foxel_write_test');
      await probe.writeAsString('ok', flush: true);
      await probe.delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Android 专用：是否已获得「所有文件访问」权限。
  static Future<bool> hasAllFilesAccess() async {
    if (kIsWeb || !Platform.isAndroid) {
      return true;
    }
    try {
      return await _channel.invokeMethod<bool>('hasAllFilesAccess') ?? false;
    } on PlatformException {
      return false;
    }
  }

  /// Android 专用：跳转到系统的「所有文件访问」授权页面。
  static Future<void> requestAllFilesAccess() async {
    if (kIsWeb || !Platform.isAndroid) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('requestAllFilesAccess');
    } on PlatformException {
      // 忽略，用户可在系统设置中手动开启。
    }
  }
}
