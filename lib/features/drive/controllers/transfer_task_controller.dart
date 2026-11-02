import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:foxel/core/api/foxel_api.dart';
import 'package:foxel/core/api/transfer_cancel.dart';

enum TransferTaskType { upload, download }

enum TransferTaskStatus { running, success, failed }

class TransferTask {
  const TransferTask({
    required this.id,
    required this.type,
    required this.name,
    required this.remotePath,
    required this.transferredBytes,
    required this.totalBytes,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.localPath,
    this.errorMessage,
  });

  final int id;
  final TransferTaskType type;
  final String name;
  final String remotePath;
  final String? localPath;
  final int transferredBytes;
  final int? totalBytes;
  final TransferTaskStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? errorMessage;

  double? get progress {
    final total = totalBytes;
    if (total == null || total <= 0) {
      return null;
    }
    return (transferredBytes / total).clamp(0.0, 1.0).toDouble();
  }

  TransferTask copyWith({
    String? localPath,
    int? transferredBytes,
    int? totalBytes,
    bool clearTotalBytes = false,
    TransferTaskStatus? status,
    String? errorMessage,
    bool clearError = false,
  }) {
    return TransferTask(
      id: id,
      type: type,
      name: name,
      remotePath: remotePath,
      localPath: localPath ?? this.localPath,
      transferredBytes: transferredBytes ?? this.transferredBytes,
      totalBytes: clearTotalBytes ? null : totalBytes ?? this.totalBytes,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

/// 一个排队中的传输任务。
class _TransferJob {
  _TransferJob({required this.taskId, required this.run, this.onSuccess});

  final int taskId;
  final Future<void> Function() run;
  final VoidCallback? onSuccess;
}

class TransferTaskController {
  /// 同时在跑的传输数量上限。
  ///
  /// 批量下载 50 个文件时，逐个 `unawaited` 会瞬间打满连接池与文件句柄，
  /// 服务和磁盘一起抖。卡在 3 个既能吃满带宽，又不会把对方打爆。
  static const int maxConcurrent = 3;

  /// 进度刷新间隔：每个 chunk 都重建列表，4GB 文件会产生数万次无意义重建。
  static const Duration _progressInterval = Duration(milliseconds: 120);

  final ValueNotifier<List<TransferTask>> tasks =
      ValueNotifier<List<TransferTask>>(<TransferTask>[]);

  /// 待执行队列（先进先出）。
  final Queue<_TransferJob> _pending = Queue<_TransferJob>();

  /// 在途任务的取消令牌。
  final Map<int, TransferCancelToken> _cancelTokens = <int, TransferCancelToken>{};

  /// 上次推送进度的时刻（节流用）。
  final Map<int, DateTime> _lastProgressAt = <int, DateTime>{};

  int _nextId = 1;
  int _running = 0;
  bool _disposed = false;

  void dispose() {
    _disposed = true;
    // 控制器被销毁时没人接收结果了，在途请求直接取消，别继续占带宽写磁盘。
    for (final token in _cancelTokens.values) {
      token.cancel('传输已取消');
    }
    _cancelTokens.clear();
    _pending.clear();
    _lastProgressAt.clear();
    tasks.dispose();
  }

  /// 切换账户 / 删除账户：真正中断本账户的传输。
  ///
  /// 分两类处理：在途的置位令牌（下一个 chunk 就会停并清理 `.part`），
  /// 排队中的直接从队列摘掉标记失败 —— 否则它们会一直占着并发槽位。
  void interruptAll(String reason) {
    if (_disposed) {
      return;
    }
    for (final token in _cancelTokens.values) {
      token.cancel(reason);
    }
    while (_pending.isNotEmpty) {
      final job = _pending.removeFirst();
      _updateTask(
        job.taskId,
        (task) => task.copyWith(
          status: TransferTaskStatus.failed,
          errorMessage: reason,
        ),
      );
    }
  }

  void clearFinished() {
    if (_disposed) {
      return;
    }
    tasks.value = tasks.value
        .where((task) => task.status == TransferTaskStatus.running)
        .toList();
  }

  void startUpload({
    required FoxelApi api,
    required String name,
    required String remotePath,
    required String localPath,
    VoidCallback? onSuccess,
  }) {
    final task = _addTask(
      type: TransferTaskType.upload,
      name: name,
      remotePath: remotePath,
      localPath: localPath,
    );
    if (task == null) {
      return;
    }

    final token = TransferCancelToken();
    _cancelTokens[task.id] = token;
    _enqueue(
      _TransferJob(
        taskId: task.id,
        onSuccess: onSuccess,
        run: () => api.uploadFile(
          remotePath: remotePath,
          localPath: localPath,
          cancelToken: token,
          onProgress: (sent, total) {
            _updateProgress(task.id, sent, total);
          },
        ),
      ),
    );
  }

  void startDownload({
    required FoxelApi api,
    required String name,
    required String remotePath,
    required File outputFile,
  }) {
    final task = _addTask(
      type: TransferTaskType.download,
      name: name,
      remotePath: remotePath,
      localPath: outputFile.path,
    );
    if (task == null) {
      return;
    }

    final token = TransferCancelToken();
    _cancelTokens[task.id] = token;
    _enqueue(
      _TransferJob(
        taskId: task.id,
        run: () => api.downloadFile(
          remotePath: remotePath,
          outputFile: outputFile,
          cancelToken: token,
          onProgress: (received, total) {
            _updateProgress(task.id, received, total);
          },
        ),
      ),
    );
  }

  /// 新增任务；控制器已释放（账户被删除 / 页面销毁）时返回 null，
  /// 调用方拿到 null 必须直接返回，避免发起无记录的真实传输。
  TransferTask? _addTask({
    required TransferTaskType type,
    required String name,
    required String remotePath,
    required String localPath,
  }) {
    if (_disposed) {
      return null;
    }
    final now = DateTime.now();
    final task = TransferTask(
      id: _nextId++,
      type: type,
      name: name,
      remotePath: remotePath,
      localPath: localPath,
      transferredBytes: 0,
      totalBytes: null,
      status: TransferTaskStatus.running,
      createdAt: now,
      updatedAt: now,
    );
    tasks.value = [task, ...tasks.value];
    return task;
  }

  void _enqueue(_TransferJob job) {
    if (_disposed) {
      return;
    }
    _pending.add(job);
    _pump();
  }

  /// 拉起排队任务，直到跑满 [maxConcurrent] 或队列空。
  void _pump() {
    while (!_disposed && _running < maxConcurrent && _pending.isNotEmpty) {
      final job = _pending.removeFirst();
      _running += 1;
      unawaited(_runJob(job));
    }
  }

  Future<void> _runJob(_TransferJob job) async {
    try {
      await job.run();
      if (_disposed) {
        return;
      }
      _updateTask(
        job.taskId,
        (task) => task.copyWith(
          status: TransferTaskStatus.success,
          transferredBytes: task.totalBytes ?? task.transferredBytes,
          clearError: true,
        ),
      );
      job.onSuccess?.call();
    } on TransferCancelledException catch (cancelled) {
      if (!_disposed) {
        _updateTask(
          job.taskId,
          (task) => task.copyWith(
            status: TransferTaskStatus.failed,
            errorMessage: cancelled.reason,
          ),
        );
      }
    } catch (error) {
      if (!_disposed) {
        _updateTask(
          job.taskId,
          (task) => task.copyWith(
            status: TransferTaskStatus.failed,
            errorMessage: error.toString(),
          ),
        );
      }
    } finally {
      _running -= 1;
      _cancelTokens.remove(job.taskId);
      _lastProgressAt.remove(job.taskId);
      if (!_disposed) {
        _pump();
      }
    }
  }

  /// 进度节流：低于 [_progressInterval] 的重复回调直接丢弃。
  /// 任务结束时会被状态更新补齐到 100%，不会停在 99%。
  void _updateProgress(int id, int transferred, int? total) {
    final now = DateTime.now();
    final last = _lastProgressAt[id];
    if (last != null && now.difference(last) < _progressInterval) {
      return;
    }
    _lastProgressAt[id] = now;
    _updateTask(
      id,
      (task) => task.copyWith(
        transferredBytes: transferred,
        totalBytes: total,
        clearTotalBytes: total == null,
      ),
    );
  }

  void _updateTask(int id, TransferTask Function(TransferTask task) update) {
    if (_disposed) {
      return;
    }
    tasks.value = [
      for (final task in tasks.value) task.id == id ? update(task) : task,
    ];
  }
}
