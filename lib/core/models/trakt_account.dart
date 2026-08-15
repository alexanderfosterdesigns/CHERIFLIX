class TraktAccount {
  const TraktAccount({
    required this.username,
    required this.accessToken,
    required this.refreshToken,
    required this.tokenType,
    required this.scope,
    required this.tokenCreatedAt,
    required this.expiresInSeconds,
  });

  final String username;
  final String accessToken;
  final String refreshToken;
  final String tokenType;
  final String scope;
  final DateTime tokenCreatedAt;
  final int expiresInSeconds;

  DateTime get expiresAt =>
      tokenCreatedAt.toUtc().add(Duration(seconds: expiresInSeconds));

  bool get needsRefresh => DateTime.now().toUtc().isAfter(
        expiresAt.subtract(const Duration(minutes: 2)),
      );

  TraktAccount copyWith({
    String? username,
    String? accessToken,
    String? refreshToken,
    String? tokenType,
    String? scope,
    DateTime? tokenCreatedAt,
    int? expiresInSeconds,
  }) {
    return TraktAccount(
      username: username ?? this.username,
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      tokenType: tokenType ?? this.tokenType,
      scope: scope ?? this.scope,
      tokenCreatedAt: tokenCreatedAt ?? this.tokenCreatedAt,
      expiresInSeconds: expiresInSeconds ?? this.expiresInSeconds,
    );
  }

  static TraktAccount? fromProfileMap(Map<String, Object?> map) {
    final username = map['trakt_username'] as String?;
    final accessToken = map['trakt_access_token'] as String?;
    final refreshToken = map['trakt_refresh_token'] as String?;
    final tokenType = map['trakt_token_type'] as String?;
    final scope = map['trakt_scope'] as String?;
    final tokenCreatedAtRaw = map['trakt_token_created_at'] as String?;
    final expiresInSeconds = (map['trakt_expires_in'] as num?)?.toInt();
    if (username == null ||
        accessToken == null ||
        refreshToken == null ||
        tokenType == null ||
        scope == null ||
        tokenCreatedAtRaw == null ||
        expiresInSeconds == null) {
      return null;
    }

    final tokenCreatedAt = DateTime.tryParse(tokenCreatedAtRaw)?.toUtc();
    if (tokenCreatedAt == null) {
      return null;
    }

    return TraktAccount(
      username: username,
      accessToken: accessToken,
      refreshToken: refreshToken,
      tokenType: tokenType,
      scope: scope,
      tokenCreatedAt: tokenCreatedAt,
      expiresInSeconds: expiresInSeconds,
    );
  }

  factory TraktAccount.fromJson(Map<String, dynamic> json) {
    final tokenCreatedAt = DateTime.parse(
      json['tokenCreatedAt'] as String,
    ).toUtc();
    return TraktAccount(
      username: json['username'] as String,
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      tokenType: json['tokenType'] as String,
      scope: json['scope'] as String? ?? '',
      tokenCreatedAt: tokenCreatedAt,
      expiresInSeconds: (json['expiresInSeconds'] as num).toInt(),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'username': username,
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'tokenType': tokenType,
      'scope': scope,
      'tokenCreatedAt': tokenCreatedAt.toUtc().toIso8601String(),
      'expiresInSeconds': expiresInSeconds,
    };
  }

  Map<String, Object?> toProfileColumns() {
    return <String, Object?>{
      'trakt_username': username,
      'trakt_access_token': accessToken,
      'trakt_refresh_token': refreshToken,
      'trakt_token_type': tokenType,
      'trakt_scope': scope,
      'trakt_token_created_at': tokenCreatedAt.toUtc().toIso8601String(),
      'trakt_expires_in': expiresInSeconds,
    };
  }
}
