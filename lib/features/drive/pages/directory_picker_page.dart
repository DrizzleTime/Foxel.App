import 'package:flutter/material.dart';

import 'package:foxel/core/api/foxel_api.dart';
import 'package:foxel/core/models/file_entry.dart';
import 'package:foxel/core/theme/design_tokens.dart';
import 'package:foxel/core/widgets/content_frame.dart';

/// 目录选择页：为批量「移动 / 复制」挑选目标目录。
///
/// 返回选中的目录路径（String），取消返回 null。
/// [blockedPaths] 内的目录及其下级不可选（例如移动自身或自身的子目录）。
/// [exactBlockedPaths] 只禁掉该目录本身，其子目录仍可选（例如来源目录）。
class DirectoryPickerPage extends StatefulWidget {
  const DirectoryPickerPage({
    super.key,
    required this.api,
    required this.title,
    this.initialPath = '/',
    this.blockedPaths = const <String>{},
    this.exactBlockedPaths = const <String>{},
    this.actionLabel = '选择此文件夹',
  });

  final FoxelApi api;
  final String title;
  final String initialPath;
  final Set<String> blockedPaths;
  final Set<String> exactBlockedPaths;
  final String actionLabel;

  @override
  State<DirectoryPickerPage> createState() => _DirectoryPickerPageState();
}

class _DirectoryPickerPageState extends State<DirectoryPickerPage> {
  late String _path = widget.initialPath;
  late Future<DirectoryListing> _listing = widget.api.listDirectory(_path);
  bool _busy = false;

  bool get _blocked => _isBlocked(_path);

  bool _isBlocked(String path) {
    final clean = path == '/' ? '/' : path.replaceAll(RegExp(r'/+$'), '');
    for (final blocked in widget.exactBlockedPaths) {
      final target = blocked == '/'
          ? '/'
          : blocked.replaceAll(RegExp(r'/+$'), '');
      if (clean == target) {
        return true;
      }
    }
    for (final blocked in widget.blockedPaths) {
      final target = blocked == '/'
          ? '/'
          : blocked.replaceAll(RegExp(r'/+$'), '');
      if (clean == target || clean.startsWith('$target/')) {
        return true;
      }
    }
    return false;
  }

  void _open(String path) {
    setState(() {
      _path = path;
      _listing = widget.api.listDirectory(path);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.title),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ContentFrame(
          child: Column(
            children: [
              _Breadcrumb(path: _path, onOpen: _open),
              Expanded(
                child: FutureBuilder<DirectoryListing>(
                  future: _listing,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            snapshot.error.toString(),
                            textAlign: TextAlign.center,
                            style: AppText.itemSubtitle,
                          ),
                        ),
                      );
                    }
                    final dirs = <FileEntry>[
                      for (final entry
                          in snapshot.data?.entries ?? const <FileEntry>[])
                        if (entry.isDir) entry,
                    ]..sort(
                      (a, b) => a.name.toLowerCase().compareTo(
                        b.name.toLowerCase(),
                      ),
                    );

                    return ListView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.page,
                        0,
                        AppSpacing.page,
                        120,
                      ),
                      children: [
                        for (final entry in dirs)
                          _DirectoryRow(
                            name: entry.name,
                            path: FoxelApi.joinPath(_path, entry.name),
                            blocked: _isBlocked(
                              FoxelApi.joinPath(_path, entry.name),
                            ),
                            onOpen: _open,
                          ),
                        if (dirs.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 40),
                            child: Center(
                              child: Text(
                                '当前目录没有子文件夹',
                                style: AppText.itemSubtitle,
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
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
              if (_blocked)
                const Padding(
                  padding: EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    '当前目录不可作为目标，请选择其他文件夹',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.warn,
                    ),
                  ),
                ),
              FilledButton.icon(
                onPressed: _blocked || _busy
                    ? null
                    : () => Navigator.of(context).pop(_path),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(widget.actionLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.path, required this.onOpen});

  final String path;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    final segments = <String>['/'];
    if (path != '/') {
      final parts = path.split('/').where((part) => part.isNotEmpty);
      var accumulated = '';
      for (final part in parts) {
        accumulated = '$accumulated/$part';
        segments.add(accumulated);
      }
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.page,
        AppSpacing.sm,
        AppSpacing.page,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          for (var index = 0; index < segments.length; index++) ...[
            if (index > 0)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2),
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 16,
                  color: AppColors.ink3,
                ),
              ),
            InkWell(
              onTap: () => onOpen(segments[index]),
              borderRadius: BorderRadius.circular(AppRadii.pill),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                child: Text(
                  index == 0 ? '根目录' : segments[index].split('/').last,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: index == segments.length - 1
                        ? AppColors.ink
                        : AppColors.ink2,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DirectoryRow extends StatelessWidget {
  const _DirectoryRow({
    required this.name,
    required this.path,
    required this.blocked,
    required this.onOpen,
  });

  final String name;
  final String path;
  final bool blocked;
  final ValueChanged<String> onOpen;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: blocked ? 0.45 : 1,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: 2,
        ),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.primarySoft,
            borderRadius: BorderRadius.circular(AppRadii.avatar),
          ),
          child: const Icon(
            Icons.folder_rounded,
            size: 20,
            color: AppColors.primary,
          ),
        ),
        title: Text(
          name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppText.itemTitle,
        ),
        subtitle: blocked
            ? const Text('来源目录，不可选为目标', style: AppText.itemHint)
            : null,
        trailing: blocked
            ? null
            : const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.ink3,
              ),
        onTap: blocked ? null : () => onOpen(path),
      ),
    );
  }
}
