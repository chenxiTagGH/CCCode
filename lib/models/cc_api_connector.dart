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
  if (_hasToken(value, 'openai-responses')) {
    return ProviderProtocol.openaiResponses;
  }
  if (_hasToken(value, 'openai-chat')) return ProviderProtocol.openaiChat;
  if (platformValue == 'anthropic' || _hasToken(modelValue, 'claude')) {
    return ProviderProtocol.anthropic;
  }
  if (platformValue == 'openai' ||
      _hasToken(modelValue, 'gpt') ||
      RegExp(r'\b(?:o1|o3|o4)-').hasMatch(modelValue)) {
    return platformValue == 'openai'
        ? ProviderProtocol.openaiChat
        : ProviderProtocol.openaiResponses;
  }
  if (platformValue == 'gemini' || _hasToken(modelValue, 'gemini')) {
    return ProviderProtocol.openaiChat;
  }
  return fallback;
}

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

  CcApiConnectionStatus get status => _status;
  Object? get error => _error;

  Future<bool> connect({CcApiKeyChooser? chooseKey}) async {
    if (_status == CcApiConnectionStatus.connecting) return false;
    _status = CcApiConnectionStatus.connecting;
    _error = null;
    try {
      final previousSession = await store.readSession();
      var session = previousSession;
      if (session == null || session.isEmpty) {
        session = await _login();
        if (session == null) {
          _status = CcApiConnectionStatus.needsLogin;
          return false;
        }
      }
      return await _synchronize(
        session,
        previousSession: previousSession,
        chooseKey: chooseKey,
      );
    } on _CcApiSelectionCancelled {
      _status = CcApiConnectionStatus.disconnected;
      return false;
    } on AccountSignedOut {
      try {
        await store.writeSession(null);
      } catch (_) {
        // Signed-out status must not depend on keychain cleanup succeeding.
      }
      _status = CcApiConnectionStatus.needsLogin;
      return false;
    } on Object catch (error) {
      _error = error;
      _status = CcApiConnectionStatus.failed;
      return false;
    }
  }

  Future<bool> refresh({CcApiKeyChooser? chooseKey}) async {
    if (_status == CcApiConnectionStatus.connecting) return false;
    _status = CcApiConnectionStatus.connecting;
    _error = null;
    try {
      final previousSession = await store.readSession();
      final session = previousSession;
      if (session == null || session.isEmpty) {
        _status = CcApiConnectionStatus.needsLogin;
        return false;
      }
      return await _synchronize(
        session,
        previousSession: previousSession,
        chooseKey: chooseKey,
      );
    } on _CcApiSelectionCancelled {
      _status = CcApiConnectionStatus.disconnected;
      return false;
    } on AccountSignedOut {
      try {
        await store.writeSession(null);
      } catch (_) {
        // Signed-out status must not depend on keychain cleanup succeeding.
      }
      _status = CcApiConnectionStatus.needsLogin;
      return false;
    } on Object catch (error) {
      _error = error;
      _status = CcApiConnectionStatus.failed;
      return false;
    }
  }

  Future<String?> _login() async {
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
        if (result is _WindowClosed || closed) return null;
        final value = await window.evaluate("localStorage.getItem('refresh_token')");
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
  }) async {
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
      if (!oldKeyResult.readable) {
        throw const AccountError('provider key unavailable');
      }
      final oldKey = oldKeyResult.value;
      final oldDefault = providers.defaultModel;
    final oldState = store.readState();
    final oldSession = session;
    final profile = await adapter.profile();
    await rotationQueue;
    final keys = await adapter.keys();
    await rotationQueue;
    final currentKey = await providers.key(providerId);
    var selected = await _selectKey(keys, currentKey, chooseKey: chooseKey);
    selected ??= await adapter.create('CCCode');
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
    final listed = await listModels(provider, whole);
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
      'account': {
        'name': profile.name,
        'email': ?profile.email,
        'balance': ?profile.balance,
      },
      'provider-key': {
        'id': selected.id,
        'name': selected.name,
        'masked': selected.masked,
        'platform': selected.platform,
      },
    };
    try {
      await providers.setKey(providerId, whole);
      await providers.save(nextProvider);
      await providers.setDefaultModel(nextDefault);
      await rotationQueue;
      await store.writeSession(rotatedSession ?? session);
      await store.writeState(nextState);
      committed = true;
    } catch (error) {
      final rollbackErrors = <Object>[];
      Future<void> attempt(Future<void> Function() action) async {
        try {
          await action();
        } catch (rollbackError) {
          rollbackErrors.add(rollbackError);
        }
      }
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
      // genuine synchronization failures, but cancellation occurs before
      // persistence and therefore never reaches this rollback path.
      await attempt(() => store.writeSession(rotatedSession ?? previousSession));
      await attempt(() => store.writeState(oldState));
      if (rollbackErrors.isNotEmpty) {
        _error = StateError('persistence failed; rollback failed: ${rollbackErrors.first}');
      }
      throw error;
    }
      _status = CcApiConnectionStatus.connected;
      return true;
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

  Future<void> signOut() async {
    final session = await store.readSession();
    if (session != null) {
      final adapter = Sub2ApiAdapter(site: site, send: send, credential: session);
      await adapter.signOut();
    }
    await store.writeSession(null);
    await store.writeState(null);
    await providers.remove(providerId);
    _status = CcApiConnectionStatus.disconnected;
    _error = null;
  }
}

