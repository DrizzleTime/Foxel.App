class UserProfile {
  const UserProfile({
    required this.username,
    required this.email,
    required this.avatarUrl,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      username: json['username'] as String? ?? '',
      email: json['email'] as String? ?? '',
      avatarUrl: json['gravatar_url'] as String? ?? '',
    );
  }

  final String username;
  final String email;
  final String avatarUrl;
}
