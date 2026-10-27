import 'package:flutter/foundation.dart';

import '../settings/user_settings.dart';
import 'secret_store.dart';

/// Persistent state used by the CC API connector.
abstract interface class CcApiStore {
  Future<String?> readSession();

  Future<void> writeSession(String? value);

  Map<String, Object?>? readState();

  Future<void> writeState(Map<String, Object?>? value);
}

/// CC API's session in the keychain and its non-secret account metadata in
/// global storage.
class GlobalCcApiStore implements CcApiStore {
  GlobalCcApiStore(this.storage, {SecretStore? secrets}) : _secrets = secrets;

  final GlobalStorage storage;
  final SecretStore? _secrets;

  SecretStore get secrets => _secrets ?? SecretStore.instance;

  static const sessionKey = 'cc-api.session';
  static const accountKey = 'cc-api.account';
  static const providerKey = 'cc-api.provider-key';

  @override
  Future<String?> readSession() async {
    try {
      return await secrets.read(sessionKey);
    } on SecretStoreException catch (error) {
      debugPrint('$sessionKey read failed (${error.runtimeType})');
      return null;
    }
  }

  @override
  Future<void> writeSession(String? value) async {
    try {
      if (value == null) {
        await secrets.delete(sessionKey);
      } else {
        await secrets.write(sessionKey, value);
      }
    } on SecretStoreException catch (error) {
      debugPrint('$sessionKey write failed (${error.runtimeType})');
      rethrow;
    }
  }

  @override
  Map<String, Object?>? readState() {
    final account = storage.get<Object>(accountKey);
    final key = storage.get<Object>(providerKey);
    if (account is! Map && key is! Map) return null;
    return {
      if (account is Map) 'account': account,
      if (key is Map) 'provider-key': key,
    };
  }

  @override
  /// Metadata contains no secrets; writes are awaited so connector rollback can
  /// account for failures consistently with Provider/key/default/session data.
  Future<void> writeState(Map<String, Object?>? value) async {
    await _write(accountKey, value?['account']);
    await _write(providerKey, value?['provider-key']);
  }

  Future<void> _write(String key, Object? value) async {
    // Metadata only: callers must never put a session or whole API key here.
    try {
      await storage.set(key, value);
    } catch (error) {
      debugPrint('$key write failed (${error.runtimeType})');
      rethrow;
    }
  }
}

