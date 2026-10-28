import 'dart:async';

import '../channel/account/account_api.dart';
import '../channel/account/channel_account.dart' show LoginWindowOpener;
import '../channel/account/login_window.dart';
import '../channel/account/sub2api_adapter.dart';
import '../channel/channel_setup.dart';
import 'cc_api_store.dart';
import 'model_provider.dart';
import 'model_providers.dart';
import 'model_runtime.dart';
import 'secret_store.dart';
import 'upstream.dart';

class _WindowClosed {
  const _WindowClosed();
}

class _CcApiSelectionCancelled implements Exception {
  const _CcApiSelectionCancelled();
}

class _CcApiInvalidated implements Exception {
  const _CcApiInvalidated();
}

class _ActiveCcApiOperation {
  _ActiveCcApiOperation(this.epoch);

  final int epoch;
  late Future<bool> future;
}

/// The connection lifecycle of the CC API connector.
enum CcApiConnectionStatus {
  disconnected,
  connecting,
  connected,
  needsLogin,
  failed,
}

/// Lists models available through a provider and key.
typedef CcApiModelLister = Future<List<RemoteModel>> Function(
  ModelProvider provider,
  String? key,
);

typedef CcApiKeyChooser = Future<AccountKey?> Function(List<AccountKey> keys);

ProviderProtocol detectCcApiProtocol({
  String? platform,
  String? modelId,
  ProviderProtocol fallback = ProviderProtocol.anthropic,
}) {
  final platformValue = platform?.trim().toLowerCase() ?? '';
  final modelValue = modelId?.trim().toLowerCase() ?? '';
  final value = '$platformValue $modelValue';
  if (_hasExplicitProtocolMarker(value, 'openai-responses')) {
    return ProviderProtocol.openaiResponses;
  }
  if (_hasExplicitProtocolMarker(value, 'openai-chat')) {
    return ProviderProtocol.openaiChat;
  }
  if (platformValue == 'anthropic' || _hasToken(modelValue, 'claude')) {
    return ProviderProtocol.anthropic;
  }
  final modelFamily = _hasModelFamilyToken(modelValue, 'gpt') ||
      _hasModelFamilyToken(modelValue, 'o1') ||
      _hasModelFamilyToken(modelValue, 'o3') ||
      _hasModelFamilyToken(modelValue, 'o4');
  if (modelFamily) return ProviderProtocol.openaiResponses;
  if (platformValue == 'openai') return ProviderProtocol.openaiChat;
  if (platformValue == 'gemini' || _hasToken(modelValue, 'gemini')) {
    return ProviderProtocol.openaiChat;
  }
  return fallback;
}

bool _hasExplicitProtocolMarker(String value, String marker) => RegExp(
  '(^|\\s)${RegExp.escape(marker)}(?=/|\\s|\\u0024)',
).hasMatch(value);

bool _hasModelFamilyToken(String value, String token) => RegExp(
  '(^|[-_./:\\s])${RegExp.escape(token)}(?=\\d|[-_./:\\s]|\\u0024)',
).hasMatch(value);

bool _hasToken(String value, String token) => RegExp(
  '(^|[-_./:\\s])${RegExp.escape(token)}(?=\\u0024|[-_./:\\s])',
).hasMatch(value);

/// Synchronizes a CC API account and its Anthropic-compatible models.
class CcApiConnector {
  CcApiConnector({
    required this.providers,
    required this.store,
    required this.openWindow,
    required this.send,
    required this.listModels,
  });

  final ModelProviders providers;
  final CcApiStore store;
  final LoginWindowOpener openWindow;
  final AccountSend send;
  final CcApiModelLister listModels;

  static const providerId = 'cc-api';
  static const providerName = 'CC API';
  static final site = ChannelAccountSite(
    type: ChannelAccountType.sub2api,
    url: Uri.parse('https://api.cc-hub.vip'),
  );

  CcApiConnectionStatus _status = CcApiConnectionStatus.disconnected;
  Object? _error;
  bool _accountStateInvalidated = false;
  int _epoch = 0;
  bool _signingOut = false;
  Future<void>? _cleanupFuture;
  final Set<_ActiveCcApiOperation> _activeOperations = {};

  CcApiConnectionStatus get status => _status;
  Object? get error => _error;

  /// The last account balance committed by a successful synchronization.
  /// Session and provider-key metadata are intentionally not exposed here.
  double? get accountBalance {
    if (_accountStateInvalidated) return null;
    final account = store.readState()?['account'];
    final balance = account is Map ? account['balance'] : null;
    return balance is num ? balance.toDouble() : null;
  }

  Future<bool> connect({CcApiKeyChooser? chooseKey}) {
    if (_signingOut) return Future<bool>.value(false);
    final operation = _ActiveCcApiOperation(++_epoch);
    final future = _connect(chooseKey: chooseKey, operation: operation);
    operation.future = future;
    _activeOperations.add(operation);
    return future.whenComplete(() => _activeOperations.remove(operation));
  }

  Future<bool> _connect({
    CcApiKeyChooser? chooseKey,
    required _ActiveCcApiOperation operation,
  }) async {
    if (_status == CcApiConnectionStatus.connecting) return false;
    final epoch = operation.epoch;

    _status = CcApiConnectionStatus.connecting;
    _error = null;
    try {
      final previousSession = await store.readSession();
      if (epoch != _epoch) throw const _CcApiInvalidated();
      if (previousSession == null || previousSession.isEmpty) {
        _accountStateInvalidated = true;
      }
      var session = previousSession;
      if (session == null || session.isEmpty) {
        session = await _login(epoch);
        if (epoch != _epoch) throw const _CcApiInvalidated();
        if (session == null) {
          _status = CcApiConnectionStatus.needsLogin;
          return false;
        }
      }
      return await _synchronize(
        session,
        previousSession: previousSession,
        chooseKey: chooseKey,
        epoch: epoch,
      );
    } on _CcApiSelectionCancelled {
      if (epoch != _epoch) return false;
      _status = CcApiConnectionStatus.disconnected;
      return false;
    } on _CcApiInvalidated {
      return false;
    } on AccountSignedOut {
      if (epoch != _epoch) return false;
      await _handleSignedOut(
        CcApiConnectionStatus.needsLogin,
        callerEpoch: epoch,
      );
      return false;
    } on Object catch (error) {
      if (epoch != _epoch) return false;
      _error = error;
      _status = CcApiConnectionStatus.failed;
      return false;
    }
  }

  Future<bool> refresh({CcApiKeyChooser? chooseKey}) {
    if (_signingOut) return Future<bool>.value(false);
    final operation = _ActiveCcApiOperation(++_epoch);
    final future = _refresh(chooseKey: chooseKey, operation: operation);
    operation.future = future;
    _activeOperations.add(operation);
    return future.whenComplete(() => _activeOperations.remove(operation));
  }

  Future<bool> _refresh({
    CcApiKeyChooser? chooseKey,
    required _ActiveCcApiOperation operation,
  }) async {
    if (_status == CcApiConnectionStatus.connecting) return false;
    final epoch = operation.epoch;
    _status = CcApiConnectionStatus.connecting;
    _error = null;
    try {
      final previousSession = await store.readSession();
      if (epoch != _epoch) throw const _CcApiInvalidated();
      final session = previousSession;
      if (session == null || session.isEmpty) {
        await _handleSignedOut(
        CcApiConnectionStatus.needsLogin,
        callerEpoch: epoch,
      );
        return false;
      }
      return await _synchronize(
        session,
        previousSession: previousSession,
        chooseKey: chooseKey,
        epoch: epoch,
      );
    } on _CcApiSelectionCancelled {
      if (epoch != _epoch) return false;
      _status = CcApiConnectionStatus.disconnected;
      return false;
    } on _CcApiInvalidated {
      return false;
    } on AccountSignedOut {
      if (epoch != _epoch) return false;
      await _handleSignedOut(
        CcApiConnectionStatus.needsLogin,
        callerEpoch: epoch,
      );
      return false;
    } on Object catch (error) {
      if (epoch != _epoch) return false;
      _error = error;
      _status = CcApiConnectionStatus.failed;
      return false;
    }
  }

  Future<String?> _login(int epoch) async {
    final window = openWindow();
    try {
      await window.open(
        site.url.replace(path: '/login'),
        title: providerName,
      );
      var closed = false;
      unawaited(window.closed.then((_) => closed = true));
      while (!closed) {
        final result = await Future.any<Object?>([
          Future<void>.delayed(const Duration(seconds: 1)),
          window.closed.then((_) => const _WindowClosed()),
        ]);
        if (epoch != _epoch) throw const _CcApiInvalidated();
        if (result is _WindowClosed || closed) return null;
        final value = await window.evaluate("localStorage.getItem('refresh_token')");
        if (epoch != _epoch) throw const _CcApiInvalidated();
        if (value is String && value.isNotEmpty) return value;
      }
      return null;
    } finally {
      try {
        await window.close();
      } catch (_) {
        // Closing a failed native window is best effort.
      }
    }
  }

  Future<bool> _synchronize(
    String session, {
    String? previousSession,
    CcApiKeyChooser? chooseKey,
    required int epoch,
  }) async {
    void guard() {
      if (epoch != _epoch) {
        throw const _CcApiInvalidated();
      }
    }
    guard();
    String? rotatedSession;
    Future<void> rotationQueue = Future<void>.value();
    var committed = false;
    final adapter = Sub2ApiAdapter(
      site: site,
      send: send,
      credential: session,
      onCredential: (value) {
        rotatedSession = value;
        // Persist only after synchronization commits; cancellation must not
        // replace the caller's existing session.
        rotationQueue = Future<void>.value();
      },
    );
    try {
      final before = providers.provider(providerId);
      final oldKeyResult = await providers.keyRead(providerId);
      guard();
      if (!oldKeyResult.readable) {
        throw const AccountError('provider key unavailable');
      }
      final oldKey = oldKeyResult.value;
      final oldDefault = providers.defaultModel;
      final oldState = store.readState();
      final profile = await adapter.profile();
    await rotationQueue;
    guard();
    final keys = await adapter.keys();
    await rotationQueue;
    guard();
    final currentKey = await providers.key(providerId);
    var selected = await _selectKey(keys, currentKey, chooseKey: chooseKey);
    guard();
    selected ??= await adapter.create('CCCode');
    guard();
    final protocol = detectCcApiProtocol(platform: selected.platform);
    final provider = (before ?? const ModelProvider(id: providerId, name: providerName))
        .copyWith(
          name: providerName,
          protocol: protocol,
          baseUrl: site.url.toString(),
          enabled: true,
          disableNonessentialTraffic: true,
        );
    final whole = await adapter.reveal(selected);
    guard();
    final listed = await listModels(provider, whole);
    guard();
    if (listed.isEmpty) {
      throw const AccountError('no models returned');
    }
    final merged = mergeModelList(
      before?.models ?? const [],
      [
        for (final model in listed)
          model.protocol == null
              ? RemoteModel(
                  model.id,
                  label: model.label,
                  contextWindow: model.contextWindow,
                  efforts: model.efforts,
                  images: model.images,
                  kind: model.kind,
                  protocol: detectCcApiProtocol(
                    platform: selected.platform,
                    modelId: model.id,
                    fallback: protocol,
                  ),
                )
              : model,
      ],
      enable: {
        for (final model in listed)
          if (!(model.kind ?? guessModelKind(model.id)).generatesImages &&
              !(before?.models.any((old) => old.id == model.id) ?? false))
            model.id,
      },
    );
    final updated = provider.copyWith(models: merged);
    final main = _defaultOf(updated, providers.defaultModel);

    final nextProvider = main == null
        ? updated
        : updated.copyWith(roles: updated.roles.copyWith('main', main));
    final existingDefault = providers.defaultModel;
    final parsedDefault = parseModelRef(existingDefault);
    final defaultValid = providers.builtinAvailable &&
            existingDefault != null &&
            parsedDefault == null
        ? true
        : parsedDefault == null
        ? providers.resolve(existingDefault) != null
        : parsedDefault.provider == providerId
        ? nextProvider.enabledModels.any(
            (model) =>
                model.id == parsedDefault.model &&
                !model.kind.generatesImages,
          )
        : switch (providers.resolve(existingDefault)) {
            (final otherProvider, final otherModel) =>
              otherProvider.enabled &&
              otherModel.enabled &&
              !otherModel.kind.generatesImages,
            _ => false,
          };
    final nextDefault = defaultValid
        ? existingDefault
        : main == null
        ? null
        : modelRef(providerId, main);
    final nextState = {
      'account': _accountState(profile),
      'provider-key': {
        'id': selected.id,
        'name': selected.name,
        'masked': selected.masked,
        'platform': selected.platform,
      },
    };
    try {
      guard();
      await providers.setKey(providerId, whole);
      guard();
      await providers.save(nextProvider);
      guard();
      await providers.setDefaultModel(nextDefault);
      await rotationQueue;
      guard();
      await store.writeSession(rotatedSession ?? session);
      guard();
      await store.writeState(nextState);
      guard();
      committed = true;
      _accountStateInvalidated = false;
    } catch (error) {
      final rollbackErrors = <Object>[];
      Future<void> attempt(Future<void> Function() action) async {
        try {
          await action();
        } catch (rollbackError) {
          rollbackErrors.add(rollbackError);
        }
      }
      if (epoch == _epoch) {
        await attempt(() async {
          if (before == null) {
            await providers.remove(providerId);
          } else {
            await providers.save(before);
          }
        });
        await attempt(() async {
          if (oldKey != null) {
            await providers.setKey(providerId, oldKey);
          } else if (oldKeyResult.readable) {
            await providers.setKey(providerId, '');
          }
        });
        await attempt(() => providers.setDefaultModel(oldDefault));
        // A rotated token may have invalidated the prior token. Keep it for
        // genuine synchronization failures, but not after invalidation.
        await attempt(() => store.writeSession(rotatedSession ?? previousSession));
        await attempt(() => store.writeState(oldState));
      }
      if (rollbackErrors.isNotEmpty) {
        _error = StateError('persistence failed; rollback failed: ${rollbackErrors.first}');
      }
      throw error;
    }
      guard();
      _status = CcApiConnectionStatus.connected;
      return true;
    } on _CcApiSelectionCancelled {
      // Selection cancellation is strictly non-committing: storage and
      // provider state remain unchanged, including any deferred rotation.
      rethrow;
    } on _CcApiInvalidated {
      return false;
    } on Object {
      // A first login must remain usable after a genuine sync failure. A
      // refresh rotation may also invalidate the prior session, so retain the
      // newest credential whenever one was issued. These writes are best
      // effort and never replace the original error.
      if (!committed && (previousSession == null || rotatedSession != null)) {
        try {
          await store.writeSession(rotatedSession ?? session);
        } catch (_) {
          // Preserve the original synchronization error.
        }
      }
      rethrow;
    } finally {
      if (!committed) {
        try {
          await rotationQueue;
        } catch (_) {
          // The original operation already failed; preserve that error.
        }
      }
    }
  }

  Map<String, Object?> _accountState(AccountProfile profile) {
    final previous = _accountStateInvalidated ? null : store.readState()?['account'];
    final previousBalance = previous is Map ? previous['balance'] : null;
    final balance = profile.balance ??
        (previousBalance is num ? previousBalance.toDouble() : null);
    return {
      'name': profile.name,
      'email': ?profile.email,
      'balance': ?balance,
    };
  }

  Future<AccountKey?> _selectKey(
    List<AccountKey> keys,
    String? currentKey, {
    CcApiKeyChooser? chooseKey,
  }) async {
    // The whole key is not in metadata, but its masked form can be matched
    // against the current provider key only after reveal; prefer stored id.
    final metadata = store.readState()?['provider-key'];
    final id = metadata is Map ? metadata['id'] : null;
    if (id is String) {
      final same = keys.where((key) => key.id == id).firstOrNull;
      if (same != null) return same;
    }
    if (currentKey != null) {
      final matches = keys
          .where((key) => key.masked == AccountKey.mask(currentKey))
          .toList();
      if (matches.length == 1) return matches.single;
    }
    if (keys.length == 1) return keys.single;
    if (keys.length > 1) {
      final selected = chooseKey == null ? null : await chooseKey(keys);
      if (selected == null) throw const _CcApiSelectionCancelled();
      final match = keys.where((key) => key.id == selected.id).firstOrNull;
      if (match == null) throw const _CcApiSelectionCancelled();
      return match;
    }
    return null;
  }

  static String? _defaultOf(ModelProvider provider, String? before) {
    final models = [
      for (final model in provider.models)
        if (model.enabled && !model.kind.generatesImages) model,
    ];
    if (models.isEmpty) return null;
    final kept = parseModelRef(before);
    if (kept?.provider == providerId &&
        models.any((model) => model.id == kept!.model)) {
      return kept!.model;
    }
    bool contains(ProviderModel model, String word) =>
        model.id.toLowerCase().contains(word);
    return (models.where((model) => contains(model, 'sonnet')).firstOrNull ??
            models.where((model) => contains(model, 'claude')).firstOrNull ??
            models.first)
        .id;
  }

  Future<void> _handleSignedOut(
    CcApiConnectionStatus nextStatus, {
    int? callerEpoch,
  }) async {
    if (_signingOut) {
      await (_cleanupFuture ?? Future<void>.value());
      return;
    }
    _accountStateInvalidated = true;
    ++_epoch;
    _status = nextStatus;
    _signingOut = true;
    final cleanup = _automaticCleanup(
      nextStatus,
      callerEpoch: callerEpoch,
    );
    _cleanupFuture = cleanup;
    await cleanup;
  }

  Future<void> _automaticCleanup(
    CcApiConnectionStatus nextStatus, {
    int? callerEpoch,
  }) async {
    while (_activeOperations.any((operation) => operation.epoch != callerEpoch)) {
      final active = <Future<bool>>[
        for (final operation in _activeOperations)
          if (operation.epoch != callerEpoch) operation.future,
      ];
      try {
        await Future.wait(active);
      } catch (_) {
        // Cleanup continues after stale operations finish.
      }
    }
    Object? firstError;
    try {
      await providers.remove(providerId);
    } catch (error) {
      firstError ??= error;
    }
    try {
      await store.writeSession(null);
    } catch (error) {
      firstError ??= error;
    }
    try {
      await store.writeState(null);
    } catch (error) {
      firstError ??= error;
    }
    if (firstError != null) {
      _error = StateError('signed-out cleanup failed: $firstError');
    }
    _signingOut = false;
    _cleanupFuture = null;
  }

  Future<void> signOut() async {
    if (_signingOut) {
      await (_cleanupFuture ?? Future<void>.value());
      return;
    }
    _accountStateInvalidated = true;
    ++_epoch;
    _status = CcApiConnectionStatus.disconnected;
    _error = null;
    _signingOut = true;
    final cleanup = _signOutCleanup();
    _cleanupFuture = cleanup;
    await cleanup;
  }

  Future<void> _signOutCleanup() async {
    while (_activeOperations.isNotEmpty) {
      final active = List<Future<bool>>.of(_activeOperations);
      try {
        await Future.wait(active);
      } catch (_) {
        // Cleanup continues even when stale operations fail.
      }
    }
    Object? firstError;
    String? session;
    try {
      session = await store.readSession();
    } catch (error) {
      firstError = error;
    }
    if (session != null) {
      try {
        final adapter = Sub2ApiAdapter(site: site, send: send, credential: session);
        await adapter.signOut();
      } catch (error) {
        firstError ??= error;
      }
    }
    try {
      await store.writeSession(null);
    } catch (error) {
      firstError ??= error;
    }
    try {
      await store.writeState(null);
    } catch (error) {
      firstError ??= error;
    }
    try {
      await providers.remove(providerId);
    } catch (error) {
      firstError ??= error;
    }
    if (firstError != null) {
      _error = StateError('sign-out cleanup failed: $firstError');
    }
    _signingOut = false;
    _cleanupFuture = null;
  }
}

