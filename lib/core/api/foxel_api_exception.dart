class FoxelApiException implements Exception {
  const FoxelApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
