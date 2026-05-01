import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:foxel/core/api/foxel_api.dart';

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

class TransferTaskController {
  final ValueNotifier<List<TransferTask>> tasks =
      ValueNotifier<List<TransferTask>>(<TransferTask>[]);

  int _nextId = 1;
  bool _disposed = false;

  void dispose() {
    _disposed = true;
    tasks.dispose();
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

    unawaited(
      _runTask(
        task.id,
        () => api.uploadFile(
          remotePath: remotePath,
          localPath: localPath,
          onProgress: (sent, total) {
            _updateTask(
              task.id,
              (task) =>
                  task.copyWith(transferredBytes: sent, totalBytes: total),
            );
          },
        ),
        onSuccess: onSuccess,
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

    unawaited(
      _runTask(
        task.id,
        () => api.downloadFile(
          remotePath: remotePath,
          outputFile: outputFile,
          onProgress: (received, total) {
            _updateTask(
              task.id,
              (task) => task.copyWith(
                transferredBytes: received,
                totalBytes: total,
                clearTotalBytes: total == null,
              ),
            );
          },
        ),
      ),
    );
  }

  TransferTask _addTask({
    required TransferTaskType type,
    required String name,
    required String remotePath,
    required String localPath,
  }) {
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

  Future<void> _runTask(
    int id,
    Future<void> Function() action, {
    VoidCallback? onSuccess,
  }) async {
    try {
      await action();
      _updateTask(
        id,
        (task) => task.copyWith(
          status: TransferTaskStatus.success,
          transferredBytes: task.totalBytes ?? task.transferredBytes,
          clearError: true,
        ),
      );
      onSuccess?.call();
    } catch (error) {
      _updateTask(
        id,
        (task) => task.copyWith(
          status: TransferTaskStatus.failed,
          errorMessage: error.toString(),
        ),
      );
    }
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
