import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'package:foxel/core/api/foxel_api.dart';
import 'package:foxel/core/models/adapter_usage.dart';
import 'package:foxel/core/models/file_entry.dart';
import 'package:foxel/features/drive/controllers/transfer_task_controller.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.api,
    required this.username,
    required this.avatarUrl,
    required this.isPro,
    required this.onOpenFiles,
    required this.taskController,
    required this.onOpenTasks,
    required this.onOpenSettings,
  });

  final FoxelApi api;
  final String username;
  final String avatarUrl;
  final bool isPro;
  final VoidCallback onOpenFiles;
  final TransferTaskController taskController;
  final VoidCallback onOpenTasks;
  final VoidCallback onOpenSettings;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late Future<_HomeData> _homeFuture;

  @override
  void initState() {
    super.initState();
    _homeFuture = _loadHomeData();
  }

  void _refresh() {
    setState(() {
      _homeFuture = _loadHomeData();
    });
  }

  Future<_HomeData> _loadHomeData() async {
    final listingFuture = widget.api.listDirectory('/');
    final usagesFuture = widget.api.adapterUsages();
    final listing = await listingFuture;
    final usages = await usagesFuture;
    return _HomeData(listing: listing, storage: _storageFor(usages));
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<String?> _askText({required String title, required String label}) {
    final controller = TextEditingController();
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

  Future<void> _createFolder() async {
    final name = await _askText(title: '新建文件夹', label: '文件夹名称');
    if (name == null || name.trim().isEmpty) {
      return;
    }
    await _runAction(() => widget.api.mkdir(FoxelApi.joinPath('/', name)));
  }

  Future<void> _uploadFile() async {
    final result = await FilePicker.platform.pickFiles(withData: false);
    final file = result?.files.single;
    final localPath = file?.path;
    if (file == null || localPath == null) {
      return;
    }
    widget.taskController.startUpload(
      api: widget.api,
      name: file.name,
      remotePath: FoxelApi.joinPath('/', file.name),
      localPath: localPath,
      onSuccess: () {
        if (mounted) {
          _refresh();
        }
      },
    );
    widget.onOpenTasks();
  }

  _StorageSummary _storageFor(List<AdapterUsage> usages) {
    var usedBytes = 0;
    var totalBytes = 0;
    var freeBytes = 0;
    var supportedCount = 0;
    for (final usage in usages) {
      if (!usage.supported) {
        continue;
      }
      usedBytes += usage.usedBytes;
      totalBytes += usage.totalBytes;
      freeBytes += usage.freeBytes;
      supportedCount += 1;
    }
    return _StorageSummary(
      usedBytes: usedBytes,
      totalBytes: totalBytes,
      freeBytes: freeBytes,
      supportedCount: supportedCount,
    );
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
    if (size < 1024 * 1024 * 1024 * 1024) {
      return '${(size / 1024 / 1024 / 1024).toStringAsFixed(1)} GB';
    }
    return '${(size / 1024 / 1024 / 1024 / 1024).toStringAsFixed(1)} TB';
  }

  String _formatMtime(int mtime) {
    if (mtime <= 0) {
      return '暂无更新';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FA),
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: FutureBuilder<_HomeData>(
            future: _homeFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const _HomeLoadingView();
              }
              if (snapshot.hasError) {
                return _HomeErrorView(
                  message: snapshot.error.toString(),
                  onRetry: _refresh,
                );
              }

              final data = snapshot.data;
              final entries = data?.listing.entries ?? const <FileEntry>[];
              final storage = data?.storage ?? _StorageSummary.empty;
              final recent = [...entries]
                ..sort((a, b) => b.mtime.compareTo(a.mtime));
              final topRecent = recent.take(6).toList();

              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 118),
                children: [
                  _HomeHeader(
                    username: widget.username,
                    avatarUrl: widget.avatarUrl,
                    isPro: widget.isPro,
                    onRefresh: _refresh,
                    onOpenSettings: widget.onOpenSettings,
                  ),
                  const SizedBox(height: 24),
                  _HeroPanel(
                    totalText:
                        '可用 ${_formatSize(storage.freeBytes)} / 总计 ${_formatSize(storage.totalBytes)}',
                    usedText: _formatSize(storage.usedBytes),
                    percentText: storage.percentText,
                    onUpload: _uploadFile,
                    onCreateFolder: _createFolder,
                    onOpenFiles: widget.onOpenFiles,
                  ),
                  const SizedBox(height: 24),
                  _SectionTitle(
                    title: '快速入口',
                    action: '全部文件',
                    onTap: widget.onOpenFiles,
                  ),
                  const SizedBox(height: 12),
                  _CategoryScroller(
                    entries: entries,
                    onOpenFiles: widget.onOpenFiles,
                  ),
                  const SizedBox(height: 24),
                  _SectionTitle(
                    title: '最近项目',
                    action: '查看文件',
                    onTap: widget.onOpenFiles,
                  ),
                  const SizedBox(height: 12),
                  if (topRecent.isEmpty)
                    _EmptyRecent(
                      onCreateFolder: _createFolder,
                      onUpload: _uploadFile,
                    )
                  else
                    _RecentList(
                      api: widget.api,
                      entries: topRecent,
                      formatSize: _formatSize,
                      formatMtime: _formatMtime,
                      onOpenFiles: widget.onOpenFiles,
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _HomeData {
  const _HomeData({required this.listing, required this.storage});

  final DirectoryListing listing;
  final _StorageSummary storage;
}

class _StorageSummary {
  const _StorageSummary({
    required this.usedBytes,
    required this.totalBytes,
    required this.freeBytes,
    required this.supportedCount,
  });

  static const empty = _StorageSummary(
    usedBytes: 0,
    totalBytes: 0,
    freeBytes: 0,
    supportedCount: 0,
  );

  final int usedBytes;
  final int totalBytes;
  final int freeBytes;
  final int supportedCount;

  String get percentText {
    if (totalBytes <= 0) {
      return '0%';
    }
    final percent = usedBytes / totalBytes * 100;
    if (percent < 10) {
      return '${percent.toStringAsFixed(1)}%';
    }
    return '${percent.toStringAsFixed(0)}%';
  }
}

class _HomeHeader extends StatelessWidget {
  const _HomeHeader({
    required this.username,
    required this.avatarUrl,
    required this.isPro,
    required this.onRefresh,
    required this.onOpenSettings,
  });

  final String username;
  final String avatarUrl;
  final bool isPro;
  final VoidCallback onRefresh;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      'Foxel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                  if (isPro) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFE7B8),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'Pro',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: const Color(0xFF7A4E00),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '早上好，$username',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF5D6B7A),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '刷新',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
        const SizedBox(width: 4),
        InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: onOpenSettings,
          child: Container(
            width: 56,
            height: 56,
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: Color(0xFFEAF1FF),
              shape: BoxShape.circle,
            ),
            child: _AvatarImage(
              avatarUrl: avatarUrl,
              username: username,
              size: 44,
            ),
          ),
        ),
      ],
    );
  }
}

class _AvatarImage extends StatelessWidget {
  const _AvatarImage({
    required this.avatarUrl,
    required this.username,
    required this.size,
  });

  final String avatarUrl;
  final String username;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = username.isEmpty
        ? 'F'
        : username.characters.first.toUpperCase();
    final fallback = Center(
      child: Text(initial, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: avatarUrl.isEmpty
            ? fallback
            : Image.network(
                avatarUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => fallback,
              ),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  const _HeroPanel({
    required this.totalText,
    required this.usedText,
    required this.percentText,
    required this.onUpload,
    required this.onCreateFolder,
    required this.onOpenFiles,
  });

  final String totalText;
  final String usedText;
  final String percentText;
  final VoidCallback onUpload;
  final VoidCallback onCreateFolder;
  final VoidCallback onOpenFiles;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF3478FF), Color(0xFF6EA0FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF3478FF).withValues(alpha: 0.26),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            right: -24,
            top: -8,
            child: Icon(
              Icons.cloud_upload_rounded,
              size: 156,
              color: Colors.white.withValues(alpha: 0.11),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '我的存储空间',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.info_outline_rounded,
                              color: Colors.white.withValues(alpha: 0.78),
                              size: 18,
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        Text(
                          usedText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.displaySmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          totalText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.78),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  _UsageBadge(value: percentText),
                ],
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _HeroAction(
                        icon: Icons.upload_rounded,
                        label: '上传',
                        onTap: onUpload,
                      ),
                    ),
                    _ActionDivider(),
                    Expanded(
                      child: _HeroAction(
                        icon: Icons.create_new_folder_rounded,
                        label: '新建',
                        onTap: onCreateFolder,
                      ),
                    ),
                    _ActionDivider(),
                    Expanded(
                      child: _HeroAction(
                        icon: Icons.folder_open_rounded,
                        label: '打开',
                        onTap: onOpenFiles,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _UsageBadge extends StatelessWidget {
  const _UsageBadge({required this.value});

  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 82,
      height: 82,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white.withValues(alpha: 0.15),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.22),
          width: 8,
        ),
      ),
      alignment: Alignment.center,
      child: Text(
        value,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _HeroAction extends StatelessWidget {
  const _HeroAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF1D5DFF), Color(0xFF58A6FF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(icon, color: Colors.white, size: 20),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: const Color(0xFF1F2937),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 48,
      color: const Color(0xFFE1E7EF),
      margin: const EdgeInsets.symmetric(horizontal: 4),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.action,
    required this.onTap,
  });

  final String title;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        TextButton(onPressed: onTap, child: Text(action)),
      ],
    );
  }
}

class _CategoryScroller extends StatelessWidget {
  const _CategoryScroller({required this.entries, required this.onOpenFiles});

  final List<FileEntry> entries;
  final VoidCallback onOpenFiles;

  @override
  Widget build(BuildContext context) {
    final folders = entries.where((entry) => entry.isDir).length;
    final images = entries.where((entry) => _isImage(entry.name)).length;
    final videos = entries.where((entry) => _isVideo(entry.name)).length;
    final docs = entries.where((entry) => _isDocument(entry.name)).length;
    final items = [
      _CategoryItem(
        icon: Icons.folder_rounded,
        label: '文件夹',
        value: '$folders 项',
        color: const Color(0xFF276EF1),
        background: const Color(0xFFEAF1FF),
      ),
      _CategoryItem(
        icon: Icons.image_rounded,
        label: '图片',
        value: '$images 项',
        color: const Color(0xFF17A673),
        background: const Color(0xFFE8F8F1),
      ),
      _CategoryItem(
        icon: Icons.movie_rounded,
        label: '视频',
        value: '$videos 项',
        color: const Color(0xFF8A5CF6),
        background: const Color(0xFFF0EBFF),
      ),
      _CategoryItem(
        icon: Icons.description_rounded,
        label: '文档',
        value: '$docs 项',
        color: const Color(0xFFD97706),
        background: const Color(0xFFFFF0DF),
      ),
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _CategoryTile(item: item, onTap: onOpenFiles),
            ),
        ],
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({required this.item, required this.onTap});

  final _CategoryItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: item.background,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: SizedBox(
          width: 108,
          height: 118,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: item.color,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(item.icon, color: Colors.white, size: 23),
                ),
                const Spacer(),
                Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  item.value,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF697586),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryItem {
  const _CategoryItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.background,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final Color background;
}

class _RecentList extends StatelessWidget {
  const _RecentList({
    required this.api,
    required this.entries,
    required this.formatSize,
    required this.formatMtime,
    required this.onOpenFiles,
  });

  final FoxelApi api;
  final List<FileEntry> entries;
  final String Function(int) formatSize;
  final String Function(int) formatMtime;
  final VoidCallback onOpenFiles;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF102A43).withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          for (var index = 0; index < entries.length; index++) ...[
            _RecentTile(
              api: api,
              entry: entries[index],
              fullPath: FoxelApi.joinPath('/', entries[index].name),
              meta: entries[index].isDir
                  ? '文件夹'
                  : '${_fileKind(entries[index])} · ${formatMtime(entries[index].mtime)}',
              trailing: entries[index].isDir
                  ? ''
                  : formatSize(entries[index].size),
              onTap: onOpenFiles,
            ),
            if (index != entries.length - 1)
              const Divider(
                height: 1,
                indent: 66,
                endIndent: 14,
                color: Color(0xFFEAF0F6),
              ),
          ],
        ],
      ),
    );
  }
}

class _RecentTile extends StatelessWidget {
  const _RecentTile({
    required this.api,
    required this.entry,
    required this.fullPath,
    required this.meta,
    required this.trailing,
    required this.onTap,
  });

  final FoxelApi api;
  final FileEntry entry;
  final String fullPath;
  final String meta;
  final String trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Row(
            children: [
              _EntryThumb(api: api, entry: entry, fullPath: fullPath),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1F2937),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF697586),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                trailing,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: const Color(0xFF697586),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryThumb extends StatelessWidget {
  const _EntryThumb({
    required this.api,
    required this.entry,
    required this.fullPath,
  });

  final FoxelApi api;
  final FileEntry entry;
  final String fullPath;

  @override
  Widget build(BuildContext context) {
    final icon = _iconFor(entry);
    final color = _colorFor(entry);
    if (!entry.isDir && (entry.hasThumbnail == true || _isImage(entry.name))) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.network(
          api.thumbnailUri(fullPath, width: 120, height: 120).toString(),
          headers: api.authHeaders(),
          width: 42,
          height: 42,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _IconBox(icon: icon, color: color),
        ),
      );
    }
    return _IconBox(icon: icon, color: color);
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, color: color, size: 22),
    );
  }
}

class _EmptyRecent extends StatelessWidget {
  const _EmptyRecent({required this.onCreateFolder, required this.onUpload});

  final VoidCallback onCreateFolder;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE1E7EF)),
      ),
      child: Column(
        children: [
          const Icon(Icons.folder_open_rounded, size: 42),
          const SizedBox(height: 10),
          Text('根目录暂无项目', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onUpload,
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('上传文件'),
              ),
              OutlinedButton.icon(
                onPressed: onCreateFolder,
                icon: const Icon(Icons.create_new_folder_rounded),
                label: const Text('新建文件夹'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HomeLoadingView extends StatelessWidget {
  const _HomeLoadingView();

  @override
  Widget build(BuildContext context) {
    return const CustomScrollView(
      physics: AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ],
    );
  }
}

class _HomeErrorView extends StatelessWidget {
  const _HomeErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 120),
        const Icon(Icons.error_outline_rounded, size: 42),
        const SizedBox(height: 12),
        Text(message, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Center(
          child: FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('重试'),
          ),
        ),
      ],
    );
  }
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
  if (_isDocument(lower)) {
    return '文档';
  }
  if (lower.endsWith('.zip') ||
      lower.endsWith('.rar') ||
      lower.endsWith('.7z')) {
    return '压缩包';
  }
  return '文件';
}

IconData _iconFor(FileEntry entry) {
  if (entry.isDir) {
    return Icons.folder_rounded;
  }
  final lower = entry.name.toLowerCase();
  if (_isImage(lower)) {
    return Icons.image_rounded;
  }
  if (_isVideo(lower)) {
    return Icons.movie_rounded;
  }
  if (lower.endsWith('.pdf')) {
    return Icons.picture_as_pdf_rounded;
  }
  if (_isDocument(lower)) {
    return Icons.description_rounded;
  }
  if (lower.endsWith('.zip') ||
      lower.endsWith('.rar') ||
      lower.endsWith('.7z')) {
    return Icons.archive_rounded;
  }
  return Icons.insert_drive_file_rounded;
}

Color _colorFor(FileEntry entry) {
  if (entry.isDir) {
    return const Color(0xFF276EF1);
  }
  final lower = entry.name.toLowerCase();
  if (_isImage(lower)) {
    return const Color(0xFF17A673);
  }
  if (_isVideo(lower)) {
    return const Color(0xFF8A5CF6);
  }
  if (lower.endsWith('.pdf')) {
    return const Color(0xFFDC2626);
  }
  if (_isDocument(lower)) {
    return const Color(0xFFD97706);
  }
  return const Color(0xFF425466);
}

bool _isImage(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.bmp');
}

bool _isVideo(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.mp4') ||
      lower.endsWith('.m4v') ||
      lower.endsWith('.mov') ||
      lower.endsWith('.webm') ||
      lower.endsWith('.mkv') ||
      lower.endsWith('.avi');
}

bool _isDocument(String name) {
  final lower = name.toLowerCase();
  return lower.endsWith('.pdf') ||
      lower.endsWith('.doc') ||
      lower.endsWith('.docx') ||
      lower.endsWith('.md') ||
      lower.endsWith('.txt') ||
      lower.endsWith('.xls') ||
      lower.endsWith('.xlsx') ||
      lower.endsWith('.ppt') ||
      lower.endsWith('.pptx');
}
