# CCCode 模型连接与 IntelliJ IDEA 支持 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 移除官网的 YMeng CC/iFruit 推荐，支持用户选择 CC API Key 并自动识别协议，同时在 macOS 和 Windows 加入 IntelliJ IDEA 外部编辑器。

**Architecture:** 官网推荐只由 `site/featured/upstreams.json` 控制；客户端不改变远程推荐加载逻辑。CC API 连接器在读取 Key 后通过可注入选择器让 UI 选择 Key，协议识别封装为纯函数，优先使用服务端 platform/protocol 元数据，再使用模型 ID 推断。外部编辑器继续复用 `Editor` 枚举和现有平台启动器。

**Tech Stack:** Flutter/Dart、Flutter widget tests、JSON fixture、macOS `open -a`、Windows `idea` command。

## Global Constraints

- 保留 `package:baocode/...` 和 Dart package 名称 `baocode`。
- IntelliJ IDEA 只在 macOS、Windows 菜单可用，Linux 不显示。
- CC API Key 完整值只能继续保存在系统密钥环，选择界面只显示名称、掩码和 platform。
- 多 Key 且没有上次有效选择时，必须由用户选择；取消选择不得修改当前 Provider、Key 或默认模型。
- 协议识别不得向每个模型发送真实对话请求，不产生额外模型调用费用。
- 修改后只运行相关测试；本机无 Flutter 时如实记录无法运行。

---

### Task 1: Remove remote featured upstreams

**Files:**
- Modify: `site/featured/upstreams.json`
- Delete: `site/featured/ymeng.png`
- Delete: `site/featured/ifruit.png`
- Modify: `test/models/upstream_import_test.dart`

**Interfaces:**
- Consumes: existing `FeaturedUpstream.parseList` and website JSON validation.
- Produces: a valid empty featured list (`{"version":1,"upstreams":[]}`) and regression assertions that `ymeng` and `ifruit` are absent.

- [ ] **Step 1: Write the failing regression test**

In the existing website-list test, add:

```dart
expect(list.map((u) => u.id), isNot(contains('ymeng')));
expect(list.map((u) => u.id), isNot(contains('ifruit')));
```

- [ ] **Step 2: Run the focused test and verify the old data fails**

Run:

```sh
flutter test test/models/upstream_import_test.dart
```

Expected before data removal: the new `isNot(contains(...))` assertions fail because both IDs are present.

- [ ] **Step 3: Remove the two entries and unused logos**

Replace `site/featured/upstreams.json` with:

```json
{
  "version": 1,
  "upstreams": []
}
```

Delete `site/featured/ymeng.png` and `site/featured/ifruit.png`.

- [ ] **Step 4: Run the focused test again**

Run:

```sh
flutter test test/models/upstream_import_test.dart
```

Expected: PASS, including the existing logo and unique-ID checks.

- [ ] **Step 5: Commit**

```sh
git add site/featured/upstreams.json site/featured/ymeng.png site/featured/ifruit.png test/models/upstream_import_test.dart
git commit -m "chore(site): remove featured upstream listings" -m "Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 2: Add IntelliJ IDEA to macOS and Windows

**Files:**
- Modify: `lib/workspace/editor_launcher.dart`
- Modify: `lib/workspace/editor_launcher_io.dart`
- Modify: `test/workspace_test.dart`
- Modify: `test/window_header_test.dart` only if the editor menu fixture requires it

**Interfaces:**
- Consumes: `Editor.availableEditors`, `Editor.macApp`, `Editor.command`, `openPath`.
- Produces: `Editor.intellijIdea` with `macApp: 'IntelliJ IDEA'`, `command: 'idea'`, `macOSOnly: false`; Linux filters it out through a new platform availability predicate.

- [ ] **Step 1: Write focused availability and persistence tests**

Add tests beside the existing editor preference tests:

```dart
test('IntelliJ IDEA is available on macOS and Windows, not Linux', () {
  expect(Editor.intellijIdea.macApp, 'IntelliJ IDEA');
  expect(Editor.intellijIdea.command, 'idea');
  expect(Editor.intellijIdea.macOSOnly, isFalse);
});

testWidgets('IntelliJ IDEA can be restored as the selected editor', (tester) async {
  final store = MemoryPreferenceStore({'editor': 'intellijIdea'});
  final workspace = await makeWorkspace(preferences: store);
  expect(workspace.editor, Editor.intellijIdea);
});
```

If the test harness exposes platform flags, assert `availableEditors` includes the item on macOS/Windows and excludes it on Linux; otherwise keep platform launch assertions in the IO test seam.

- [ ] **Step 2: Run the focused workspace tests and verify the new enum value fails**

Run:

```sh
flutter test test/workspace_test.dart
```

Expected: FAIL because `Editor.intellijIdea` does not exist yet.

- [ ] **Step 3: Add the enum entry**

In `Editor`, add after `vscode`:

```dart
intellijIdea(
  'IntelliJ IDEA',
  'idea',
  macApp: 'IntelliJ IDEA',
  icon: Codicons.tools,
),
```

Do not set `macOSOnly`; the existing `available` getter makes it visible on macOS and Windows and the Linux-specific filtering will be added in the next step.

- [ ] **Step 4: Filter IntelliJ IDEA out on Linux**

Change the editor availability metadata to distinguish the supported platforms. Add a field such as:

```dart
final bool desktopOnly;
```

or an equivalent existing-platform predicate, then make `intellijIdea.available` return false when `AppPlatform.isLinux`. Keep all existing editor availability behavior unchanged.

- [ ] **Step 5: Route Windows through the existing command path**

Keep `_onWindows` unchanged unless the platform test shows the command needs explicit arguments. `Editor.intellijIdea.command == 'idea'` must flow through `WindowControls.openExternal(path, app: 'idea')` just like VS Code and Cursor.

- [ ] **Step 6: Run focused tests**

Run:

```sh
flutter test test/workspace_test.dart test/window_header_test.dart
```

Expected: PASS.

- [ ] **Step 7: Commit**

```sh
git add lib/workspace/editor_launcher.dart lib/workspace/editor_launcher_io.dart test/workspace_test.dart test/window_header_test.dart
git commit -m "feat: add IntelliJ IDEA editor launcher" -m "Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 3: Let CC API users choose a Key and detect model protocol

**Files:**
- Modify: `lib/channel/account/account_api.dart`
- Modify: `lib/models/upstream.dart`
- Modify: `lib/models/model_provider.dart`
- Modify: `lib/models/cc_api_connector.dart`
- Modify: `lib/settings/pages/cc_api_card.dart`
- Modify: `lib/settings/pages/models_page.dart`
- Modify: `test/models/cc_api_connector_test.dart`
- Modify: `test/settings/models_page_test.dart`
- Modify: `test/models/upstream_import_test.dart` only if shared protocol parsing tests belong there

**Interfaces:**
- Consumes: `AccountKey.platform`, existing `ModelProvider.protocol`, `ProviderModel.protocol`, `RemoteModel`, and `CcApiConnector.connect/refresh`.
- Produces:
  - `typedef CcApiKeyChooser = Future<AccountKey?> Function(List<AccountKey> keys);`
  - `Future<bool> connect({CcApiKeyChooser? chooseKey})` and `Future<bool> refresh({CcApiKeyChooser? chooseKey})`.
  - `ProviderProtocol detectCcApiProtocol({String? platform, String? modelId, ProviderProtocol fallback = ProviderProtocol.anthropic})` as a pure testable helper.
  - `RemoteModel.protocol` parsed from explicit model metadata and copied into `ProviderModel.protocol` by `mergeModelList`.

- [ ] **Step 1: Add failing protocol-detection tests**

In `test/models/cc_api_connector_test.dart`, add cases:

```dart
expect(detectCcApiProtocol(platform: 'anthropic'), ProviderProtocol.anthropic);
expect(detectCcApiProtocol(platform: 'openai'), ProviderProtocol.openaiChat);
expect(detectCcApiProtocol(platform: 'gemini'), ProviderProtocol.openaiChat);
expect(detectCcApiProtocol(modelId: 'claude-sonnet-4-5'), ProviderProtocol.anthropic);
expect(detectCcApiProtocol(modelId: 'gpt-5.6-terra'), ProviderProtocol.openaiResponses);
expect(detectCcApiProtocol(modelId: 'gemini-2.5-pro'), ProviderProtocol.openaiChat);
expect(detectCcApiProtocol(modelId: 'vendor-model'), ProviderProtocol.anthropic);
```

Also add a model-list parsing assertion for an explicit field:

```dart
final models = parseModelList({
  'data': [
    {'id': 'gpt-5.6-terra', 'protocol': 'openai-responses'},
  ],
});
expect(models.single.protocol, ProviderProtocol.openaiResponses);
```

- [ ] **Step 2: Run tests and verify the helpers/fields fail**

Run:

```sh
flutter test test/models/cc_api_connector_test.dart
```

Expected: FAIL because the new helper and `RemoteModel.protocol` are not implemented.

- [ ] **Step 3: Implement explicit model protocol parsing**

Extend `RemoteModel` with:

```dart
final ProviderProtocol? protocol;
```

Parse explicit fields in `parseModelList` using `ProviderProtocol.forModels` and accepted keys `protocol`, `protocol_type`, `api_protocol`, and `api_type`. Keep unknown values null. Copy the field through `mergeModelList` into both existing refreshed `ProviderModel` entries (only when the old model has no explicit protocol) and newly created entries.

- [ ] **Step 4: Implement the pure CC API protocol detector**

Add `detectCcApiProtocol` near CC API model logic with this order:

```dart
ProviderProtocol detectCcApiProtocol({
  String? platform,
  String? modelId,
  ProviderProtocol fallback = ProviderProtocol.anthropic,
}) {
  final value = '${platform ?? ''} ${modelId ?? ''}'.toLowerCase();
  if (value.contains('openai-responses')) return ProviderProtocol.openaiResponses;
  if (value.contains('openai-chat')) return ProviderProtocol.openaiChat;
  if (platform == 'anthropic' || value.contains('claude')) {
    return ProviderProtocol.anthropic;
  }
  if (platform == 'openai' || value.contains('gpt') || value.contains('o1-') || value.contains('o3-') || value.contains('o4-')) {
    return ProviderProtocol.openaiResponses;
  }
  if (platform == 'gemini' || value.contains('gemini')) return ProviderProtocol.openaiChat;
  return fallback;
}
```

Use exact token matching/word boundaries in the final implementation so an unrelated vendor ID containing `gpt` as a substring is not misclassified.

- [ ] **Step 5: Add Key chooser injection and selection rules**

Add `CcApiKeyChooser` and make `connect`/`refresh` accept it. In `_synchronize`:

1. Read session and account profile.
2. Fetch keys.
3. Preserve the stored Key ID if it still exists.
4. If no stored valid Key exists and `keys.length > 1`, call `chooseKey`; if it returns null, throw a cancellation result that leaves settings untouched.
5. If exactly one key exists, use it without showing a chooser.
6. If there are no keys, keep the existing create-key flow.
7. Never silently fall back to `keys.first` for a new multi-Key login.

The chooser receives only metadata (`id`, `name`, `masked`, `platform`). Keep reveal after selection.

- [ ] **Step 6: Build the production Key picker UI**

Add a `showCcApiKeyPicker(BuildContext context, List<AccountKey> keys)` function in `cc_api_card.dart` or a focused neighboring file. Render a dialog with one radio/list tile per key, showing name, masked value, and platform; require an explicit selection and provide Cancel. The selected `AccountKey` is returned without revealing the full key.

Pass the callback from `CcApiCard` into `connector.connect` and `connector.refresh`. Keep duplicate-tap protection and existing generic error text.

- [ ] **Step 7: Use selected Key platform and model metadata before listing models**

Create the provisional provider after Key selection:

```dart
final protocol = detectCcApiProtocol(platform: selected.platform);
final provider = previous.copyWith(
  protocol: protocol,
  baseUrl: site.url.toString(),
  enabled: true,
  disableNonessentialTraffic: true,
);
```

Call `listModels(provider, whole)`. For each returned model, preserve explicit `RemoteModel.protocol`; where absent, apply `detectCcApiProtocol(platform: selected.platform, modelId: model.id, fallback: protocol)` before merging. Keep the provider protocol as the selected Key's platform protocol so the connection form no longer defaults blindly to Anthropic.

- [ ] **Step 8: Add regression tests for Key selection and cancellation**

Add tests covering:

```dart
test('new login with multiple keys requires explicit selection', () async {
  final fixture = await makeFixture(
    loginRefreshToken: 'refresh-1',
    accountKeys: [fakeKey(id: '1', name: 'Anthropic'), fakeKey(id: '2', name: 'OpenAI')],
    selectedKey: null,
    models: const [RemoteModel('gpt-5.6-terra')],
  );
  fixture.chooseKey = (keys) async => keys.singleWhere((key) => key.id == '2');
  expect(await fixture.connector.connect(chooseKey: fixture.chooseKey), isTrue);
  expect(fixture.revealedKeyId, '2');
});

test('cancelled key selection preserves the previous provider', () async {
  // Seed an existing provider/key, return null from chooseKey, and assert the snapshot is unchanged.
});
```

Also assert an OpenAI-selected Key produces `ProviderProtocol.openaiChat` or the explicit model protocol and that `ProviderModel.protocol` is persisted.

- [ ] **Step 9: Run focused tests**

Run:

```sh
flutter test test/models/cc_api_connector_test.dart test/settings/models_page_test.dart
```

Expected: PASS, including existing rollback, stale metadata, disabled-model, and default-model tests.

- [ ] **Step 10: Commit**

```sh
git add lib/channel/account/account_api.dart lib/models/upstream.dart lib/models/model_provider.dart lib/models/cc_api_connector.dart lib/settings/pages/cc_api_card.dart lib/settings/pages/models_page.dart test/models/cc_api_connector_test.dart test/settings/models_page_test.dart
git commit -m "feat: choose CC API keys and detect model protocols" -m "Co-Authored-By: Claude Code <noreply@anthropic.com>"
```

---

### Task 4: Integrated verification and release build

**Files:**
- No source changes unless a focused test exposes an integration defect.

- [ ] **Step 1: Run all directly related tests**

```sh
flutter test test/models/upstream_import_test.dart test/models/cc_api_connector_test.dart test/settings/models_page_test.dart test/workspace_test.dart
```

- [ ] **Step 2: Run static formatting/checks available locally**

```sh
dart format --output=none lib/channel/account/account_api.dart lib/models/upstream.dart lib/models/model_provider.dart lib/models/cc_api_connector.dart lib/settings/pages/cc_api_card.dart lib/settings/pages/models_page.dart lib/workspace/editor_launcher.dart lib/workspace/editor_launcher_io.dart test/models/cc_api_connector_test.dart test/settings/models_page_test.dart test/workspace_test.dart
git diff --check
```

- [ ] **Step 3: Push and trigger the desktop release workflow**

```sh
git push origin main
gh workflow run release.yml --repo chenxiTagGH/CCCode --ref main -f editions=both
```

- [ ] **Step 4: Verify all platform jobs**

```sh
RUN_ID=$(gh run list --repo chenxiTagGH/CCCode --workflow release.yml --limit 1 --json databaseId --jq '.[0].databaseId')
gh run view "$RUN_ID" --repo chenxiTagGH/CCCode --json status,conclusion,jobs
```

Expected: macOS standard/channel, Windows standard/channel, Linux x64/arm64 standard/channel all complete successfully. If manually dispatched, artifacts are available in Actions and publish jobs may remain skipped.
