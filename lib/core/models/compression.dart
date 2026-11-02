/// 压缩相关的模型。
///
/// 对应服务端 `GET /api/fs/compression` 与 `POST /api/fs/compress`，
/// 结构定义见 `domain/virtual_fs/compression.py`。
library;

/// 某个节点路径的压缩能力。
class CompressionCapability {
  const CompressionCapability({
    required this.formats,
    required this.native,
  });

  factory CompressionCapability.fromJson(Map<String, dynamic> json) {
    final rawFormats = json['formats'];
    return CompressionCapability(
      formats: rawFormats is List
          ? rawFormats.whereType<String>().toList(growable: false)
          : const <String>[],
      native: json['native'] as bool? ?? false,
    );
  }

  /// 服务端当前只会返回 `['zip']` 或空数组。
  final List<String> formats;

  /// 存储端是否原生支持打包。
  ///
  /// - true：服务器就地打包，请求同步返回，通常秒级完成。
  /// - false：需要「下载 → 打包 → 回传」，转入任务队列。
  final bool native;

  /// 空 formats 表示该节点不支持压缩，入口需要置灰。
  bool get supported => formats.isNotEmpty;
}

/// `POST /api/fs/compress` 的结果。
///
/// 服务端有三种形态：
/// 1. `compressed: true` —— 存储端同步打包完成；
/// 2. `queued: true` + `upstream_task_id` —— 存储端异步打包；
/// 3. `queued: true` + `task_id` —— 转入服务端任务队列。
class CompressResult {
  const CompressResult({
    required this.path,
    required this.compressed,
    required this.queued,
    this.taskId,
    this.taskName,
    this.upstreamTaskId,
  });

  factory CompressResult.fromJson(Map<String, dynamic> json) {
    return CompressResult(
      path: json['path'] as String? ?? '',
      compressed: json['compressed'] as bool? ?? false,
      queued: json['queued'] as bool? ?? false,
      taskId: json['task_id'] as String?,
      taskName: json['task_name'] as String?,
      upstreamTaskId: json['upstream_task_id'] as String?,
    );
  }

  /// 目标压缩包路径。
  final String path;

  /// 是否已经打包完成（同步路径）。
  final bool compressed;

  /// 是否仍在后台进行（存储端或服务端队列）。
  final bool queued;

  /// 服务端任务队列 id；非空表示可以在「任务」页跟踪。
  final String? taskId;

  final String? taskName;

  /// 存储端自身的异步任务 id，App 端无法跟踪进度。
  final String? upstreamTaskId;

  /// 已进入服务端队列（能跟踪进度）。
  bool get hasTrackableTask => taskId != null && taskId!.isNotEmpty;
}
