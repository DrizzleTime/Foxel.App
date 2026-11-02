import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:foxel/core/storage/portable_prefs_store.dart';

/// 桌面端「启动时最小化到托盘」开关。
///
/// 状态落在 `<程序目录>/userdata/.start-minimized` 这个**标记文件**上，
/// 而不是 `prefs.json`：Windows runner 在创建窗口之前就要知道答案，
/// 让它去解析 JSON 只能换来一份手写的脆弱解析器。约定很简单——
/// **文件存在 = 开启**，内容不参与判定。
///
/// 与 `windows/runner/flutter_window.cpp` 的 `ShouldStartMinimized()` 共用同一文件，
/// 任何一侧改名都必须同步改另一侧。
class DesktopWindowStore {
  const DesktopWindowStore._();

  static const String _markerName = '.start-minimized';

  /// 当前平台是否支持托盘常驻相关设置（只有 Windows runner 实现了托盘）。
  static bool get isSupported => !kIsWeb && Platform.isWindows;

  static File get _markerFile {
    final executableDir = File(Platform.resolvedExecutable).parent.path;
    return File(
      '$executableDir${Platform.pathSeparator}$kPortableDataDirName'
      '${Platform.pathSeparator}$_markerName',
    );
  }

  /// 读取当前设置；非 Windows 或标记文件不存在时为 false（启动显示主窗口）。
  static Future<bool> startMinimized() async {
    if (!isSupported) {
      return false;
    }
    return _markerFile.exists();
  }

  /// 写入设置：开启时创建标记文件，关闭时删除。
  ///
  /// 失败只记日志不抛异常：这个开关属于偏好项，写不进去最坏是下次启动
  /// 仍按默认行为显示窗口，不该让设置页崩掉。
  static Future<void> setStartMinimized(bool value) async {
    if (!isSupported) {
      return;
    }
    final file = _markerFile;
    try {
      if (value) {
        await file.parent.create(recursive: true);
        await file.writeAsString('1', flush: true);
      } else if (await file.exists()) {
        await file.delete();
      }
    } catch (error) {
      debugPrint('[Foxel] 托盘启动设置写入失败：$error');
    }
  }
}
