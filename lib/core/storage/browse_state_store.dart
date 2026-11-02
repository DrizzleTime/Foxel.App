import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 文件浏览状态（当前路径 / 排序 / 视图模式），按账户隔离保存。
class BrowseState {
  const BrowseState({
    required this.path,
    required this.sortField,
    required this.ascending,
    required this.viewMode,
  });

  final String path;
  final String sortField;
  final bool ascending;
  final String viewMode;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'path': path,
    'sortField': sortField,
    'ascending': ascending,
    'viewMode': viewMode,
  };

  factory BrowseState.fromJson(Map<String, dynamic> json) {
    return BrowseState(
      path: json['path'] as String? ?? '/',
      sortField: json['sortField'] as String? ?? 'name',
      ascending: json['ascending'] as bool? ?? true,
      viewMode: json['viewMode'] as String? ?? 'grid',
    );
  }
}

class BrowseStateStore {
  static String keyFor(String accountId) =>
      'foxel_acc_${accountId}_browse_state';

  Future<BrowseState?> load(String accountId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(keyFor(accountId));
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return BrowseState.fromJson(decoded);
      }
    } catch (_) {
      // 状态损坏时回退到默认浏览状态。
    }
    return null;
  }

  Future<void> save(String accountId, BrowseState state) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyFor(accountId), jsonEncode(state.toJson()));
  }
}
