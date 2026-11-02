/// 当前账户的隔离策略（由 AppRoot 在账户变化时写入）。
///
/// 用于让无法直接拿到 Account 的底层存储（如播放进度）也能遵循
/// 「独立媒体缓存」开关：关闭时多个账户共用同一份缓存分区。
class IsolationPolicy {
  const IsolationPolicy._();

  /// 关闭后播放进度不再按账户分区，改用共享分区。
  static bool cacheIsolated = true;

  /// 缓存分区名：开启隔离时用账户 ID，否则共用 `shared`。
  static String cacheScope(String accountId) =>
      cacheIsolated ? accountId : 'shared';
}
