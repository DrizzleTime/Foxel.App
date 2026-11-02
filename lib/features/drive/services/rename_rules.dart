import 'package:characters/characters.dart';

/// 批量重命名方式。
enum RenameMode {
  /// 查找替换文件名中的指定文本。
  replace,

  /// 添加前缀 / 后缀。
  affix,

  /// 按顺序追加序号。
  numbering,

  /// 大小写转换。
  letterCase,

  /// 修改扩展名（仅文件）。
  extension,
}

/// 序号插入位置。
enum NumberPosition { prefix, suffix }

/// 大小写转换方式。
enum LetterCaseMode { lower, upper, capitalize }

/// 重命名目标（文件或文件夹）。
class RenameTarget {
  const RenameTarget({required this.name, required this.isDir});

  final String name;
  final bool isDir;
}

/// 重命名规则（只保留当前方式用得到的字段，其余为默认值）。
class RenameRule {
  const RenameRule({
    this.mode = RenameMode.replace,
    this.findText = '',
    this.replaceText = '',
    this.caseSensitive = true,
    this.includeExtension = false,
    this.prefix = '',
    this.suffix = '',
    this.startNumber = 1,
    this.step = 1,
    this.digits = 3,
    this.numberPosition = NumberPosition.suffix,
    this.separator = '_',
    this.letterCase = LetterCaseMode.lower,
    this.newExtension = '',
  });

  final RenameMode mode;

  // 查找替换
  final String findText;
  final String replaceText;
  final bool caseSensitive;
  final bool includeExtension;

  // 前后缀
  final String prefix;
  final String suffix;

  // 序号
  final int startNumber;
  final int step;
  final int digits;
  final NumberPosition numberPosition;
  final String separator;

  // 大小写
  final LetterCaseMode letterCase;

  // 扩展名
  final String newExtension;

  RenameRule copyWith({
    RenameMode? mode,
    String? findText,
    String? replaceText,
    bool? caseSensitive,
    bool? includeExtension,
    String? prefix,
    String? suffix,
    int? startNumber,
    int? step,
    int? digits,
    NumberPosition? numberPosition,
    String? separator,
    LetterCaseMode? letterCase,
    String? newExtension,
  }) {
    return RenameRule(
      mode: mode ?? this.mode,
      findText: findText ?? this.findText,
      replaceText: replaceText ?? this.replaceText,
      caseSensitive: caseSensitive ?? this.caseSensitive,
      includeExtension: includeExtension ?? this.includeExtension,
      prefix: prefix ?? this.prefix,
      suffix: suffix ?? this.suffix,
      startNumber: startNumber ?? this.startNumber,
      step: step ?? this.step,
      digits: digits ?? this.digits,
      numberPosition: numberPosition ?? this.numberPosition,
      separator: separator ?? this.separator,
      letterCase: letterCase ?? this.letterCase,
      newExtension: newExtension ?? this.newExtension,
    );
  }

  /// 规则是否已经提供了足够信息来生成新名称。
  bool get isConfigured {
    switch (mode) {
      case RenameMode.replace:
        return findText.trim().isNotEmpty;
      case RenameMode.affix:
        return prefix.isNotEmpty || suffix.isNotEmpty;
      case RenameMode.numbering:
        return true;
      case RenameMode.letterCase:
        return true;
      case RenameMode.extension:
        return newExtension.trim().isNotEmpty;
    }
  }
}

/// 单项预览结果。
class RenamePreviewItem {
  const RenamePreviewItem({
    required this.target,
    required this.newName,
    this.skipReason,
    this.conflictReason,
  });

  final RenameTarget target;

  /// 计算出的新名称（跳过或冲突时仍会给出，便于提示）。
  final String newName;

  /// 无需重命名（例如不含查找文本、名称未变化）。
  final String? skipReason;

  /// 不可应用的原因（重名、空名称等）。
  final String? conflictReason;

  bool get isSkipped => skipReason != null;

  bool get isUsable => skipReason == null && conflictReason == null;

  /// 是否真的改名了。
  bool get isChanged => newName != target.name;
}

/// 批量重命名规则计算与冲突检测。
///
/// 纯逻辑，不依赖 Flutter，便于单测覆盖边界。
class RenamePlanner {
  const RenamePlanner._();

  /// 名称长度上限（按字素计），避免路径过长。
  static const int maxNameLength = 100;

  /// Windows 保留设备名，直接用作文件/文件夹名会失败。
  static const Set<String> _reservedNames = <String>{
    'con', 'prn', 'aux', 'nul',
    'com1', 'com2', 'com3', 'com4', 'com5', 'com6', 'com7', 'com8', 'com9',
    'lpt1', 'lpt2', 'lpt3', 'lpt4', 'lpt5', 'lpt6', 'lpt7', 'lpt8', 'lpt9',
  };

  /// 计算预览。
  ///
  /// [targets] 按列表当前顺序传入（序号按此顺序生成）；
  /// [existingNames] 是当前目录中未被选中的条目名，用于检测「目标名已被占用」。
  static List<RenamePreviewItem> preview({
    required List<RenameTarget> targets,
    required RenameRule rule,
    Set<String> existingNames = const <String>{},
  }) {
    final results = <RenamePreviewItem>[];
    final seen = <String, int>{}; // 归一化新名 -> 首次出现的下标
    final occupied = existingNames
        .map((name) => name.toLowerCase())
        .toSet();

    // 先算一遍所有新名。本批中「不会被改名」的项，其原名仍然占用目录：
    // 否则 A→B 而 B 恰好本批不变（不含查找文本 / 名称未变化）时会漏判冲突，
    // 执行阶段就会把 B 覆盖掉。
    final rawNames = <String?>[
      for (var index = 0; index < targets.length; index++)
        _applyRule(targets[index], rule, index),
    ];
    // 本批所有原名都算占用：这样 A→B 且 B 也在本批（会被改成 C，或与 A 互换）
    // 时会被判冲突。并发下发 rename 时服务端会撞名甚至覆盖，必须在预览阶段拦下。
    for (final target in targets) {
      occupied.add(target.name.toLowerCase());
    }

    for (var index = 0; index < targets.length; index++) {
      final target = targets[index];
      final rawNew = rawNames[index];
      if (rawNew == null) {
        results.add(
          RenamePreviewItem(
            target: target,
            newName: target.name,
            skipReason: '不含查找文本',
          ),
        );
        continue;
      }

      final cleaned = _sanitizeKeepingExtension(rawNew, target.isDir);
      if (cleaned.isEmpty) {
        results.add(
          RenamePreviewItem(
            target: target,
            newName: cleaned,
            conflictReason: '清洗后名称为空',
          ),
        );
        continue;
      }

      if (cleaned == target.name) {
        results.add(
          RenamePreviewItem(
            target: target,
            newName: cleaned,
            skipReason: '名称未变化',
          ),
        );
        continue;
      }

      final key = cleaned.toLowerCase();
      String? conflict;
      if (occupied.contains(key)) {
        conflict = '目标名已存在';
      } else if (seen.containsKey(key)) {
        conflict = '与第 ${seen[key]! + 1} 项重名';
      } else {
        seen[key] = index;
      }

      results.add(
        RenamePreviewItem(
          target: target,
          newName: cleaned,
          conflictReason: conflict,
        ),
      );
    }

    return results;
  }

  /// 按规则算出原始新名；返回 null 表示该规则不适用于此项（跳过）。
  static String? _applyRule(RenameTarget target, RenameRule rule, int index) {
    final isDir = target.isDir;
    final base = isDir ? target.name : _baseName(target.name);
    final extension = isDir ? '' : _extensionOf(target.name);

    switch (rule.mode) {
      case RenameMode.replace:
        final haystack = rule.includeExtension && !isDir
            ? target.name
            : base;
        final pattern = RegExp(
          RegExp.escape(rule.findText),
          caseSensitive: rule.caseSensitive,
        );
        if (!pattern.hasMatch(haystack)) {
          return null;
        }
        final replaced = haystack.replaceAll(pattern, rule.replaceText);
        if (rule.includeExtension && !isDir) {
          return replaced;
        }
        return '$replaced$extension';

      case RenameMode.affix:
        return '${rule.prefix}$base${rule.suffix}$extension';

      case RenameMode.numbering:
        final value = rule.startNumber + index * rule.step;
        final digits = rule.digits.clamp(1, 9);
        final text = value.toString().padLeft(digits, '0');
        if (rule.numberPosition == NumberPosition.prefix) {
          return '$text${rule.separator}$base$extension';
        }
        return '$base${rule.separator}$text$extension';

      case RenameMode.letterCase:
        return '${_applyCase(base, rule.letterCase)}$extension';

      case RenameMode.extension:
        if (isDir) {
          return null; // 文件夹没有扩展名
        }
        final ext = rule.newExtension.trim().replaceAll('.', '');
        if (ext.isEmpty) {
          return null;
        }
        return '$base.$ext';
    }
  }

  static String _applyCase(String value, LetterCaseMode mode) {
    switch (mode) {
      case LetterCaseMode.lower:
        return value.toLowerCase();
      case LetterCaseMode.upper:
        return value.toUpperCase();
      case LetterCaseMode.capitalize:
        if (value.isEmpty) {
          return value;
        }
        final chars = value.characters;
        return '${chars.first.toUpperCase()}${chars.skip(1)}';
    }
  }

  /// 去掉扩展名（文件）。
  static String _baseName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0) {
      return name;
    }
    return name.substring(0, dot);
  }

  /// 扩展名（含点）；无扩展名返回空串。
  static String _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) {
      return '';
    }
    return name.substring(dot);
  }

  /// 清洗名称（保留扩展名部分不被截断得太早）。
  static String _sanitizeKeepingExtension(String raw, bool isDir) {
    final extension = isDir ? '' : _extensionOf(raw);
    var base = isDir ? raw : _baseName(raw);
    base = _sanitizeSegment(base);
    if (base.isEmpty) {
      return '';
    }
    if (isDir) {
      return base;
    }
    final ext = _sanitizeSegment(
      extension.replaceAll('.', ''),
      allowLeadingDot: false,
    );
    return ext.isEmpty ? base : '$base.$ext';
  }

  /// 清洗单个名称段：替换非法字符、压缩空白、去首尾点、按字素截断、避开保留名。
  static String _sanitizeSegment(
    String value, {
    bool allowLeadingDot = true,
  }) {
    var name = value.trim();
    if (name.isEmpty) {
      return '';
    }
    name = name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_');
    name = name.replaceAll(RegExp(r'\s+'), ' ');
    name = name.replaceAll(RegExp(r'^[.\s]+|[.\s]+$'), '');
    if (name.isEmpty) {
      return '';
    }
    if (name.characters.length > maxNameLength) {
      name = name.characters.take(maxNameLength).toString();
      name = name.replaceAll(RegExp(r'^[.\s]+|[.\s]+$'), '');
    }
    if (!allowLeadingDot) {
      name = name.replaceAll(RegExp(r'^\.+'), '');
    }
    if (name.isEmpty) {
      return '';
    }
    final stem = name.split('.').first.toLowerCase();
    if (_reservedNames.contains(stem)) {
      name = 'foxel_$name';
    }
    return name;
  }
}
