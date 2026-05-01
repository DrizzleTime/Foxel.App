String cleanPath(String path) {
  var cleaned = path.trim().replaceAll('\\', '/');
  cleaned = cleaned.replaceAll(RegExp(r'/+'), '/');
  if (cleaned.isEmpty || cleaned == '/') {
    return '/';
  }
  if (!cleaned.startsWith('/')) {
    cleaned = '/$cleaned';
  }
  return cleaned.replaceAll(RegExp(r'/+$'), '');
}

String joinPath(String base, String name) {
  final cleanedBase = cleanPath(base);
  final prefix = cleanedBase == '/' ? '' : cleanedBase;
  return cleanPath('$prefix/$name');
}

String parentPath(String path) {
  final cleaned = cleanPath(path);
  if (cleaned == '/') {
    return '/';
  }
  final index = cleaned.lastIndexOf('/');
  if (index <= 0) {
    return '/';
  }
  return cleaned.substring(0, index);
}

String encodePath(String path) {
  final cleaned = cleanPath(path);
  final withoutLeadingSlash = cleaned == '/' ? '' : cleaned.substring(1);
  return withoutLeadingSlash
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .map(Uri.encodeComponent)
      .join('/');
}
