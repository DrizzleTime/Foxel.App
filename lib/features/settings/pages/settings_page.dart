import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:foxel/core/models/account.dart';
import 'package:foxel/core/storage/desktop_window_store.dart';
import 'package:foxel/core/storage/download_dir_store.dart';
import 'package:foxel/core/theme/design_tokens.dart';
import 'package:foxel/core/widgets/content_frame.dart';
import 'package:foxel/features/accounts/widgets/account_avatar.dart';
import 'package:foxel/core/app_version.dart';

/// 设置页（底部导航第三个 Tab）。
///
/// 账户管理的入口放在这里：顶部当前账户卡内嵌「账户管理」入口行，
/// 点击进入独立的账户管理页。
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.account,
    required this.accountCount,
    required this.onOpenAccountCenter,
    required this.onAddAccount,
    required this.onClearLocalData,
  });

  final Account account;
  final int accountCount;
  final VoidCallback onOpenAccountCenter;
  final VoidCallback onAddAccount;
  final ValueChanged<Account> onClearLocalData;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String? _downloadDir;
  int? _usageBytes;
  bool _startMinimized = false;

  @override
  void initState() {
    super.initState();
    _loadDownloadDir();
    _loadUsage();
    _loadStartMinimized();
  }

  @override
  void didUpdateWidget(covariant SettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account.id != widget.account.id) {
      _loadDownloadDir();
      _loadUsage();
    }
  }

  Future<void> _loadDownloadDir() async {
    final accountId = widget.account.id;
    final dir = await DownloadDirStore.currentDirFor(
      widget.account.id,
      account: widget.account,
    );
    // 统计/查询期间可能已切换账户：只接受当前账户的结果。
    if (!mounted || widget.account.id != accountId) {
      return;
    }
    setState(() => _downloadDir = dir);
  }

  Future<void> _loadUsage() async {
    final accountId = widget.account.id;
    final bytes = await DownloadDirStore.dirSizeBytes(
      widget.account.id,
      account: widget.account,
    );
    if (!mounted || widget.account.id != accountId) {
      return;
    }
    setState(() => _usageBytes = bytes);
  }

  Future<void> _loadStartMinimized() async {
    final enabled = await DesktopWindowStore.startMinimized();
    if (!mounted) {
      return;
    }
    setState(() => _startMinimized = enabled);
  }

  /// 开关立即落盘，但只影响**下一次**启动：当前进程的窗口已经创建，
  /// 不在这里做隐藏动作，避免用户拨一下开关窗口就消失。
  Future<void> _setStartMinimized(bool value) async {
    setState(() => _startMinimized = value);
    await DesktopWindowStore.setStartMinimized(value);
    if (!mounted) {
      return;
    }
    _showMessage(value ? '下次启动将只驻留系统托盘' : '下次启动将直接显示主窗口');
  }

  String get _usageLabel {
    final bytes = _usageBytes;
    if (bytes == null) {
      return '计算中';
    }
    if (bytes == 0) {
      return '暂无已下载文件';
    }
    return '本地已下载 ${_formatBytes(bytes)}';
  }

  static String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var value = bytes.toDouble();
    var index = 0;
    while (value >= 1024 && index < units.length - 1) {
      value /= 1024;
      index++;
    }
    final text = value >= 100 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
    return '$text ${units[index]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        bottom: false,
        child: ContentFrame(
          child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            AppSpacing.lg,
            AppSpacing.page,
            AppSpacing.navBottom,
          ),
          children: [
            const Text('设置', style: AppText.pageTitle),
            const SizedBox(height: 2),
            Text(
              widget.account.displayName,
              style: AppText.pageSubtitle,
            ),
            const SizedBox(height: AppSpacing.lg),
            _CurrentAccountCard(
              account: widget.account,
              accountCount: widget.accountCount,
              onOpenAccountCenter: widget.onOpenAccountCenter,
            ),
            const SizedBox(height: AppSpacing.xl),
            const Text('通用', style: AppText.sectionLabel),
            const SizedBox(height: AppSpacing.sm),
            _Group(
              children: [
                _SettingsRow(
                  icon: Icons.download_rounded,
                  title: '下载目录',
                  subtitle: _downloadDir ?? '加载中',
                  onTap: _editDownloadDir,
                ),
                _SettingsRow(
                  icon: Icons.storage_rounded,
                  title: '存储用量',
                  subtitle: _usageLabel,
                  onTap: _loadUsage,
                ),
                // 托盘常驻只有 Windows runner 实现，其他平台不展示这个开关。
                if (DesktopWindowStore.isSupported)
                  _SettingsSwitchRow(
                    icon: Icons.minimize_rounded,
                    title: '启动时最小化到托盘',
                    subtitle: _startMinimized
                        ? '启动后只显示托盘图标，不弹出主窗口'
                        : '启动时显示主窗口，同时常驻托盘',
                    value: _startMinimized,
                    onChanged: _setStartMinimized,
                  ),
                const _SettingsRow(
                  icon: Icons.info_outline_rounded,
                  title: '关于 Foxel',
                  subtitle: '版本 $appVersion',
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            const Text('当前账户', style: AppText.sectionLabel),
            const SizedBox(height: AppSpacing.sm),
            _Group(
              children: [
                _SettingsRow(
                  icon: Icons.cleaning_services_rounded,
                  title: '清除本地数据',
                  subtitle: '删除缓存与下载目录配置，保留账户',
                  warning: true,
                  onTap: () => widget.onClearLocalData(widget.account),
                ),
                _SettingsRow(
                  icon: Icons.add_rounded,
                  title: '添加账户',
                  subtitle: '手动输入或扫码登录',
                  onTap: widget.onAddAccount,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Text(
                '切换账户、添加或移除账户请进入「账户管理」',
                style: AppText.itemHint,
              ),
            ),
          ],
          ),
        ),
      ),
    );
  }

  /// 下载目录设置：支持手动输入、系统目录浏览、恢复默认（按账户隔离）。
  Future<void> _editDownloadDir() async {
    final account = widget.account;
    final current =
        _downloadDir ??
        await DownloadDirStore.currentDirFor(account.id, account: account);
    // 默认目录优先使用显示名称（未填写时才是账户 ID）。
    final defaultDir = await DownloadDirStore.defaultDirForAccount(account);
    if (!mounted) {
      return;
    }
    final controller = TextEditingController(text: current);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('下载目录'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '当前账户的下载位置，可按账户分别设置。',
                style: AppText.itemHint,
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: '下载目录完整路径',
                  prefixIcon: Icon(Icons.folder_rounded),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      // 系统目录选择器：桌面端返回真实路径，Android 走 SAF 选择器。
                      final selected = await FilePicker.platform
                          .getDirectoryPath(
                            dialogTitle: '选择下载目录',
                          );
                      // 选择器期间对话框可能已被关闭，controller 随之释放
                      if (!mounted || !dialogContext.mounted) {
                        return;
                      }
                      if (selected != null && selected.isNotEmpty) {
                        controller.text = selected;
                      }
                    },
                    icon: const Icon(Icons.folder_open_rounded, size: 18),
                    label: const Text('浏览...'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => controller.text = defaultDir,
                    child: const Text('恢复默认'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '默认：$defaultDir',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.ink3,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    final selectedPath = controller.text.trim();
    controller.dispose();

    if (confirmed != true || !mounted || selectedPath.isEmpty) {
      return;
    }
    await _applyDownloadDir(account, selectedPath);
  }

  Future<void> _applyDownloadDir(Account account, String path) async {
    final writable = await DownloadDirStore.isWritable(path);
    if (!writable) {
      if (!mounted) {
        return;
      }
      // Android 10+ 写公共目录需要「所有文件访问」权限，桌面端不需要。
      if (!kIsWeb && Platform.isAndroid) {
        final granted = await DownloadDirStore.hasAllFilesAccess();
        if (!granted) {
          final goSettings = await showDialog<bool>(
            context: context,
            builder: (dialogContext) {
              return AlertDialog(
                title: const Text('目录暂不可写'),
                content: const Text(
                  'Android 10 及以上系统需要「所有文件访问」权限才能写入该目录，'
                  '是否前往系统设置开启？开启后返回应用重试即可。',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(dialogContext).pop(false),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('去授权'),
                  ),
                ],
              );
            },
          );
          if (goSettings == true) {
            await DownloadDirStore.requestAllFilesAccess();
          }
          return;
        }
      }
      if (mounted) {
        _showMessage('该目录不可写入：$path');
      }
      return;
    }

    await DownloadDirStore.setDirFor(account.id, path);
    await _loadDownloadDir();
    if (mounted) {
      _showMessage('下载目录已更新');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _CurrentAccountCard extends StatelessWidget {
  const _CurrentAccountCard({
    required this.account,
    required this.accountCount,
    required this.onOpenAccountCenter,
  });

  final Account account;
  final int accountCount;
  final VoidCallback onOpenAccountCenter;

  @override
  Widget build(BuildContext context) {
    final color = Color(account.colorValue);
    return Container(
      decoration: AppDecorations.currentAccount(color),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.card),
            child: Row(
              children: [
                AccountAvatar(
                  account: account,
                  size: 48,
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
                          fontSize: 15.5,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${account.accountLabel} · ${account.hostLabel}',
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
                    account.isStale ? AppColors.warn : color,
                  ),
                  child: Text(
                    account.isStale ? '需重新验证' : '使用中',
                    style: AppText.pill.copyWith(
                      color: account.isStale ? AppColors.warn : color,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AppColors.border),
          InkWell(
            onTap: onOpenAccountCenter,
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(AppRadii.card),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.card,
                AppSpacing.md,
                AppSpacing.card,
                AppSpacing.lg,
              ),
              child: Row(
                children: [
                  Icon(Icons.manage_accounts_rounded, size: 19, color: color),
                  const SizedBox(width: 10),
                  Text(
                    '账户管理',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    '共 $accountCount 个账户',
                    style: AppText.itemHint,
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: AppColors.ink3,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 分组卡片：用 [Material] 承载 ListTile，保证点击水波纹可见。
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

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.warning = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final color = warning ? AppColors.warn : AppColors.ink2;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 2,
      ),
      leading: Icon(icon, size: 20, color: color),
      title: Text(
        title,
        style: AppText.itemTitle.copyWith(
          color: warning ? AppColors.warn : AppColors.ink,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppText.itemHint,
      ),
      trailing: onTap == null
          ? null
          : Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.ink3),
      onTap: onTap,
    );
  }
}

/// 带开关的设置行：版式与 [_SettingsRow] 对齐，尾部换成 [Switch]。
///
/// 整行可点（与开关同效），避免用户只有精确点到 48dp 的开关才能切换。
class _SettingsSwitchRow extends StatelessWidget {
  const _SettingsSwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: 2,
      ),
      leading: Icon(icon, size: 20, color: AppColors.ink2),
      title: Text(title, style: AppText.itemTitle),
      subtitle: Text(
        subtitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: AppText.itemHint,
      ),
      trailing: Switch(value: value, onChanged: onChanged),
      onTap: () => onChanged(!value),
    );
  }
}
