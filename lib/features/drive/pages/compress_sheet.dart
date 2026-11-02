import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:foxel/core/api/foxel_api.dart';
import 'package:foxel/core/api/foxel_api_exception.dart';
import 'package:foxel/core/models/compression.dart';
import 'package:foxel/core/theme/design_tokens.dart';
import 'package:foxel/features/drive/pages/directory_picker_page.dart';

/// 压缩提交成功后的结果，供调用方刷新列表并给出反馈。
class CompressOutcome {
  const CompressOutcome({
    required this.path,
    required this.queued,
    this.taskId,
  });

  /// 生成的压缩包完整路径。
  final String path;

  /// 是否仍在后台进行（存储端异步或服务端队列）。
  final bool queued;

  /// 服务端任务 id；非空表示可在「任务」页跟踪。
  final String? taskId;

  String get name {
    final index = path.lastIndexOf('/');
    return index >= 0 ? path.substring(index + 1) : path;
  }
}

/// 打开压缩设置弹层。
///
/// 返回 null 表示用户取消；返回 [CompressOutcome] 表示服务端已接受请求
/// （注意：`queued == true` 时压缩包尚未出现在目录里）。
Future<CompressOutcome?> showCompressSheet({
  required BuildContext context,
  required FoxelApi api,
  required List<String> sources,
  required String initialDir,
  required String defaultName,
  required int sourceBytes,
  required String Function(int) formatSize,
}) {
  return showModalBottomSheet<CompressOutcome>(
    context: context,
    isScrollControlled: true,
    // 提交中不能被拖拽/点遮罩关掉，否则结果会被丢弃（服务端其实已经建了包）。
    enableDrag: false,
    backgroundColor: AppColors.surface,
    builder: (_) => _CompressSheet(
      api: api,
      sources: sources,
      initialDir: initialDir,
      defaultName: defaultName,
      sourceBytes: sourceBytes,
      formatSize: formatSize,
    ),
  );
}

class _CompressSheet extends StatefulWidget {
  const _CompressSheet({
    required this.api,
    required this.sources,
    required this.initialDir,
    required this.defaultName,
    required this.sourceBytes,
    required this.formatSize,
  });

  final FoxelApi api;
  final List<String> sources;
  final String initialDir;
  final String defaultName;
  final int sourceBytes;
  final String Function(int) formatSize;

  @override
  State<_CompressSheet> createState() => _CompressSheetState();
}

class _CompressSheetState extends State<_CompressSheet> {
  late final TextEditingController _nameController = TextEditingController(
    text: widget.defaultName,
  );
  late String _dir = widget.initialDir;

  CompressionCapability? _capability;
  bool _loadingCapability = true;
  bool _submitting = false;
  String? _nameError;
  String? _submitError;

  /// 能力探测的请求序号：连续切换目录时只认最后一次的结果。
  int _capabilitySeq = 0;

  @override
  void initState() {
    super.initState();
    _loadCapability();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadCapability() async {
    final requestId = ++_capabilitySeq;
    if (!_loadingCapability) {
      setState(() {
        _loadingCapability = true;
      });
    }
    CompressionCapability? capability;
    String? failure;
    try {
      capability = await widget.api.compressionCapabilities(_dir);
    } catch (error) {
      failure = error.toString();
    }
    // 已有更新的探测在途 / 弹层已关闭：丢弃这次结果，避免串目录。
    if (!mounted || requestId != _capabilitySeq) {
      return;
    }
    setState(() {
      _capability = capability;
      _loadingCapability = false;
      // 能力探测失败不阻断提交：真正的问题会在 compress 时以明确的状态码返回。
      _submitError = capability == null ? failure : null;
    });
  }

  /// 去掉用户输入里的换行与首尾空白，压缩包名不允许出现路径分隔符。
  String get _cleanName => _nameController.text.trim().replaceAll('/', '');

  Future<void> _pickDirectory() async {
    final picked = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => DirectoryPickerPage(
          api: widget.api,
          title: '选择保存位置',
          initialPath: _dir,
          // 压缩包不能落在被压缩的目录里，服务端会直接 400，
          // 这里在选择阶段就禁掉这些位置。
          blockedPaths: widget.sources.toSet(),
          actionLabel: '保存到此处',
        ),
      ),
    );
    if (picked == null || !mounted) {
      return;
    }
    setState(() {
      _dir = picked;
      _nameError = null;
      _submitError = null;
    });
    await _loadCapability();
  }

  /// 冲突时按时间戳生成一个大概率不重名的名字。
  void _autoRename() {
    final now = DateTime.now();
    final stamp =
        '${now.year}${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}';
    final base = _cleanName.isEmpty ? widget.defaultName : _cleanName;
    setState(() {
      _nameController.text = '$base-$stamp';
      _nameError = null;
    });
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }
    final name = _cleanName;
    if (name.isEmpty) {
      setState(() => _nameError = '请输入压缩包名称');
      return;
    }
    if (name.endsWith('.')) {
      setState(() => _nameError = '名称不能以点结尾');
      return;
    }

    final dst = FoxelApi.joinPath(_dir, '$name.zip');
    // 服务端也会拦这一条，本地先拦可以省一次往返。
    for (final source in widget.sources) {
      if (dst == source || dst.startsWith('$source/')) {
        setState(() => _nameError = '压缩包不能放在被压缩的文件夹里');
        return;
      }
    }

    setState(() {
      _submitting = true;
      _nameError = null;
      _submitError = null;
    });

    try {
      final result = await widget.api.compress(
        sources: widget.sources,
        dst: dst,
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(
        CompressOutcome(
          path: result.path.isEmpty ? dst : result.path,
          queued: result.queued && !result.compressed,
          taskId: result.taskId,
        ),
      );
    } on FoxelApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        if (error.statusCode == 409) {
          _nameError = '同名压缩包已存在，换个名称';
        } else if (error.statusCode == 400) {
          _nameError = error.message;
        } else if (error.statusCode == 501) {
          _submitError = '该存储节点不支持压缩';
        } else {
          _submitError = error.message;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitting = false;
        _submitError = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final capability = _capability;
    final supported = capability == null || capability.supported;
    final canSubmit = supported && !_submitting && !_loadingCapability;

    return PopScope(
      // 提交中禁止返回/点遮罩关闭：一旦关掉，服务端已接受的压缩结果就丢了。
      canPop: !_submitting,
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.page,
          right: AppSpacing.page,
          bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.page,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.86,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                _buildSourceCard(),
                const SizedBox(height: 16),
                _buildNameField(),
                const SizedBox(height: 12),
                _buildLocationField(),
                const SizedBox(height: 14),
                _buildHint(),
                if (_submitError != null) ...[
                  const SizedBox(height: 12),
                  _buildErrorText(_submitError!),
                ],
                const SizedBox(height: 20),
                _buildPrimaryButton(canSubmit),
                const SizedBox(height: 10),
                _buildCancelButton(),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          const Expanded(
            child: Text(
              '压缩为 ZIP',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
                letterSpacing: -0.2,
              ),
            ),
          ),
          IconButton(
            tooltip: '关闭',
            onPressed: _submitting
                ? null
                : () => Navigator.of(context).maybePop(),
            icon: const Icon(
              Icons.close_rounded,
              size: 20,
              color: AppColors.ink2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceCard() {
    final count = widget.sources.length;
    final size = widget.sourceBytes > 0
        ? widget.formatSize(widget.sourceBytes)
        : '';
    final summary = count == 1
        ? widget.sources.first.split('/').last
        : '$count 个项目';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFBFD),
        borderRadius: BorderRadius.circular(AppRadii.tile),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primarySoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.archive_rounded,
              size: 20,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                if (size.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    '合计 $size',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNameField() {
    final hasError = _nameError != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '压缩包名称',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppColors.ink2,
          ),
        ),
        const SizedBox(height: 7),
        Container(
          height: 50,
          padding: const EdgeInsets.only(left: 14, right: 6),
          decoration: BoxDecoration(
            color: hasError ? const Color(0xFFFFFCFC) : AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadii.field),
            border: Border.all(
              color: hasError ? AppColors.danger : const Color(0xFFDCE4EE),
              width: 1.4,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nameController,
                  enabled: !_submitting,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _submit(),
                  inputFormatters: [
                    // 文件名里出现分隔符会让服务端拼出意料之外的路径。
                    FilteringTextInputFormatter.deny(RegExp(r'[/\\]')),
                  ],
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.ink,
                  ),
                  // 外框由上面的 Container 绘制，这里必须彻底清空 InputDecorator
                  // 自己的边框。只写 `border: InputBorder.none` 不够：
                  // 边框回退链是 decoration.enabledBorder → theme.enabledBorder
                  // → decoration.border，而全局 inputDecorationTheme 配了
                  // enabledBorder / focusedBorder，它们优先级高于 border，
                  // 结果就是外框里再套一个 14 圆角的内框（聚焦时还会变蓝）。
                  // 因此逐状态覆盖，并用 contentPadding 撑出可点击高度。
                  decoration: const InputDecoration(
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    disabledBorder: InputBorder.none,
                    errorBorder: InputBorder.none,
                    focusedErrorBorder: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(vertical: 12),
                    hintText: '输入压缩包名称',
                    hintStyle: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.ink3,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // 后缀固定：服务端只接受 .zip，让用户改后缀只会得到一次 400。
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: hasError
                      ? const Color(0xFFFDECEC)
                      : const Color(0xFFF2F5F9),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  '.zip',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: hasError ? AppColors.danger : AppColors.ink3,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (hasError) ...[
          const SizedBox(height: 7),
          Row(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                size: 14,
                color: AppColors.danger,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  _nameError!,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.danger,
                  ),
                ),
              ),
              if (_nameError!.contains('已存在'))
                GestureDetector(
                  onTap: _autoRename,
                  child: const Text(
                    '自动改名',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.primary,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildLocationField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '保存位置',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: AppColors.ink2,
          ),
        ),
        const SizedBox(height: 7),
        InkWell(
          onTap: _submitting ? null : _pickDirectory,
          borderRadius: BorderRadius.circular(AppRadii.field),
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(AppRadii.field),
              border: Border.all(color: const Color(0xFFDCE4EE), width: 1.4),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.folder_outlined,
                  size: 18,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    _dir,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  '更改',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHint() {
    if (_loadingCapability) {
      return _hintBox(
        background: const Color(0xFFF5F8FB),
        foreground: AppColors.ink3,
        icon: Icons.hourglass_empty_rounded,
        title: '正在检查该位置的压缩能力…',
      );
    }
    final capability = _capability;
    if (capability == null) {
      return _hintBox(
        background: const Color(0xFFF5F8FB),
        foreground: AppColors.ink3,
        icon: Icons.help_outline_rounded,
        title: '未能检测压缩能力',
        body: '仍可尝试提交，具体结果以服务端返回为准。',
      );
    }
    if (!capability.supported) {
      return _hintBox(
        background: const Color(0xFFFDECEC),
        foreground: AppColors.danger,
        icon: Icons.block_rounded,
        title: '该位置不支持压缩',
        body: '存储节点既不能原生打包，也无法完成下载与回传。换一个位置试试。',
      );
    }
    if (capability.native) {
      return _hintBox(
        background: const Color(0xFFE9F9F3),
        foreground: const Color(0xFF12B886),
        icon: Icons.check_circle_outline_rounded,
        title: '云端直接打包 · 通常 10 秒内完成',
        body: '该存储节点原生支持 ZIP，服务器就地打包，不产生下载与回传流量。',
      );
    }
    final size = widget.sourceBytes > 0
        ? '共 ${widget.formatSize(widget.sourceBytes)}，'
        : '';
    return _hintBox(
      background: const Color(0xFFFFF7E8),
      foreground: const Color(0xFFB37400),
      icon: Icons.cloud_outlined,
      title: '该节点需服务端中转打包',
      body: '$size需先下载到服务器、打包后再回传，耗时较长。可离开本页，进度在「任务」中查看。',
    );
  }

  Widget _hintBox({
    required Color background,
    required Color foreground,
    required IconData icon,
    required String title,
    String? body,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadii.tile),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 18, color: foreground),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: foreground,
                    height: 1.5,
                  ),
                ),
                if (body != null) ...[
                  const SizedBox(height: 3),
                  Text(
                    body,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      height: 1.65,
                      color: foreground.withValues(alpha: 0.72),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorText(String message) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.error_outline_rounded,
          size: 15,
          color: AppColors.danger,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppColors.danger,
              height: 1.55,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPrimaryButton(bool canSubmit) {
    return SizedBox(
      height: 50,
      child: FilledButton(
        onPressed: canSubmit ? _submit : null,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.35),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.field),
          ),
        ),
        child: _submitting
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text(
                '开始压缩',
                style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
              ),
      ),
    );
  }

  Widget _buildCancelButton() {
    return SizedBox(
      height: 50,
      child: OutlinedButton(
        onPressed: _submitting
            ? null
            : () => Navigator.of(context).maybePop(),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.ink2,
          side: const BorderSide(color: Color(0xFFDCE4EE), width: 1.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.field),
          ),
        ),
        child: const Text(
          '取消',
          style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}
