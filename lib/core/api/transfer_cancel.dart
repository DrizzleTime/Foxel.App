/// 传输取消令牌。
///
/// `http` 包没有原生取消能力：请求发出后只能等它自己结束。这里走「协作式取消」——
/// 传输循环每个 chunk 检查一次令牌，命中就抛 [TransferCancelledException]，
/// 由 `downloadFile` 的清理逻辑删掉半截的 `.part` 文件，再由队列把任务标成「已中断」。
///
/// 这样切账户 / 删账户时不会出现「界面显示失败、磁盘上文件却已经下完」的假中断。
class TransferCancelToken {
  bool _cancelled = false;
  String? _reason;

  bool get isCancelled => _cancelled;

  /// 取消原因（如「已因切换账户中断」），用于任务卡片的说明文案。
  String? get reason => _reason;

  void cancel([String? reason]) {
    _cancelled = true;
    _reason = reason ?? _reason;
  }
}

/// 传输被主动取消（区别于网络错误）。
///
/// 调用方应当把它和普通失败分开处理：取消不是错误，不需要把堆栈甩给用户。
class TransferCancelledException implements Exception {
  const TransferCancelledException([this.reason = '传输已中断']);

  final String reason;

  @override
  String toString() => reason;
}
