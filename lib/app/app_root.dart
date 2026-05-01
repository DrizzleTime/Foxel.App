import 'package:flutter/material.dart';

import 'package:foxel/core/api/foxel_api.dart';
import 'package:foxel/core/models/session.dart';
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
  FoxelSession? _session;
  FoxelApi? _api;
  bool _loading = true;
  String _initialBaseUrl = '';
  String _initialUsername = '';

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
    _initialUsername = session.username;
    final api = FoxelApi(baseUrl: session.baseUrl, token: session.token);
    try {
      final profile = await api.me();
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
        _api = api;
        _loading = false;
        _initialUsername = refreshed.username;
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
    _api?.close();
    setState(() {
      _session = normalized;
      _api = FoxelApi(baseUrl: normalized.baseUrl, token: normalized.token);
      _initialBaseUrl = normalized.baseUrl;
      _initialUsername = normalized.username;
    });
  }

  void _openSettings() {
    final session = _session;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsPage(
          initialBaseUrl: session?.baseUrl ?? _initialBaseUrl,
          initialUsername: session?.username ?? _initialUsername,
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
        initialUsername: _initialUsername,
        onLoggedIn: _handleLoggedIn,
      );
    }

    return DriveShellPage(
      api: api,
      username: session.username,
      email: session.email,
      avatarUrl: session.avatarUrl,
      baseUrl: session.baseUrl,
      onOpenSettings: _openSettings,
      onLogout: _logout,
    );
  }
}
