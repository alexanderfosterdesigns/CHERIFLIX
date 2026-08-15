import 'maturity_tier.dart';
import 'trakt_account.dart';

class Profile {
  const Profile({
    required this.id,
    required this.name,
    required this.avatarLabel,
    required this.languageCode,
    required this.maturityTier,
    required this.createdAt,
    this.traktAccount,
    this.pinHash,
  });

  static const Object _unset = Object();

  final String id;
  final String name;
  final String avatarLabel;
  final String languageCode;
  final MaturityTier maturityTier;
  final DateTime createdAt;
  final TraktAccount? traktAccount;
  final String? pinHash;
  bool get isLocked => pinHash?.isNotEmpty == true;

  bool get hasTraktConnection => traktAccount != null;

  Profile copyWith({
    String? name,
    String? avatarLabel,
    String? languageCode,
    MaturityTier? maturityTier,
    Object? traktAccount = _unset,
    Object? pinHash = _unset,
  }) {
    return Profile(
      id: id,
      name: name ?? this.name,
      avatarLabel: avatarLabel ?? this.avatarLabel,
      languageCode: languageCode ?? this.languageCode,
      maturityTier: maturityTier ?? this.maturityTier,
      createdAt: createdAt,
      traktAccount: identical(traktAccount, _unset)
          ? this.traktAccount
          : traktAccount as TraktAccount?,
      pinHash: identical(pinHash, _unset) ? this.pinHash : pinHash as String?,
    );
  }

  factory Profile.fromMap(Map<String, Object?> map) {
    return Profile(
      id: map['id']! as String,
      name: map['name']! as String,
      avatarLabel: map['avatar_label']! as String,
      languageCode: map['language_code']! as String,
      maturityTier:
          MaturityTierCodec.fromWireValue(map['maturity_tier']! as String),
      createdAt: DateTime.parse(map['created_at']! as String),
      traktAccount: TraktAccount.fromProfileMap(map),
      pinHash: map['pin_hash'] as String?,
    );
  }

  Map<String, Object?> toMap({bool includeTraktAccount = true}) {
    return <String, Object?>{
      'id': id,
      'name': name,
      'avatar_label': avatarLabel,
      'language_code': languageCode,
      'maturity_tier': maturityTier.wireValue,
      'created_at': createdAt.toUtc().toIso8601String(),
      'pin_hash': pinHash,
      'trakt_username': includeTraktAccount ? traktAccount?.username : null,
      'trakt_access_token':
          includeTraktAccount ? traktAccount?.accessToken : null,
      'trakt_refresh_token':
          includeTraktAccount ? traktAccount?.refreshToken : null,
      'trakt_token_type': includeTraktAccount ? traktAccount?.tokenType : null,
      'trakt_scope': includeTraktAccount ? traktAccount?.scope : null,
      'trakt_token_created_at': includeTraktAccount
          ? traktAccount?.tokenCreatedAt.toUtc().toIso8601String()
          : null,
      'trakt_expires_in':
          includeTraktAccount ? traktAccount?.expiresInSeconds : null,
    };
  }
}
