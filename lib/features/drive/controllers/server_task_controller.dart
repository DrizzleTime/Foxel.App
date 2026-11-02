import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:foxel/core/api/foxel_api.dart';
import 'package:foxel/core/models/server_task.dart';

/// 服务端任务队列的轮询控制器。
///
/// 本阶段只关心压缩任务（`compress_archive`）：任务页需要展示服务端打包进度，
/// 而队列里还混有 `process_file` 等其他类型，它们的进度字段语义不同，
/// 直接混排会让界面出现半空白的卡片，因此这里做类型过滤。
///
/// 轮询是单次 Timer 递归：有进行中的任务时 2 秒一次，全部结束后降到 10 秒，
/// 避免页面停在后台时空转请求。
class ServerTaskController {
  ServerTaskController({required this.api});

  final FoxelApi api;

  /// 按服务端返回顺序反转（最新的任务排在最前）。
  final ValueNotifier<List<ServerTask>> tasks =
      ValueNotifier<List<ServerTask>>(const <ServerTask>[]);

  /// 首次加载中；后续轮询不再触发整页 loading，避免界面闪烁。
  final ValueNotifier<bool> loading = ValueNotifier<bool>(false);

  final ValueNotifier<String?> error = ValueNotifier<String?>(null);

  Timer? _timer;
  bool _fetching = false;
  bool _disposed = false;

  /// 是否已被 [stop] 暂停。
  ///
  /// 只取消 Timer 是不够的：`_tick` 在 `await refresh()` 返回后会无条件排下一轮，
  /// 于是 stop() 之后轮询会自己复活。必须留一个标志让 `_tick` 自己退出。
  bool _stopped = false;

  bool get isDisposed => _disposed;

  /// 开始轮询（页面可见时调用）。
  void start() {
    if (_disposed || _timer != null || _fetching) {
      return;
    }
    _stopped = false;
    loading.value = tasks.value.isEmpty;
    unawaited(_tick());
  }

  /// 停止轮询（页面不可见时调用），避免离开任务页后仍在发请求。
  void stop() {
    _stopped = true;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _tick() async {
    if (_disposed || _stopped) {
      return;
    }
    _timer?.cancel();
    _timer = null;
    await refresh();
    if (_disposed || _stopped) {
      return;
    }
    final hasActive = tasks.value.any((task) => task.isActive);
    _timer = Timer(
      Duration(seconds: hasActive ? 2 : 8),
      () => unawaited(_tick()),
    );
  }

  /// 立即拉取一次队列（压缩提交后调用可即时看到新任务）。
  Future<void> refresh() async {
    if (_disposed || _fetching) {
      return;
    }
    _fetching = true;
    try {
      final items = await api.taskQueue();
      if (_disposed) {
        return;
      }
      tasks.value = items
          .where((task) => task.isCompression)
          .toList(growable: false)
          .reversed
          .toList(growable: false);
      error.value = null;
    } catch (failure) {
      if (_disposed) {
        return;
      }
      // 保留上一轮数据：网络抖动时清空列表比显示旧数据更糟。
      error.value = failure.toString();
    } finally {
      _fetching = false;
      if (!_disposed) {
        loading.value = false;
      }
    }
  }

  void dispose() {
    _disposed = true;
    stop();
    tasks.dispose();
    loading.dispose();
    error.dispose();
  }
}
