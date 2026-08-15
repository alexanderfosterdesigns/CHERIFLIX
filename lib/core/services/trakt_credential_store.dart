import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/trakt_account.dart';

abstract interface class TraktCredentialStore {
  Future<TraktAccount?> read(String profileId);

  Future<void> write(String profileId, TraktAccount account);

  Future<void> delete(String profileId);
}

class SecureTraktCredentialStore implements TraktCredentialStore {
  const SecureTraktCredentialStore({
    FlutterSecureStorage storage = const FlutterSecureStorage(),
  }) : _storage = storage;

  final FlutterSecureStorage _storage;

  @override
  Future<TraktAccount?> read(String profileId) async {
    final raw = await _storage.read(key: _key(profileId));
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      return TraktAccount.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(String profileId, TraktAccount account) {
    return _storage.write(
      key: _key(profileId),
      value: jsonEncode(account.toJson()),
    );
  }

  @override
  Future<void> delete(String profileId) {
    return _storage.delete(key: _key(profileId));
  }

  String _key(String profileId) => 'cheriflix.trakt.$profileId';
}

class MemoryTraktCredentialStore implements TraktCredentialStore {
  final Map<String, TraktAccount> _accounts = <String, TraktAccount>{};

  @override
  Future<TraktAccount?> read(String profileId) async {
    return _accounts[profileId];
  }

  @override
  Future<void> write(String profileId, TraktAccount account) async {
    _accounts[profileId] = account;
  }

  @override
  Future<void> delete(String profileId) async {
    _accounts.remove(profileId);
  }
}
