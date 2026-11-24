class AppUser {
  final String id;
  final String name;
  final String email;
  final String baseCurrency;
  final String? avatarPath;
  final DateTime createdAt;
  const AppUser({required this.id, required this.name, required this.email, required this.baseCurrency, this.avatarPath, required this.createdAt});

  AppUser copyWith({String? name, String? email, String? baseCurrency, String? avatarPath}) => AppUser(
      id: id, name: name ?? this.name, email: email ?? this.email, baseCurrency: baseCurrency ?? this.baseCurrency,
      avatarPath: avatarPath ?? this.avatarPath, createdAt: createdAt);

  factory AppUser.fromMap(Map<String, Object?> m) => AppUser(
      id: m['id'] as String, name: m['name'] as String, email: m['email'] as String,
      baseCurrency: m['base_currency'] as String, avatarPath: m['avatar_path'] as String?,
      createdAt: DateTime.parse(m['created_at'] as String));
}

class SessionInfo {
  final String id;
  final String userId;
  final String device;
  final DateTime createdAt;
  final DateTime lastSeenAt;
  final DateTime? revokedAt;
  final bool cloud;
  const SessionInfo({required this.id, required this.userId, required this.device, required this.createdAt, required this.lastSeenAt, this.revokedAt, this.cloud = false});
  bool get active => revokedAt == null;

  factory SessionInfo.fromMap(Map<String, Object?> m) => SessionInfo(
      id: m['id'] as String, userId: m['user_id'] as String, device: m['device'] as String,
      createdAt: DateTime.parse(m['created_at'] as String), lastSeenAt: DateTime.parse(m['last_seen_at'] as String),
      revokedAt: m['revoked_at'] == null ? null : DateTime.parse(m['revoked_at'] as String));
}

class SignUpResult {
  final AppUser user;
  final String recoveryCode; // shown once
  const SignUpResult(this.user, this.recoveryCode);
}
