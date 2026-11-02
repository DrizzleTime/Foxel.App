import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// 便携版用户数据目录名。
///
/// 不能用 `data`：Flutter Windows 的 `data/` 是运行时资源目录
/// （app.so / flutter_assets / icudtl.dat），用户数据必须与它分开。
const String kPortableDataDirName = 'userdata';

const String _prefsFileName = 'prefs.json';

/// Windows 便携版偏好存储：把 `shared_preferences` 的全部数据写到
/// `<程序目录>/userdata/prefs.json`，删除程序目录即清空数据。
///
/// 通过替换 `SharedPreferencesStorePlatform.instance` 生效，
/// 因此 `SharedPreferences` 的所有调用点都无需改动。
class PortablePrefsStore extends SharedPreferencesStorePlatform {
  PortablePrefsStore(this.file);

  final File file;

  Map<String, Object>? _cache;

  /// 读取失败后置位：此时**禁止任何写入**，否则会把空数据覆盖到已有文件上，
  /// 造成账户 / token / 下载目录配置被静默清空。
  bool _loadFailed = false;

  /// 写队列：所有「改内存 → 落盘」串行执行。
  ///
  /// 否则并发写会争用同一个临时文件，最坏出现 tmp 被先移走、
  /// 后一次 rename 失败并丢掉整个数据文件。
  Future<void> _writeChain = Future<void>.value();

  Future<Map<String, Object>> _load() async {
    final cached = _cache;
    if (cached != null) {
      return cached;
    }
    final map = <String, Object>{};
    try {
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          decoded.forEach((key, value) {
            if (key is String && value != null) {
              map[key] = value as Object;
            }
          });
        }
      }
    } catch (error) {
      // 读取失败：不建立缓存，并阻止后续写入（保住磁盘上的数据）。
      _loadFailed = true;
      if (kDebugMode) {
        debugPrint('[Foxel] 便携数据读取失败，本次会话不写盘：$error');
      }
      return <String, Object>{};
    }
    _cache = map;
    return map;
  }

  /// 串行执行一次写操作；返回是否真正落盘成功。
  Future<bool> _mutate(void Function(Map<String, Object> map) change) {
    final result = _writeChain.then((_) async {
      final map = await _load();
      if (_loadFailed) {
        // 磁盘数据读不出来，绝不覆盖写入。
        debugPrint('[Foxel] 数据文件读取异常，已跳过本次写入');
        return false;
      }
      change(map);
      return _persist();
    });
    // 队列自身不能因为某次失败而断裂。
    _writeChain = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// 原子写：先写临时文件，再替换目标；目标被占用时回退为覆盖写。
  Future<bool> _persist() async {
    final map = _cache ?? <String, Object>{};
    // 临时文件带 pid：多个实例同时启动时不会争用同一个 tmp。
    final tmp = File('${file.path}.${pid}.tmp');
    try {
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final raw = jsonEncode(map);
      await tmp.writeAsString(raw, flush: true);
      try {
        // 直接 rename 覆盖（Dart 在 Windows 上使用 MOVEFILE_REPLACE_EXISTING）。
        // 先 delete 再 rename 会留下「数据文件不存在」的空窗，进程被杀即全量丢失。
        await tmp.rename(file.path);
      } catch (_) {
        // 目标被占用时降级为覆盖写，保证数据仍能落盘。
        await file.writeAsString(raw, flush: true);
        if (await tmp.exists()) {
          await tmp.delete();
        }
      }
      return true;
    } catch (error) {
      // 不静默吞掉：返回 false 让上层知道这次写入没有落盘。
      debugPrint('[Foxel] 便携数据写入失败：$error');
      return false;
    }
  }

  @override
  Future<bool> clear() => _mutate((map) => map.clear());

  @override
  Future<Map<String, Object>> getAll() => _load();

  @override
  Future<bool> remove(String key) => _mutate((map) => map.remove(key));

  @override
  Future<bool> setValue(String valueType, String key, Object value) =>
      _mutate((map) => map[key] = value);
}

/// 便携版存储配置入口（幂等）。
///
/// 只在 Windows 生效。必须在第一次读写 `SharedPreferences` 之前调用；
/// 由于插件注册可能把实例换回系统实现，这里每次都按「当前实例类型」判断，
/// 不使用一次性布尔标志。
class PortableStorage {
  const PortableStorage._();

  /// 当前使用的数据文件路径（用于诊断展示）。
  static String? dataFilePath;

  static void ensureConfigured() {
    if (kIsWeb || !Platform.isWindows) {
      return;
    }
    final current = SharedPreferencesStorePlatform.instance;
    if (current is PortablePrefsStore) {
      dataFilePath = current.file.path;
      return;
    }
    final executableDir = File(Platform.resolvedExecutable).parent.path;
    final file = File(
      '$executableDir${Platform.pathSeparator}$kPortableDataDirName'
      '${Platform.pathSeparator}$_prefsFileName',
    );
    SharedPreferencesStorePlatform.instance = PortablePrefsStore(file);
    dataFilePath = file.path;
    if (kDebugMode) {
      debugPrint('[Foxel] 便携版数据文件：${file.path}');
    }
  }
}
