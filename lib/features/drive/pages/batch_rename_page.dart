import 'package:flutter/material.dart';

import 'package:foxel/core/api/foxel_api.dart';
import 'package:foxel/core/models/file_entry.dart';
import 'package:foxel/core/theme/design_tokens.dart';
import 'package:foxel/core/widgets/content_frame.dart';
import 'package:foxel/features/drive/services/rename_rules.dart';

/// 批量重命名页：配置规则 → 实时预览 → 逐项执行。
///
/// 关闭时返回 true 表示至少有一项成功改名，调用方需要刷新列表。
class BatchRenamePage extends StatefulWidget {
  const BatchRenamePage({
    super.key,
    required this.api,
    required this.directoryPath,
    required this.targets,
    this.existingNames = const <String>{},
  });

  final FoxelApi api;

  /// 这些条目所在的目录。
  final String directoryPath;

  /// 待重命名的条目（按列表当前顺序传入，序号按此顺序生成）。
  final List<FileEntry> targets;

  /// 目录中未被选中的条目名，用于检测目标名冲突。
  final Set<String> existingNames;

  @override
  State<BatchRenamePage> createState() => _BatchRenamePageState();
}

class _BatchRenamePageState extends State<BatchRenamePage> {
  RenameRule _rule = const RenameRule();
  final _findController = TextEditingController();
  final _replaceController = TextEditingController();
  final _prefixController = TextEditingController();
  final _suffixController = TextEditingController();
  final _extensionController = TextEditingController();

  bool _running = false;
  int _done = 0;
  String? _failureSummary;

  /// 实际成功改名的数量（用于返回调用方，避免「只看预览就返回」被当成成功）。
  int _appliedCount = 0;

  /// 待处理条目（成功后移除，避免用旧名重试）。
  late List<FileEntry> _targets = widget.targets;

  /// 已被占用的名称（成功后并入新名，保持冲突检测准确）。
  late Set<String> _existingNames = widget.existingNames.toSet();

  @override
  void dispose() {
    _findController.dispose();
    _replaceController.dispose();
    _prefixController.dispose();
    _suffixController.dispose();
    _extensionController.dispose();
    super.dispose();
  }

  List<RenameTarget> get _renameTargets => <RenameTarget>[
    for (final entry in _targets)
      RenameTarget(name: entry.name, isDir: entry.isDir),
  ];

  List<RenamePreviewItem> get _preview => RenamePlanner.preview(
    targets: _renameTargets,
    rule: _rule,
    existingNames: _existingNames,
  );

  void _updateRule(RenameRule next) {
    setState(() {
      _rule = next;
      _failureSummary = null;
    });
  }

  Future<void> _apply() async {
    final items = _preview.where((item) => item.isUsable).toList();
    if (items.isEmpty || _running) {
      return;
    }

    setState(() {
      _running = true;
      _done = 0;
      _failureSummary = null;
    });

    final failures = <String>[];
    final failedItems = <RenamePreviewItem>[];
    var completed = 0;

    // 受限并发 3：避免一次性打满服务端。
    const concurrency = 3;
    for (var start = 0; start < items.length; start += concurrency) {
      final slice = items.skip(start).take(concurrency).toList();
      final results = await Future.wait(
        slice.map((item) async {
          try {
            await widget.api.rename(
              src: FoxelApi.joinPath(widget.directoryPath, item.target.name),
              dst: FoxelApi.joinPath(widget.directoryPath, item.newName),
            );
            return null;
          } catch (error) {
            // 把失败项与条目本身绑定，便于精确剔除 / 重试。
            return (item: item, error: '$error');
          }
        }),
      );
      for (final failure in results) {
        if (failure != null) {
          failures.add('${failure.item.target.name}：${failure.error}');
          failedItems.add(failure.item);
        }
      }
      completed += slice.length;
      if (mounted) {
        setState(() => _done = completed);
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _running = false;
      _failureSummary = failures.isEmpty
          ? null
          : '${failures.length} 项失败：${failures.take(3).join('；')}'
                '${failures.length > 3 ? ' 等' : ''}';
    });

    final successCount = items.length - failures.length;
    _appliedCount += successCount;
    if (successCount > 0) {
      // 刷新本地快照：已成功的项移出待处理列表，新名并入占用集合，
      // 这样重试时不会用已不存在的旧名。
      final failedNames = <String>{
        for (final item in failedItems) item.target.name,
      };
      final newNames = <String>{
        for (final item in items)
          if (item.isUsable && !failedNames.contains(item.target.name))
            item.newName,
      };
      final appliedNames = <String>{
        for (final item in items)
          if (!failedNames.contains(item.target.name)) item.target.name,
      };
      setState(() {
        _targets = _targets
            .where((entry) => !appliedNames.contains(entry.name))
            .toList();
        _existingNames.addAll(newNames);
      });
    }
    if (failures.isEmpty) {
      Navigator.of(context).pop(true);
      return;
    }
    if (successCount > 0) {
      // 部分成功：留在页面让用户看到失败原因，返回时再刷新。
      _showMessage('已重命名 $successCount 项，${failures.length} 项失败');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final usable = preview.where((item) => item.isUsable).length;
    final changed = preview.where((item) => item.isChanged).length;

    return PopScope(
      // 系统返回键 / 侧滑返回也要带回「是否已改名」，否则上一页不会刷新列表。
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        // 运行中不允许离开，否则改名结果会连同刷新一起丢失。
        if (didPop || _running) {
          return;
        }
        Navigator.of(context).pop(_appliedCount > 0);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: const Text('批量重命名'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).pop(_appliedCount > 0),
          ),
        ),
      body: SafeArea(
        top: false,
        child: ContentFrame(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.page,
                    AppSpacing.sm,
                    AppSpacing.page,
                    AppSpacing.page,
                  ),
                  children: [
                    _SummaryBar(targets: _targets, preview: preview),
                    const SizedBox(height: AppSpacing.lg),
                    const _SectionLabel('重命名方式'),
                    _ModePicker(
                      value: _rule.mode,
                      onChanged: (mode) => _updateRule(_rule.copyWith(mode: mode)),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _RuleForm(
                      rule: _rule,
                      findController: _findController,
                      replaceController: _replaceController,
                      prefixController: _prefixController,
                      suffixController: _suffixController,
                      extensionController: _extensionController,
                      onChanged: _updateRule,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _SectionLabel(
                      '预览（$usable 项可用 · $changed 项改名）',
                    ),
                    if (!_rule.isConfigured)
                      const _HintCard(text: '先填写规则，预览会自动更新')
                    else
                      _PreviewList(items: preview),
                    if (_failureSummary != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      _DangerCard(text: _failureSummary!),
                    ],
                  ],
                ),
              ),
              _BottomBar(
                running: _running,
                done: _done,
                total: usable,
                onCancel: () => Navigator.of(context).pop(_appliedCount > 0),
                onApply: usable == 0 || _running ? null : _apply,
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }
}

class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.targets, required this.preview});

  final List<FileEntry> targets;
  final List<RenamePreviewItem> preview;

  @override
  Widget build(BuildContext context) {
    final folders = targets.where((entry) => entry.isDir).length;
    final files = targets.length - folders;
    final size = targets
        .where((entry) => !entry.isDir)
        .fold<int>(0, (sum, entry) => sum + entry.size);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: BorderRadius.circular(AppRadii.tile),
      ),
      child: Text(
        '已选 ${targets.length} 项 · $files 个文件'
        '${size > 0 ? '（${_formatSize(size)}）' : ''}'
        '${folders > 0 ? ' + $folders 个文件夹' : ''}',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
        ),
      ),
    );
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  }
}

class _ModePicker extends StatelessWidget {
  const _ModePicker({required this.value, required this.onChanged});

  final RenameMode value;
  final ValueChanged<RenameMode> onChanged;

  static const _labels = <RenameMode, String>{
    RenameMode.replace: '查找替换',
    RenameMode.affix: '前后缀',
    RenameMode.numbering: '序号编号',
    RenameMode.letterCase: '大小写',
    RenameMode.extension: '改扩展名',
  };

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final entry in _labels.entries)
          ChoiceChip(
            label: Text(entry.value),
            selected: value == entry.key,
            onSelected: (_) => onChanged(entry.key),
            labelStyle: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: value == entry.key ? Colors.white : AppColors.ink2,
            ),
            selectedColor: AppColors.primary,
            backgroundColor: AppColors.surface,
            side: const BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            showCheckmark: false,
          ),
      ],
    );
  }
}

class _RuleForm extends StatelessWidget {
  const _RuleForm({
    required this.rule,
    required this.findController,
    required this.replaceController,
    required this.prefixController,
    required this.suffixController,
    required this.extensionController,
    required this.onChanged,
  });

  final RenameRule rule;
  final TextEditingController findController;
  final TextEditingController replaceController;
  final TextEditingController prefixController;
  final TextEditingController suffixController;
  final TextEditingController extensionController;
  final ValueChanged<RenameRule> onChanged;

  @override
  Widget build(BuildContext context) {
    switch (rule.mode) {
      case RenameMode.replace:
        return Column(
          children: [
            _Field(
              label: '查找',
              controller: findController,
              hint: '例如 IMG_',
              onChanged: (value) => onChanged(rule.copyWith(findText: value)),
            ),
            _Field(
              label: '替换为',
              controller: replaceController,
              hint: '留空表示删除该文本',
              onChanged: (value) =>
                  onChanged(rule.copyWith(replaceText: value)),
            ),
            _SwitchRow(
              label: '区分大小写',
              value: rule.caseSensitive,
              onChanged: (value) =>
                  onChanged(rule.copyWith(caseSensitive: value)),
            ),
            _SwitchRow(
              label: '含扩展名（谨慎）',
              value: rule.includeExtension,
              onChanged: (value) =>
                  onChanged(rule.copyWith(includeExtension: value)),
            ),
          ],
        );

      case RenameMode.affix:
        return Column(
          children: [
            _Field(
              label: '前缀',
              controller: prefixController,
              hint: '例如 2026_',
              onChanged: (value) => onChanged(rule.copyWith(prefix: value)),
            ),
            _Field(
              label: '后缀',
              controller: suffixController,
              hint: '例如 _终稿',
              onChanged: (value) => onChanged(rule.copyWith(suffix: value)),
            ),
          ],
        );

      case RenameMode.numbering:
        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _NumberField(
                    label: '起始',
                    value: rule.startNumber,
                    onChanged: (value) =>
                        onChanged(rule.copyWith(startNumber: value)),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _NumberField(
                    label: '步长',
                    value: rule.step,
                    onChanged: (value) =>
                        onChanged(rule.copyWith(step: value)),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _NumberField(
                    label: '位数',
                    value: rule.digits,
                    onChanged: (value) =>
                        onChanged(rule.copyWith(digits: value)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            _ChoiceRow<NumberPosition>(
              label: '插入位置',
              value: rule.numberPosition,
              options: const {
                NumberPosition.suffix: '追加到名称后',
                NumberPosition.prefix: '添加到名称前',
              },
              onChanged: (value) =>
                  onChanged(rule.copyWith(numberPosition: value)),
            ),
            _ChoiceRow<String>(
              label: '连接符',
              value: rule.separator,
              options: const {'_': '下划线 _', '-': '短横线 -', ' ': '空格'},
              onChanged: (value) => onChanged(rule.copyWith(separator: value)),
            ),
          ],
        );

      case RenameMode.letterCase:
        return _ChoiceRow<LetterCaseMode>(
          label: '转换方式',
          value: rule.letterCase,
          options: const {
            LetterCaseMode.lower: '全部小写',
            LetterCaseMode.upper: '全部大写',
            LetterCaseMode.capitalize: '首字母大写',
          },
          onChanged: (value) => onChanged(rule.copyWith(letterCase: value)),
        );

      case RenameMode.extension:
        return Column(
          children: [
            _Field(
              label: '新扩展名',
              controller: extensionController,
              hint: '例如 jpg（不用写点）',
              onChanged: (value) =>
                  onChanged(rule.copyWith(newExtension: value)),
            ),
            const _HintCard(
              text: '只作用于文件，文件夹会自动跳过；改错扩展名可能导致文件无法打开',
              warn: true,
            ),
          ],
        );
    }
  }
}

class _PreviewList extends StatelessWidget {
  const _PreviewList({required this.items});

  final List<RenamePreviewItem> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final item in items)
          Container(
            margin: const EdgeInsets.only(bottom: AppSpacing.sm),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: item.isUsable || item.isSkipped
                  ? AppColors.surface
                  : const Color(0xFFFFFBFB),
              borderRadius: BorderRadius.circular(AppRadii.tile),
              border: Border.all(
                color: item.isUsable || item.isSkipped
                    ? AppColors.border
                    : AppColors.danger.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.target.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.itemSubtitle.copyWith(
                          decoration: item.isChanged
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        item.newName.isEmpty ? '（空名称）' : item.newName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: item.isUsable
                              ? AppColors.ok
                              : item.isSkipped
                              ? AppColors.ink3
                              : AppColors.danger,
                        ),
                      ),
                      if (item.skipReason != null || item.conflictReason != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            item.conflictReason ?? item.skipReason!,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: item.conflictReason != null
                                  ? AppColors.danger
                                  : AppColors.ink3,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (item.conflictReason != null)
                  const _Tag(text: '冲突', color: AppColors.danger)
                else if (item.isSkipped)
                  const _Tag(text: '跳过', color: AppColors.ink3)
                else
                  const _Tag(text: '将改名', color: AppColors.ok),
              ],
            ),
          ),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.running,
    required this.done,
    required this.total,
    required this.onCancel,
    required this.onApply,
  });

  final bool running;
  final int done;
  final int total;
  final VoidCallback onCancel;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.md,
        AppSpacing.page,
        AppSpacing.page,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: running ? null : onCancel,
              child: const Text('取消'),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: onApply,
              child: Text(
                running
                    ? '正在重命名 $done / $total'
                    : total == 0
                    ? '应用'
                    : '应用（$total 项可用）',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.fieldLabel),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            onChanged: onChanged,
            style: const TextStyle(fontSize: 13.5, color: AppColors.ink),
            decoration: InputDecoration(hintText: hint),
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppText.fieldLabel),
        const SizedBox(height: 6),
        TextFormField(
          initialValue: '$value',
          keyboardType: TextInputType.number,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
          onChanged: (text) {
            final parsed = int.tryParse(text.trim());
            if (parsed != null) {
              onChanged(parsed);
            }
          },
        ),
      ],
    );
  }
}

class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppText.fieldLabel),
          const SizedBox(height: 6),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final entry in options.entries)
                GestureDetector(
                  onTap: () => onChanged(entry.key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: value == entry.key
                          ? AppColors.primarySoft
                          : AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadii.pill),
                      border: Border.all(
                        color: value == entry.key
                            ? AppColors.primary
                            : AppColors.border,
                      ),
                    ),
                    child: Text(
                      entry.value,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: value == entry.key
                            ? AppColors.primary
                            : AppColors.ink2,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: AppColors.ink2,
              ),
            ),
          ),
          Switch.adaptive(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(text, style: AppText.sectionLabel),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({required this.text, this.warn = false});

  final String text;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: warn ? const Color(0xFFFFFDF8) : const Color(0xFFFAFCFF),
        borderRadius: BorderRadius.circular(AppRadii.tile),
        border: Border.all(
          color: warn ? const Color(0xFFF0D9A8) : AppColors.border,
        ),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: warn ? const Color(0xFF8A5A08) : AppColors.ink2,
        ),
      ),
    );
  }
}

class _DangerCard extends StatelessWidget {
  const _DangerCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadii.tile),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: AppColors.danger,
        ),
      ),
    );
  }
}
