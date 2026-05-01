class FoxelSession {
  const FoxelSession({
    required this.baseUrl,
    required this.username,
    required this.token,
    this.email = '',
    this.avatarUrl = '',
  });

  final String baseUrl;
  final String username;
  final String token;
  final String email;
  final String avatarUrl;

  FoxelSession copyWith({
    String? baseUrl,
    String? username,
    String? token,
    String? email,
    String? avatarUrl,
  }) {
    return FoxelSession(
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      token: token ?? this.token,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }
}
