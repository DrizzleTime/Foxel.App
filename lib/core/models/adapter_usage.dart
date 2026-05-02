class AdapterUsage {
  const AdapterUsage({
    required this.name,
    required this.supported,
    required this.usedBytes,
    required this.totalBytes,
    required this.freeBytes,
  });

  factory AdapterUsage.fromJson(Map<String, dynamic> json) {
    return AdapterUsage(
      name: json['name'] as String? ?? '',
      supported: json['supported'] as bool? ?? false,
      usedBytes: (json['used_bytes'] as num?)?.toInt() ?? 0,
      totalBytes: (json['total_bytes'] as num?)?.toInt() ?? 0,
      freeBytes: (json['free_bytes'] as num?)?.toInt() ?? 0,
    );
  }

  final String name;
  final bool supported;
  final int usedBytes;
  final int totalBytes;
  final int freeBytes;
}
