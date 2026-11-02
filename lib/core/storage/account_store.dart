import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:foxel/core/models/account.dart';
import 'package:foxel/core/storage/token_protector.dart';

/// 多账户存储。
///
/// 全局层只保存「账户索引 + 当前账户指针 + 各账户 token」，
/// 其余数据（下载目录 / 浏览状态 / 播放进度 / 任务）全部挂在
/// `foxel_acc_<id>_*` 前缀下，形成每账户一个沙箱。
class AccountStore {
  static const _indexKey = 'foxel_accounts_index';
  static const _activeKey = 'foxel_active_account_id';

  /// 旧版本会话迁移标记：迁移只做一次，且必须清理旧 key，
  /// 否则用户删光账户后重启会被再次迁移出「默认账户」。
  static const _migrationKey = 'foxel_migration_v2_done';

  /// 「独立媒体缓存」关闭时的共享分区前缀（如播放进度），随账户清理一并清掉。
  static const _sharedCachePrefix = 'foxel_acc_shared_';

  /// 旧版本（单会话）遗留 key，仅用于迁移。
  static const _legacyBaseUrlKey = 'foxel_base_url';
  static const _legacyUsernameKey = 'foxel_username';
  static const _legacyTokenKey = 'foxel_token';
  static const _legacyEmailKey = 'foxel_email';
  static const _legacyAvatarUrlKey = 'foxel_avatar_url';

  /// 旧版本的全局下载目录（多账户后改为按账户存储）。
  static const _legacyDownloadDirKey = 'foxel_download_dir';

  static String tokenKey(String accountId) => 'foxel_acc_${accountId}_token';

  /// 索引读写队列：所有「读索引 → 改 → 写回」串行执行，
  /// 避免切换账户、后台校验、删除账户交错时互相覆盖导致账户丢失。
  Future<void> _queue = Future<void>.value();

  Future<T> _serialized<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  /// 读取全部账户，必要时执行一次旧版本迁移。
  ///
  /// 迁移判据：**索引 key 不存在**（真正的旧版本升级）才迁移。
  /// 删除最后一个账户时索引会被写成 `[]`，此时索引存在 → 永不再迁移，
  /// 避免「删光账户后重启又被迁移出一个默认账户」。
  Future<List<Account>> loadAccounts({bool migrate = true}) async {
    final prefs = await SharedPreferences.getInstance();
    final hasIndex = prefs.getString(_indexKey) != null;
    final accounts = await _parseAccounts(prefs);

    final migratedBefore = prefs.getBool(_migrationKey) ?? false;
    if (accounts.isEmpty && migrate && !hasIndex && !migratedBefore) {
      // 迁移整体走队列：并发首启时只有一个会真正迁移，不会生成两个「默认账户」。
      return _serialized(() async {
        final recheck = await _parseAccounts(prefs);
        if (recheck.isNotEmpty) {
          return recheck;
        }
        final migrated = _migrateLegacy(prefs);
        // 无论是否迁移出账户，都打标记并清掉旧 key，杜绝二次迁移。
        await prefs.setBool(_migrationKey, true);
        await _purgeLegacyKeys(prefs);
        if (migrated == null) {
          return <Account>[];
        }
        await _upsertLocked(migrated);
        await setActiveId(migrated.id);
        return <Account>[migrated];
      });
    }

    if (migrate && (hasIndex || migratedBefore) && !_legacyCleaned) {
      // 清理会写盘，必须纳入串行队列并只执行一次，
      // 否则启动期多次 loadAccounts 会形成不受保护的并发写。
      await _serialized(() async {
        if (_legacyCleaned) {
          return;
        }
        await _cleanupLegacyKeys(prefs, accounts);
        _legacyCleaned = true;
      });
    }

    return accounts;
  }

  /// 仅解析索引与 token，不做迁移/清理（迁移需要写操作，走队列）。
  Future<List<Account>> _parseAccounts(SharedPreferences prefs) async {
    final raw = prefs.getString(_indexKey);
    final accounts = <Account>[];

    if (raw != null && raw.isNotEmpty) {
      dynamic decoded;
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        // 索引整体损坏：按空列表处理，避免应用无法启动。
        decoded = null;
      }
      if (decoded is List) {
        for (final item in decoded) {
          if (item is! Map<String, dynamic>) {
            continue;
          }
          // 单条损坏只跳过该条，不牵连其余账户。
          try {
            final id = item['id'];
            if (id is! String || id.isEmpty) {
              continue;
            }
            // token 可能是 DPAPI 密文（Windows），也可能是旧版明文。
            // 解不开（换 Windows 用户 / 换机器）时按空 token 处理：
            // 账户记录仍然保留，界面上会落到「需重新验证」。
            final stored = prefs.getString(tokenKey(id)) ?? '';
            final token = await TokenProtector.unprotect(stored);
            accounts.add(
              Account.fromJson(item, token: token ?? ''),
            );
          } catch (_) {
            continue;
          }
        }
      }
    }

    return accounts;
  }

  /// 幂等清理：把旧版全局下载目录让给唯一的账户，然后清掉旧会话 key。
  Future<void> _cleanupLegacyKeys(
    SharedPreferences prefs,
    List<Account> accounts,
  ) async {
    const legacyKeys = <String>[
      _legacyBaseUrlKey,
      _legacyUsernameKey,
      _legacyTokenKey,
      _legacyEmailKey,
      _legacyAvatarUrlKey,
      _legacyDownloadDirKey,
    ];
    final keys = prefs.getKeys();
    final hasLegacy = legacyKeys.any(keys.contains);
    final marked = prefs.getBool(_migrationKey) ?? false;
    if (!hasLegacy && marked) {
      // 已经干净，避免每次启动都写偏好设置。
      return;
    }

    final legacyDir = prefs.getString(_legacyDownloadDirKey);
    if (legacyDir != null &&
        legacyDir.trim().isNotEmpty &&
        accounts.length == 1) {
      final accountDirKey = 'foxel_acc_${accounts.first.id}_download_dir';
      final existing = prefs.getString(accountDirKey);
      if (existing == null || existing.trim().isEmpty) {
        await prefs.setString(accountDirKey, legacyDir.trim());
      }
    }
    await prefs.setBool(_migrationKey, true);
    await _purgeLegacyKeys(prefs);
  }

  /// 清除旧版本遗留的会话 key。
  Future<void> _purgeLegacyKeys(SharedPreferences prefs) async {
    for (final key in <String>[
      _legacyBaseUrlKey,
      _legacyUsernameKey,
      _legacyTokenKey,
      _legacyEmailKey,
      _legacyAvatarUrlKey,
      _legacyDownloadDirKey,
    ]) {
      await prefs.remove(key);
    }
  }

  Account? _migrateLegacy(SharedPreferences prefs) {
    final baseUrl = prefs.getString(_legacyBaseUrlKey);
    final username = prefs.getString(_legacyUsernameKey);
    final token = prefs.getString(_legacyTokenKey);
    if (baseUrl == null ||
        baseUrl.isEmpty ||
        username == null ||
        username.isEmpty ||
        token == null ||
        token.isEmpty) {
      return null;
    }
    return Account(
      id: Account.generateId(),
      alias: '默认账户',
      baseUrl: baseUrl,
      username: username,
      token: token,
      email: prefs.getString(_legacyEmailKey) ?? '',
      avatarUrl: prefs.getString(_legacyAvatarUrlKey) ?? '',
      colorValue: Account.defaultColorValue,
      createdAt: DateTime.now(),
      lastUsedAt: DateTime.now(),
    );
  }

  Future<String?> activeId() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_activeKey);
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  /// 当前账户；不存在时回退到最近使用的账户。
  Future<Account?> activeAccount() async {
    final accounts = await loadAccounts();
    if (accounts.isEmpty) {
      return null;
    }
    final id = await activeId();
    for (final account in accounts) {
      if (account.id == id) {
        return account;
      }
    }
    return accounts.first;
  }

  Future<void> setActiveId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_activeKey, id);
  }

  /// 新增或更新账户（token 单独存放）。
  Future<void> upsert(Account account) => _serialized(() => _upsertLocked(account));

  /// 已持有队列锁时使用的内部实现。
  Future<void> _upsertLocked(Account account) async {
    final prefs = await SharedPreferences.getInstance();
    final accounts = await loadAccounts(migrate: false);
    final next = <Account>[
      for (final item in accounts) if (item.id != account.id) item,
      account,
    ];
    await prefs.setString(_indexKey, jsonEncode(next.map(_toIndex).toList()));
    // 写入即加密：旧版明文 token 会在下一次 upsert 时自动升级成密文。
    await prefs.setString(
      tokenKey(account.id),
      await TokenProtector.protect(account.token),
    );
  }

  Map<String, dynamic> _toIndex(Account account) {
    final json = account.toJson();
    json.remove('token');
    return json;
  }

  /// 更新 token。
  ///
  /// 必须走串行队列：与 [remove] 并发时，删除流程刚把 key 清掉、
  /// 这里的写入又会把 token 补回去，留下一个账户已删但 token 还在的残骸。
  Future<void> updateToken(String id, String token) => _serialized(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      tokenKey(id),
      await TokenProtector.protect(token),
    );
  });

  /// 记录「最后使用时间」。
  Future<void> touch(String id) => _serialized(() async {
    final accounts = await loadAccounts(migrate: false);
    for (final account in accounts) {
      if (account.id == id) {
        await _upsertLocked(account.copyWith(lastUsedAt: DateTime.now()));
        return;
      }
    }
  });

  /// 标记账户失效（token 过期等），本地沙箱数据保留。
  Future<void> markStale(String id, {required bool stale}) =>
      _serialized(() async {
        final accounts = await loadAccounts(migrate: false);
        for (final account in accounts) {
          if (account.id == id) {
            await _upsertLocked(account.copyWith(isStale: stale));
            return;
          }
        }
      });

  /// 移除账户及其沙箱内的全部本地数据。
  Future<void> remove(String id) => _serialized(() => _removeLocked(id));

  Future<void> _removeLocked(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final accounts = await loadAccounts(migrate: false);
    final next = <Account>[
      for (final item in accounts) if (item.id != id) item,
    ];
    await prefs.setString(_indexKey, jsonEncode(next.map(_toIndex).toList()));

    final prefix = 'foxel_acc_${id}_';
    // 共享分区（关闭「独立媒体缓存」时的播放进度）只在删掉最后一个账户时清理：
    // 否则删 A 会顺手把 B / C 共用的那份进度也清掉。
    final purgeSharedCache = next.isEmpty;
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith(prefix) ||
          (purgeSharedCache && key.startsWith(_sharedCachePrefix))) {
        await prefs.remove(key);
      }
    }

    final active = prefs.getString(_activeKey);
    if (active == id) {
      if (next.isEmpty) {
        await prefs.remove(_activeKey);
      } else {
        await prefs.setString(_activeKey, next.first.id);
      }
    }

    if (next.isEmpty) {
      // 用户已删光账户：连同旧版本会话 key 一起清掉，并标记迁移已完成，
      // 保证下次启动直接进入空态而不会复活出「默认账户」。
      await prefs.setBool(_migrationKey, true);
      await _purgeLegacyKeys(prefs);
    }
  }

  /// 旧版 key 是否已清理（进程内幂等，避免重复写盘）。
  bool _legacyCleaned = false;

  /// 批量移除账户（多选删除）。
  ///
  /// 单个失败不影响其余账户，出错 id 通过返回值告知调用方。
  Future<List<String>> removeAll(Iterable<String> ids) => _serialized(() async {
    final failed = <String>[];
    for (final id in ids) {
      try {
        await _removeLocked(id);
      } catch (_) {
        failed.add(id);
      }
    }
    return failed;
  });

  /// 清除账户的本地缓存与状态，但保留账户与登录态。
  Future<void> clearLocalData(String id) => _serialized(() async {
    final prefs = await SharedPreferences.getInstance();
    final prefix = 'foxel_acc_${id}_';
    for (final key in prefs.getKeys().toList()) {
      if (key.startsWith(_sharedCachePrefix) ||
          (key.startsWith(prefix) && key != tokenKey(id))) {
        await prefs.remove(key);
      }
    }
  });
}
