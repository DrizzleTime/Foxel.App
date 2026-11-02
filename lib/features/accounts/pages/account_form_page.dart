import 'dart:async';

import 'package:flutter/material.dart';

import 'package:foxel/core/api/foxel_api.dart';
import 'package:foxel/core/models/account.dart';
import 'package:foxel/core/storage/download_dir_store.dart';
import 'package:foxel/core/theme/design_tokens.dart';
import 'package:foxel/core/widgets/content_frame.dart';
import 'package:foxel/features/accounts/widgets/account_avatar.dart';

/// 新建 / 编辑账户表单。
///
/// 新建：填写服务器与凭据 → 验证并添加。
/// 编辑：修改别名、服务器（需重新验证）与数据隔离开关。
class AccountFormPage extends StatefulWidget {
  const AccountFormPage({
    super.key,
    this.account,
    required this.onSave,
    this.onLogout,
  });

  /// 为 null 时表示新建账户。
  final Account? account;

  /// 保存账户；新建时 [switchAfterAdd] 表示是否立即切换到该账户。
  /// 异步返回后再关闭页面，避免首个账户创建后仍停留在空态。
  final Future<void> Function(Account account, {bool switchAfterAdd}) onSave;

  /// 编辑模式下「退出登录」：清除该账户凭证，账户转为失效状态。
  final Future<void> Function()? onLogout;

  @override
  State<AccountFormPage> createState() => _AccountFormPageState();
}

class _AccountFormPageState extends State<AccountFormPage> {
  final _baseUrlController = TextEditingController();
  final _aliasController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscurePassword = true;
  bool _verifying = false;
  bool _switchAfterAdd = true;
  String? _errorText;
  String? _downloadDir;
  _AccountIsolationDraft? _pendingIsolation;

  bool get _isEdit => widget.account != null;

  @override
  void initState() {
    super.initState();
    final account = widget.account;
    if (account != null) {
      _baseUrlController.text = account.baseUrl;
      _aliasController.text = account.alias;
      _usernameController.text = account.username;
      _loadDownloadDir(account.id);
    }
  }

  Future<void> _loadDownloadDir(String accountId) async {
    final dir = await DownloadDirStore.currentDirFor(accountId);
    if (mounted) {
      setState(() => _downloadDir = dir);
    }
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _aliasController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_verifying) {
      return;
    }
    final baseUrl = _baseUrlController.text.trim();
    final alias = _aliasController.text.trim();
    final username = _usernameController.text.trim();
    final password = _passwordController.text;

    setState(() {
      _errorText = null;
      _verifying = true;
    });

    try {
      final normalized = FoxelApi.normalizeBaseUrl(baseUrl);
      final existing = widget.account;
      final reuseToken =
          existing != null &&
          existing.baseUrl == normalized &&
          existing.token.isNotEmpty &&
          password.isEmpty;

      String token;
      String resolvedUsername;
      String email;
      String avatarUrl;

      if (reuseToken) {
        // 用 try/finally 保证校验失败时也关闭临时客户端，避免连接泄漏。
        final client = FoxelApi(baseUrl: normalized, token: existing.token);
        try {
          final profile = await client.me();
          token = existing.token;
          resolvedUsername = profile.username.isEmpty
              ? existing.username
              : profile.username;
          // 服务端没返回的字段沿用本地值，别把已有邮箱/头像洗掉。
          email = profile.email.isEmpty ? existing.email : profile.email;
          avatarUrl = profile.avatarUrl.isEmpty
              ? existing.avatarUrl
              : profile.avatarUrl;
        } finally {
          client.close();
        }
      } else {
        if (username.isEmpty) {
          throw const FormatException('请输入账号');
        }
        if (password.isEmpty) {
          throw const FormatException('请输入密码');
        }
        final client = FoxelApi(baseUrl: normalized);
        try {
          final session = await client.login(
            username: username,
            password: password,
          );
          token = session.token;
          resolvedUsername = session.username;
          email = session.email;
          avatarUrl = session.avatarUrl;
        } finally {
          client.close();
        }
      }

      final account = Account(
        id: existing?.id ?? Account.generateId(),
        alias: alias,
        baseUrl: normalized,
        username: resolvedUsername,
        token: token,
        email: email,
        avatarUrl: avatarUrl,
        colorValue: existing?.colorValue ?? Account.defaultColorValue,
        createdAt: existing?.createdAt ?? DateTime.now(),
        lastUsedAt: existing?.lastUsedAt,
        isolatedDownloadDir: _isolatedDownloadDir,
        isolatedTasks: _isolatedTasks,
        rememberBrowseState: _rememberBrowseState,
        isolatedCache: _isolatedCache,
        isStale: false,
      );

      if (!mounted) {
        return;
      }
      await widget.onSave(account, switchAfterAdd: _switchAfterAdd);
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _errorText = _friendlyError(error));
    } finally {
      if (mounted) {
        setState(() => _verifying = false);
      }
    }
  }

  bool get _isolatedDownloadDir =>
      _pendingIsolation?.isolatedDownloadDir ??
      widget.account?.isolatedDownloadDir ??
      true;
  bool get _isolatedTasks =>
      _pendingIsolation?.isolatedTasks ?? widget.account?.isolatedTasks ?? true;
  bool get _rememberBrowseState =>
      _pendingIsolation?.rememberBrowseState ??
      widget.account?.rememberBrowseState ??
      true;
  bool get _isolatedCache =>
      _pendingIsolation?.isolatedCache ?? widget.account?.isolatedCache ?? true;

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('FormatException')) {
      return text.replaceFirst(RegExp(r'^.*FormatException: '), '');
    }
    if (text.contains('FoxelApiException')) {
      return text.replaceFirst(RegExp(r'^.*FoxelApiException: '), '');
    }
    if (text.contains('SocketException') ||
        text.contains('ClientException') ||
        text.contains('ConnectionRefused') ||
        text.contains('Failed host lookup')) {
      return '无法连接该服务器，请检查地址或网络';
    }
    return text.replaceFirst(RegExp(r'^Exception: '), '');
  }

  @override
  Widget build(BuildContext context) {
    final account = widget.account;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_isEdit ? '编辑账户' : '添加账户'),
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: ContentFrame(
          child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            if (_isEdit)
              _EditHeader(account: account!)
            else
              const _AddHeader(),
            const SizedBox(height: 16),
            _LabeledField(
              label: '服务器地址',
              child: TextField(
                controller: _baseUrlController,
                decoration: const InputDecoration(
                  hintText: 'https://cloud.foxel.cc',
                  prefixIcon: Icon(Icons.dns_rounded),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _LabeledField(
              label: '显示名称（选填）',
              child: TextField(
                controller: _aliasController,
                decoration: const InputDecoration(
                  hintText: '例如：团队云 · 工作',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_isEdit)
              _ReadOnlyField(
                label: '账号',
                value: account?.accountLabel ?? '',
                icon: Icons.person_rounded,
              )
            else
              _LabeledField(
                label: '账号',
                child: TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    hintText: '用户名或邮箱',
                    prefixIcon: Icon(Icons.person_rounded),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            _LabeledField(
              label: _isEdit ? '密码（修改服务器时需重新验证）' : '密码',
              child: TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                decoration: InputDecoration(
                  hintText: _isEdit ? '留空则使用现有登录态' : '',
                  prefixIcon: const Icon(Icons.lock_rounded),
                  suffixIcon: IconButton(
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
            ),
            if (_errorText != null) ...[
              const SizedBox(height: 10),
              _ErrorText(text: _errorText!),
            ],
            const SizedBox(height: 20),
            const _SectionLabel(text: '数据隔离'),
            const SizedBox(height: 8),
            _IsolationSwitch(
              title: '独立下载目录',
              subtitle: _isEdit
                  ? (_downloadDir ??
                        'Foxel/${DownloadDirStore.folderNameFor(account!)}')
                  : '默认 Download/Foxel/<显示名称，未填则用账户ID>',
              value: _isolatedDownloadDir,
              onChanged: (value) => _updateIsolation(
                isolatedDownloadDir: value,
              ),
            ),
            _IsolationSwitch(
              title: '独立传输队列',
              subtitle: '切换账户时中断本账户任务',
              value: _isolatedTasks,
              onChanged: (value) => _updateIsolation(isolatedTasks: value),
            ),
            _IsolationSwitch(
              title: '记住浏览位置',
              subtitle: '切回时恢复上次目录与排序',
              value: _rememberBrowseState,
              onChanged: (value) =>
                  _updateIsolation(rememberBrowseState: value),
            ),
            _IsolationSwitch(
              title: '独立媒体缓存',
              subtitle: '播放进度随账户清理',
              value: _isolatedCache,
              onChanged: (value) => _updateIsolation(isolatedCache: value),
            ),
            if (!_isEdit) ...[
              const SizedBox(height: 12),
              SwitchListTile.adaptive(
                value: _switchAfterAdd,
                onChanged: (value) =>
                    setState(() => _switchAfterAdd = value),
                title: const Text('添加后立即切换到该账户'),
                contentPadding: EdgeInsets.zero,
              ),
            ],
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _verifying ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadii.tile),
                ),
              ),
              icon: _verifying
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_rounded),
              label: Text(
                _verifying ? '验证中' : (_isEdit ? '保存' : '验证并添加'),
                style: AppText.button,
              ),
            ),
            if (_isEdit) ...[
              const SizedBox(height: 24),
              const _SectionLabel(text: '危险操作'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _confirmLogout(context),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('退出登录（清除凭证）'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFF59E0B),
                ),
              ),
            ],
          ],
          ),
        ),
      ),
    );
  }

  void _updateIsolation({
    bool? isolatedDownloadDir,
    bool? isolatedTasks,
    bool? rememberBrowseState,
    bool? isolatedCache,
  }) {
    // 只改本地 draft：隔离开关与其它字段一样，点「保存」时统一提交。
    // （编辑态下即时保存会重建 API 与整棵页面树，导致列表闪烁与请求中断。）
    setState(() {
      _pendingIsolation = _AccountIsolationDraft(
        isolatedDownloadDir: isolatedDownloadDir ?? _isolatedDownloadDir,
        isolatedTasks: isolatedTasks ?? _isolatedTasks,
        rememberBrowseState: rememberBrowseState ?? _rememberBrowseState,
        isolatedCache: isolatedCache ?? _isolatedCache,
      );
    });
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('退出登录'),
          content: const Text(
            '将清除该账户在本机的登录凭证，账户会保留在列表中并标记为失效，'
            '之后可重新验证。本地下载目录与缓存不受影响。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('退出'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) {
      return;
    }
    // 等凭证清理完成再返回，避免退回后仍看到「已连接」状态。
    await widget.onLogout?.call();
    if (!mounted) {
      return;
    }
    Navigator.of(context).pop();
  }
}

class _AccountIsolationDraft {
  const _AccountIsolationDraft({
    required this.isolatedDownloadDir,
    required this.isolatedTasks,
    required this.rememberBrowseState,
    required this.isolatedCache,
  });

  final bool isolatedDownloadDir;
  final bool isolatedTasks;
  final bool rememberBrowseState;
  final bool isolatedCache;
}

class _AddHeader extends StatelessWidget {
  const _AddHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF0FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: Color(0xFF4C6FFF)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '添加后会创建独立沙箱，下载目录、任务与缓存都与已有账户隔离。',
              style: TextStyle(fontSize: 12.5, color: Color(0xFF3D5BD9)),
            ),
          ),
        ],
      ),
    );
  }
}

class _EditHeader extends StatelessWidget {
  const _EditHeader({required this.account});

  final Account account;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE7ECF2)),
      ),
      child: Row(
        children: [
          AccountAvatar(account: account, size: 52, radius: 17),
          const SizedBox(width: 12),
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
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  account.hostLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF93A0AF),
                  ),
                ),
              ],
            ),
          ),
          if (account.isStale)
            const _SmallTag(text: '失效', color: Color(0xFFF59E0B))
          else
            const _SmallTag(text: '已连接', color: Color(0xFF12B886)),
        ],
      ),
    );
  }
}

class _SmallTag extends StatelessWidget {
  const _SmallTag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2, bottom: 6),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Color(0xFF5C6B7A),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  const _ReadOnlyField({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return _LabeledField(
      label: label,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF7F9FC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE7ECF2)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: const Color(0xFF93A0AF)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: Color(0xFF93A0AF),
                ),
              ),
            ),
            const Text(
              '只读',
              style: TextStyle(fontSize: 11, color: Color(0xFFB6C0CD)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline_rounded, size: 16, color: Color(0xFFE5484D)),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              color: Color(0xFFE5484D),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: Color(0xFF93A0AF),
        letterSpacing: 0.6,
      ),
    );
  }
}

class _IsolationSwitch extends StatelessWidget {
  const _IsolationSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    // 用 Material 承载 SwitchListTile，避免点击反馈被背景色容器遮挡。
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Material(
        color: AppColors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.tile),
          side: const BorderSide(color: AppColors.border),
        ),
        child: SwitchListTile.adaptive(
          value: value,
          onChanged: onChanged,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
          ),
          title: Text(title, style: AppText.itemTitle.copyWith(fontSize: 14)),
          subtitle: Text(subtitle, style: AppText.itemHint),
        ),
      ),
    );
  }
}
