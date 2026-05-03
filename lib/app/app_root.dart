import 'package:flutter/material.dart';

import 'package:foxel/core/api/foxel_api.dart';
import 'package:foxel/core/api/license_api.dart';
import 'package:foxel/core/models/license_info.dart';
import 'package:foxel/core/models/session.dart';
import 'package:foxel/core/storage/license_store.dart';
import 'package:foxel/core/storage/session_store.dart';
import 'package:foxel/features/auth/pages/settings_page.dart';
import 'package:foxel/features/drive/pages/drive_shell_page.dart';

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});

  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  final _store = SessionStore();
  final _licenseStore = LicenseStore();
  final _licenseApi = LicenseApi();
  FoxelSession? _session;
  LicenseInfo? _licenseInfo;
  FoxelApi? _api;
  bool _loading = true;
  String _initialBaseUrl = '';

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _api?.close();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final session = await _store.load();
    if (session == null) {
      setState(() => _loading = false);
      return;
    }

    _initialBaseUrl = session.baseUrl;
    final api = FoxelApi(baseUrl: session.baseUrl, token: session.token);
    try {
      final profile = await api.me();
      final licenseInfo = await _loadAndVerifyLicense(session.baseUrl);
      final refreshed = session.copyWith(
        username: profile.username.isEmpty
            ? session.username
            : profile.username,
        email: profile.email,
        avatarUrl: profile.avatarUrl,
      );
      await _store.save(refreshed);
      setState(() {
        _session = refreshed;
        _licenseInfo = licenseInfo;
        _api = api;
        _loading = false;
      });
    } catch (_) {
      api.close();
      await _store.clearToken();
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _handleLoggedIn(FoxelSession session) async {
    final normalized = session.copyWith(
      baseUrl: FoxelApi.normalizeBaseUrl(session.baseUrl),
    );
    await _store.save(normalized);
    final licenseInfo = await _loadAndVerifyLicense(normalized.baseUrl);
    _api?.close();
    setState(() {
      _session = normalized;
      _licenseInfo = licenseInfo;
      _api = FoxelApi(baseUrl: normalized.baseUrl, token: normalized.token);
      _initialBaseUrl = normalized.baseUrl;
    });
  }

  Future<LicenseInfo?> _loadAndVerifyLicense(String baseUrl) async {
    final saved = await _licenseStore.load();
    final licenseKey = saved?.licenseKey.trim();
    if (licenseKey == null || licenseKey.isEmpty) {
      return null;
    }
    return _verifyLicenseWithBaseUrl(baseUrl: baseUrl, licenseKey: licenseKey);
  }

  Future<LicenseInfo> _verifyLicense(String licenseKey) async {
    final session = _session;
    if (session == null) {
      final info = LicenseInfo.failed(
        licenseKey: licenseKey.trim(),
        appAddress: '',
        error: '未登录',
      );
      await _licenseStore.save(info);
      setState(() => _licenseInfo = info);
      return info;
    }
    final info = await _verifyLicenseWithBaseUrl(
      baseUrl: session.baseUrl,
      licenseKey: licenseKey,
    );
    if (mounted) {
      setState(() => _licenseInfo = info);
    }
    return info;
  }

  Future<LicenseInfo> _verifyLicenseWithBaseUrl({
    required String baseUrl,
    required String licenseKey,
  }) async {
    final appAddress = FoxelApi.appAddressFromBaseUrl(baseUrl);
    final info = await _licenseApi.verify(
      appAddress: appAddress,
      licenseKey: licenseKey.trim(),
    );
    await _licenseStore.save(info);
    return info;
  }

  void _openSettings() {
    final session = _session;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(
          initialBaseUrl: session?.baseUrl ?? _initialBaseUrl,
          onLoggedIn: (newSession) {
            _handleLoggedIn(newSession);
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await _store.clearToken();
    _api?.close();
    setState(() {
      _session = null;
      _api = null;
      _licenseInfo = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final session = _session;
    final api = _api;
    if (session == null || api == null) {
      return SettingsPage(
        initialBaseUrl: _initialBaseUrl,
        onLoggedIn: _handleLoggedIn,
      );
    }

    return DriveShellPage(
      api: api,
      username: session.username,
      email: session.email,
      avatarUrl: session.avatarUrl,
      baseUrl: session.baseUrl,
      licenseInfo: _licenseInfo,
      onVerifyLicense: _verifyLicense,
      onOpenSettings: _openSettings,
      onLogout: _logout,
    );
  }
}
