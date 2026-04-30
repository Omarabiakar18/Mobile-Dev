class AppUser {
  AppUser({
    required this.id,
    required this.email,
    required this.name,
    this.phone,
    required this.createdAt,
  });

  final String id;
  final String email;
  final String name;
  final String? phone;
  final DateTime createdAt;

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        email: j['email'] as String,
        name: j['name'] as String,
        phone: j['phone'] as String?,
        createdAt: DateTime.parse(j['createdAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'name': name,
        'phone': phone,
        'createdAt': createdAt.toIso8601String(),
      };
}

class AuthResult {
  AuthResult({required this.user, required this.accessToken, required this.refreshToken});

  final AppUser user;
  final String accessToken;
  final String refreshToken;

  factory AuthResult.fromJson(Map<String, dynamic> j) => AuthResult(
        user: AppUser.fromJson(j['user'] as Map<String, dynamic>),
        accessToken: j['accessToken'] as String,
        refreshToken: j['refreshToken'] as String,
      );
}
