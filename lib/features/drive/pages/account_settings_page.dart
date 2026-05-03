import 'package:flutter/material.dart';

import 'package:foxel/core/api/foxel_api.dart';
import 'package:foxel/core/models/license_info.dart';

class AccountSettingsPage extends StatefulWidget {
  const AccountSettingsPage({
    super.key,
    required this.username,
    required this.email,
    required this.avatarUrl,
    required this.baseUrl,
    required this.licenseInfo,
    required this.onVerifyLicense,
    required this.onSwitchServer,
    required this.onLogout,
  });

  final String username;
  final String email;
  final String avatarUrl;
  final String baseUrl;
  final LicenseInfo? licenseInfo;
  final Future<LicenseInfo> Function(String licenseKey) onVerifyLicense;
  final VoidCallback onSwitchServer;
  final VoidCallback onLogout;

  @override
  State<AccountSettingsPage> createState() => _AccountSettingsPageState();
}

class _AccountSettingsPageState extends State<AccountSettingsPage> {
  final _licenseController = TextEditingController();
  bool _verifyingLicense = false;

  @override
  void initState() {
    super.initState();
    _licenseController.text = widget.licenseInfo?.licenseKey ?? '';
  }

  @override
  void didUpdateWidget(covariant AccountSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextKey = widget.licenseInfo?.licenseKey ?? '';
    if (oldWidget.licenseInfo?.licenseKey != nextKey &&
        _licenseController.text != nextKey) {
      _licenseController.text = nextKey;
    }
  }

  @override
  void dispose() {
    _licenseController.dispose();
    super.dispose();
  }

  Future<void> _verifyLicense() async {
    final licenseKey = _licenseController.text.trim();
    if (licenseKey.isEmpty) {
      _showMessage('请输入 License Key');
      return;
    }
    setState(() => _verifyingLicense = true);
    final info = await widget.onVerifyLicense(licenseKey);
    if (!mounted) {
      return;
    }
    setState(() => _verifyingLicense = false);
    _showMessage(info.isPro ? '验证成功' : '验证未通过');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 126),
          children: [
            Text(
              '设置',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            _AccountCard(
              username: widget.username,
              email: widget.email,
              avatarUrl: widget.avatarUrl,
              baseUrl: widget.baseUrl,
            ),
            const SizedBox(height: 14),
            _LicenseCard(
              info: widget.licenseInfo,
              appAddress: FoxelApi.appAddressFromBaseUrl(widget.baseUrl),
              controller: _licenseController,
              verifying: _verifyingLicense,
              onVerify: _verifyLicense,
            ),
            const SizedBox(height: 14),
            _SettingsGroup(
              children: [
                _SettingsRow(
                  icon: Icons.sync_alt_rounded,
                  title: '切换服务或重新登录',
                  subtitle: '修改后端地址、账号或刷新登录状态',
                  onTap: widget.onSwitchServer,
                ),
                _SettingsRow(
                  icon: Icons.logout_rounded,
                  title: '退出登录',
                  subtitle: '清除本地登录凭证',
                  destructive: true,
                  onTap: () => _confirmLogout(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('退出登录'),
          content: const Text('确定清除本地登录状态？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('退出'),
            ),
          ],
        );
      },
    );
    if (confirmed == true) {
      widget.onLogout();
    }
  }
}

class _LicenseCard extends StatelessWidget {
  const _LicenseCard({
    required this.info,
    required this.appAddress,
    required this.controller,
    required this.verifying,
    required this.onVerify,
  });

  final LicenseInfo? info;
  final String appAddress;
  final TextEditingController controller;
  final bool verifying;
  final VoidCallback onVerify;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusText = _statusText(info);
    final statusColor = info?.isPro == true
        ? const Color(0xFF15803D)
        : const Color(0xFFB45309);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE1E7EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '会员信息',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  statusText,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'License Key',
              hintText: 'foxel_xxx',
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: verifying ? null : onVerify,
              icon: verifying
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_rounded),
              label: Text(verifying ? '验证中' : '验证 License'),
            ),
          ),
          const SizedBox(height: 14),
          _LicenseDetail(label: '绑定地址', value: appAddress),
          _LicenseDetail(label: '状态', value: info?.status ?? '未验证'),
          _LicenseDetail(label: '套餐', value: info?.plan ?? '-'),
          _LicenseDetail(label: '过期时间', value: _formatMillis(info?.expiresAt)),
          _LicenseDetail(label: '验证时间', value: _formatMillis(info?.verifiedAt)),
          if (info?.error != null && info!.error!.isNotEmpty)
            _LicenseDetail(label: '错误', value: info!.error!),
        ],
      ),
    );
  }

  String _statusText(LicenseInfo? info) {
    if (info == null || info.licenseKey.isEmpty) {
      return '未验证';
    }
    if (info.isPro) {
      return 'Pro';
    }
    if (info.valid && info.expiresAt != null) {
      return '已过期';
    }
    return '无效';
  }

  String _formatMillis(int? value) {
    if (value == null || value <= 0) {
      return '-';
    }
    final time = DateTime.fromMillisecondsSinceEpoch(value);
    final month = time.month.toString().padLeft(2, '0');
    final day = time.day.toString().padLeft(2, '0');
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '${time.year}-$month-$day $hour:$minute';
  }
}

class _LicenseDetail extends StatelessWidget {
  const _LicenseDetail({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF697586)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.username,
    required this.email,
    required this.avatarUrl,
    required this.baseUrl,
  });

  final String username;
  final String email;
  final String avatarUrl;
  final String baseUrl;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE1E7EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _AvatarImage(avatarUrl: avatarUrl, username: username, size: 52),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      username,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      email.isEmpty ? '未设置邮箱' : email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF697586),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '后端地址',
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(color: const Color(0xFF697586)),
          ),
          const SizedBox(height: 6),
          Text(
            baseUrl,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _AvatarImage extends StatelessWidget {
  const _AvatarImage({
    required this.avatarUrl,
    required this.username,
    required this.size,
  });

  final String avatarUrl;
  final String username;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = username.isEmpty
        ? 'F'
        : username.characters.first.toUpperCase();
    final fallback = Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFFEAF1FF),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: const TextStyle(
          color: Color(0xFF276EF1),
          fontWeight: FontWeight.w800,
          fontSize: 20,
        ),
      ),
    );
    if (avatarUrl.isEmpty) {
      return fallback;
    }
    return ClipOval(
      child: Image.network(
        avatarUrl,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: Column(children: children),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive
        ? const Color(0xFFDC2626)
        : const Color(0xFF276EF1);
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(title, style: TextStyle(color: destructive ? color : null)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }
}
