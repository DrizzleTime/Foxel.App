import 'package:flutter/material.dart';

import 'package:foxel/core/api/foxel_api.dart';
import 'package:foxel/core/models/license_info.dart';

class FoxelLicensePage extends StatefulWidget {
  const FoxelLicensePage({
    super.key,
    required this.baseUrl,
    required this.licenseInfo,
    required this.onVerifyLicense,
  });

  final String baseUrl;
  final LicenseInfo? licenseInfo;
  final Future<LicenseInfo> Function(String licenseKey) onVerifyLicense;

  @override
  State<FoxelLicensePage> createState() => _FoxelLicensePageState();
}

class _FoxelLicensePageState extends State<FoxelLicensePage> {
  final _licenseController = TextEditingController();
  LicenseInfo? _licenseInfo;
  bool _verifyingLicense = false;

  @override
  void initState() {
    super.initState();
    _licenseInfo = widget.licenseInfo;
    _licenseController.text = _licenseInfo?.licenseKey ?? '';
  }

  @override
  void didUpdateWidget(covariant FoxelLicensePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.licenseInfo != widget.licenseInfo) {
      _licenseInfo = widget.licenseInfo;
    }
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
    setState(() {
      _licenseInfo = info;
      _verifyingLicense = false;
    });
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
      appBar: AppBar(
        title: const Text('授权'),
        backgroundColor: const Color(0xFFF4F7FA),
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
          children: [
            _LicenseCard(
              info: _licenseInfo,
              appAddress: FoxelApi.appAddressFromBaseUrl(widget.baseUrl),
              controller: _licenseController,
              verifying: _verifyingLicense,
              onVerify: _verifyLicense,
            ),
          ],
        ),
      ),
    );
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
    final statusText = licenseStatusText(info);
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

String licenseStatusText(LicenseInfo? info) {
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
