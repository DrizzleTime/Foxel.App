import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'package:foxel/core/api/foxel_api.dart';
import 'package:foxel/core/models/file_entry.dart';
import 'package:foxel/features/drive/controllers/transfer_task_controller.dart';
import 'package:foxel/features/media/pages/image_viewer_page.dart';
import 'package:foxel/features/media/pages/video_player_page.dart';

enum _SortField { name, size, modified, type }

enum _ViewMode { grid, list }

class FileBrowserPage extends StatefulWidget {
  const FileBrowserPage({
    super.key,
    required this.api,
    required this.taskController,
    required this.onOpenTasks,
  });

  final FoxelApi api;
  final TransferTaskController taskController;
  final VoidCallback onOpenTasks;

  @override
  State<FileBrowserPage> createState() => _FileBrowserPageState();
}

class _FileBrowserPageState extends State<FileBrowserPage> {
  final _searchController = TextEditingController();

  String _path = '/';
  late Future<DirectoryListing> _listingFuture;
  String _searchQuery = '';
  _SortField _sortField = _SortField.name;
  bool _sortAscending = true;
  _ViewMode _viewMode = _ViewMode.grid;

  @override
  void initState() {
    super.initState();
    _listingFuture = widget.api.listDirectory(_path);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _listingFuture = widget.api.listDirectory(_path);
    });
  }

  void _openPath(String path) {
    setState(() {
      _path = FoxelApi.cleanPath(path);
      _searchController.clear();
      _searchQuery = '';
      _listingFuture = widget.api.listDirectory(_path);
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _runAction(Future<void> Function() action) async {
    try {
      await action();
      _refresh();
    } catch (error) {
      if (mounted) {
        _showMessage(error.toString());
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
    final name = await _askText(title: '新建文件夹', label: '文件夹名称');
    if (name == null || name.trim().isEmpty) {
      return;
    }
    await _runAction(() => widget.api.mkdir(FoxelApi.joinPath(_path, name)));
  }

  Future<void> _uploadFile() async {
    final result = await FilePicker.platform.pickFiles(withData: false);
    final file = result?.files.single;
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
  }

  Future<void> _renameEntry(FileEntry entry) async {
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
    if (entry.isDir) {
      _showMessage('暂不支持下载文件夹');
      return;
    }
    try {
      final dir =
          await getDownloadsDirectory() ??
          await getApplicationDocumentsDirectory();
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final output = File('${dir.path}/${entry.name}');
      widget.taskController.startDownload(
        api: widget.api,
        name: entry.name,
        remotePath: FoxelApi.joinPath(_path, entry.name),
        outputFile: output,
      );
      widget.onOpenTasks();
    } catch (error) {
      if (mounted) {
        _showMessage(error.toString());
      }
    }
  }

  void _openEntry(FileEntry entry) {
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
            path: fullPath,
            name: entry.name,
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
      final result = switch (_sortField) {
        _SortField.name => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        _SortField.size => a.size.compareTo(b.size),
        _SortField.modified => a.mtime.compareTo(b.mtime),
        _SortField.type => _fileKind(a).compareTo(_fileKind(b)),
      };
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
      canPop: _path == '/',
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _path != '/') {
          _openPath(FoxelApi.parentPath(_path));
        }
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F7FA),
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _Toolbar(
                controller: _searchController,
                query: _searchQuery,
                sortLabel: _sortLabel,
                sortAscending: _sortAscending,
                sortField: _sortField,
                viewMode: _viewMode,
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
              ),
              Expanded(
                child: FutureBuilder<DirectoryListing>(
                  future: _listingFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const _LoadingView();
                    }
                    if (snapshot.hasError) {
                      return _ErrorView(
                        message: snapshot.error.toString(),
                        onRetry: _refresh,
                      );
                    }

                    final entries =
                        snapshot.data?.entries ?? const <FileEntry>[];
                    final summary = _summaryFor(entries);
                    final visibleEntries = _visibleEntries(entries);
                    final hasSearch = _searchQuery.trim().isNotEmpty;

                    return RefreshIndicator(
                      onRefresh: () async => _refresh(),
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(
                            child: _DirectoryStatusBar(
                              path: _path,
                              summary: summary,
                              visibleCount: visibleEntries.length,
                              hasSearch: hasSearch,
                              formatSize: _formatSize,
                              formatMtime: _formatMtime,
                              onOpenPath: _openPath,
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
                                secondaryIcon: Icons.create_new_folder_rounded,
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
                              onOpen: _openEntry,
                              onMore: _showEntryActions,
                            )
                          else
                            _FileList(
                              api: widget.api,
                              entries: visibleEntries,
                              currentPath: _path,
                              formatSize: _formatSize,
                              formatMtime: _formatMtime,
                              fileKind: _fileKind,
                              onOpen: _openEntry,
                              onMore: _showEntryActions,
                            ),
                          const SliverToBoxAdapter(
                            child: SizedBox(height: 120),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: Builder(
          builder: (context) {
            final compact = MediaQuery.sizeOf(context).width < 560;
            final bottomInset = MediaQuery.of(context).viewPadding.bottom + 96;
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

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.query,
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
  });

  final TextEditingController controller;
  final String query;
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

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 720;
          final actionGap = compact ? 4.0 : 6.0;
          final search = TextField(
            controller: controller,
            onChanged: onSearchChanged,
            decoration: InputDecoration(
              hintText: '搜索当前目录',
              prefixIconConstraints: const BoxConstraints(
                minWidth: 36,
                minHeight: 36,
              ),
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: '清空搜索',
                      onPressed: onClearSearch,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      iconSize: 18,
                      icon: const Icon(Icons.close_rounded),
                    ),
              suffixIconConstraints: const BoxConstraints(
                minWidth: 32,
                minHeight: 32,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          );
          final sortMenu = PopupMenuButton<_SortField>(
            tooltip: '排序',
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
              selected: true,
              compact: compact,
            ),
          );
          final directionButton = IconButton.outlined(
            tooltip: sortAscending ? '升序' : '降序',
            onPressed: onToggleSortDirection,
            icon: Icon(
              sortAscending
                  ? Icons.arrow_upward_rounded
                  : Icons.arrow_downward_rounded,
            ),
          );
          final viewSwitch = SegmentedButton<_ViewMode>(
            segments: [
              ButtonSegment(
                value: _ViewMode.grid,
                icon: const Icon(Icons.grid_view_rounded),
                label: compact ? const SizedBox.shrink() : const Text('网格'),
              ),
              ButtonSegment(
                value: _ViewMode.list,
                icon: const Icon(Icons.view_list_rounded),
                label: compact ? const SizedBox.shrink() : const Text('列表'),
              ),
            ],
            selected: {viewMode},
            onSelectionChanged: (value) => onViewModeChanged(value.first),
            showSelectedIcon: false,
          );
          final createButton = compact
              ? IconButton.outlined(
                  tooltip: '新建文件夹',
                  onPressed: onCreateFolder,
                  icon: const Icon(Icons.create_new_folder_rounded),
                )
              : OutlinedButton.icon(
                  onPressed: onCreateFolder,
                  icon: const Icon(Icons.create_new_folder_rounded),
                  label: const Text('新建'),
                );
          final compactActions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              sortMenu,
              SizedBox(width: actionGap),
              directionButton,
              SizedBox(width: actionGap),
              viewSwitch,
              SizedBox(width: actionGap),
              createButton,
            ],
          );
          final desktopActions = Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [sortMenu, directionButton, viewSwitch, createButton],
          );

          if (compact) {
            return Row(
              children: [
                Expanded(child: search),
                const SizedBox(width: 8),
                Flexible(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: compactActions,
                  ),
                ),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 10),
              desktopActions,
            ],
          );
        },
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.icon,
    required this.label,
    this.selected = false,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF276EF1) : const Color(0xFF425466);
    return Container(
      height: 36,
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10),
      decoration: BoxDecoration(
        color: selected ? const Color(0xFFEAF1FF) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD7E0EA)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          if (!compact) ...[
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color)),
          ],
        ],
      ),
    );
  }
}

class _DirectoryStatusBar extends StatelessWidget {
  const _DirectoryStatusBar({
    required this.path,
    required this.summary,
    required this.visibleCount,
    required this.hasSearch,
    required this.formatSize,
    required this.formatMtime,
    required this.onOpenPath,
  });

  final String path;
  final _DirectorySummary summary;
  final int visibleCount;
  final bool hasSearch;
  final String Function(int) formatSize;
  final String Function(int) formatMtime;
  final ValueChanged<String> onOpenPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentLabel = path == '/'
        ? '全部文件'
        : path.split('/').where((item) => item.isNotEmpty).last;
    final totalCount = summary.folderCount + summary.fileCount;
    final detailText = hasSearch
        ? '匹配 $visibleCount 项 · 共 $totalCount 项'
        : summary.latestMtime > 0
        ? '${summary.folderCount} 个文件夹 · ${summary.fileCount} 个文件 · ${formatSize(summary.totalSize)} · 更新 ${formatMtime(summary.latestMtime)}'
        : '${summary.folderCount} 个文件夹 · ${summary.fileCount} 个文件 · ${formatSize(summary.totalSize)}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: const Color(0xFF276EF1).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.folder_rounded,
                  color: Color(0xFF276EF1),
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
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
                    const SizedBox(height: 2),
                    Text(
                      detailText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF697586),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (path != '/') ...[
            const SizedBox(height: 6),
            _BreadcrumbBar(path: path, onOpenPath: onOpenPath),
          ],
        ],
      ),
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
      chips.add(const Icon(Icons.chevron_right_rounded, size: 18));
      chips.add(
        _BreadcrumbChip(
          label: segment,
          selected: current == path,
          onTap: () => onOpenPath(current),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.only(top: 4),
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
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: ActionChip(
        onPressed: onTap,
        avatar: selected
            ? const Icon(Icons.folder_open_rounded, size: 18)
            : null,
        label: Text(label, overflow: TextOverflow.ellipsis),
        backgroundColor: selected ? const Color(0xFFEAF1FF) : Colors.white,
        side: const BorderSide(color: Color(0xFFD7E0EA)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
  });

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
              return _FileGridTile(
                api: api,
                entry: entry,
                fullPath: FoxelApi.joinPath(currentPath, entry.name),
                formatSize: formatSize,
                formatMtime: formatMtime,
                fileKind: fileKind,
                onOpen: () => onOpen(entry),
                onMore: () => onMore(entry),
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
  });

  final FoxelApi api;
  final FileEntry entry;
  final String fullPath;
  final String Function(int) formatSize;
  final String Function(int) formatMtime;
  final String Function(FileEntry) fileKind;
  final VoidCallback onOpen;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onOpen,
        onLongPress: onMore,
        child: Padding(
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
      ),
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
  });

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
          return _FileListTile(
            api: api,
            entry: entry,
            fullPath: FoxelApi.joinPath(currentPath, entry.name),
            formatSize: formatSize,
            formatMtime: formatMtime,
            fileKind: fileKind,
            onOpen: () => onOpen(entry),
            onMore: () => onMore(entry),
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
  });

  final FoxelApi api;
  final FileEntry entry;
  final String fullPath;
  final String Function(int) formatSize;
  final String Function(int) formatMtime;
  final String Function(FileEntry) fileKind;
  final VoidCallback onOpen;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onOpen,
        onLongPress: onMore,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
          child: Row(
            children: [
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
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final color = destructive ? const Color(0xFFDC2626) : null;
    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(label, style: TextStyle(color: color)),
      onTap: onTap,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
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
