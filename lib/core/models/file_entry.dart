class FileEntry {
  const FileEntry({
    required this.name,
    required this.isDir,
    required this.size,
    required this.mtime,
    this.type,
    this.hasThumbnail,
  });

  factory FileEntry.fromJson(Map<String, dynamic> json) {
    return FileEntry(
      name: json['name'] as String? ?? '',
      isDir: json['is_dir'] as bool? ?? false,
      size: (json['size'] as num?)?.toInt() ?? 0,
      mtime: (json['mtime'] as num?)?.toInt() ?? 0,
      type: json['type'] as String?,
      hasThumbnail: json['has_thumbnail'] as bool?,
    );
  }

  final String name;
  final bool isDir;
  final int size;
  final int mtime;
  final String? type;
  final bool? hasThumbnail;
}

class DirectoryListing {
  const DirectoryListing({required this.path, required this.entries});

  factory DirectoryListing.fromJson(Map<String, dynamic> json) {
    final rawEntries = json['entries'] as List<dynamic>? ?? const [];
    return DirectoryListing(
      path: json['path'] as String? ?? '/',
      entries: rawEntries
          .whereType<Map<String, dynamic>>()
          .map(FileEntry.fromJson)
          .toList(),
    );
  }

  final String path;
  final List<FileEntry> entries;
}
