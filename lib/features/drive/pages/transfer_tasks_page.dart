import 'dart:async';

import 'package:flutter/material.dart';

import 'package:foxel/core/api/foxel_api.dart';
import 'package:foxel/core/models/server_task.dart';
import 'package:foxel/core/theme/design_tokens.dart';
import 'package:foxel/features/drive/controllers/server_task_controller.dart';
import 'package:foxel/features/drive/controllers/transfer_task_controller.dart';
import 'package:foxel/features/drive/pages/compress_sheet.dart';

/// 任务页：本地传输任务 + 服务端任务。
///
/// 两者语义不同，用分段隔离：
/// - 传输：本机发起的上传 / 下载，进度由 [TransferTaskController] 在本地维护；
/// - 服务端任务：服务端队列里的压缩任务，进度只能靠轮询 [ServerTaskController]。
class TransferTasksPage extends StatefulWidget {
  const TransferTasksPage({
    super.key,
    required this.controller,
    required this.api,
  });

  final TransferTaskController controller;
  final FoxelApi api;

  @override
  State<TransferTasksPage> createState() => _TransferTasksPageState();
}

class _TransferTasksPageState extends State<TransferTasksPage> {
  late final ServerTaskController _serverTasks = ServerTaskController(
    api: widget.api,
  );

  /// 0 = 本地传输，1 = 服务端任务。
  int _segment = 0;

  @override
  void initState() {
    super.initState();
    _serverTasks.start();
  }

  @override
  void dispose() {
    _serverTasks.dispose();
    super.dispose();
  }

  void _selectSegment(int index) {
    if (_segment == index) {
      return;
    }
    setState(() => _segment = index);
    // 切到服务端分段时立刻拉一次，避免用户刚提交完压缩却看到旧列表。
    if (index == 1) {
      unawaited(_serverTasks.refresh());
    }
  }

  Future<void> _retryServerTask(ServerTask task) async {
    final sources = task.sources;
    if (sources.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('该任务缺少源路径，无法重试')),
      );
      return;
    }
    final dst = task.archivePath;
    final dir = dst == null ? '/' : FoxelApi.parentPath(dst);
    var name = task.archiveName;
    if (name.toLowerCase().endsWith('.zip')) {
      name = name.substring(0, name.length - 4);
    }
    final outcome = await showCompressSheet(
      context: context,
      api: widget.api,
      sources: sources,
      initialDir: dir,
      defaultName: name,
      sourceBytes: task.sourceBytes ?? 0,
      formatSize: _formatSize,
    );
    if (outcome != null && mounted) {
      unawaited(_serverTasks.refresh());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            outcome.queued
                ? '已重新提交，进度稍后刷新'
                : '已创建 ${outcome.name}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([
            widget.controller.tasks,
            _serverTasks.tasks,
            _serverTasks.loading,
            _serverTasks.error,
          ]),
          builder: (context, _) {
            final localTasks = widget.controller.tasks.value;
            final serverTasks = _serverTasks.tasks.value;
            return CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _TasksHeader(
                    segment: _segment,
                    localTasks: localTasks,
                    serverTasks: serverTasks,
                    onClearFinished: widget.controller.clearFinished,
                    onRefreshServer: () => unawaited(_serverTasks.refresh()),
                  ),
                ),
                SliverToBoxAdapter(
                  child: _SegmentBar(
                    segment: _segment,
                    onSelected: _selectSegment,
                  ),
                ),
                if (_segment == 0) ..._buildLocalSlivers(localTasks)
                else ..._buildServerSlivers(serverTasks),
              ],
            );
          },
        ),
      ),
    );
  }

  List<Widget> _buildLocalSlivers(List<TransferTask> tasks) {
    if (tasks.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _EmptyTasksView(
            icon: Icons.assignment_outlined,
            title: '暂无传输任务',
            body: '上传或下载文件后，会在这里显示进度。',
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 150),
        sliver: SliverList.separated(
          itemBuilder: (context, index) => _TaskTile(task: tasks[index]),
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemCount: tasks.length,
        ),
      ),
    ];
  }

  List<Widget> _buildServerSlivers(List<ServerTask> tasks) {
    if (_serverTasks.loading.value && tasks.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    final error = _serverTasks.error.value;
    if (tasks.isEmpty && error != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _EmptyTasksView(
            icon: Icons.cloud_off_rounded,
            title: '无法读取服务端任务',
            body: error,
          ),
        ),
      ];
    }
    if (tasks.isEmpty) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _EmptyTasksView(
            icon: Icons.archive_outlined,
            title: '暂无服务端压缩任务',
            body: '在文件页选中项目后点「压缩」，需要服务器中转的打包任务会出现在这里。',
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 150),
        sliver: SliverList.separated(
          itemBuilder: (context, index) => _ServerTaskTile(
            task: tasks[index],
            onRetry: () => unawaited(_retryServerTask(tasks[index])),
          ),
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemCount: tasks.length,
        ),
      ),
    ];
  }
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
  return '${(size / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
}

class _TasksHeader extends StatelessWidget {
  const _TasksHeader({
    required this.segment,
    required this.localTasks,
    required this.serverTasks,
    required this.onClearFinished,
    required this.onRefreshServer,
  });

  final int segment;
  final List<TransferTask> localTasks;
  final List<ServerTask> serverTasks;
  final VoidCallback onClearFinished;
  final VoidCallback onRefreshServer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isServer = segment == 1;

    final int runningCount;
    final int finishedCount;
    final String subtitle;
    if (isServer) {
      runningCount = serverTasks.where((task) => task.isActive).length;
      finishedCount = serverTasks.length - runningCount;
      subtitle = serverTasks.isEmpty
          ? '暂无服务端压缩任务'
          : '$runningCount 个进行中 · $finishedCount 个已结束';
    } else {
      runningCount = localTasks
          .where((task) => task.status == TransferTaskStatus.running)
          .length;
      finishedCount = localTasks.length - runningCount;
      subtitle = localTasks.isEmpty
          ? '暂无上传或下载任务'
          : '$runningCount 个进行中 · $finishedCount 个已结束';
    }

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
            child: Icon(
              isServer
                  ? Icons.archive_rounded
                  : Icons.assignment_rounded,
              color: const Color(0xFF276EF1),
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
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF5D6B7A),
                  ),
                ),
              ],
            ),
          ),
          if (isServer)
            IconButton(
              tooltip: '刷新',
              onPressed: onRefreshServer,
              icon: const Icon(Icons.refresh_rounded),
            )
          else
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

/// 传输 / 服务端任务 的分段控件。
class _SegmentBar extends StatelessWidget {
  const _SegmentBar({required this.segment, required this.onSelected});

  final int segment;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          _SegmentChip(
            label: '传输',
            icon: Icons.swap_vert_rounded,
            selected: segment == 0,
            onTap: () => onSelected(0),
          ),
          const SizedBox(width: 6),
          _SegmentChip(
            label: '服务端任务',
            icon: Icons.cloud_queue_rounded,
            selected: segment == 1,
            onTap: () => onSelected(1),
          ),
        ],
      ),
    );
  }
}

class _SegmentChip extends StatelessWidget {
  const _SegmentChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.pill),
        child: Container(
          height: 34,
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : Colors.white,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected ? Colors.white : AppColors.ink3,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: selected ? Colors.white : AppColors.ink3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 服务端压缩任务卡片。
class _ServerTaskTile extends StatelessWidget {
  const _ServerTaskTile({required this.task, required this.onRetry});

  final ServerTask task;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final status = task.status;
    final color = switch (status) {
      ServerTaskStatus.pending || ServerTaskStatus.running => AppColors.primary,
      ServerTaskStatus.success => AppColors.ok,
      ServerTaskStatus.failed => AppColors.danger,
      ServerTaskStatus.unknown => AppColors.ink3,
    };
    final progress = task.progress;
    final fraction = status == ServerTaskStatus.success
        ? 1.0
        : (progress?.fraction ?? 0.0);

    final sourceBytes = task.sourceBytes;
    final bytesDone = progress?.bytesDone;
    final bytesTotal = progress?.bytesTotal ?? sourceBytes;
    final bytesLabel = switch (status) {
      ServerTaskStatus.success =>
        task.archiveBytes != null
            ? '压缩包 ${_formatSize(task.archiveBytes!)}'
            : '已完成',
      _ =>
        bytesDone != null && bytesTotal != null && bytesTotal > 0
            ? '${_formatSize(bytesDone)} / ${_formatSize(bytesTotal)}'
            : (sourceBytes != null && sourceBytes > 0
                  ? '共 ${_formatSize(sourceBytes)}'
                  : ''),
    };

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.archive_rounded, color: color),
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
                            task.archiveName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          task.statusText,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _subtitleFor(task),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF667085),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: fraction,
              minHeight: 6,
              backgroundColor: const Color(0xFFE6ECF2),
              color: color,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  bytesLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF667085),
                  ),
                ),
              ),
              if (task.isActive)
                Text(
                  '${(fraction * 100).clamp(0, 100).toStringAsFixed(0)}%',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF667085),
                  ),
                ),
            ],
          ),
          if (task.isActive) ...[
            const SizedBox(height: 9),
            _StageStrip(stage: progress?.stageEnum),
            if (_detailText(progress) case final detail?) ...[
              const SizedBox(height: 7),
              Text(
                '正在读取 $detail',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.ink3,
                ),
              ),
            ],
          ],
          if (status == ServerTaskStatus.failed) ...[
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    task.error ?? '压缩失败',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.danger,
                      height: 1.55,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: task.sources.isEmpty ? null : onRetry,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 30),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    foregroundColor: AppColors.ink2,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                    ),
                  ),
                  child: const Text(
                    '改名重试',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _subtitleFor(ServerTask task) {
    final parts = <String>[];
    final count = task.fileCount;
    if (count != null) {
      parts.add('$count 个文件');
    }
    final dir = task.archivePath == null
        ? null
        : FoxelApi.parentPath(task.archivePath!);
    if (dir != null && dir.isNotEmpty) {
      parts.add(dir);
    }
    return parts.isEmpty ? '压缩任务' : parts.join(' · ');
  }

  /// 当前正在处理的文件；空串按「没有」处理，避免渲染出一行「正在读取 」。
  static String? _detailText(ServerTaskProgress? progress) {
    final detail = progress?.detail;
    if (detail == null || detail.isEmpty) {
      return null;
    }
    return detail;
  }
}

/// 四段阶段条：准备 → 下载 → 打包 → 回传。
///
/// 服务端的 stage 是「当前阶段」，这里把已走过的阶段也画成实色，
/// 否则进度条会看起来像在倒退。
class _StageStrip extends StatelessWidget {
  const _StageStrip({required this.stage});

  final ServerTaskStage? stage;

  static const _labels = <String>['准备', '下载', '打包', '回传'];

  int get _current {
    return switch (stage) {
      ServerTaskStage.preparing => 0,
      ServerTaskStage.downloading => 1,
      ServerTaskStage.compressing => 2,
      ServerTaskStage.uploading => 3,
      ServerTaskStage.completed => 4,
      _ => 0,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var index = 0; index < _labels.length; index++) ...[
          if (index > 0) const SizedBox(width: 5),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: index < _current
                        ? AppColors.primary.withValues(alpha: 0.45)
                        : index == _current
                        ? AppColors.primary
                        : const Color(0xFFE6ECF2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _labels[index],
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: index <= _current ? AppColors.primary : AppColors.ink3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
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
}

class _EmptyTasksView extends StatelessWidget {
  const _EmptyTasksView({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

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
              child: Icon(icon, color: const Color(0xFF276EF1), size: 34),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
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
