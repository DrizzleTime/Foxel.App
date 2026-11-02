/// 服务端任务队列的模型。
///
/// 对应服务端 `GET /api/tasks/queue` 与 `GET /api/tasks/queue/{id}` 的返回，
/// 结构定义见 `domain/tasks/task_queue.py` 中的 `Task` / `TaskProgress`。
library;

/// 任务状态，对应服务端 `TaskStatus`。
enum ServerTaskStatus { pending, running, success, failed, unknown }

/// 任务阶段，对应服务端 `progress.stage`。
///
/// 压缩任务的阶段序列固定为
/// `preparing → downloading → compressing → uploading → completed`。
enum ServerTaskStage {
  preparing,
  downloading,
  compressing,
  uploading,
  completed,
  unknown,
}

/// 任务进度，对应服务端 `TaskProgress`。
class ServerTaskProgress {
  const ServerTaskProgress({
    this.stage,
    this.percent,
    this.bytesDone,
    this.bytesTotal,
    this.detail,
  });

  factory ServerTaskProgress.fromJson(Map<String, dynamic> json) {
    return ServerTaskProgress(
      stage: json['stage'] as String?,
      percent: (json['percent'] as num?)?.toDouble(),
      bytesDone: (json['bytes_done'] as num?)?.toInt(),
      bytesTotal: (json['bytes_total'] as num?)?.toInt(),
      detail: json['detail'] as String?,
    );
  }

  final String? stage;

  /// 0–100 的百分比（服务端用的就是 0–100，不是 0–1）。
  final double? percent;

  final int? bytesDone;
  final int? bytesTotal;

  /// 当前正在处理的文件路径等细节文案。
  final String? detail;

  ServerTaskStage get stageEnum {
    return switch (stage) {
      'preparing' => ServerTaskStage.preparing,
      'downloading' => ServerTaskStage.downloading,
      'compressing' => ServerTaskStage.compressing,
      'uploading' => ServerTaskStage.uploading,
      'completed' => ServerTaskStage.completed,
      _ => ServerTaskStage.unknown,
    };
  }

  /// 0–1 的进度比例，供 LinearProgressIndicator 使用。
  double get fraction => ((percent ?? 0) / 100).clamp(0.0, 1.0).toDouble();
}

/// 服务端队列中的一个任务。
class ServerTask {
  const ServerTask({
    required this.id,
    required this.name,
    required this.status,
    required this.progress,
    required this.meta,
    required this.taskInfo,
    this.error,
  });

  factory ServerTask.fromJson(Map<String, dynamic> json) {
    final rawProgress = json['progress'];
    final rawMeta = json['meta'];
    final rawInfo = json['task_info'];
    return ServerTask(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      status: _statusFromName(json['status'] as String?),
      progress: rawProgress is Map<String, dynamic>
          ? ServerTaskProgress.fromJson(rawProgress)
          : null,
      meta: rawMeta is Map<String, dynamic> ? rawMeta : const {},
      taskInfo: rawInfo is Map<String, dynamic> ? rawInfo : const {},
      error: json['error'] as String?,
    );
  }

  /// 服务端生成的 uuid hex。
  final String id;

  /// 任务类型名，压缩任务固定为 `compress_archive`。
  final String name;

  final ServerTaskStatus status;
  final ServerTaskProgress? progress;

  /// 服务端在任务运行中补充的元数据：
  /// `sources` / `dst` / `files` / `bytes` / `archive_bytes` / `path`。
  final Map<String, dynamic> meta;

  /// 入队时的原始参数（含 `user_id`、挂载 `bindings`），仅供重试使用。
  final Map<String, dynamic> taskInfo;

  final String? error;

  static ServerTaskStatus _statusFromName(String? name) {
    return switch (name) {
      'pending' => ServerTaskStatus.pending,
      'running' => ServerTaskStatus.running,
      'success' => ServerTaskStatus.success,
      'failed' => ServerTaskStatus.failed,
      _ => ServerTaskStatus.unknown,
    };
  }

  /// 是否为本阶段关注的压缩任务。
  bool get isCompression => name == 'compress_archive';

  /// 目标压缩包路径。运行中取自 `meta.dst`，完成后 `meta.path` 更准。
  String? get archivePath {
    final path = meta['path'];
    if (path is String && path.isNotEmpty) {
      return path;
    }
    final dst = meta['dst'];
    if (dst is String && dst.isNotEmpty) {
      return dst;
    }
    final infoDst = taskInfo['dst'];
    if (infoDst is String && infoDst.isNotEmpty) {
      return infoDst;
    }
    return null;
  }

  /// 压缩包文件名（列表主标题）。
  String get archiveName {
    final path = archivePath;
    if (path == null || path.isEmpty || path == '/') {
      return '压缩包';
    }
    final index = path.lastIndexOf('/');
    final name = index >= 0 ? path.substring(index + 1) : path;
    return name.isEmpty ? '压缩包' : name;
  }

  /// 归档的源路径列表，重试时复用。
  List<String> get sources {
    final raw = meta['sources'] ?? taskInfo['sources'];
    if (raw is List) {
      return raw.whereType<String>().where((item) => item.isNotEmpty).toList();
    }
    return const <String>[];
  }

  int? get fileCount => (meta['files'] as num?)?.toInt();

  /// 打包前的原始总字节数。
  int? get sourceBytes => (meta['bytes'] as num?)?.toInt();

  /// 打包后的压缩包字节数（完成后才有）。
  int? get archiveBytes => (meta['archive_bytes'] as num?)?.toInt();

  bool get isActive =>
      status == ServerTaskStatus.pending || status == ServerTaskStatus.running;

  /// 状态文案；运行中显示阶段名，比单纯的「进行中」更有信息量。
  String get statusText {
    return switch (status) {
      ServerTaskStatus.pending => '等待中',
      ServerTaskStatus.success => '已完成',
      ServerTaskStatus.failed => '失败',
      ServerTaskStatus.running => switch (progress?.stageEnum) {
        ServerTaskStage.preparing => '准备中',
        ServerTaskStage.downloading => '下载中',
        ServerTaskStage.compressing => '打包中',
        ServerTaskStage.uploading => '回传中',
        ServerTaskStage.completed => '已完成',
        _ => '进行中',
      },
      ServerTaskStatus.unknown => '未知',
    };
  }
}
