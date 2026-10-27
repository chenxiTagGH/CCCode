import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:baocode/channel/account/account_api.dart';
import 'package:baocode/channel/account/login_window.dart';
import 'package:baocode/models/cc_api_connector.dart';
import 'package:baocode/models/cc_api_store.dart';
import 'package:baocode/models/model_provider.dart';
import 'package:baocode/models/model_providers.dart';
import 'package:baocode/models/model_runtime.dart' show UpstreamException;
import 'package:baocode/models/secret_store.dart';
import 'package:baocode/models/upstream.dart';
import 'package:baocode/settings/jsonc_file.dart';
import 'package:baocode/settings/user_settings.dart';

void main() {
  test('detects CC API protocols from platform and model identity', () {
    expect(detectCcApiProtocol(platform: 'anthropic'), ProviderProtocol.anthropic);
    expect(detectCcApiProtocol(platform: 'openai'), ProviderProtocol.openaiChat);
    expect(
      detectCcApiProtocol(platform: 'openai', modelId: 'gpt-5.6-terra'),
      ProviderProtocol.openaiResponses,
    );
    expect(detectCcApiProtocol(platform: 'gemini'), ProviderProtocol.openaiChat);
    expect(detectCcApiProtocol(modelId: 'claude-sonnet-4-5'), ProviderProtocol.anthropic);
    expect(detectCcApiProtocol(modelId: 'gpt-5.6-terra'), ProviderProtocol.openaiResponses);
    expect(detectCcApiProtocol(modelId: 'gemini-2.5-pro'), ProviderProtocol.openaiChat);
    expect(
      detectCcApiProtocol(modelId: 'openai-responses/gpt-5'),
      ProviderProtocol.openaiResponses,
    );
    expect(
      detectCcApiProtocol(platform: 'vendor', modelId: 'openai-chat/model'),
      ProviderProtocol.openaiChat,
    );
    expect(detectCcApiProtocol(modelId: 'vendor-model'), ProviderProtocol.anthropic);
    expect(
      detectCcApiProtocol(modelId: 'legitimate-gptlike-vendor'),
      ProviderProtocol.anthropic,
    );
    expect(
      detectCcApiProtocol(modelId: 'vendor-openai-responses-model'),
      ProviderProtocol.anthropic,
    );
    expect(
      detectCcApiProtocol(modelId: 'vendor-openai-chat-model'),
      ProviderProtocol.anthropic,
    );
    expect(
      detectCcApiProtocol(platform: 'vendor', modelId: 'openai-chat/model'),
      ProviderProtocol.openaiChat,
    );
  });

  test('parses and merges explicit model protocol metadata', () {
    final models = parseModelList({
      'data': [
        {'id': 'gpt-5.6-terra', 'protocol': 'openai-responses'},
      ],
    });
    expect(models.single.protocol, ProviderProtocol.openaiResponses);
    expect(
      mergeModelList(const [], models).single.protocol,
      ProviderProtocol.openaiResponses,
    );
  });

  test('GlobalCcApiStore keeps session secret and metadata in separate fakes', () async {
    final files = FakeJsoncStorage();
    final storage = GlobalStorage('memory.json', storage: files);
    await storage.load();
    await storage.set(GlobalCcApiStore.accountKey, {'email': 'a@example.com'});
    await storage.set(GlobalCcApiStore.providerKey, {'id': '7'});
    final secrets = RecordingSecretStore();
    final store = GlobalCcApiStore(storage, secrets: secrets);

    await store.writeSession('refresh-secret');
    await store.writeState({
      'account': {'email': 'a@example.com'},
      'provider-key': {'id': '7', 'masked': 'sk-••••'},
    });

    expect(await store.readSession(), 'refresh-secret');
    expect(storage.get<Object>(GlobalCcApiStore.accountKey),
        {'email': 'a@example.com'});
    expect(storage.get<Object>(GlobalCcApiStore.providerKey),
        {'id': '7', 'masked': 'sk-••••'});
    expect(secrets.writes, {'cc-api.session': 'refresh-secret'});
  });

  test('GlobalCcApiStore treats unreadable secret as signed out', () async {
    final storage = GlobalStorage('memory.json', storage: FakeJsoncStorage());
    final store = GlobalCcApiStore(storage, secrets: ThrowingSecretStore());
    expect(await store.readSession(), isNull);
  });

  test('new login with multiple keys requires explicit selection', () async {
    final fixture = await makeFixture(
      loginRefreshToken: 'refresh-1',
      accountKeys: [
        fakeKey(id: '1', name: 'Anthropic', platform: 'anthropic'),
        fakeKey(id: '2', name: 'OpenAI', platform: 'openai'),
      ],
      revealedKey: 'sk-openai',
      models: const [RemoteModel('gpt-5.6-terra')],
      preloadSession: true,
    );
    fixture.chooseKey = (keys) async => keys.singleWhere((key) => key.id == '2');

    expect(await fixture.connector.connect(chooseKey: fixture.chooseKey), isTrue);
    expect(fixture.revealedKeyId, '2');
    expect(
      fixture.providers.provider('cc-api')!.protocol,
      ProviderProtocol.openaiChat,
    );
    expect(
      fixture.providers.provider('cc-api')!.models.single.protocol,
      ProviderProtocol.openaiResponses,
    );
  });

  test('cancelled key selection preserves the previous provider', () async {
    final fixture = await makeFixture(
      loginRefreshToken: 'refresh-1',
      accountKeys: [
        fakeKey(id: '1', name: 'one'),
        fakeKey(id: '2', name: 'two'),
      ],
      existingModels: const [ProviderModel(id: 'old-model')],
      existingKey: 'old-key',
      existingDefault: '@cc-api/old-model',
      preloadSession: false,
    );
    fixture.store.session = null;
    fixture.store.state = {'provider-key': {'id': 'old'}};
    final before = await fixture.snapshot();

    expect(await fixture.connector.connect(chooseKey: (_) async => null), isFalse);
    expect(await fixture.snapshot(), before);
    expect(fixture.revealedKeyId, isNull);
  });

  test('successful connection saves provider identity, protocol, and rotated session', () async {
    final fixture = await makeFixture(
      loginRefreshToken: 'refresh-1',
      accountKeys: [fakeKey(id: '7', name: 'CCCode')],
      revealedKey: 'sk-cccode',
      models: const [RemoteModel('claude-sonnet-4-5')],
      preloadSession: true,
    );

    expect(await fixture.connector.connect(), isTrue);
    final provider = fixture.providers.provider('cc-api')!;
    expect(provider.id, 'cc-api');
    expect(provider.name, 'CC API');
    expect(provider.protocol, ProviderProtocol.anthropic);
    expect(provider.baseUrl, 'https://api.cc-hub.vip');
    expect(fixture.store.session, 'refresh-2');
  });

  test('successful connection saves the cc-api provider and default model', () async {
    final fixture = await makeFixture(
      loginRefreshToken: 'refresh-1',
      accountKeys: [fakeKey(id: '7', name: 'CCCode')],
      revealedKey: 'sk-cccode',
      models: const [RemoteModel('claude-sonnet-4-5')],
      preloadSession: false,
    );

    expect(await fixture.connector.connect(), isTrue);
    final provider = fixture.providers.provider('cc-api');
    expect(provider?.baseUrl, 'https://api.cc-hub.vip');
    expect(provider?.models.single.id, 'claude-sonnet-4-5');
    expect(fixture.providers.defaultModel, '@cc-api/claude-sonnet-4-5');
    expect(await fixture.providers.key('cc-api'), 'sk-cccode');
    expect(fixture.window.closeRequested, isTrue);
  });

  test('creates a key when none exists and prefers Anthropic group', () async {
    final fixture = await makeFixture(
      loginRefreshToken: 'refresh-1',
      accountKeys: const [],
      revealedKey: 'sk-created',
      models: const [RemoteModel('claude-sonnet-4-5')],
      preloadSession: true,
    );

    expect(await fixture.connector.connect(), isTrue);
    expect(fixture.createdKeyRequest, isNotNull);
    expect(fixture.createdKeyRequest!['name'], 'CCCode');
    expect(fixture.createdKeyRequest!['group_id'], 7);
  });

  test('creates a key in first available group when Anthropic is absent', () async {
    final fixture = await makeFixture(
      loginRefreshToken: 'refresh-1',
      accountKeys: const [],
      groups: const [AccountGroup(id: '2', name: 'Codex', platform: 'openai')],
      revealedKey: 'sk-created',
      models: const [RemoteModel('claude-sonnet-4-5')],
      preloadSession: true,
    );

    expect(await fixture.connector.connect(), isTrue);
    expect(fixture.createdKeyRequest, isNotNull);
    expect(fixture.createdKeyRequest!['group_id'], 2);
    expect(fixture.revealedKeyId, '8');
  });

  test('closing login window before refresh token leaves existing config unchanged',
    final fixture = await makeFixture(
      loginRefreshToken: null,
      existingModels: const [ProviderModel(id: 'old-model')],
      existingKey: 'old-key',
      existingDefault: '@cc-api/old-model',
    );
    final before = await fixture.snapshot();
    final pending = fixture.connector.connect();
    await fixture.window.opened.future.timeout(const Duration(seconds: 1));
    scheduleMicrotask(fixture.window.dismiss);
    expect(await pending, isFalse);
    expect(fixture.window.wasOpened, isTrue);
    expect(await fixture.snapshot(), before);
  });

  test('login token is read only after a polling interval', () async {
    final fixture = await makeFixture(
      loginRefreshToken: 'refresh-2',
      loginTokens: const [null, 'refresh-1'],
      accountKeys: [fakeKey(id: '7', name: 'CCCode')],
      revealedKey: 'sk-cccode',
      models: const [RemoteModel('claude-sonnet-4-5')],
      preloadSession: false,
    );

    final stopwatch = Stopwatch()..start();
    expect(await fixture.connector.connect(), isTrue);
    stopwatch.stop();
    expect(fixture.window.evaluations, 2);
    expect(stopwatch.elapsed, greaterThanOrEqualTo(const Duration(seconds: 1)));
  });

  test('model refresh failure preserves the previous provider models', () async {
    final fixture = await makeFixture(
      loginRefreshToken: 'refresh-1',
      existingModels: const [ProviderModel(id: 'claude-sonnet-4-5')],
      existingKey: 'sk-existing',
      existingDefault: '@cc-api/claude-sonnet-4-5',
      modelError: const UpstreamException('offline'),
    );
    final before = await fixture.snapshot();

    expect(await fixture.connector.refresh(), isFalse);
    expect(fixture.listModelsInvoked, isTrue);
    expect(await fixture.snapshot(), before);
    // A token rotated during the failed synchronization is still durable.
    expect(fixture.store.session, 'refresh-2');
  });

  test('current provider key wins over stale metadata', () async {
    final fixture = await makeFixture(
      loginRefreshToken: 'refresh-1',
      accountKeys: [
        fakeKey(id: '1', name: 'stale'),
        fakeKey(
          id: '2',
          name: 'current',
          masked: AccountKey.mask('sk-current-whole'),
        ),
      ],
      revealedKey: 'sk-current-whole',
      accountWholeKeys: {'2': 'sk-current-whole'},
      models: const [RemoteModel('claude-sonnet-4-5')],
      existingKey: 'sk-current-whole',
      preloadSession: true,
    );
    fixture.store.state = {'provider-key': {'id': '1'}};

    expect(await fixture.connector.connect(), isTrue);
    expect(fixture.revealedKeyId, '2');
    expect(fixture.providers.provider('cc-api')!.id, 'cc-api');
  });

  test('newest returned key wins without CCCode or stored match', () async {
    final fixture = await makeFixture(
      loginRefreshToken: 'refresh-1',
      accountKeys: [
        fakeKey(id: '9', name: 'newest', masked: AccountKey.mask('sk-newest-whole')),
        fakeKey(id: '3', name: 'older', masked: AccountKey.mask('sk-older-whole')),
      ],
      accountWholeKeys: {
        '9': 'sk-newest-whole',
        '3': 'sk-older-whole',
      },
      revealedKey: 'sk-newest-whole',
      models: const [RemoteModel('claude-sonnet-4-5')],
      preloadSession: true,
    );

    expect(await fixture.connector.connect(), isTrue);
    expect(fixture.revealedKeyId, '9');
  });

  test('stored key identity beats a stale local secret match', () async {
    final fixture = await makeFixture(
      loginRefreshToken: 'refresh-1',
      accountKeys: [
        fakeKey(id: '1', name: 'stored'),
        fakeKey(
          id: '2',
          name: 'stale secret',
          masked: AccountKey.mask('sk-stale-whole'),
        ),
      ],
      revealedKey: 'sk-stored',
      accountWholeKeys: {
        '1': 'sk-stored',
        '2': 'sk-stale-whole',
      },
      existingKey: 'sk-stale-whole',
      models: const [RemoteModel('claude-sonnet-4-5')],
      preloadSession: true,
    );
    fixture.store.state = {'provider-key': {'id': '1'}};

    expect(await fixture.connector.connect(), isTrue);
    expect(fixture.revealedKeyId, '1');
  });

  test('stored key identity beats the CCCode fallback', () async {
    final fixture = await makeFixture(
      loginRefreshToken: 'refresh-1',
      accountKeys: [
        fakeKey(id: '1', name: 'old'),
        fakeKey(id: '2', name: 'CCCode'),
      ],
      revealedKey: 'sk-stored',
      accountWholeKeys: {
        '1': 'sk-stored',
        '2': 'sk-newest',
      },
      models: const [RemoteModel('claude-sonnet-4-5')],
      preloadSession: true,
    );
    fixture.store.state = {'provider-key': {'id': '1'}};

    expect(await fixture.connector.connect(), isTrue);
    expect(fixture.revealedKeyId, '1');
  });

  test('keeps disabled models disabled and unrelated defaults intact', () async {
    final fixture = await makeFixture(
      loginRefreshToken: 'refresh-1',
      accountKeys: [fakeKey(id: '7', name: 'CCCode')],
      revealedKey: 'sk-cccode',
      models: const [
        RemoteModel('old-disabled'),
        RemoteModel('claude-sonnet-4-5'),
      ],
      existingModels: const [
        ProviderModel(id: 'old-disabled', enabled: false),
      ],
      existingDefault: '@other/kept-model',
      extraProviders: const [
        ModelProvider(id: 'other', name: 'Other', baseUrl: 'https://other'),
      ],
      preloadSession: true,
    );

    expect(await fixture.connector.connect(), isTrue);
    final provider = fixture.providers.provider('cc-api')!;
    expect(provider.model('old-disabled')!.enabled, isFalse);
    expect(fixture.providers.defaultModel, '@other/kept-model');
  });

  test('image-only models never become the conversation default', () async {
    final fixture = await makeFixture(
      loginRefreshToken: 'refresh-1',
      accountKeys: [fakeKey(id: '7', name: 'CCCode')],
      revealedKey: 'sk-cccode',
      models: const [RemoteModel('gpt-image-1')],
      existingDefault: '@cc-api/old-model',
      preloadSession: true,
    );

    expect(await fixture.connector.connect(), isTrue);
    expect(fixture.providers.defaultModel, isNull);
  });

  test('login open and evaluate failures close the window', () async {
    final openFailure = await makeFixture(
      loginRefreshToken: null,
      windowOpenError: StateError('open failed'),
      preloadSession: false,
    );
    expect(await openFailure.connector.connect(), isFalse);
    expect(openFailure.window.closeRequested, isTrue);

    final evaluateFailure = await makeFixture(
      loginRefreshToken: null,
      windowEvaluateError: StateError('evaluate failed'),
      preloadSession: false,
    );
    expect(await evaluateFailure.connector.connect(), isFalse);
    expect(evaluateFailure.window.closeRequested, isTrue);
  });

  test('unreadable provider key fails before any key write or clear', () async {
    final secrets = ThrowingSecretStore();
    final providers = ModelProviders.memory(secrets: secrets);
    final store = FakeCcApiStore()..session = 'refresh-1';
    final window = FakeLoginWindow(null);
    final connector = CcApiConnector(
      providers: providers,
      store: store,
      openWindow: () => window,
      send: (_, __, {headers = const {}, json}) async =>
          throw StateError('must not contact account API'),
      listModels: (_, __) async => const [],
    );

    expect(await connector.connect(), isFalse);
    expect(secrets.writes, isEmpty);
    expect(secrets.deletes, isEmpty);
  });
}

Future<ConnectorFixture> makeFixture({
  String? loginRefreshToken,
  List<AccountKey> accountKeys = const [],
  Map<String, String> accountWholeKeys = const {},
  String? revealedKey,
  List<RemoteModel> models = const [],
  List<ProviderModel> existingModels = const [],
  String? existingKey,
  String? existingDefault,
  UpstreamException? modelError,
  bool preloadSession = true,
  Object? windowOpenError,
  Object? windowEvaluateError,
  List<ModelProvider> extraProviders = const [],
  List<AccountGroup> groups = const [
    AccountGroup(id: '7', name: 'Claude', platform: 'anthropic'),
  ],
  List<String?> loginTokens = const [],
  CcApiKeyChooser? chooseKey,
}) async {
  final providers = ModelProviders.memory(
    secrets: MemorySecretStore(
      if (existingKey != null) 'provider.cc-api': existingKey,
    ),
    providers: [
      ...extraProviders,
      if (existingModels.isNotEmpty)
        ModelProvider(
          id: 'cc-api',
          name: 'CC API',
          baseUrl: 'https://api.cc-hub.vip',
          models: existingModels,
        ),
    ],
  );
  final window = FakeLoginWindow(
    loginRefreshToken,
    tokens: loginTokens,
    openError: windowOpenError,
    evaluateError: windowEvaluateError,
  );
  final listedKeys = [...accountKeys];
  final store = FakeCcApiStore()
    ..session = preloadSession ? loginRefreshToken : null;
  final fixture = ConnectorFixture._(providers, window, store);
  fixture.chooseKey = chooseKey;
  fixture.connector = CcApiConnector(
    providers: providers,
    store: store,
    openWindow: () => window,
    send: (method, url, {headers = const {}, json}) async {
      expect(method, anyOf('GET', 'POST'));
      expect(url.host, 'api.cc-hub.vip');
      if (method == 'POST' && url.path == '/api/v1/auth/refresh') {
        expect(headers, isNot(containsPair('Authorization', anything)));
        expect(json, {'refresh_token': loginRefreshToken});
        return const AccountResponse(200, {
          'code': 0,
          'message': 'success',
          'data': {
            'access_token': 'access-1',
            'refresh_token': 'refresh-2',
            'expires_in': 3600,
            'token_type': 'Bearer',
          },
        });
      }
      expect(headers['Authorization'], 'Bearer access-1');
      if (method == 'GET' && url.path == '/api/v1/auth/me') {
        return const AccountResponse(200, {
          'code': 0,
          'message': 'success',
          'data': {
            'id': 1,
            'email': 'cccode@example.com',
            'username': 'CCCode',
            'balance': 100,
          },
        });
      }
      if (method == 'GET' && url.path == '/api/v1/keys') {
        expect(url.queryParameters['page'], '1');
        expect(url.queryParameters['page_size'], '100');
        return AccountResponse(200, {
          'code': 0,
          'message': 'success',
          'data': {
            'items': [
              for (final key in listedKeys)
                {
                  'id': int.tryParse(key.id) ?? key.id,
                  'name': key.name,
                  'key': accountWholeKeys[key.id] ?? key.masked,
                  'group': {'platform': key.platform ?? 'anthropic'},
                },
            ],
            'total': listedKeys.length,
          },
        });
      }
      if (method == 'GET' && url.path.startsWith('/api/v1/keys/')) {
        fixture.revealedKeyId = url.path.split('/').last;
        return AccountResponse(200, {
          'code': 0,
          'message': 'success',
          'data': {
            'id': url.path.split('/').last,
            'key': accountWholeKeys[url.path.split('/').last] ?? revealedKey,
          },
        });
      }
      if (method == 'GET' && url.path == '/api/v1/groups/available') {
        return const AccountResponse(200, {
          'code': 0,
          'message': 'success',
          'data': [
            for (final group in groups)
              {
                'id': int.parse(group.id),
                'name': group.name,
                'platform': group.platform,
              },
          ],
        });
      }
      if (method == 'POST' && url.path == '/api/v1/keys') {
        expect(json, isA<Map>());
        fixture.createdKeyRequest = Map<String, Object?>.from(json! as Map);
        listedKeys.insert(
          0,
          AccountKey(
            id: '8',
            name: fixture.createdKeyRequest!['name'] as String,
            masked: AccountKey.mask(fixture.createdKey),
            platform: groups
                .firstWhere((group) => group.id == '${fixture.createdKeyRequest!['group_id']}')
                .platform,
          ),
        );
        return const AccountResponse(200, {
          'code': 0,
          'message': 'success',
          'data': {'id': 8},
        });
      }
      return const AccountResponse(404, {'code': 404, 'message': 'not found'});
    },
    listModels: (_, __) async {
      fixture.listModelsInvoked = true;
      if (modelError != null) throw modelError;
      return models;
    },
  );
  if (existingDefault != null) {
    await providers.setDefaultModel(existingDefault);
  }
  return fixture;
}

AccountKey fakeKey({
  required String id,
  required String name,
  String? masked,
  String? platform,
}) => AccountKey(
  id: id,
  name: name,
  masked: masked ?? 'sk-••••',
  platform: platform,
);

class ConnectorFixture {
  ConnectorFixture._(this.providers, this.window, this.store);

  final ModelProviders providers;
  final FakeLoginWindow window;
  final FakeCcApiStore store;
  late CcApiConnector connector;
  bool listModelsInvoked = false;
  CcApiKeyChooser? chooseKey;
  String? revealedKeyId;
  Map<String, Object?>? createdKeyRequest;
  String createdKey = 'sk-created';

  Future<List<Object?>> snapshot() async {
    final provider = providers.provider('cc-api');
    return [
      store.session,
      store.state,
      provider?.id,
      provider?.name,
      provider?.baseUrl,
      provider?.protocol,
      provider?.models
          .map((model) => [model.id, model.label, model.protocol, model.enabled])
          .toList(),
      await providers.key('cc-api'),
      providers.defaultModel,
    ];
  }
}

class FakeCcApiStore implements CcApiStore {
  String? session;
  Map<String, Object?>? state;

  @override
  Future<String?> readSession() async => session;

  @override
  Future<void> writeSession(String? value) async => session = value;

  @override
  Map<String, Object?>? readState() => state;

  @override
  Future<void> writeState(Map<String, Object?>? value) async => state = value;
}

class RecordingSecretStore implements SecretStore {
  final values = <String, String>{};
  final writes = <String, String>{};

  @override
  Future<String?> read(String id) async => values[id];

  @override
  Future<void> write(String id, String value) async {
    values[id] = value;
    writes[id] = value;
  }

  @override
  Future<void> delete(String id) async => values.remove(id);
}

class FakeJsoncStorage implements JsoncFileStorage {
  final values = <String, String>{};

  @override
  Future<String?> read(String path) async => values[path];

  @override
  Future<void> write(String path, String text) async => values[path] = text;

  @override
  Stream<void> changes(String path) => const Stream<void>.empty();
}

class ThrowingSecretStore implements SecretStore {
  final writes = <String, Object?>{};
  final deletes = <String>[];

  @override
  Future<String?> read(String id) async => throw const SecretStoreException('unreadable');

  @override
  Future<void> write(String id, String value) async => writes[id] = value;

  @override
  Future<void> delete(String id) async => deletes.add(id);
}

class FakeLoginWindow implements LoginWindow {
  FakeLoginWindow(
    this.refreshToken, {
    this.tokens = const [],
    this.openError,
    this.evaluateError,
  });

  final String? refreshToken;
  final List<String?> tokens;
  final Object? openError;
  final Object? evaluateError;
  final opened = Completer<void>();
  final _closed = Completer<void>();
  bool wasOpened = false;
  bool closeRequested = false;

  void dismiss() {
    if (!_closed.isCompleted) _closed.complete();
  }

  @override
  Future<void> open(Uri url, {required String title}) async {
    wasOpened = true;
    if (openError != null) throw openError!;
    if (!opened.isCompleted) opened.complete();
  }

  var evaluations = 0;

  @override
  Future<Object?> evaluate(String expression) async {
    expect(expression, "localStorage.getItem('refresh_token')");
    if (evaluateError != null) throw evaluateError!;
    final value = evaluations < tokens.length ? tokens[evaluations] : refreshToken;
    evaluations++;
    return value;
  }

  @override
  Future<Map<String, String>> cookies(Uri url) async => const {};

  @override
  Future<void> close() async {
    closeRequested = true;
    if (!_closed.isCompleted) _closed.complete();
  }

  @override
  Future<void> get closed => _closed.future;
}
