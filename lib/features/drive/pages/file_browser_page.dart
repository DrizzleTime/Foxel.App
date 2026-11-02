import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:foxel/core/api/foxel_api.dart';
import 'package:foxel/core/models/account.dart';
import 'package:foxel/core/models/file_entry.dart';
import 'package:foxel/core/storage/browse_state_store.dart';
import 'package:foxel/core/storage/download_dir_store.dart';
import 'package:foxel/core/theme/design_tokens.dart';
import 'package:foxel/features/accounts/widgets/account_avatar.dart';
import 'package:foxel/features/drive/controllers/transfer_task_controller.dart';
import 'package:foxel/features/drive/pages/batch_rename_page.dart';
import 'package:foxel/features/drive/pages/compress_sheet.dart';
import 'package:foxel/features/drive/pages/directory_picker_page.dart';
import 'package:foxel/features/media/pages/image_viewer_page.dart';
import 'package:foxel/features/media/pages/video_player_page.dart';

enum _SortField { name, size, modified, type }

enum _ViewMode { grid, list }

class FileBrowserPage extends StatefulWidget {
  const FileBrowserPage({
    super.key,
    required this.api,
    required this.taskController,
    required this.account,
    required this.onOpenTasks,
    required this.onOpenAccountCenter,
  });

  final FoxelApi api;
  final TransferTaskController taskController;
  final Account account;
  final VoidCallback onOpenTasks;

  /// 点击顶部账户条 → 打开账户管理页。
  final VoidCallback onOpenAccountCenter;

  @override
  State<FileBrowserPage> createState() => _FileBrowserPageState();
}

/// 批量操作中的单项失败记录。
class _BatchFailure<T> {
  const _BatchFailure({required this.item, required this.error});

  final T item;
  final String error;
}

class _FileBrowserPageState extends State<FileBrowserPage> {
  final _searchController = TextEditingController();
  final _scrollController = ScrollController();
  final _scrollOffsets = <String, double>{};

  String _path = '/';
  String? _pendingRestorePath;
  late Future<DirectoryListing> _listingFuture;
  String _searchQuery = '';
  _SortField _sortField = _SortField.name;
  bool _sortAscending = true;
  _ViewMode _viewMode = _ViewMode.grid;

  // ---- 多选批量操作 ----
  /// 是否处于选择模式（点条目 = 勾选）。
  bool _selecting = false;

  /// 已选条目的完整路径。
  final Set<String> _selectedPaths = <String>{};

  /// 批量操作进行中：避免重复提交。
  bool _batchBusy = false;

  /// 当前可见条目的快照（供批量操作取名称 / 类型）。
  List<FileEntry> _visibleEntryList = const <FileEntry>[];

  /// 当前目录的完整条目（含被搜索隐藏的），用于重命名冲突检测。
  List<FileEntry> _allEntries = const <FileEntry>[];

  // ---- 顶部提示条（浮在搜索框位置，替代压在底部导航上的黑色 SnackBar）----
  static const Duration _toastDuration = Duration(milliseconds: 2400);

  String _toastText = '';
  String? _toastActionLabel;
  VoidCallback? _toastAction;
  _ToastTone _toastTone = _ToastTone.info;
  bool _toastVisible = false;
  Timer? _toastTimer;

  @override
  void initState() {
    super.initState();
    _listingFuture = widget.api.listDirectory(_path);
    unawaited(_restoreBrowseState());
  }

  @override
  void dispose() {
    _toastTimer?.cancel();
    _saveCurrentScrollOffset();
    unawaited(_saveBrowseState());
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// 恢复该账户上次浏览的位置（路径 / 排序 / 视图模式）。
  Future<void> _restoreBrowseState() async {
    if (!widget.account.rememberBrowseState) {
      return;
    }
    final state = await BrowseStateStore().load(widget.account.id);
    if (state == null || !mounted) {
      return;
    }
    setState(() {
      _path = state.path;
      _sortField = _sortFieldFromName(state.sortField);
      _sortAscending = state.ascending;
      _viewMode = state.viewMode == 'list' ? _ViewMode.list : _ViewMode.grid;
      _listingFuture = widget.api.listDirectory(_path);
    });
  }

  Future<void> _saveBrowseState() async {
    if (!widget.account.rememberBrowseState) {
      return;
    }
    await BrowseStateStore().save(
      widget.account.id,
      BrowseState(
        path: _path,
        sortField: _sortField.name,
        ascending: _sortAscending,
        viewMode: _viewMode.name,
      ),
    );
  }

  static _SortField _sortFieldFromName(String name) {
    for (final field in _SortField.values) {
      if (field.name == name) {
        return field;
      }
    }
    return _SortField.name;
  }

  void _refresh() {
    setState(() {
      _listingFuture = widget.api.listDirectory(_path);
    });
  }

  void _openPath(String path) {
    _saveCurrentScrollOffset();
    final nextPath = FoxelApi.cleanPath(path);
    setState(() {
      _path = nextPath;
      _pendingRestorePath = nextPath;
      _searchController.clear();
      _searchQuery = '';
      // 切换目录即退出多选：否则会留下指向旧目录的「幽灵选中」。
      _selecting = false;
      _selectedPaths.clear();
      _listingFuture = widget.api.listDirectory(_path);
    });
    unawaited(_saveBrowseState());
  }

  void _saveCurrentScrollOffset() {
    if (_scrollController.hasClients) {
      _scrollOffsets[_path] = _scrollController.offset;
    }
  }

  void _restoreScrollOffset(String path) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      final offset = _scrollOffsets[path] ?? 0;
      final maxOffset = _scrollController.position.maxScrollExtent;
      _scrollController.jumpTo(offset.clamp(0.0, maxOffset));
    });
  }

  // ---------------------------------------------------------------- 多选

  /// 进入选择模式；[initial] 用于长按直接选中该项。
  void _enterSelection([FileEntry? initial]) {
    setState(() {
      _selecting = true;
      _selectedPaths.clear();
      if (initial != null) {
        _selectedPaths.add(FoxelApi.joinPath(_path, initial.name));
      }
    });
  }

  void _exitSelection() {
    if (!_selecting && _selectedPaths.isEmpty) {
      return;
    }
    setState(() {
      _selecting = false;
      _selectedPaths.clear();
    });
  }

  void _toggleSelection(FileEntry entry) {
    final fullPath = FoxelApi.joinPath(_path, entry.name);
    setState(() {
      if (!_selectedPaths.remove(fullPath)) {
        _selectedPaths.add(fullPath);
      }
    });
  }

  void _selectAllVisible() {
    final all = _visibleEntryList
        .map((entry) => FoxelApi.joinPath(_path, entry.name))
        .toList();
    final allSelected =
        all.isNotEmpty && all.every(_selectedPaths.contains);
    setState(() {
      _selectedPaths.clear();
      if (!allSelected) {
        _selectedPaths.addAll(all);
      }
    });
  }

  /// 已选条目（按当前列表顺序）。
  List<FileEntry> get _selectedEntries => <FileEntry>[
    for (final entry in _visibleEntryList)
      if (_selectedPaths.contains(FoxelApi.joinPath(_path, entry.name))) entry,
  ];

  /// 当前目录中未被选中的条目名（用于重命名冲突检测）。
  Set<String> get _unselectedNames => <String>{
    for (final entry in _allEntries)
      if (!_selectedPaths.contains(FoxelApi.joinPath(_path, entry.name)))
        entry.name,
  };

  /// 受限并发执行；返回失败项（含原始条目），便于精确重试。
  Future<List<_BatchFailure<T>>> _runLimited<T>(
    List<T> items,
    Future<void> Function(T item) action, {
    int concurrency = 3,
  }) async {
    final failures = <_BatchFailure<T>>[];
    for (var start = 0; start < items.length; start += concurrency) {
      if (!mounted) {
        // 页面已销毁（切账户等）：停止后续分片，避免继续改服务端数据。
        break;
      }
      final slice = items.skip(start).take(concurrency).toList();
      final results = await Future.wait(
        slice.map((item) async {
          try {
            await action(item);
            return null;
          } catch (error) {
            return _BatchFailure<T>(item: item, error: '$error');
          }
        }),
      );
      for (final failure in results) {
        if (failure != null) {
          failures.add(failure);
        }
      }
    }
    return failures;
  }

  /// 递归展开目录为其中的文件（相对当前目录的路径）。
  ///
  /// 服务端没有打包下载接口，因此文件夹按「展开为文件队列」处理。
  /// 最近一次展开中读取失败的目录数（用于提示，不静默吞掉异常）。
  int _skippedDirCount = 0;

  Future<List<String>> _collectFiles(
    String basePath,
    List<String> relativeDirs,
  ) async {
    final files = <String>[];
    for (final dir in relativeDirs) {
      try {
        final listing = await widget.api.listDirectory(
          FoxelApi.joinPath(basePath, dir),
        );
        for (final child in listing.entries) {
          final childPath = dir.isEmpty ? child.name : '$dir/${child.name}';
          if (child.isDir) {
            files.addAll(await _collectFiles(basePath, <String>[childPath]));
          } else {
            files.add(childPath);
          }
        }
      } catch (_) {
        // 单个目录读取失败不影响其余文件，但要计数并在结果里告知用户。
        _skippedDirCount += 1;
      }
    }
    return files;
  }

  Future<void> _batchDownload() async {
    final selected = _selectedEntries;
    if (selected.isEmpty || _batchBusy) {
      return;
    }
    // 快照目录：批量进行中若用户返回上级目录，仍按发起时的目录执行。
    final base = _path;
    setState(() => _batchBusy = true);
    try {
      final localDir = await DownloadDirStore.resolveFor(
        widget.account.id,
        account: widget.account,
      );
      final files = <String>[];
      _skippedDirCount = 0;
      for (final entry in selected) {
        if (entry.isDir) {
          files.addAll(await _collectFiles(base, <String>[entry.name]));
        } else {
          files.add(entry.name);
        }
      }
      final folderCount = selected.where((entry) => entry.isDir).length;
      final skipped = _skippedDirCount;
      if (!mounted) {
        return;
      }
      if (files.isEmpty && skipped > 0) {
        _showMessage('选中的文件夹读取失败，请检查权限后重试');
        return;
      }
      if (files.isEmpty) {
        _showMessage('选中的文件夹里没有可下载的文件');
        return;
      }
      for (final relative in files) {
        if (!mounted) {
          return;
        }
        // 保留相对目录结构，避免同名的子目录文件互相覆盖。
        // 每一段都要清洗：服务端可以返回 "a/../../b" 这种路径，直接拼会写穿目录。
        final segments = <String>[
          for (final segment in relative.split('/'))
            if (segment.isNotEmpty)
              DownloadDirStore.sanitizeFileSegment(segment),
        ];
        if (segments.isEmpty) {
          _skippedDirCount += 1;
          continue;
        }
        final name = segments.last;
        final dirSegments = segments.sublist(0, segments.length - 1);
        var target = localDir;
        if (dirSegments.isNotEmpty) {
          target = Directory(
            <String>[localDir.path, ...dirSegments].join(Platform.pathSeparator),
          );
          if (!await target.exists()) {
            await target.create(recursive: true);
          }
        }
        widget.taskController.startDownload(
          api: widget.api,
          name: name,
          // 远端路径必须用原始相对路径，清洗只作用于本地落盘名。
          remotePath: FoxelApi.joinPath(base, relative),
          outputFile: File(
            '${target.path}${Platform.pathSeparator}$name',
          ),
        );
      }
      if (!mounted) {
        return;
      }
      _exitSelection();
      _showMessage(
        '已加入 ${files.length} 个下载任务'
        '${folderCount > 0 ? '（含 $folderCount 个文件夹的内容）' : ''}'
        '${skipped > 0 ? '，$skipped 个子目录读取失败已跳过' : ''}',
      );
    } catch (error) {
      if (mounted) {
        _showMessage(error.toString(), isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _batchBusy = false);
      }
    }
  }

  /// 批量移动 / 复制：先选目标目录，再逐项执行。
  Future<void> _batchTransfer({required bool move}) async {
    final selected = _selectedEntries;
    if (selected.isEmpty || _batchBusy) {
      return;
    }
    final base = _path;
    final sourcePaths = <String>{
      for (final entry in selected) FoxelApi.joinPath(base, entry.name),
    };
    // 提前置位：目录选择页弹出期间若仍可点，会叠加第二次提交
    setState(() => _batchBusy = true);
    // 取消弹层 / 页面销毁的路径都必须复位，否则批量栏会永久卡在忙碌态。
    try {
      final target = await Navigator.of(context).push<String>(
        MaterialPageRoute<String>(
          builder: (_) => DirectoryPickerPage(
            api: widget.api,
            title: move ? '移动到…' : '复制到…',
            initialPath: _path,
            // 禁止选到被移动/复制的条目自身及其后代
            blockedPaths: sourcePaths,
            // 来源目录本身不可作为目标（dst == src），但它的子目录可以
            exactBlockedPaths: <String>{base},
            actionLabel: move ? '移动到此处' : '复制到此处',
          ),
        ),
      );
      if (target == null || !mounted) {
        return;
      }

      final failures = await _runLimited<FileEntry>(selected, (entry) async {
        final src = FoxelApi.joinPath(base, entry.name);
        final dst = FoxelApi.joinPath(target, entry.name);
        if (move) {
          await widget.api.move(src: src, dst: dst);
        } else {
          await widget.api.copy(src: src, dst: dst);
        }
      });
      if (!mounted) {
        return;
      }
      final ok = selected.length - failures.length;
      if (failures.isEmpty) {
        _exitSelection();
        _refresh();
        _showMessage('已${move ? '移动' : '复制'} $ok 项到「${_nameOf(target)}」');
      } else {
        // 失败项保留选中，便于重试（按条目精确剔除成功项）。
        final failedPaths = <String>{
          for (final failure in failures)
            FoxelApi.joinPath(base, failure.item.name),
        };
        setState(() {
          _selectedPaths.retainWhere(failedPaths.contains);
        });
        _refresh();
        _showMessage(
          '已${move ? '移动' : '复制'} $ok 项，${failures.length} 项失败：'
          '${failures.first.error}',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _batchBusy = false);
      }
    }
  }

  Future<void> _batchDelete() async {
    final selected = _selectedEntries;
    if (selected.isEmpty || _batchBusy) {
      return;
    }
    final folders = selected.where((entry) => entry.isDir).length;
    final files = selected.length - folders;
    final size = selected
        .where((entry) => !entry.isDir)
        .fold<int>(0, (sum, entry) => sum + entry.size);

    // 提前置位：确认框弹出期间禁止重复触发
    setState(() => _batchBusy = true);
    final base = _path;
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('删除 ${selected.length} 项？'),
          content: Text(
            '包含 ${files > 0 ? '$files 个文件' : ''}'
            '${files > 0 && folders > 0 ? '与' : ''}'
            '${folders > 0 ? '$folders 个文件夹及其全部内容' : ''}'
            '${size > 0 ? '，合计约 ${_formatSize(size)}' : ''}。\n'
            '服务器上的文件将被删除，此操作不可撤销。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text('删除 ${selected.length} 项'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        return;
      }

      final failures = await _runLimited<FileEntry>(selected, (entry) async {
        await widget.api.deletePath(FoxelApi.joinPath(base, entry.name));
      });
      if (!mounted) {
        return;
      }
      final ok = selected.length - failures.length;
      _refresh();
      if (failures.isEmpty) {
        _exitSelection();
        _showMessage('已删除 $ok 项');
      } else {
        // 失败项保留选中，便于重试（按条目精确剔除成功项）。
        final failedPaths = <String>{
          for (final failure in failures)
            FoxelApi.joinPath(base, failure.item.name),
        };
        setState(() {
          _selectedPaths.retainWhere(failedPaths.contains);
        });
        _showMessage('已删除 $ok 项，${failures.length} 项失败');
      }
    } finally {
      if (mounted) {
        setState(() => _batchBusy = false);
      }
    }
  }

  Future<void> _openBatchRename() async {
    final selected = _selectedEntries;
    if (selected.isEmpty || _batchBusy) {
      return;
    }
    setState(() => _batchBusy = true);
    try {
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(
          builder: (_) => BatchRenamePage(
            api: widget.api,
            directoryPath: _path,
            targets: selected,
            existingNames: _unselectedNames,
          ),
        ),
      );
      if (changed == true && mounted) {
        _exitSelection();
        _refresh();
        _showMessage('批量重命名已完成');
      }
    } finally {
      if (mounted) {
        setState(() => _batchBusy = false);
      }
    }
  }

  void _showBatchMore() {
    final selected = _selectedEntries;
    if (selected.isEmpty) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.page,
            0,
            AppSpacing.page,
            AppSpacing.page,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '对已选 ${selected.length} 项执行',
                  style: AppText.sectionLabel,
                ),
              ),
              _ActionRow(
                icon: Icons.download_rounded,
                label: '下载',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _batchDownload();
                },
              ),
              _ActionRow(
                icon: Icons.archive_rounded,
                label: '压缩为 ZIP',
                trailing: const _NewPill(),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _compressSelection();
                },
              ),
              _ActionRow(
                icon: Icons.drive_file_move_outline,
                label: '移动到…',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _batchTransfer(move: true);
                },
              ),
              _ActionRow(
                icon: Icons.copy_rounded,
                label: '复制到…',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _batchTransfer(move: false);
                },
              ),
              _ActionRow(
                icon: Icons.drive_file_rename_outline_rounded,
                label: '批量重命名',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openBatchRename();
                },
              ),
              _ActionRow(
                icon: Icons.delete_outline_rounded,
                label: '删除',
                destructive: true,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _batchDelete();
                },
              ),
              _ActionRow(
                icon: Icons.deselect_rounded,
                label: '取消选择',
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  setState(() => _selectedPaths.clear());
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 批量操作栏的底部偏移。
  ///
  /// 文件页是底部导航壳内的一个 tab，操作栏必须落在浮动导航之上：
  /// 导航高 74 + 最小下边距 12 + 8 的间隙（有系统手势条时取更大的安全区）。
  double _batchBarBottom(BuildContext context) {
    const navHeight = 74.0;
    const navMinInset = 12.0;
    const gap = 8.0;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final navBottom = safeBottom > navMinInset ? safeBottom : navMinInset;
    return navBottom + navHeight + gap;
  }

  // ---------------------------------------------------------------- 压缩

  /// 压缩包的默认名：去掉扩展名，本身的 zip 再压时加后缀避免与源同名。
  static String _archiveNameFor(String baseName) {
    final lower = baseName.toLowerCase();
    if (lower.endsWith('.zip')) {
      return '${baseName.substring(0, baseName.length - 4)}-压缩';
    }
    final dot = baseName.lastIndexOf('.');
    if (dot > 0) {
      return baseName.substring(0, dot);
    }
    return baseName;
  }

  /// 多选时的默认名：用当前目录名，根目录退化为 archive。
  String get _directoryArchiveName {
    if (_path == '/') {
      return 'archive';
    }
    final index = _path.lastIndexOf('/');
    final name = index >= 0 ? _path.substring(index + 1) : _path;
    return name.isEmpty ? 'archive' : '$name-归档';
  }

  /// 已选条目里「已知体积」之和。
  ///
  /// 文件夹内部体积需要递归遍历才能得到，这里不发起额外请求，
  /// 只统计列表里直接可见的文件，标注为「合计」而不是精确总量。
  int _knownBytesOf(List<String> sources) {
    var total = 0;
    for (final entry in _visibleEntryList) {
      if (entry.isDir) {
        continue;
      }
      if (sources.contains(FoxelApi.joinPath(_path, entry.name))) {
        total += entry.size;
      }
    }
    return total;
  }

  Future<void> _startCompress({
    required List<String> sources,
    required String defaultName,
  }) async {
    if (sources.isEmpty) {
      return;
    }
    final outcome = await showCompressSheet(
      context: context,
      api: widget.api,
      sources: sources,
      initialDir: _path,
      defaultName: defaultName,
      sourceBytes: _knownBytesOf(sources),
      formatSize: _formatSize,
    );
    if (outcome == null || !mounted) {
      return;
    }
    setState(() {
      _selecting = false;
      _selectedPaths.clear();
    });
    _refresh();
    _showToast(
      outcome.queued
          ? '已加入服务端任务队列，可在「任务」中查看进度'
          : '已创建 ${outcome.name}',
      actionLabel: outcome.queued ? '查看' : null,
      action: outcome.queued ? widget.onOpenTasks : null,
    );
  }

  /// 压缩当前选中的条目。
  Future<void> _compressSelection() async {
    final selected = _selectedEntries;
    if (selected.isEmpty) {
      return;
    }
    // 服务端要求 sources 内名称唯一，同名项无法共享同一个归档内路径。
    final names = <String>{};
    for (final entry in selected) {
      if (!names.add(entry.name)) {
        _showMessage('选中的项目里有同名条目，请只保留一个再压缩');
        return;
      }
    }
    await _startCompress(
      sources: [for (final path in _selectedPaths) FoxelApi.cleanPath(path)],
      defaultName: _directoryArchiveName,
    );
  }


  String _nameOf(String path) {
    if (path == '/') {
      return '根目录';
    }
    final trimmed = path.replaceAll(RegExp(r'/+$'), '');
    final index = trimmed.lastIndexOf('/');
    final name = index < 0 ? trimmed : trimmed.substring(index + 1);
    return name.isEmpty ? trimmed : name;
  }

  /// 顶部提示条：浮在搜索框那一行，不遮挡列表与底部导航。
  void _showToast(
    String message, {
    String? actionLabel,
    VoidCallback? action,
    bool isError = false,
  }) {
    if (!mounted) {
      return;
    }
    _toastTimer?.cancel();
    // 多选态没有搜索框位置可占，退回系统 SnackBar，保证提示不丢。
    if (_selecting) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    setState(() {
      _toastText = message;
      _toastActionLabel = actionLabel;
      _toastAction = action;
      _toastTone = isError ? _ToastTone.error : _ToastTone.info;
      _toastVisible = true;
    });
    _toastTimer = Timer(_toastDuration, () {
      if (!mounted) {
        return;
      }
      setState(() => _toastVisible = false);
    });
  }

  void _hideToast() {
    _toastTimer?.cancel();
    if (!_toastVisible) {
      return;
    }
    setState(() => _toastVisible = false);
  }

  void _showMessage(String message, {bool isError = false}) {
    _showToast(message, isError: isError);
  }

  Future<void> _runAction(Future<void> Function() action) async {
    try {
      await action();
      // 操作期间可能已切账户（State 被 ValueKey 替换并 dispose）。
      if (!mounted) {
        return;
      }
      _refresh();
    } catch (error) {
      if (mounted) {
        _showMessage(error.toString(), isError: true);
      }
    }
  }

  Future<String?> _askText({
    required String title,
    required String label,
    String initialValue = '',
  }) {
    final controller = TextEditingController(text: initialValue);
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(labelText: label),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('确定'),
            ),
          ],
        );
      },
    ).whenComplete(controller.dispose);
  }

  Future<void> _createFolder() async {
    // 操作可能由切换账户前的弹层触发，State 已被替换。
    if (!mounted) {
      return;
    }
    final name = await _askText(title: '新建文件夹', label: '文件夹名称');
    if (name == null || name.trim().isEmpty) {
      return;
    }
    await _runAction(() => widget.api.mkdir(FoxelApi.joinPath(_path, name)));
  }

  Future<void> _uploadFile() async {
    // 操作可能由切换账户前的弹层触发，State 已被替换。
    if (!mounted) {
      return;
    }
    try {
      final result = await FilePicker.platform.pickFiles(withData: false);
      final file = result?.files.isNotEmpty == true ? result!.files.first : null;
      final localPath = file?.path;
      if (file == null || localPath == null) {
        return;
      }
      final remotePath = FoxelApi.joinPath(_path, file.name);
      widget.taskController.startUpload(
        api: widget.api,
        name: file.name,
        remotePath: remotePath,
        localPath: localPath,
        onSuccess: () {
          if (mounted) {
            _refresh();
          }
        },
      );
      widget.onOpenTasks();
    } catch (error) {
      if (mounted) {
        _showMessage('选择文件失败：$error', isError: true);
      }
    }
  }

  Future<void> _renameEntry(FileEntry entry) async {
    // 操作可能由切换账户前的弹层触发，State 已被替换。
    if (!mounted) {
      return;
    }
    final newName = await _askText(
      title: '重命名',
      label: '新名称',
      initialValue: entry.name,
    );
    if (newName == null || newName.trim().isEmpty || newName == entry.name) {
      return;
    }
    final src = FoxelApi.joinPath(_path, entry.name);
    final dst = FoxelApi.joinPath(_path, newName.trim());
    await _runAction(() => widget.api.rename(src: src, dst: dst));
  }

  Future<void> _copyEntry(FileEntry entry) async {
    // 操作可能由切换账户前的弹层触发，State 已被替换。
    if (!mounted) {
      return;
    }
    final target = await _askText(
      title: '复制到',
      label: '目标完整路径',
      initialValue: FoxelApi.joinPath(_path, '${entry.name}_copy'),
    );
    if (target == null || target.trim().isEmpty) {
      return;
    }
    await _runAction(
      () => widget.api.copy(
        src: FoxelApi.joinPath(_path, entry.name),
        dst: target.trim(),
      ),
    );
  }

  Future<void> _moveEntry(FileEntry entry) async {
    // 操作可能由切换账户前的弹层触发，State 已被替换。
    if (!mounted) {
      return;
    }
    final target = await _askText(
      title: '移动到',
      label: '目标完整路径',
      initialValue: FoxelApi.joinPath(_path, entry.name),
    );
    if (target == null || target.trim().isEmpty) {
      return;
    }
    await _runAction(
      () => widget.api.move(
        src: FoxelApi.joinPath(_path, entry.name),
        dst: target.trim(),
      ),
    );
  }

  Future<void> _deleteEntry(FileEntry entry) async {
    // 操作可能由切换账户前的弹层触发，State 已被替换。
    if (!mounted) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除'),
          content: Text('确定删除 ${entry.name}？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    await _runAction(
      () => widget.api.deletePath(FoxelApi.joinPath(_path, entry.name)),
    );
  }

  Future<void> _downloadEntry(FileEntry entry) async {
    // 操作可能由切换账户前的弹层触发，State 已被替换。
    if (!mounted) {
      return;
    }
    if (entry.isDir) {
      _showMessage('暂不支持下载文件夹');
      return;
    }
    try {
      final dir = await DownloadDirStore.resolveFor(widget.account.id, account: widget.account);
      // 服务端文件名不可信：先清洗再拼本地路径。直接拼会踩两类坑——
      // ".." 指到上级目录、":" "*" 之类在 Windows 上建文件直接失败。
      final safeName = DownloadDirStore.sanitizeFileSegment(entry.name);
      if (safeName.isEmpty) {
        _showMessage('文件名不可用，已跳过：${entry.name}', isError: true);
        return;
      }
      final output = File('${dir.path}${Platform.pathSeparator}$safeName');
      widget.taskController.startDownload(
        api: widget.api,
        name: entry.name,
        remotePath: FoxelApi.joinPath(_path, entry.name),
        outputFile: output,
      );
      widget.onOpenTasks();
    } catch (error) {
      if (!mounted) {
        return;
      }
      if (!kIsWeb &&
          Platform.isAndroid &&
          !await DownloadDirStore.hasAllFilesAccess()) {
        if (!mounted) {
          return;
        }
        final goSettings = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            return AlertDialog(
              title: const Text('无法写入下载目录'),
              content: const Text(
                'Android 10 及以上系统需要「所有文件访问」权限才能写入公共下载目录，'
                '是否前往系统设置开启？开启后返回应用重新下载即可。',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('去授权'),
                ),
              ],
            );
          },
        );
        if (goSettings == true) {
          await DownloadDirStore.requestAllFilesAccess();
        }
        if (!mounted) {
          return;
        }
        return;
      }
      _showMessage('无法写入下载目录：$error', isError: true);
    }
  }

  void _openEntry(FileEntry entry) {
    // 操作可能由切换账户前的弹层触发，State 已被替换。
    if (!mounted) {
      return;
    }
    final fullPath = FoxelApi.joinPath(_path, entry.name);
    if (entry.isDir) {
      _openPath(fullPath);
      return;
    }
    final lower = entry.name.toLowerCase();
    if (_isImage(lower)) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ImageViewerPage(
            api: widget.api,
            path: fullPath,
            name: entry.name,
          ),
        ),
      );
      return;
    }
    if (_isVideo(lower)) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => VideoPlayerPage(
            api: widget.api,
            accountId: widget.account.id,
            path: fullPath,
            name: entry.name,
            size: entry.size,
            mtime: entry.mtime,
          ),
        ),
      );
      return;
    }
    _showMessage('该文件类型暂不支持预览，可使用下载');
  }

  void _showEntryActions(FileEntry entry) {
    final fullPath = FoxelApi.joinPath(_path, entry.name);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    _EntryVisual(
                      api: widget.api,
                      entry: entry,
                      fullPath: fullPath,
                      size: 48,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            entry.isDir
                                ? fullPath
                                : '${_formatSize(entry.size)} · ${_formatMtime(entry.mtime)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (!entry.isDir)
                  _ActionRow(
                    icon: Icons.download_rounded,
                    label: '下载',
                    onTap: () {
                      Navigator.of(context).pop();
                      _downloadEntry(entry);
                    },
                  ),
                _ActionRow(
                  icon: Icons.archive_rounded,
                  label: '压缩为 ZIP',
                  trailing: const _NewPill(),
                  onTap: () {
                    Navigator.of(context).pop();
                    _startCompress(
                      sources: [fullPath],
                      defaultName: _archiveNameFor(entry.name),
                    );
                  },
                ),
                _ActionRow(
                  icon: Icons.drive_file_rename_outline_rounded,
                  label: '重命名',
                  onTap: () {
                    Navigator.of(context).pop();
                    _renameEntry(entry);
                  },
                ),
                _ActionRow(
                  icon: Icons.content_copy_rounded,
                  label: '复制到',
                  onTap: () {
                    Navigator.of(context).pop();
                    _copyEntry(entry);
                  },
                ),
                _ActionRow(
                  icon: Icons.drive_file_move_rounded,
                  label: '移动到',
                  onTap: () {
                    Navigator.of(context).pop();
                    _moveEntry(entry);
                  },
                ),
                _ActionRow(
                  icon: Icons.delete_outline_rounded,
                  label: '删除',
                  destructive: true,
                  onTap: () {
                    Navigator.of(context).pop();
                    _deleteEntry(entry);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<FileEntry> _visibleEntries(List<FileEntry> entries) {
    final query = _searchQuery.trim().toLowerCase();
    final visible = entries.where((entry) {
      if (query.isEmpty) {
        return true;
      }
      return entry.name.toLowerCase().contains(query);
    }).toList();

    visible.sort((a, b) {
      if (a.isDir != b.isDir) {
        return a.isDir ? -1 : 1;
      }
      var result = switch (_sortField) {
        _SortField.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        _SortField.size => a.size.compareTo(b.size),
        _SortField.modified => a.mtime.compareTo(b.mtime),
        _SortField.type => _fileKind(a).compareTo(_fileKind(b)),
      };
      // 稳定 tie-break：List.sort 不稳定，同键项顺序不确定会影响批量重命名的序号
      if (result == 0) {
        result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      return _sortAscending ? result : -result;
    });

    return visible;
  }

  _DirectorySummary _summaryFor(List<FileEntry> entries) {
    var folderCount = 0;
    var fileCount = 0;
    var totalSize = 0;
    var latestMtime = 0;
    for (final entry in entries) {
      if (entry.isDir) {
        folderCount += 1;
      } else {
        fileCount += 1;
        totalSize += entry.size;
      }
      if (entry.mtime > latestMtime) {
        latestMtime = entry.mtime;
      }
    }
    return _DirectorySummary(
      folderCount: folderCount,
      fileCount: fileCount,
      totalSize: totalSize,
      latestMtime: latestMtime,
    );
  }

  bool _isImage(String name) {
    return name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.gif') ||
        name.endsWith('.webp') ||
        name.endsWith('.bmp');
  }

  bool _isVideo(String name) {
    return name.endsWith('.mp4') ||
        name.endsWith('.m4v') ||
        name.endsWith('.mov') ||
        name.endsWith('.webm') ||
        name.endsWith('.mkv') ||
        name.endsWith('.avi');
  }

  String _fileKind(FileEntry entry) {
    if (entry.isDir) {
      return '文件夹';
    }
    final lower = entry.name.toLowerCase();
    if (_isImage(lower)) {
      return '图片';
    }
    if (_isVideo(lower)) {
      return '视频';
    }
    if (lower.endsWith('.pdf')) {
      return 'PDF';
    }
    if (lower.endsWith('.zip') ||
        lower.endsWith('.rar') ||
        lower.endsWith('.7z')) {
      return '压缩包';
    }
    if (lower.endsWith('.doc') ||
        lower.endsWith('.docx') ||
        lower.endsWith('.md') ||
        lower.endsWith('.txt')) {
      return '文档';
    }
    return '文件';
  }

  String _formatSize(int size) {
    if (size < 1024) {
      return '$size B';
    }
    if (size < 1024 * 1024) {
      return '${(size / 1024).toStringAsFixed(1)} KB';
    }
    if (size < 1024 * 1024 * 1024) {
      return '${(size / 1024 / 1024).toStringAsFixed(1)} MB';
    }
    return '${(size / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
  }

  String _formatMtime(int mtime) {
    if (mtime <= 0) {
      return '未知时间';
    }
    final millis = mtime > 100000000000 ? mtime : mtime * 1000;
    final time = DateTime.fromMillisecondsSinceEpoch(millis);
    final now = DateTime.now();
    final minute = time.minute.toString().padLeft(2, '0');
    if (time.year == now.year &&
        time.month == now.month &&
        time.day == now.day) {
      return '今天 ${time.hour}:$minute';
    }
    if (time.year == now.year) {
      return '${time.month}月${time.day}日';
    }
    return '${time.year}/${time.month}/${time.day}';
  }

  String get _sortLabel {
    return switch (_sortField) {
      _SortField.name => '名称',
      _SortField.size => '大小',
      _SortField.modified => '时间',
      _SortField.type => '类型',
    };
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 多选态下返回键优先退出选择，而不是跳上级目录
      canPop: !_selecting && _path == '/',
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          return;
        }
        if (_selecting) {
          _exitSelection();
        } else if (_path != '/') {
          _openPath(FoxelApi.parentPath(_path));
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F7FA),
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              FutureBuilder<DirectoryListing>(
            future: _listingFuture,
            builder: (context, snapshot) {
              final loading = snapshot.connectionState != ConnectionState.done;
              final entries = snapshot.data?.entries ?? const <FileEntry>[];
              final summary = loading
                  ? const _DirectorySummary(
                      folderCount: 0,
                      fileCount: 0,
                      totalSize: 0,
                      latestMtime: 0,
                    )
                  : _summaryFor(entries);
              final visibleEntries = loading
                  ? const <FileEntry>[]
                  : _visibleEntries(entries);
              // 供批量操作取名称 / 类型；搜索过滤后以可见项为准。
              _visibleEntryList = visibleEntries;
              // 冲突检测必须覆盖完整条目，否则被搜索隐藏的同名文件会被覆盖。
              _allEntries = entries;
              final hasSearch = _searchQuery.trim().isNotEmpty;
              if (!loading &&
                  !snapshot.hasError &&
                  _pendingRestorePath == _path) {
                _pendingRestorePath = null;
                _restoreScrollOffset(_path);
              }

              return Column(
                children: [
                  _AccountBar(
                    account: widget.account,
                    onTap: widget.onOpenAccountCenter,
                  ),
                  if (_selecting)
                    _SelectionBar(
                      selectedCount: _selectedPaths.length,
                      totalCount: visibleEntries.length,
                      busy: _batchBusy,
                      onCancel: _exitSelection,
                      onSelectAll: _selectAllVisible,
                    )
                  else
                  _Toolbar(
                    controller: _searchController,
                    query: _searchQuery,
                    toast: _TopToast(
                      text: _toastText,
                      actionLabel: _toastActionLabel,
                      onAction: _toastAction,
                      tone: _toastTone,
                      visible: _toastVisible,
                      onDismiss: _hideToast,
                    ),
                    sortLabel: _sortLabel,
                    sortAscending: _sortAscending,
                    sortField: _sortField,
                    viewMode: _viewMode,
                    path: _path,
                    summary: summary,
                    visibleCount: visibleEntries.length,
                    hasSearch: hasSearch,
                    // 接口固定取第一页 200 条：取满即提示可能还有更多。
                    truncated: !loading &&
                        !snapshot.hasError &&
                        entries.length >= 200,
                    statusText: loading
                        ? '加载中'
                        : snapshot.hasError
                        ? '加载失败'
                        : null,
                    formatSize: _formatSize,
                    formatMtime: _formatMtime,
                    onOpenPath: _openPath,
                    onSearchChanged: (value) {
                      setState(() => _searchQuery = value);
                    },
                    onClearSearch: () {
                      setState(() {
                        _searchController.clear();
                        _searchQuery = '';
                      });
                    },
                    onSortSelected: (field) {
                      setState(() => _sortField = field);
                    },
                    onToggleSortDirection: () {
                      setState(() => _sortAscending = !_sortAscending);
                    },
                    onViewModeChanged: (mode) {
                      setState(() => _viewMode = mode);
                    },
                    onCreateFolder: _createFolder,
                    onEnterSelection: visibleEntries.isEmpty
                        ? null
                        : () => _enterSelection(),
                  ),
                  Expanded(
                    child: loading
                        ? const _LoadingView()
                        : snapshot.hasError
                        ? _ErrorView(
                            message: snapshot.error.toString(),
                            onRetry: _refresh,
                          )
                        : RefreshIndicator(
                            onRefresh: () async => _refresh(),
                            child: CustomScrollView(
                              controller: _scrollController,
                              physics: const AlwaysScrollableScrollPhysics(),
                              slivers: [
                                if (_selecting && _selectedEntries.isNotEmpty)
                                  SliverToBoxAdapter(
                                    child: _SelectionSummary(
                                      entries: _selectedEntries,
                                      formatSize: _formatSize,
                                    ),
                                  ),
                                if (entries.isEmpty)
                                  SliverFillRemaining(
                                    hasScrollBody: false,
                                    child: _EmptyView(
                                      title: '当前目录为空',
                                      message: '可以上传文件，或先创建一个文件夹。',
                                      icon: Icons.folder_open_rounded,
                                      primaryLabel: '上传文件',
                                      primaryIcon: Icons.upload_file_rounded,
                                      onPrimary: _uploadFile,
                                      secondaryLabel: '新建文件夹',
                                      secondaryIcon:
                                          Icons.create_new_folder_rounded,
                                      onSecondary: _createFolder,
                                    ),
                                  )
                                else if (visibleEntries.isEmpty)
                                  SliverFillRemaining(
                                    hasScrollBody: false,
                                    child: _EmptyView(
                                      title: '没有匹配结果',
                                      message: '当前目录没有包含“$_searchQuery”的文件。',
                                      icon: Icons.search_off_rounded,
                                      primaryLabel: '清空搜索',
                                      primaryIcon: Icons.close_rounded,
                                      onPrimary: () {
                                        setState(() {
                                          _searchController.clear();
                                          _searchQuery = '';
                                        });
                                      },
                                    ),
                                  )
                                else if (_viewMode == _ViewMode.grid)
                                  _FileGrid(
                                    api: widget.api,
                                    entries: visibleEntries,
                                    currentPath: _path,
                                    formatSize: _formatSize,
                                    formatMtime: _formatMtime,
                                    fileKind: _fileKind,
                                    selecting: _selecting,
                                    selectedPaths: _selectedPaths,
                                    onOpen: _selecting
                                        ? _toggleSelection
                                        : _openEntry,
                                    onMore: _showEntryActions,
                                    onToggle: _toggleSelection,
                                    onLongPress: _enterSelection,
                                  )
                                else
                                  _FileList(
                                    api: widget.api,
                                    entries: visibleEntries,
                                    currentPath: _path,
                                    formatSize: _formatSize,
                                    formatMtime: _formatMtime,
                                    fileKind: _fileKind,
                                    selecting: _selecting,
                                    selectedPaths: _selectedPaths,
                                    onOpen: _selecting
                                        ? _toggleSelection
                                        : _openEntry,
                                    onMore: _showEntryActions,
                                    onToggle: _toggleSelection,
                                    onLongPress: _enterSelection,
                                  ),
                                SliverToBoxAdapter(
                                  child: SizedBox(
                                    // 多选态要同时避开底部导航与操作栏
                                    height: _selecting
                                        ? _batchBarBottom(context) + 74
                                        : 84,
                                  ),
                                ),
                              ],
                            ),
                          ),
                  ),
                ],
              );
            },
              ),
              if (_selecting)
                Positioned(
                  left: 14,
                  right: 14,
                  // 抬到浮动导航之上，避免被遮挡后无法点击
                  bottom: _batchBarBottom(context),
                  child: _BatchActionBar(
                    count: _selectedPaths.length,
                    busy: _batchBusy,
                    onDownload: _batchDownload,
                    onCompress: _compressSelection,
                    onMove: () => _batchTransfer(move: true),
                    onCopy: () => _batchTransfer(move: false),
                    onDelete: _batchDelete,
                    onMore: _showBatchMore,
                  ),
                ),
            ],
          ),
        ),
        floatingActionButton: _selecting
            ? null
            : Builder(
          builder: (context) {
            final compact = MediaQuery.sizeOf(context).width < 560;
            final bottomInset = MediaQuery.of(context).viewPadding.bottom + 72;
            final button = compact
                ? FloatingActionButton(
                    tooltip: '上传文件',
                    onPressed: _uploadFile,
                    child: const Icon(Icons.upload_file_rounded),
                  )
                : FloatingActionButton.extended(
                    tooltip: '上传文件',
                    onPressed: _uploadFile,
                    icon: const Icon(Icons.upload_file_rounded),
                    label: const Text('上传'),
                  );
            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: button,
            );
          },
        ),
      ),
    );
  }
}

class _DirectorySummary {
  const _DirectorySummary({
    required this.folderCount,
    required this.fileCount,
    required this.totalSize,
    required this.latestMtime,
  });

  final int folderCount;
  final int fileCount;
  final int totalSize;
  final int latestMtime;
}

/// 多选模式的顶部条：取消 / 已选择 N 项 / 全选。
class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.selectedCount,
    required this.totalCount,
    required this.busy,
    required this.onCancel,
    required this.onSelectAll,
  });

  final int selectedCount;
  final int totalCount;
  final bool busy;
  final VoidCallback onCancel;
  final VoidCallback onSelectAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          TextButton(
            onPressed: busy ? null : onCancel,
            child: const Text(
              '取消',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: AppColors.ink2,
              ),
            ),
          ),
          Expanded(
            child: Text(
              selectedCount == 0 ? '选择文件' : '已选择 $selectedCount 项',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
              ),
            ),
          ),
          TextButton(
            onPressed: busy || totalCount == 0 ? null : onSelectAll,
            child: const Text(
              '全选',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 选中项构成提示：X 个文件（合计体积）+ Y 个文件夹。
class _SelectionSummary extends StatelessWidget {
  const _SelectionSummary({
    required this.entries,
    required this.formatSize,
  });

  final List<FileEntry> entries;
  final String Function(int) formatSize;

  @override
  Widget build(BuildContext context) {
    final folders = entries.where((entry) => entry.isDir).length;
    final files = entries.length - folders;
    final size = entries
        .where((entry) => !entry.isDir)
        .fold<int>(0, (sum, entry) => sum + entry.size);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.sm,
        AppSpacing.page,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.primarySoft,
          borderRadius: BorderRadius.circular(AppRadii.tile),
        ),
        child: Text(
          '含 $files 个文件${size > 0 ? '（${formatSize(size)}）' : ''}'
          '${folders > 0 ? ' + $folders 个文件夹' : ''}',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}

/// 多选模式的底部操作栏（悬浮胶囊）。
class _BatchActionBar extends StatelessWidget {
  const _BatchActionBar({
    required this.count,
    required this.busy,
    required this.onDownload,
    required this.onCompress,
    required this.onMove,
    required this.onCopy,
    required this.onDelete,
    required this.onMore,
  });

  final int count;
  final bool busy;
  final VoidCallback onDownload;
  final VoidCallback onCompress;
  final VoidCallback onMove;
  final VoidCallback onCopy;
  final VoidCallback onDelete;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final enabled = count > 0 && !busy;
    return Material(
      color: AppColors.surface,
      clipBehavior: Clip.antiAlias,
      elevation: 6,
      shadowColor: const Color(0x1A8B97AA),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.nav),
        side: const BorderSide(color: AppColors.border),
      ),
      child: SizedBox(
        height: 62,
        child: busy
            ? const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            : Row(
                children: [
                  _BatchAction(
                    icon: Icons.download_rounded,
                    label: '下载',
                    color: AppColors.primary,
                    onTap: enabled ? onDownload : null,
                  ),
                  _BatchAction(
                    icon: Icons.archive_rounded,
                    label: '压缩',
                    color: AppColors.primary,
                    onTap: enabled ? onCompress : null,
                  ),
                  _BatchAction(
                    icon: Icons.drive_file_move_outline,
                    label: '移动',
                    onTap: enabled ? onMove : null,
                  ),
                  _BatchAction(
                    icon: Icons.copy_rounded,
                    label: '复制',
                    onTap: enabled ? onCopy : null,
                  ),
                  _BatchAction(
                    icon: Icons.delete_outline_rounded,
                    label: '删除',
                    color: AppColors.danger,
                    onTap: enabled ? onDelete : null,
                  ),
                  _BatchAction(
                    icon: Icons.more_horiz_rounded,
                    label: '更多',
                    onTap: enabled ? onMore : null,
                  ),
                ],
              ),
      ),
    );
  }
}

class _BatchAction extends StatelessWidget {
  const _BatchAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = AppColors.ink2,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final effective = onTap == null ? AppColors.ink3 : color;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20, color: effective),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: effective,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.query,
    required this.toast,
    required this.sortLabel,
    required this.sortAscending,
    required this.sortField,
    required this.viewMode,
    required this.onSearchChanged,
    required this.onClearSearch,
    required this.onSortSelected,
    required this.onToggleSortDirection,
    required this.onViewModeChanged,
    required this.onCreateFolder,
    required this.path,
    required this.summary,
    required this.visibleCount,
    required this.hasSearch,
    required this.truncated,
    required this.statusText,
    required this.formatSize,
    required this.formatMtime,
    required this.onOpenPath,
    this.onEnterSelection,
  });

  /// 进入多选模式；null 表示当前目录不可选（空目录 / 加载中）。
  final VoidCallback? onEnterSelection;

  final TextEditingController controller;
  final String query;

  /// 顶部提示条：与搜索框共用同一格（浮在上面，不挤动布局）。
  final Widget toast;
  final String sortLabel;
  final bool sortAscending;
  final _SortField sortField;
  final _ViewMode viewMode;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onClearSearch;
  final ValueChanged<_SortField> onSortSelected;
  final VoidCallback onToggleSortDirection;
  final ValueChanged<_ViewMode> onViewModeChanged;
  final VoidCallback onCreateFolder;
  final String path;
  final _DirectorySummary summary;
  final int visibleCount;
  final bool hasSearch;

  /// 目录条目取满一页（200 条）时置位：提示可能还有未展示的条目。
  final bool truncated;
  final String? statusText;
  final String Function(int) formatSize;
  final String Function(int) formatMtime;
  final ValueChanged<String> onOpenPath;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF4F7FA),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final search = TextField(
            controller: controller,
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: '搜索当前目录',
              filled: true,
              fillColor: Colors.white,
              prefixIconConstraints: const BoxConstraints(
                minWidth: 28,
                minHeight: 28,
              ),
              prefixIcon: const Icon(Icons.search_rounded, size: 15),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空搜索',
                      onPressed: onClearSearch,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 24,
                        minHeight: 24,
                      ),
                      iconSize: 14,
                      icon: const Icon(Icons.close_rounded),
                    ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 24,
                minHeight: 24,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFD7E0EA)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFD7E0EA)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Color(0xFFB9C6D7)),
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 7),
            ),
          );
          final sortMenu = PopupMenuButton<_SortField>(
            tooltip: '排序',
            padding: EdgeInsets.zero,
            onSelected: onSortSelected,
            itemBuilder: (context) => const [
              PopupMenuItem(value: _SortField.name, child: Text('按名称')),
              PopupMenuItem(value: _SortField.modified, child: Text('按时间')),
              PopupMenuItem(value: _SortField.size, child: Text('按大小')),
              PopupMenuItem(value: _SortField.type, child: Text('按类型')),
            ],
            child: _ToolbarButton(
              icon: Icons.sort_rounded,
              label: sortLabel,
              trailingIcon: Icons.keyboard_arrow_down_rounded,
              compact: compact,
            ),
          );
          final directionButton = _ToolbarButton(
            icon: sortAscending
                ? Icons.arrow_upward_rounded
                : Icons.arrow_downward_rounded,
            label: sortAscending ? '升序' : '降序',
            compact: true,
            onTap: onToggleSortDirection,
            tooltip: sortAscending ? '切换为降序' : '切换为升序',
          );
          final viewButton = _ToolbarButton(
            icon: viewMode == _ViewMode.grid
                ? Icons.grid_view_rounded
                : Icons.view_list_rounded,
            label: viewMode == _ViewMode.grid ? '网格' : '列表',
            compact: compact,
            selected: true,
            onTap: () {
              onViewModeChanged(
                viewMode == _ViewMode.grid ? _ViewMode.list : _ViewMode.grid,
              );
            },
            tooltip: viewMode == _ViewMode.grid ? '切换到列表视图' : '切换到网格视图',
          );
          final createButton = _ToolbarButton(
            icon: Icons.add_rounded,
            label: '新建',
            compact: compact,
            onTap: onCreateFolder,
            tooltip: '新建文件夹',
          );
          // 多选入口：与「升序 / 列表 / 新建」保持一致的带边框按钮
          final selectButton = _ToolbarButton(
            icon: Icons.check_circle_outline_rounded,
            label: '选择',
            compact: compact,
            onTap: onEnterSelection,
            tooltip: '进入多选模式',
          );
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              sortMenu,
              const SizedBox(width: 4),
              directionButton,
              const SizedBox(width: 4),
              viewButton,
              const SizedBox(width: 4),
              createButton,
              const SizedBox(width: 4),
              selectButton,
            ],
          );
          return Container(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0A000000),
                  blurRadius: 12,
                  offset: Offset(0, 5),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Stack(
                  // 提示条铺满搜索框这一格：只做覆盖，不改布局尺寸。
                  fit: StackFit.passthrough,
                  children: [
                    search,
                    Positioned.fill(child: toast),
                  ],
                ),
                const SizedBox(height: 8),
                _HeaderMeta(
                  path: path,
                  summary: summary,
                  visibleCount: visibleCount,
                  hasSearch: hasSearch,
                  truncated: truncated,
                  statusText: statusText,
                  formatSize: formatSize,
                  formatMtime: formatMtime,
                  onOpenPath: onOpenPath,
                  actions: actions,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

enum _ToastTone { info, error }

/// 顶部提示条（B 方案：主色浅底）。
///
/// 与搜索框共用同一格，用 Stack 铺在上面覆盖搜索框；显示/隐藏只做位移与
/// 透明度动画，不改变布局尺寸，因此列表不会跳动。
class _TopToast extends StatelessWidget {
  const _TopToast({
    required this.text,
    required this.tone,
    required this.visible,
    required this.onDismiss,
    this.actionLabel,
    this.onAction,
  });

  final String text;
  final _ToastTone tone;
  final bool visible;
  final VoidCallback onDismiss;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final info = tone == _ToastTone.info;
    final background = info
        ? const Color(0xFFEAF0FF)
        : const Color(0xFFFDECEC);
    final borderColor = info
        ? const Color(0xFFD3DFFF)
        : const Color(0xFFF7C9C9);
    final textColor = info
        ? const Color(0xFF1B3A78)
        : const Color(0xFF7A1F1F);
    final accent = info ? const Color(0xFF3C5BE0) : AppColors.danger;
    final iconColor = info ? AppColors.primary : AppColors.danger;
    final shadowColor = info
        ? const Color(0x1A4C6FFF)
        : const Color(0x1AE5484D);

    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 190),
        curve: Curves.easeOutCubic,
        offset: visible ? Offset.zero : const Offset(0, -0.5),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 170),
          opacity: visible ? 1 : 0,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: borderColor),
                boxShadow: [
                  BoxShadow(
                    color: shadowColor,
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      info
                          ? Icons.check_rounded
                          : Icons.priority_high_rounded,
                      size: 13,
                      color: iconColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.6,
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                  ),
                  if (actionLabel != null) ...[
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () {
                        onDismiss();
                        onAction?.call();
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 2,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              actionLabel!,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: accent,
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 14,
                              color: accent,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    this.label,
    this.trailingIcon,
    this.selected = false,
    this.compact = false,
    this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final String? label;
  final IconData? trailingIcon;
  final bool selected;
  final bool compact;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF276EF1) : const Color(0xFF425466);
    final content = Container(
      height: 32,
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFF2F6FF) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? const Color(0xFFC7D8FF) : const Color(0xFFD7E0EA),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          if (label != null) ...[
            const SizedBox(width: 4),
            Text(
              label!,
              style: TextStyle(
                color: color,
                fontSize: 11,
                height: 1,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
          if (trailingIcon != null) ...[
            const SizedBox(width: 2),
            Icon(trailingIcon, size: 14, color: color),
          ],
        ],
      ),
    );

    Widget button = content;
    if (onTap != null) {
      button = Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: content,
        ),
      );
    }
    if (tooltip != null) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

class _HeaderMeta extends StatelessWidget {
  const _HeaderMeta({
    required this.path,
    required this.summary,
    required this.visibleCount,
    required this.hasSearch,
    required this.truncated,
    required this.statusText,
    required this.formatSize,
    required this.formatMtime,
    required this.onOpenPath,
    required this.actions,
  });

  final String path;
  final _DirectorySummary summary;
  final int visibleCount;
  final bool hasSearch;
  final bool truncated;
  final String? statusText;
  final String Function(int) formatSize;
  final String Function(int) formatMtime;
  final ValueChanged<String> onOpenPath;
  final Widget actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentLabel = path == '/'
        ? '全部文件'
        : path.split('/').where((item) => item.isNotEmpty).last;
    final totalCount = summary.folderCount + summary.fileCount;
    final baseDetail =
        statusText ??
        (hasSearch
            ? '匹配 $visibleCount 项 · 共 $totalCount 项'
            : summary.latestMtime > 0
            ? '${summary.folderCount} 个文件夹 · ${summary.fileCount} 个文件 · ${formatSize(summary.totalSize)} · 更新 ${formatMtime(summary.latestMtime)}'
            : '${summary.folderCount} 个文件夹 · ${summary.fileCount} 个文件 · ${formatSize(summary.totalSize)}');
    // 接口只取第一页：取满 200 条时明确告知，避免用户以为目录里就这么多。
    final detailText = statusText == null && truncated && !hasSearch
        ? '$baseDetail · 仅显示前 200 项'
        : baseDetail;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: const Color(0xFF276EF1).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.folder_rounded,
                color: Color(0xFF276EF1),
                size: 15,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currentLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    detailText,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF697586),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        if (path != '/') ...[
          const SizedBox(height: 2),
          _BreadcrumbBar(path: path, onOpenPath: onOpenPath),
        ],
        const SizedBox(height: 8),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: actions),
      ],
    );
  }
}

class _BreadcrumbBar extends StatelessWidget {
  const _BreadcrumbBar({required this.path, required this.onOpenPath});

  final String path;
  final ValueChanged<String> onOpenPath;

  @override
  Widget build(BuildContext context) {
    final segments = path == '/'
        ? const <String>[]
        : path.split('/').where((item) => item.isNotEmpty).toList();
    final chips = <Widget>[
      _BreadcrumbChip(
        label: '全部文件',
        selected: path == '/',
        onTap: () => onOpenPath('/'),
      ),
    ];
    var current = '';
    for (final segment in segments) {
      current = FoxelApi.joinPath(current.isEmpty ? '/' : current, segment);
      final segmentPath = current;
      chips.add(const Icon(Icons.chevron_right_rounded, size: 18));
      chips.add(
        _BreadcrumbChip(
          label: segment,
          selected: segmentPath == path,
          onTap: () => onOpenPath(segmentPath),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(top: 0),
      child: Row(children: chips),
    );
  }
}

class _BreadcrumbChip extends StatelessWidget {
  const _BreadcrumbChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF276EF1) : const Color(0xFF5D6B7A);
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(5),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          child: Text(
            label,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _FileGrid extends StatelessWidget {
  const _FileGrid({
    required this.api,
    required this.entries,
    required this.currentPath,
    required this.formatSize,
    required this.formatMtime,
    required this.fileKind,
    required this.onOpen,
    required this.onMore,
    required this.selecting,
    required this.selectedPaths,
    required this.onToggle,
    required this.onLongPress,
  });

  final FoxelApi api;
  final List<FileEntry> entries;
  final String currentPath;
  final String Function(int) formatSize;
  final String Function(int) formatMtime;
  final String Function(FileEntry) fileKind;
  final ValueChanged<FileEntry> onOpen;
  final ValueChanged<FileEntry> onMore;
  final bool selecting;
  final Set<String> selectedPaths;
  final ValueChanged<FileEntry> onToggle;
  final ValueChanged<FileEntry> onLongPress;

  @override
  Widget build(BuildContext context) {
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final crossAxisCount = width >= 1100
            ? 6
            : width >= 900
            ? 5
            : width >= 680
            ? 4
            : width >= 460
            ? 3
            : 2;
        final compact = width < 460;
        return SliverPadding(
          padding: EdgeInsets.fromLTRB(
            compact ? 12 : 16,
            2,
            compact ? 12 : 16,
            12,
          ),
          sliver: SliverGrid(
            delegate: SliverChildBuilderDelegate((context, index) {
              final entry = entries[index];
              final fullPath = FoxelApi.joinPath(currentPath, entry.name);
              return _FileGridTile(
                api: api,
                entry: entry,
                fullPath: fullPath,
                formatSize: formatSize,
                formatMtime: formatMtime,
                fileKind: fileKind,
                selecting: selecting,
                selected: selectedPaths.contains(fullPath),
                onOpen: () => onOpen(entry),
                onMore: () => onMore(entry),
                onToggle: () => onToggle(entry),
                onLongPress: () => onLongPress(entry),
              );
            }, childCount: entries.length),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              crossAxisSpacing: compact ? 8 : 10,
              mainAxisSpacing: compact ? 8 : 10,
              childAspectRatio: compact ? 0.88 : 0.9,
            ),
          ),
        );
      },
    );
  }
}

class _FileGridTile extends StatelessWidget {
  const _FileGridTile({
    required this.api,
    required this.entry,
    required this.fullPath,
    required this.formatSize,
    required this.formatMtime,
    required this.fileKind,
    required this.onOpen,
    required this.onMore,
    required this.selecting,
    required this.selected,
    required this.onToggle,
    required this.onLongPress,
  });

  final FoxelApi api;
  final FileEntry entry;
  final String fullPath;
  final String Function(int) formatSize;
  final String Function(int) formatMtime;
  final String Function(FileEntry) fileKind;
  final VoidCallback onOpen;
  final VoidCallback onMore;
  final bool selecting;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? AppColors.primarySoft : Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: selecting ? onToggle : onOpen,
        onLongPress: selecting ? onToggle : onLongPress,
        child: Stack(
          children: [
            Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _EntryVisual(api: api, entry: entry, fullPath: fullPath),
              ),
              const SizedBox(height: 8),
              Text(
                entry.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.isDir
                          ? fileKind(entry)
                          : '${formatSize(entry.size)} · ${formatMtime(entry.mtime)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF697586),
                      ),
                    ),
                  ),
                  if (!selecting)
                    SizedBox(
                      width: 28,
                      height: 28,
                      child: IconButton(
                        tooltip: '更多',
                        padding: EdgeInsets.zero,
                        onPressed: onMore,
                        icon: const Icon(Icons.more_horiz_rounded),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
            // 勾选标记放在最上层，避免被缩略图 / 图标遮住一半
            if (selecting)
              Positioned(
                left: 4,
                top: 4,
                child: _SelectionMark(selected: selected),
              ),
          ],
        ),
      ),
    );
  }
}

/// 多选勾选标记（圆形）。
class _SelectionMark extends StatelessWidget {
  const _SelectionMark({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    const size = 22.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppColors.primary : Colors.white,
        border: Border.all(
          color: selected ? AppColors.primary : const Color(0xFFC6CFDD),
          width: 2,
        ),
        // 落在缩略图 / 图标上时也能清晰分辨
        boxShadow: const [
          BoxShadow(
            color: Color(0x1F16202C),
            blurRadius: 4,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: selected
          ? const Icon(Icons.check_rounded, size: 13.6, color: Colors.white)
          : null,
    );
  }
}

class _FileList extends StatelessWidget {
  const _FileList({
    required this.api,
    required this.entries,
    required this.currentPath,
    required this.formatSize,
    required this.formatMtime,
    required this.fileKind,
    required this.onOpen,
    required this.onMore,
    required this.selecting,
    required this.selectedPaths,
    required this.onToggle,
    required this.onLongPress,
  });

  final bool selecting;
  final Set<String> selectedPaths;
  final ValueChanged<FileEntry> onToggle;
  final ValueChanged<FileEntry> onLongPress;

  final FoxelApi api;
  final List<FileEntry> entries;
  final String currentPath;
  final String Function(int) formatSize;
  final String Function(int) formatMtime;
  final String Function(FileEntry) fileKind;
  final ValueChanged<FileEntry> onOpen;
  final ValueChanged<FileEntry> onMore;

  @override
  Widget build(BuildContext context) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      sliver: SliverList.separated(
        itemCount: entries.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final entry = entries[index];
          final fullPath = FoxelApi.joinPath(currentPath, entry.name);
          return _FileListTile(
            api: api,
            entry: entry,
            fullPath: fullPath,
            formatSize: formatSize,
            formatMtime: formatMtime,
            fileKind: fileKind,
            selecting: selecting,
            selected: selectedPaths.contains(fullPath),
            onOpen: () => onOpen(entry),
            onMore: () => onMore(entry),
            onToggle: () => onToggle(entry),
            onLongPress: () => onLongPress(entry),
          );
        },
      ),
    );
  }
}

class _FileListTile extends StatelessWidget {
  const _FileListTile({
    required this.api,
    required this.entry,
    required this.fullPath,
    required this.formatSize,
    required this.formatMtime,
    required this.fileKind,
    required this.onOpen,
    required this.onMore,
    required this.selecting,
    required this.selected,
    required this.onToggle,
    required this.onLongPress,
  });

  final FoxelApi api;
  final FileEntry entry;
  final String fullPath;
  final String Function(int) formatSize;
  final String Function(int) formatMtime;
  final String Function(FileEntry) fileKind;
  final VoidCallback onOpen;
  final VoidCallback onMore;
  final bool selecting;
  final bool selected;
  final VoidCallback onToggle;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: selected ? AppColors.primarySoft : Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: selecting ? onToggle : onOpen,
        onLongPress: selecting ? onToggle : onLongPress,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
          child: Row(
            children: [
              if (selecting) ...[
                _SelectionMark(selected: selected),
                const SizedBox(width: 10),
              ],
              _EntryVisual(
                api: api,
                entry: entry,
                fullPath: fullPath,
                size: 48,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      entry.isDir
                          ? fileKind(entry)
                          : '${fileKind(entry)} · ${formatSize(entry.size)} · ${formatMtime(entry.mtime)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF697586),
                      ),
                    ),
                  ],
                ),
              ),
              if (!selecting)
                IconButton(
                  tooltip: '更多',
                  visualDensity: VisualDensity.compact,
                  onPressed: onMore,
                  icon: const Icon(Icons.more_horiz_rounded),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryVisual extends StatelessWidget {
  const _EntryVisual({
    required this.api,
    required this.entry,
    required this.fullPath,
    this.size,
  });

  final FoxelApi api;
  final FileEntry entry;
  final String fullPath;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final icon = _iconFor(entry);
    final color = _colorFor(entry);
    final hasThumb = entry.hasThumbnail == true || _canPreviewAsMedia(entry);
    final content = hasThumb && !entry.isDir
        ? Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                api.thumbnailUri(fullPath, width: 420, height: 420).toString(),
                headers: api.authHeaders(),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    _IconPreview(icon: icon, color: color),
              ),
              if (_isVideoName(entry.name))
                Align(
                  alignment: Alignment.center,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.48),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
            ],
          )
        : _IconPreview(icon: icon, color: color);

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size ?? double.infinity,
        height: size ?? double.infinity,
        child: content,
      ),
    );
  }

  static bool _canPreviewAsMedia(FileEntry entry) {
    final lower = entry.name.toLowerCase();
    return _isImageName(lower) || _isVideoName(lower);
  }

  static bool _isImageName(String name) {
    return name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.gif') ||
        name.endsWith('.webp') ||
        name.endsWith('.bmp');
  }

  static bool _isVideoName(String name) {
    final lower = name.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mkv') ||
        lower.endsWith('.avi');
  }

  static IconData _iconFor(FileEntry entry) {
    if (entry.isDir) {
      return Icons.folder_rounded;
    }
    final lower = entry.name.toLowerCase();
    if (_isImageName(lower)) {
      return Icons.image_rounded;
    }
    if (_isVideoName(lower)) {
      return Icons.movie_rounded;
    }
    if (lower.endsWith('.pdf')) {
      return Icons.picture_as_pdf_rounded;
    }
    if (lower.endsWith('.zip') ||
        lower.endsWith('.rar') ||
        lower.endsWith('.7z')) {
      return Icons.archive_rounded;
    }
    if (lower.endsWith('.doc') || lower.endsWith('.docx')) {
      return Icons.description_rounded;
    }
    if (lower.endsWith('.md') || lower.endsWith('.txt')) {
      return Icons.notes_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  static Color _colorFor(FileEntry entry) {
    if (entry.isDir) {
      return const Color(0xFF276EF1);
    }
    final lower = entry.name.toLowerCase();
    if (_isImageName(lower)) {
      return const Color(0xFF17A673);
    }
    if (_isVideoName(lower)) {
      return const Color(0xFF8A5CF6);
    }
    if (lower.endsWith('.pdf')) {
      return const Color(0xFFDC2626);
    }
    if (lower.endsWith('.zip') ||
        lower.endsWith('.rar') ||
        lower.endsWith('.7z')) {
      return const Color(0xFFD97706);
    }
    return const Color(0xFF425466);
  }
}

class _IconPreview extends StatelessWidget {
  const _IconPreview({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 30),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  /// 行尾附加内容（如「新增」胶囊）。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? const Color(0xFFDC2626) : null;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color)),
      trailing: trailing,
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}

/// 「新增」胶囊：只用于本次新增的入口，帮助老用户发现新功能。
class _NewPill extends StatelessWidget {
  const _NewPill();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: const Text(
        '新增',
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 42),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({
    required this.title,
    required this.message,
    required this.icon,
    required this.primaryLabel,
    required this.primaryIcon,
    required this.onPrimary,
    this.secondaryLabel,
    this.secondaryIcon,
    this.onSecondary,
  });

  final String title;
  final String message;
  final IconData icon;
  final String primaryLabel;
  final IconData primaryIcon;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final IconData? secondaryIcon;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 54, color: const Color(0xFF697586)),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF697586)),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: onPrimary,
                  icon: Icon(primaryIcon),
                  label: Text(primaryLabel),
                ),
                if (secondaryLabel != null &&
                    secondaryIcon != null &&
                    onSecondary != null)
                  OutlinedButton.icon(
                    onPressed: onSecondary,
                    icon: Icon(secondaryIcon),
                    label: Text(secondaryLabel!),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶部「当前账户」条：仅作标识，点击进入账户管理页（切换在账户管理页内完成）。
class _AccountBar extends StatelessWidget {
  const _AccountBar({required this.account, required this.onTap});

  final Account account;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(account.colorValue);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        color: color.withValues(alpha: 0.08),
        child: Row(
          children: [
            AccountAvatar(account: account, size: 26, radius: 9, fontSize: 13),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                account.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
            const Spacer(),
            if (account.isStale)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: AppColors.warn.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Text(
                  '需重新验证',
                  style: AppText.pill.copyWith(color: AppColors.warn),
                ),
              )
            else
              Text(
                '当前账户',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color.withValues(alpha: 0.75),
                ),
              ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 18, color: color),
          ],
        ),
      ),
    );
  }
}
