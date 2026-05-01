import 'package:flutter/material.dart';

import 'package:foxel/features/drive/controllers/transfer_task_controller.dart';

class TransferTasksPage extends StatelessWidget {
  const TransferTasksPage({super.key, required this.controller});

  final TransferTaskController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      body: SafeArea(
        bottom: false,
        child: ValueListenableBuilder<List<TransferTask>>(
          valueListenable: controller.tasks,
          builder: (context, tasks, _) {
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _TasksHeader(
                    tasks: tasks,
                    onClearFinished: controller.clearFinished,
                  ),
                ),
                if (tasks.isEmpty)
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: _EmptyTasksView(),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 118),
                    sliver: SliverList.separated(
                      itemBuilder: (context, index) {
                        return _TaskTile(task: tasks[index]);
                      },
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemCount: tasks.length,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _TasksHeader extends StatelessWidget {
  const _TasksHeader({required this.tasks, required this.onClearFinished});

  final List<TransferTask> tasks;
  final VoidCallback onClearFinished;

  @override
  Widget build(BuildContext context) {
    final runningCount = tasks
        .where((task) => task.status == TransferTaskStatus.running)
        .length;
    final finishedCount = tasks.length - runningCount;
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE3E9F0))),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFF276EF1).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.assignment_rounded,
              color: Color(0xFF276EF1),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '任务',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  tasks.isEmpty
                      ? '暂无上传或下载任务'
                      : '$runningCount 个进行中 · $finishedCount 个已结束',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF5D6B7A),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: '清理已完成',
            onPressed: finishedCount == 0 ? null : onClearFinished,
            icon: const Icon(Icons.cleaning_services_rounded),
          ),
        ],
      ),
    );
  }
}

class _TaskTile extends StatelessWidget {
  const _TaskTile({required this.task});

  final TransferTask task;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUpload = task.type == TransferTaskType.upload;
    final progress = task.progress;
    final statusColor = _statusColor(task.status);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isUpload ? Icons.cloud_upload_rounded : Icons.downloading_rounded,
              color: statusColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        task.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _statusText(task.status),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  isUpload
                      ? '上传到 ${task.remotePath}'
                      : '下载自 ${task.remotePath}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF667085),
                  ),
                ),
                const SizedBox(height: 10),
                LinearProgressIndicator(
                  value: task.status == TransferTaskStatus.running
                      ? progress
                      : task.status == TransferTaskStatus.success
                      ? 1
                      : progress,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(999),
                  backgroundColor: const Color(0xFFE6ECF2),
                  color: statusColor,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _progressText(task),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF667085),
                        ),
                      ),
                    ),
                    if (progress != null)
                      Text(
                        '${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF667085),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                  ],
                ),
                if (task.errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    task.errorMessage!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFFD92D20),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _statusColor(TransferTaskStatus status) {
    return switch (status) {
      TransferTaskStatus.running => const Color(0xFF276EF1),
      TransferTaskStatus.success => const Color(0xFF039855),
      TransferTaskStatus.failed => const Color(0xFFD92D20),
    };
  }

  String _statusText(TransferTaskStatus status) {
    return switch (status) {
      TransferTaskStatus.running => '进行中',
      TransferTaskStatus.success => '完成',
      TransferTaskStatus.failed => '失败',
    };
  }

  String _progressText(TransferTask task) {
    final total = task.totalBytes;
    if (total == null || total <= 0) {
      return '${_formatSize(task.transferredBytes)} 已传输';
    }
    return '${_formatSize(task.transferredBytes)} / ${_formatSize(total)}';
  }

  String _formatSize(int size) {
    if (size < 1024) {
      return '$size B';
    }
    if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    }
    if (size < 1024 * 1024 * 1024) {
      return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(size / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }
}

class _EmptyTasksView extends StatelessWidget {
  const _EmptyTasksView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF1FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.assignment_outlined,
                color: Color(0xFF276EF1),
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '暂无任务',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '上传或下载文件后，会在这里显示进度。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: const Color(0xFF667085),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
