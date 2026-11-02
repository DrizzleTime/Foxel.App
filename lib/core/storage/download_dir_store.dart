import 'dart:io';

import 'package:characters/characters.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:foxel/core/models/account.dart';

/// 下载目录配置。
///
/// Android 端默认目录固定为 /storage/emulated/0/Download/Foxel，
/// 用户可以在「设置 → 下载目录」中修改。
///
/// 注意：这里只剩**账户级**接口（`dirKeyFor` / `currentDirFor` / `resolveFor`…）。
/// 早期那套「全局一个下载目录」的 API 已经删干净了 —— 多账户下它会绕过沙箱，
/// 让 A 账户的文件落进 B 账户目录，留着就是给后来人挖坑。
class DownloadDirStore {
  static const _channel = MethodChannel('foxel/storage');

  /// Android 端固定默认下载目录。
  static const String androidDefaultDir = '/storage/emulated/0/Download/Foxel';

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

  /// 沙箱内下载目录的配置 key。
  static String dirKeyFor(String accountId) =>
      'foxel_acc_${accountId}_download_dir';

  /// 账户是否已有自定义（含自动生成）下载目录记录。
  static Future<bool> hasCustomDirFor(String accountId) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(dirKeyFor(accountId));
    return saved != null && saved.trim().isNotEmpty;
  }

  /// 已落盘的下载目录（未配置时为 null），用于区分「自动生成」与「用户自定义」。
  static Future<String?> savedDirFor(String accountId) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(dirKeyFor(accountId));
    if (saved == null || saved.trim().isEmpty) {
      return null;
    }
    return saved.trim();
  }

  /// 文件夹名最大长度（含重名后缀）。
  static const int maxFolderNameLength = 40;

  /// Windows 保留设备名：用作目录名会创建失败。
  static const _reservedNames = <String>{
    'con', 'prn', 'aux', 'nul',
    'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
    'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
  };

  /// 目录名清洗：替换各平台非法字符、压缩空白、避开保留名、安全截断。
  static String sanitizeFolderName(String raw) {
    var name = raw.trim();
    if (name.isEmpty) {
      return '';
    }
    // 各平台非法或易出问题的字符统一替换为下划线。
    name = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_');
    name = name.replaceAll(RegExp(r'\s+'), ' ');
    name = _trimEdges(name);
    if (name.isEmpty) {
      return '';
    }
    // 按字素截断，避免切断代理对（emoji）产生非法字符串。
    if (name.characters.length > maxFolderNameLength) {
      name = _trimEdges(
        name.characters.take(maxFolderNameLength).toString(),
      );
    }
    if (name.isEmpty) {
      return '';
    }
    // Windows 保留名（含 CON.txt 这类带扩展名的形式）加前缀规避。
    final stem = name.split('.').first.toLowerCase();
    if (_reservedNames.contains(stem)) {
      name = 'foxel_$name';
    }
    return name;
  }

  static String _trimEdges(String value) {
    return value.replaceAll(RegExp(r'^[.\s]+|[.\s]+$'), '');
  }

  /// 把**服务端返回的文件名**清洗成各平台都能落盘的一段路径。
  ///
  /// 与 [sanitizeFolderName] 的区别：
  /// * 不截断长度 —— 文件名不承担目录层级职责，截断会造成同名覆盖；
  /// * 重点防 `..` —— 直接拼进 `${dir}/${name}` 会写到上级目录。
  ///
  /// 返回空串表示这一段不可用，调用方应跳过该条目而不是拼出畸形路径。
  static String sanitizeFileSegment(String raw) {
    final trimmed = raw.trim();
    // "." / ".." 以及各种变体（"..."/".. "）都会指向上级目录，必须先挡掉。
    if (trimmed.isEmpty || RegExp(r'^\.+$').hasMatch(trimmed)) {
      return '';
    }
    var name = trimmed.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_');
    name = name.replaceAll(RegExp(r'\s+'), ' ');
    name = _trimEdges(name);
    if (name.isEmpty) {
      return '';
    }
    // Windows 保留名（CON / NUL / COM1…）加前缀规避，含 "CON.txt" 形式。
    final stem = name.split('.').first.toLowerCase();
    if (_reservedNames.contains(stem)) {
      name = 'foxel_$name';
    }
    return name;
  }

  /// 账户对应的文件夹名：**优先显示名称**，未填写时退回账户 ID。
  ///
  /// [disambiguator] 用于显示名称与既有账户重复时追加短标识，避免两个账户
  /// 共用同一个下载目录；拼接后统一截断，防止路径过长。
  static String folderNameFor(Account account, {String? disambiguator}) {
    final name = sanitizeFolderName(account.alias);
    if (name.isEmpty) {
      return account.id;
    }
    if (disambiguator == null || disambiguator.isEmpty) {
      return name;
    }
    final combined = '$name-$disambiguator';
    if (combined.characters.length <= maxFolderNameLength) {
      return combined;
    }
    final budget =
        maxFolderNameLength - disambiguator.length - 1;
    final head = budget > 0
        ? name.characters.take(budget).toString()
        : '';
    return _trimEdges('$head-$disambiguator');
  }

  /// 账户默认下载目录。
  ///
  /// 开启「独立下载目录」时为 `<平台默认>/Foxel/<显示名称 或 账户ID>`；
  /// 关闭时与其他关闭该开关的账户共用 `<平台默认>/Foxel`。
  static Future<String> defaultDirForAccount(
    Account account, {
    String? disambiguator,
  }) {
    if (!account.isolatedDownloadDir) {
      return _joinFoxel('');
    }
    return _joinFoxel(folderNameFor(account, disambiguator: disambiguator));
  }

  /// 兼容旧签名（仅凭账户 ID）：`<平台默认>/Foxel/<账户ID>`。
  static Future<String> defaultDirFor(String accountId) => _joinFoxel(accountId);

  static Future<String> _joinFoxel(String folderName) async {
    final base = await defaultDir();
    if (base.isEmpty) {
      return '';
    }
    final separator = Platform.pathSeparator;
    final trimmed = base.endsWith(separator)
        ? base.substring(0, base.length - separator.length)
        : base;
    if (folderName.isEmpty) {
      return '$trimmed${separator}Foxel';
    }
    return '$trimmed${separator}Foxel$separator$folderName';
  }

  /// 账户下载目录：优先用户自定义，否则使用该账户沙箱默认目录。
  /// 账户下载目录：优先用户自定义，否则使用默认目录。
  ///
  /// 传入 [account] 时按「显示名称」计算默认目录，与设置页「恢复默认」、
  /// 创建账户时落定的目录保持一致；仅传 id 时退回 id 命名（兼容旧调用）。
  static Future<String> currentDirFor(String accountId, {Account? account}) async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(dirKeyFor(accountId));
    if (saved != null && saved.trim().isNotEmpty) {
      return saved.trim();
    }
    if (account != null) {
      return defaultDirForAccount(account);
    }
    return defaultDirFor(accountId);
  }

  /// 保存账户自定义下载目录。
  static Future<void> setDirFor(String accountId, String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(dirKeyFor(accountId), path.trim());
  }

  /// 恢复账户默认下载目录。
  static Future<void> resetDirFor(String accountId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(dirKeyFor(accountId));
  }

  /// 解析账户下载目录并确保存在。
  ///
  /// 平台查询不到可用目录时（返回空串）抛出可读错误，避免对空路径建目录。
  /// 传入 [account] 时按「显示名称」计算默认目录，与设置页展示保持一致。
  static Future<Directory> resolveFor(
    String accountId, {
    Account? account,
  }) async {
    final path = await currentDirFor(accountId, account: account);
    if (path.trim().isEmpty) {
      throw const FileSystemException('无法确定下载目录，请在「设置 → 下载目录」中手动指定');
    }
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 统计账户下载目录已占用的字节数（不存在时返回 0）。
  static Future<int> dirSizeBytes(String accountId, {Account? account}) async {
    if (kIsWeb) {
      return 0;
    }
    final path = await currentDirFor(accountId, account: account);
    if (path.isEmpty) {
      return 0;
    }
    final dir = Directory(path);
    if (!await dir.exists()) {
      return 0;
    }
    var total = 0;
    try {
      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            total += await entity.length();
          } catch (_) {
            // 单个文件读取失败时跳过。
          }
        }
      }
    } catch (_) {
      return total;
    }
    return total;
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
