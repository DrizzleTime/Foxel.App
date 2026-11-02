import 'dart:math';

import 'package:characters/characters.dart';

/// 一个 Foxel 账户 = 一个独立沙箱。
///
/// 每个账户拥有自己的凭证、下载目录、传输任务、浏览状态与缓存，
/// 切换账户只是把「当前指针」指向另一个 [Account.id]。
class Account {
  const Account({
    required this.id,
    required this.alias,
    required this.baseUrl,
    required this.username,
    required this.token,
    this.email = '',
    this.avatarUrl = '',
    this.colorValue = defaultColorValue,
    this.createdAt,
    this.lastUsedAt,
    this.isolatedDownloadDir = true,
    this.isolatedTasks = true,
    this.rememberBrowseState = true,
    this.isolatedCache = true,
    this.isStale = false,
  });

  /// 沙箱 ID，同时用作下载目录与缓存目录名。
  final String id;

  /// 用户自定义显示名称，留空时回退到用户名 / 服务器。
  final String alias;
  final String baseUrl;
  final String username;
  final String token;
  final String email;
  final String avatarUrl;

  /// 账户主题色 ARGB（用于「当前账户」视觉标识）。
  final int colorValue;

  final DateTime? createdAt;
  final DateTime? lastUsedAt;

  /// 数据隔离开关，默认全部开启。
  final bool isolatedDownloadDir;
  final bool isolatedTasks;
  final bool rememberBrowseState;
  final bool isolatedCache;

  /// 上次校验失败（token 过期等），需要重新验证。
  final bool isStale;

  static const int defaultColorValue = 0xFF4C6FFF;

  static const List<int> palette = <int>[
    0xFF4C6FFF,
    0xFF6E56CF,
    0xFF12B886,
    0xFFF59E0B,
    0xFFE5484D,
    0xFF0EA5E9,
    0xFF8B5CF6,
    0xFF14B8A6,
  ];

  static final Random _random = Random();

  /// 账户 ID：时间戳 + 随机后缀，避免同微秒内批量创建时撞车。
  static String generateId() {
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final suffix = _random.nextInt(0x1000000).toRadixString(36).padLeft(5, '0');
    return 'acc_${stamp}_$suffix';
  }

  static int colorForIndex(int index) {
    if (palette.isEmpty) {
      return defaultColorValue;
    }
    return palette[index % palette.length];
  }

  String get displayName {
    final trimmedAlias = alias.trim();
    if (trimmedAlias.isNotEmpty) {
      return trimmedAlias;
    }
    final trimmedUsername = username.trim();
    if (trimmedUsername.isNotEmpty) {
      return trimmedUsername;
    }
    return baseUrl;
  }

  String get initial {
    final name = displayName.trim();
    if (name.isEmpty) {
      return '?';
    }
    // 按字素取首字：substring(0, 1) 会把 emoji 的代理对切成半个码元，
    // 头像位置渲染成方块。
    return name.characters.take(1).toString().toUpperCase();
  }

  /// 服务器域名（含端口），用于列表副标题。
  String get hostLabel {
    final value = baseUrl.trim();
    if (value.isEmpty) {
      return '';
    }
    try {
      final uri = Uri.parse(value);
      if (uri.host.isEmpty) {
        return value;
      }
      return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
    } catch (_) {
      return value;
    }
  }

  /// 列表副标题：用户名（邮箱优先）。
  String get accountLabel {
    final mail = email.trim();
    if (mail.isNotEmpty) {
      return mail;
    }
    return username.trim().isEmpty ? hostLabel : username.trim();
  }

  Account copyWith({
    String? alias,
    String? baseUrl,
    String? username,
    String? token,
    String? email,
    String? avatarUrl,
    int? colorValue,
    DateTime? createdAt,
    DateTime? lastUsedAt,
    bool? isolatedDownloadDir,
    bool? isolatedTasks,
    bool? rememberBrowseState,
    bool? isolatedCache,
    bool? isStale,
  }) {
    return Account(
      id: id,
      alias: alias ?? this.alias,
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      token: token ?? this.token,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      colorValue: colorValue ?? this.colorValue,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      isolatedDownloadDir: isolatedDownloadDir ?? this.isolatedDownloadDir,
      isolatedTasks: isolatedTasks ?? this.isolatedTasks,
      rememberBrowseState: rememberBrowseState ?? this.rememberBrowseState,
      isolatedCache: isolatedCache ?? this.isolatedCache,
      isStale: isStale ?? this.isStale,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'alias': alias,
      'baseUrl': baseUrl,
      'username': username,
      'email': email,
      'avatarUrl': avatarUrl,
      'colorValue': colorValue,
      'createdAt': createdAt?.millisecondsSinceEpoch,
      'lastUsedAt': lastUsedAt?.millisecondsSinceEpoch,
      'isolatedDownloadDir': isolatedDownloadDir,
      'isolatedTasks': isolatedTasks,
      'rememberBrowseState': rememberBrowseState,
      'isolatedCache': isolatedCache,
      'isStale': isStale,
    };
  }

  /// 索引中的记录（不含 token，token 单独存）。
  factory Account.fromJson(Map<String, dynamic> json, {String token = ''}) {
    return Account(
      id: json['id'] as String? ?? '',
      alias: json['alias'] as String? ?? '',
      baseUrl: json['baseUrl'] as String? ?? '',
      username: json['username'] as String? ?? '',
      token: token,
      email: json['email'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String? ?? '',
      colorValue: _asInt(json['colorValue']) ?? defaultColorValue,
      createdAt: _dateFrom(json['createdAt']),
      lastUsedAt: _dateFrom(json['lastUsedAt']),
      isolatedDownloadDir: json['isolatedDownloadDir'] as bool? ?? true,
      isolatedTasks: json['isolatedTasks'] as bool? ?? true,
      rememberBrowseState: json['rememberBrowseState'] as bool? ?? true,
      isolatedCache: json['isolatedCache'] as bool? ?? true,
      isStale: json['isStale'] as bool? ?? false,
    );
  }

  /// 容错取整：索引被外部改写时也不抛类型错误。
  static int? _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static DateTime? _dateFrom(dynamic value) {
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) {
        return DateTime.fromMillisecondsSinceEpoch(parsed);
      }
    }
    return null;
  }
}
