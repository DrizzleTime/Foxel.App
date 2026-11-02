import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:foxel/core/models/account.dart';
import 'package:foxel/core/models/accounts_snapshot.dart';
import 'package:foxel/core/theme/design_tokens.dart';
import 'package:foxel/core/widgets/content_frame.dart';
import 'package:foxel/features/accounts/widgets/account_avatar.dart';

/// 账户管理页。
///
/// - 有账户时：从「设置 → 账户管理」进入的独立二级页（AppBar 返回 + 右上「编辑」），
///   点击列表项即切换账户；「编辑」进入多选模式批量删除。
/// - 无账户时：作为启动首页呈现唯一空态（居中引导 + 添加账户 / 扫码添加），
///   此时不显示返回按钮与底部导航。
class AccountCenterPage extends StatefulWidget {
  const AccountCenterPage({
    super.key,
    required this.snapshot,
    required this.onSwitchAccount,
    required this.onAddAccount,
    required this.onAddManually,
    required this.onAddByQr,
    required this.onEditAccount,
    required this.onRemoveAccounts,
    this.asRoot = false,
  });

  /// 账户数据源（增删改后实时刷新）。
  final ValueListenable<AccountsSnapshot> snapshot;

  /// 切换账户；返回 true 表示切换成功。
  final Future<bool> Function(Account account) onSwitchAccount;

  /// 打开「添加账户」方式选择（手动 / 扫码）。
  final VoidCallback onAddAccount;
  final VoidCallback onAddManually;
  final VoidCallback onAddByQr;
  final ValueChanged<Account> onEditAccount;

  /// 批量移除账户；返回 true 表示已删除。
  final Future<bool> Function(List<Account> accounts) onRemoveAccounts;

  /// 无账户启动时以根页面形态呈现。
  final bool asRoot;

  @override
  State<AccountCenterPage> createState() => _AccountCenterPageState();
}

class _AccountCenterPageState extends State<AccountCenterPage> {
  bool _editing = false;
  final Set<String> _selected = <String>{};

  /// 删除进行中：禁用按钮，避免重复提交。
  bool _deleting = false;

  void _enterEditMode() {
    setState(() {
      _editing = true;
      _selected.clear();
    });
  }

  void _exitEditMode() {
    setState(() {
      _editing = false;
      _selected.clear();
    });
  }

  void _toggle(Account account) {
    setState(() {
      if (!_selected.remove(account.id)) {
        _selected.add(account.id);
      }
    });
  }

  void _toggleAll(List<Account> selectable) {
    setState(() {
      final allSelected =
          selectable.isNotEmpty &&
          selectable.every((account) => _selected.contains(account.id));
      _selected.clear();
      if (!allSelected) {
        _selected.addAll(selectable.map((account) => account.id));
      }
    });
  }

  Future<void> _deleteSelected(List<Account> selectable) async {
    final targets = <Account>[
      for (final account in selectable)
        if (_selected.contains(account.id)) account,
    ];
    if (targets.isEmpty || _deleting) {
      return;
    }
    setState(() => _deleting = true);
    try {
      final removed = await widget.onRemoveAccounts(targets);
      if (!mounted) {
        return;
      }
      if (!removed) {
        return;
      }
      _exitEditMode();
      // 账户已清空且这是二级页：主动返回，避免停在无返回按钮的空态上。
      if (widget.snapshot.value.accounts.isEmpty) {
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.pop();
        }
      }
    } finally {
      if (mounted) {
        setState(() => _deleting = false);
      }
    }
  }

  Future<void> _handleSwitch(Account account) async {
    final ok = await widget.onSwitchAccount(account);
    if (!ok || !mounted) {
      return;
    }
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AccountsSnapshot>(
      valueListenable: widget.snapshot,
      builder: (context, snapshot, _) {
        final active = snapshot.active;
        if (active == null) {
          return _EmptyState(
            asRoot: widget.asRoot,
            onAddManually: widget.onAddManually,
            onAddByQr: widget.onAddByQr,
          );
        }

        // 多选时所有账户都可勾选（包括当前账户）：删掉当前账户后会自动
        // 切到剩余账户，一个不剩则回到空态。
        final selectable = snapshot.accounts;
        final selectedAccounts = <Account>[
          for (final account in selectable)
            if (_selected.contains(account.id)) account,
        ];

        final body = ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            6,
            AppSpacing.page,
            32,
          ),
          children: [
            if (_editing) ...[
              _Group(
                children: [
                  for (final account in selectable)
                    _AccountTile(
                      account: account,
                      isActive: account.id == active.id,
                      runningTasks:
                          snapshot.runningTaskCounts[account.id] ?? 0,
                      editing: true,
                      selected: _selected.contains(account.id),
                      onTap: () => _toggle(account),
                      onEdit: () {},
                      onRemove: () {},
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              InkWell(
                onTap: () => _toggleAll(selectable),
                borderRadius: BorderRadius.circular(AppRadii.tile),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: AppSpacing.sm,
                  ),
                  child: Row(
                    children: [
                      _CheckBox(
                        checked: selectable.isNotEmpty &&
                            selectable.every(
                              (account) => _selected.contains(account.id),
                            ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      const Text(
                        '全选',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      const Expanded(
                        child: Text(
                          '含当前账户；删除后自动切换或回到空态',
                          style: AppText.itemHint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ] else ...[
              _CurrentAccountCard(
                account: active,
                runningTasks: snapshot.runningTaskCounts[active.id] ?? 0,
                onEdit: () => widget.onEditAccount(active),
              ),
              const SizedBox(height: AppSpacing.xl),
              Text(
                snapshot.others.isEmpty
                    ? '其他账户'
                    : '其他账户 · 点选即切换 (${snapshot.others.length})',
                style: AppText.sectionLabel,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (snapshot.others.isEmpty)
                const _EmptyHint(text: '还没有其他账户，添加后可在这里切换')
              else
                _Group(
                  children: [
                    for (final account in snapshot.others)
                      _AccountTile(
                        account: account,
                        isActive: false,
                        runningTasks:
                            snapshot.runningTaskCounts[account.id] ?? 0,
                        editing: false,
                        selected: false,
                        onTap: () => _handleSwitch(account),
                        onEdit: () => widget.onEditAccount(account),
                        onRemove: () => widget.onRemoveAccounts(<Account>[
                          account,
                        ]),
                      ),
                  ],
                ),
            ],
            if (!_editing) ...[
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: widget.onAddAccount,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('添加账户'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.ink,
                  side: const BorderSide(color: AppColors.border),
                  padding: const EdgeInsets.symmetric(
                    vertical: AppSpacing.md,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadii.tile),
                  ),
                ),
              ),
            ],
          ],
        );

        if (widget.asRoot) {
          return Scaffold(
            backgroundColor: AppColors.background,
            body: SafeArea(child: ContentFrame(child: body)),
          );
        }

        if (_editing) {
          return Scaffold(
            backgroundColor: AppColors.background,
            appBar: AppBar(
              automaticallyImplyLeading: false,
              leadingWidth: 76,
              leading: TextButton(
                onPressed: _exitEditMode,
                child: const Text(
                  '取消',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink2,
                  ),
                ),
              ),
              title: Text(
                selectedAccounts.isEmpty
                    ? '选择账户'
                    : '已选择 ${selectedAccounts.length} 项',
              ),
              centerTitle: true,
              actions: [
                TextButton(
                  onPressed: selectedAccounts.isEmpty || _deleting
                      ? null
                      : () => _deleteSelected(selectable),
                  child: Text(
                    '删除',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: selectedAccounts.isEmpty
                          ? AppColors.ink3
                          : AppColors.danger,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
              ],
            ),
            body: SafeArea(top: false, child: ContentFrame(child: body)),
          );
        }

        return Scaffold(
          backgroundColor: AppColors.background,
          appBar: AppBar(
            title: const Text('账户管理'),
            actions: [
              TextButton(
                onPressed: selectable.isEmpty ? null : _enterEditMode,
                child: Text(
                  '编辑',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: selectable.isEmpty
                        ? AppColors.ink3
                        : AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
            ],
          ),
          body: SafeArea(top: false, child: ContentFrame(child: body)),
        );
      },
    );
  }
}

/// 唯一空态：无账户时的启动页与账户管理页空态。
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.asRoot,
    required this.onAddManually,
    required this.onAddByQr,
  });

  final bool asRoot;
  final VoidCallback onAddManually;
  final VoidCallback onAddByQr;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: ContentFrame(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.page,
              AppSpacing.lg,
              AppSpacing.page,
              24,
            ),
            child: Column(
              children: [
                if (asRoot) ...[
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('账户', style: AppText.pageTitle),
                  ),
                  const SizedBox(height: 2),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('还没有账户', style: AppText.pageSubtitle),
                  ),
                ],
                Expanded(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 40),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 76,
                            height: 76,
                            decoration: BoxDecoration(
                              color: AppColors.primarySoft,
                              borderRadius: BorderRadius.circular(26),
                            ),
                            child: const Icon(
                              Icons.person_outline_rounded,
                              size: 34,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 18),
                          const Text('还没有账户', style: AppText.emptyTitle),
                          const SizedBox(height: AppSpacing.sm),
                          const Text(
                            '添加第一个 Foxel 服务器\n即可开始管理文件',
                            textAlign: TextAlign.center,
                            style: AppText.emptyBody,
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: 230,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                FilledButton(
                                  onPressed: onAddManually,
                                  child: const Text('添加账户'),
                                ),
                                const SizedBox(height: 10),
                                OutlinedButton(
                                  onPressed: onAddByQr,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.ink,
                                    side: const BorderSide(
                                      color: AppColors.border,
                                    ),
                                  ),
                                  child: const Text('扫码添加'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CurrentAccountCard extends StatelessWidget {
  const _CurrentAccountCard({
    required this.account,
    required this.runningTasks,
    required this.onEdit,
  });

  final Account account;
  final int runningTasks;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final color = Color(account.colorValue);
    final stale = account.isStale;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.card),
      decoration: AppDecorations.currentAccount(color),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AccountAvatar(
                account: account,
                size: 56,
                radius: AppRadii.avatarLarge,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      account.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      account.accountLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.itemSubtitle,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      account.hostLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.itemHint,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 9,
                  vertical: 4,
                ),
                decoration: AppDecorations.pill(
                  stale ? AppColors.warn : color,
                ),
                child: Text(
                  stale ? '需重新验证' : '使用中',
                  style: AppText.pill.copyWith(
                    color: stale ? AppColors.warn : color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              _StatChip(label: '传输中', value: '$runningTasks', color: color),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _StatChip(
                  label: '上次使用',
                  value: formatLastUsed(account.lastUsedAt),
                  color: AppColors.ink3,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onEdit,
              icon: const Icon(Icons.tune_rounded, size: 18),
              label: const Text('编辑账户信息'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.ink,
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(
                  vertical: AppSpacing.md,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.tile),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: const TextStyle(fontSize: 10.5, color: AppColors.ink3),
          ),
        ],
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.account,
    required this.isActive,
    required this.runningTasks,
    required this.editing,
    required this.selected,
    required this.onTap,
    required this.onEdit,
    required this.onRemove,
  });

  final Account account;

  /// 是否是当前账户（多选时也允许勾选，仅做标记）。
  final bool isActive;
  final int runningTasks;
  final bool editing;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 2,
      ),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (editing) ...[
            _CheckBox(checked: selected),
            const SizedBox(width: AppSpacing.md),
          ],
          AccountAvatar(account: account, size: 40, radius: AppRadii.avatar),
        ],
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              account.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.itemTitle,
            ),
          ),
          if (isActive) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: AppDecorations.pill(Color(account.colorValue)),
              child: Text(
                '使用中',
                style: AppText.pill.copyWith(
                  fontSize: 10,
                  color: Color(account.colorValue),
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        '${account.hostLabel} · ${formatLastUsed(account.lastUsedAt)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppText.itemSubtitle.copyWith(
          color: account.isStale ? AppColors.warn : AppColors.ink3,
        ),
      ),
      trailing: editing
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (account.isStale)
                  const _Tag(text: '失效', color: AppColors.warn)
                else if (runningTasks > 0)
                  _Tag(text: '$runningTasks 传输', color: AppColors.ink3),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert_rounded, size: 20),
                  onSelected: (value) {
                    if (value == 'edit') {
                      onEdit();
                    } else if (value == 'remove') {
                      onRemove();
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'edit', child: Text('编辑账户')),
                    PopupMenuItem(value: 'remove', child: Text('移除账户')),
                  ],
                ),
              ],
            ),
      tileColor: editing && selected
          ? AppColors.primarySoft.withValues(alpha: 0.55)
          : null,
      onTap: onTap,
    );
  }
}

class _CheckBox extends StatelessWidget {
  const _CheckBox({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: checked ? AppColors.primary : Colors.transparent,
        border: checked
            ? null
            : Border.all(color: const Color(0xFFC6CFDD), width: 2),
      ),
      child: checked
          ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
          : null,
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: AppDecorations.pill(color),
      child: Text(text, style: AppText.pill.copyWith(color: color)),
    );
  }
}

/// 分组卡片。
///
/// 必须用 [Material] 而不是带背景色的 Container：ListTile 的背景与水波纹画在
/// 最近的 Material 上，若被 DecoratedBox 覆盖会出现「点击无反馈」。
class _Group extends StatelessWidget {
  const _Group({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Column(children: children),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: AppDecorations.group(),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            size: 18,
            color: AppColors.ink3,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: AppText.itemSubtitle)),
        ],
      ),
    );
  }
}

String formatLastUsed(DateTime? time) {
  if (time == null) {
    return '从未使用';
  }
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) {
    return '刚刚';
  }
  if (diff.inHours < 1) {
    return '${diff.inMinutes} 分钟前';
  }
  if (diff.inDays < 1) {
    return '${diff.inHours} 小时前';
  }
  if (diff.inDays < 30) {
    return '${diff.inDays} 天前';
  }
  final month = time.month.toString().padLeft(2, '0');
  final day = time.day.toString().padLeft(2, '0');
  return '${time.year}-$month-$day';
}
