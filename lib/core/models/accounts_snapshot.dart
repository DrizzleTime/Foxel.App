import 'package:foxel/core/models/account.dart';

/// 账户列表 + 当前账户 + 各账户在跑的任务数。
///
/// 用 [ValueNotifier] 推送给 push 出来的账户管理页，保证增删改后页面实时刷新
/// （push 的路由不会随根组件重建）。
class AccountsSnapshot {
  const AccountsSnapshot({
    required this.accounts,
    required this.activeId,
    this.runningTaskCounts = const <String, int>{},
  });

  static const empty = AccountsSnapshot(accounts: <Account>[], activeId: null);

  final List<Account> accounts;
  final String? activeId;
  final Map<String, int> runningTaskCounts;

  Account? get active {
    for (final account in accounts) {
      if (account.id == activeId) {
        return account;
      }
    }
    return accounts.isEmpty ? null : accounts.first;
  }

  List<Account> get others {
    final current = active;
    return <Account>[
      for (final account in accounts)
        if (account.id != current?.id) account,
    ];
  }
}
