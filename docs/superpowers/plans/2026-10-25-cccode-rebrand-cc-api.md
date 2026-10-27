# CCCode Rebrand and CC API Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebrand the fork as CCCode and add a built-in CC API card that logs users into `https://api.cc-hub.vip`, synchronizes a usable Provider and model list, and selects a default model without changing the Dart package name.

**Architecture:** Keep the Dart package identity `cccode` and all `package:baocode/...` imports, but replace user-visible and platform runtime identifiers with CCCode values and the `cccode://` scheme. Extract the account/session synchronization currently embedded in the channel account flow into a reusable connector used by the ordinary Models settings page. The connector composes the existing Sub2API adapter, login window, SecretStore, and ModelProviders persistence instead of adding a second protocol implementation.

**Tech Stack:** Flutter, Dart 3.13.4+, native macOS/Windows/Linux runners, WebKit/WebView2/WebKitGTK login window, existing SecretStore, existing ModelProviders, Flutter widget tests, Dart unit tests.

## Global Constraints

- Keep `pubspec.yaml` package name `cccode` and keep every `package:baocode/...` import unchanged.
- Replace user-visible and runtime CCCode identifiers with CCCode; do not add CCCode compatibility for schemes, data directories, native channels, or platform identifiers.
- Register/use `cccode://`; do not keep `cccode://` registration.
- Use `/Users/tangchenxi/logos/cc-ai-api/final/cc-ai-api-logo.svg` as the source Logo.
- Use `cc-api` as the built-in Provider ID and `https://api.cc-hub.vip` as its base URL.
- Store refresh tokens and Provider API keys only through existing SecretStore-backed storage.
- Never log refresh tokens, API keys, cookies, full authorization headers, or login-window contents.
- Do not hard-code Claude, GPT, or Gemini model IDs; derive models from the CC API response.
- Preserve an existing valid Provider/model configuration when refresh or model synchronization fails.
- Run only targeted tests and analysis related to the changed files; do not run the full test suite casually.
- Do not commit or push changes unless the user explicitly requests it.

---

## File Map

### Branding and platform identity

- Modify: `assets/branding/logo.svg`, `assets/branding/app_icon.png`, and add generated CCCode icon variants under `assets/branding/`.
- Modify: `macos/Runner/Configs/AppInfo.xcconfig`, `macos/Runner/Info.plist`, `macos/Runner/*.swift`, `macos/Runner.xcodeproj/project.pbxproj` where literal product or channel identifiers are present.
- Modify: `windows/runner/`, `windows/BrowserBridge/`, rename `tool/cccode.iss` to `tool/cccode.iss`, and update Windows build scripts to reference the new installer file.
- Modify: `linux/CMakeLists.txt`, `linux/runner/`, `tool/package_linux_deb.sh`.
- Modify: `browser_extension/`, browser host manifests, and packaging scripts.
- Modify: `tool/build_macos.dart`, `tool/build_windows.dart`, `tool/release_manifest.dart`, `tool/dmg_background.swift`, and related release helpers.
- Modify: README and site files that ship with the fork; remove CCCode product/domain links and labels, use relative links where no CCCode website has been supplied, and use `https://api.cc-hub.vip` only for CC API links. Retain `package:baocode` imports in Dart files.

### CC API connection

- Create: `lib/models/cc_api_connector.dart` — reusable connection state machine and Provider synchronization.
- Create: `lib/models/cc_api_store.dart` — CC API refresh-token/session state persistence.
- Modify: `lib/channel/account/sub2api_adapter.dart` — expose/reuse the adapter behavior without channel-only assumptions where needed.
- Modify: `lib/channel/account/channel_account.dart` only if shared account synchronization is extracted rather than duplicated.
- Reuse: `lib/channel/account/login_window.dart`, `lib/channel/account/account_api.dart`, `lib/channel/account/account_send.dart`, `lib/channel/account/account_send_io.dart`, `lib/models/model_providers.dart`, `lib/models/model_runtime.dart`, and `lib/models/upstream.dart`.

### Models UI and localization

- Create: `lib/settings/pages/cc_api_card.dart` — fixed CC API card and status presentation.
- Modify: `lib/settings/pages/models_page.dart` — place the card before external featured upstream cards and wire actions.
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_zh.arb`, generated localization files if this repository checks them in.
- Modify: `test/settings/models_page_test.dart` and create `test/models/cc_api_connector_test.dart`.
- Modify: `test/channel/account_test.dart` only for adapter behavior that is shared by the new connector.

---

### Task 1: Add CC API connector contracts and failing unit tests

**Files:**
- Create: `lib/models/cc_api_store.dart`
- Create: `lib/models/cc_api_connector.dart`
- Create: `test/models/cc_api_connector_test.dart`

**Interfaces:**
- `CcApiStore.readSession() -> Future<String?>`
- `CcApiStore.writeSession(String? value) -> Future<void>`
- `CcApiStore.readState() -> Map<String, Object?>?`
- `CcApiStore.writeState(Map<String, Object?>? value) -> void`
- `CcApiConnector.connect() -> Future<bool>`
- `CcApiConnector.refresh() -> Future<bool>`
- `CcApiConnector.signOut() -> Future<void>`
- `CcApiConnector.status -> CcApiConnectionStatus`
- `CcApiConnectionStatus` values: `disconnected`, `connecting`, `connected`, `needsLogin`, `failed`.

- [ ] **Step 1: Write failing store and connector tests**

Add tests using `MemorySecretStore`, `MemoryChannelAccountStore`-style fakes, a fake `LoginWindow`, and a fake `AccountSend`. Cover these exact cases:

```dart
test('successful connection saves the cc-api provider and default model', () async {
  final connector = makeConnector(
    loginRefreshToken: 'refresh-1',
    accountKeys: [fakeKey(id: '7', name: 'CCCode')],
    revealedKey: 'sk-cccode',
    models: const [RemoteModel('claude-sonnet-4-5')],
  );

  expect(await connector.connect(), isTrue);
  final provider = connector.providers.provider('cc-api');
  expect(provider?.baseUrl, 'https://api.cc-hub.vip');
  expect(provider?.models.single.id, 'claude-sonnet-4-5');
  expect(connector.providers.defaultModel, 'cc-api/claude-sonnet-4-5');
  expect(await connector.providers.key('cc-api'), 'sk-cccode');
});

test('closing login window before refresh token leaves existing config unchanged', () async {
  final connector = makeConnector(loginRefreshToken: null);
  expect(await connector.connect(), isFalse);
  expect(connector.providers.provider('cc-api'), isNull);
});

test('model refresh failure preserves the previous provider models', () async {
  final connector = makeConnector(
    existingModels: const [ProviderModel(id: 'claude-sonnet-4-5')],
    modelError: const UpstreamException('offline'),
  );

  expect(await connector.refresh(), isFalse);
  expect(connector.providers.provider('cc-api')!.models.single.id,
      'claude-sonnet-4-5');
});
```

The test helper must inject all external behavior; no test may call the real CC API or open a real native window.

- [ ] **Step 2: Run the new test file and verify it fails**

Run:

```bash
flutter test test/models/cc_api_connector_test.dart
```

Expected: FAIL because the connector contracts and implementation do not exist yet.

- [ ] **Step 3: Define the smallest data contracts**

Create the enum, store interface, connector constructor dependencies, and result/status types. The connector must accept injected `LoginWindowOpener`, `AccountSend`, `ModelProviders`, `CcApiStore`, and `ModelLister` functions so unit tests can run without platform plugins or network access.

- [ ] **Step 4: Run the test file again**

Run the same command. Expected: the tests compile and fail at the unimplemented connection behavior, not at missing symbols or invalid test setup.

---

### Task 2: Implement CC API session storage and account synchronization

**Files:**
- Modify: `lib/models/cc_api_store.dart`
- Modify: `lib/models/cc_api_connector.dart`
- Modify: `lib/channel/account/sub2api_adapter.dart` if a shared constructor/helper is required
- Test: `test/models/cc_api_connector_test.dart`
- Test: `test/channel/account_test.dart`

**Interfaces:**
- Use `SecretStore` key `cc-api.session` for the refresh token.
- Use global storage keys `cc-api.account` and `cc-api.provider-key` only for non-secret metadata; never write the full token or API key there.
- `CcApiConnector` must use `ProviderProtocol.anthropic`, `baseUrl: 'https://api.cc-hub.vip'`, `id: 'cc-api'`, and `name: 'CC API'`.

- [ ] **Step 1: Add adapter tests for CC API’s Sub2API endpoints**

Extend the existing Sub2API fake transport tests with these expected requests:

```text
POST https://api.cc-hub.vip/api/v1/auth/refresh
GET  https://api.cc-hub.vip/api/v1/auth/me
GET  https://api.cc-hub.vip/api/v1/keys?page=1&page_size=100
GET  https://api.cc-hub.vip/api/v1/keys/7
POST https://api.cc-hub.vip/api/v1/keys
GET  https://api.cc-hub.vip/api/v1/groups/available
```

Assert that refresh token rotation is persisted, 401 clears the adapter credential, and API keys never appear in thrown error strings.

- [ ] **Step 2: Run the focused adapter tests and verify the new assertions fail**

Run:

```bash
flutter test test/channel/account_test.dart --plain-name 'Sub2ApiAdapter'
```

Expected: existing behavior passes, while any new CC API-specific persistence/selection assertions fail until the connector is implemented.

- [ ] **Step 3: Implement `CcApiStore` with SecretStore-backed session persistence**

Use the same error-handling style as `GlobalChannelAccountStore`: catch `SecretStoreException`, log only the storage key and error type, and treat unreadable credentials as signed out. Keep metadata in global storage and use `cc-api.session` only for the refresh token.

- [ ] **Step 4: Implement login polling**

Open `https://api.cc-hub.vip/login` with the injected `LoginWindow`. Poll `localStorage.getItem('refresh_token')` once per second until a value is returned or the window closes. Close the window after success. If the window closes first, return `false` without changing Provider state.

- [ ] **Step 5: Implement key selection and creation**

Use the existing Sub2API adapter. Select the current Provider key if it still appears in `/keys`; otherwise select the newest key named `CCCode`, then the newest returned key. If no key exists, call the adapter’s `create('CCCode')`, which prefers an Anthropic group and falls back to the first available group.

- [ ] **Step 6: Implement Provider/model synchronization**

Reveal the selected key, call the injected `ModelLister` with a Provider configured for CC API, merge with existing models using `mergeModelList`, enable newly returned chat models, save the Provider, save the key through `ModelProviders.setKey`, and set `models.default` only when the existing default is absent or no longer resolves.

Use the existing default-selection rule in a dedicated private helper: choose the first model whose lowercase ID contains `sonnet`, then `claude`, then the first non-image model. Never choose an image-only model as the default conversation model.

- [ ] **Step 7: Preserve old state on synchronization errors**

Wrap refresh, key retrieval, and model listing so a failure returns `false`, updates connector status/error, and leaves the previous `cc-api` Provider, model list, API key, and default model untouched. Only clear the refresh session on a confirmed 401/403 from the account API.

- [ ] **Step 8: Run focused connector and adapter tests**

Run:

```bash
flutter test test/channel/account_test.dart --plain-name 'Sub2ApiAdapter'
flutter test test/models/cc_api_connector_test.dart
```

Expected: PASS for login cancellation, successful synchronization, token rotation, expired session, default model selection, and failed refresh preservation.

---

### Task 3: Add the CC API card and model-page wiring

**Files:**
- Create: `lib/settings/pages/cc_api_card.dart`
- Modify: `lib/settings/pages/models_page.dart`
- Modify: `lib/main.dart` only if the connector needs application-level construction/wiring
- Modify: `test/settings/models_page_test.dart`

**Interfaces:**
- `CcApiCard({required CcApiConnector connector, required VoidCallback onChanged})`
- The card consumes `connector.status`, `connector.providers.provider('cc-api')`, and `connector.refresh/connect`.
- The card must not open an external browser; it uses the existing `ChannelLoginWindow` implementation.

- [ ] **Step 1: Add widget tests for all card states**

Add tests that pump `ModelsSettingsPage` with a fake connector and assert:

```dart
expect(find.text('CC API'), findsOneWidget);
expect(find.text('Claude、GPT、Gemini 一键接入'), findsOneWidget);
```

Cover unconnected (`登录 CC API`), connecting (disabled action), connected (`已连接 · 1 个模型`), needs login, and failed refresh. Verify external featured cards remain present and their tap callback still receives their original URL.

- [ ] **Step 2: Run the focused settings tests and verify the new tests fail**

Run:

```bash
flutter test test/settings/models_page_test.dart
```

Expected: FAIL because the fixed card and connector injection are not wired yet.

- [ ] **Step 3: Implement the card using existing settings components**

Match `FeaturedUpstreamsStrip` dimensions and existing hover/click behavior. Use the CCCode Logo asset, a disabled/spinning `IdeButton` or card action while connecting, and localized status text. Keep the card fixed at the start of the row; the existing remote cards remain scrollable after it.

- [ ] **Step 4: Wire a default connector into `ModelsSettingsPage`**

Add an optional connector parameter for tests and construct the production connector from `ModelProviders.current`, `GlobalStorage`, `SecretStore`, `ChannelLoginWindow.new`, `sendToAccountSite`, and `listUpstreamModels`. Do not trigger network traffic or login in `initState`; only run the connector when the user clicks the card or when an already-connected card is explicitly refreshed.

- [ ] **Step 5: Refresh the settings page after connection**

After a successful connection, notify the page, keep the models list visible, and ensure the default-model dropdown resolves `cc-api/<model-id>`. On failure, keep the prior Provider row and show the connector error without closing Settings.

- [ ] **Step 6: Run focused widget tests**

Run:

```bash
flutter test test/settings/models_page_test.dart
```

Expected: PASS for all card states and unchanged external featured-card behavior.

---

### Task 4: Add localization and Logo resources

**Files:**
- Add/modify: `assets/branding/cccode_logo.svg`
- Add/modify: `assets/branding/cccode_icon.png` and platform icon variants
- Modify: `pubspec.yaml` asset declarations without changing `name: cccode`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_zh.arb`, generated localization output if checked in
- Modify: `test/l10n_test.dart` or a focused new resource test

- [ ] **Step 1: Copy and validate the source SVG**

Copy the user-provided SVG into the repository as `assets/branding/cccode_logo.svg`. Validate it is well-formed XML and retains the four source colors. Do not execute SVG contents as code.

- [ ] **Step 2: Add exact localization keys**

Add English and Chinese entries for:

```text
modelsCcApiName
modelsCcApiDescription
modelsCcApiSignIn
modelsCcApiConnecting
modelsCcApiConnected
modelsCcApiNeedsLogin
modelsCcApiRefreshFailed
modelsCcApiUnavailable
```

Use `CC API` as the name in both languages and `Claude、GPT、Gemini 一键接入` / `One-click access to Claude, GPT and Gemini` as the card descriptions.

- [ ] **Step 3: Generate or update platform icon variants**

Use the repository’s existing icon-generation path to create the PNG/ICNS/ICO resources from the CCCode SVG. Keep all generated files under tracked branding/icon directories and update the asset manifest without changing the Dart package name.

- [ ] **Step 4: Run localization and resource tests**

Run:

```bash
flutter test test/l10n_test.dart
```

Expected: PASS with all new English and Chinese keys resolved and the SVG asset loadable.

---

### Task 5: Replace CCCode platform/runtime branding without changing Dart package imports

**Files:**
- Modify: all files returned by the exact search command below, excluding `pubspec.yaml` and Dart import strings that begin with `package:baocode/`.
- Test: add `test/branding/cccode_identity_test.dart` or a shell validation under `tool/`.

- [ ] **Step 1: Generate the replacement inventory**

Run:

```bash
rg -l --hidden --glob '!.git/**' --glob '!pubspec.lock' 'CCCode|cccode|CCCODE' . | sort
```

Review every result and classify each match as one of: user-visible product text, runtime identifier, URL/domain, package import, historical documentation, or external dependency. Only package imports remain unchanged; the CCCode fork’s shipped docs, site, scripts, platform runners, and runtime strings change to CCCode values.

- [ ] **Step 2: Replace runtime identifiers in native runners**

Change native method channels, data/log paths, app titles, mutex/settings keys, URL schemes, browser native messaging host names, installer switches, and registry identifiers consistently to `cccode`. Keep the method names and request markers semantically identical so Dart/native behavior does not change beyond the identifier strings.

- [ ] **Step 3: Replace build and packaging names**

Update macOS, Windows, and Linux build scripts so bundle names, executable names, installer names, desktop entries, icons, and product metadata use CCCode. Update the Windows installer script filename/references if it remains named `cccode.iss`; no `cccode.exe`, `vip.cchub.cccode`, or `cccode://` values may remain in shipped platform configuration.

- [ ] **Step 4: Replace browser extension branding**

Update extension manifests, locale strings, native host names, help URLs, tab-group labels, and packaging output names to CCCode. Keep the bridge protocol behavior unchanged.

- [ ] **Step 5: Replace shipped docs/site branding**

Update README files, site labels, screenshots’ surrounding copy, changelog generators, installer copy, and release helper comments/URLs to say CCCode. Remove `the website`, `dl.baocode.dev`, and `github.com/chenxiTagGH/CCCode` links from shipped fork content; use relative links or the user’s CCCode repository URL only when it is already configured in the fork. Do not alter `package:baocode/...` Dart imports or package resolution.

- [ ] **Step 6: Verify no forbidden runtime CCCode identifiers remain**

Run:

```bash
rg -n --hidden --glob '!.git/**' --glob '!pubspec.lock' \
  'CCCode|CCCODE|cccode://|dev\.cccode\.desktop|cccode\.exe|package:baocode/' .
```

Expected: only the intentionally preserved `package:baocode/...` imports and any explicitly documented third-party/upstream references remain; no user-visible or runtime platform identifier remains.

---

### Task 6: Update URL scheme and platform registration tests

**Files:**
- Modify: `lib/models/upstream_import.dart` and related URL handling only where the scheme is currently hard-coded as `cccode`.
- Modify: `lib/platform/open_requests.dart`, `lib/window/code_args.dart` comments/constants if required by the new scheme.
- Modify: `macos/Runner/Info.plist`, `macos/Runner/AppDelegate.swift`, `windows/runner/open_requests.*`, `tool/cccode.iss`, and Linux registration files.
- Test: `test/models/upstream_import_test.dart`, `test/platform/open_requests_test.dart` if present, and a new focused scheme assertion if needed.

- [ ] **Step 1: Change the canonical scheme to `cccode`**

Update `UpstreamImport.scheme` and every native URL registration/command-line flag that carries the scheme. Keep query parsing and import validation behavior unchanged.

- [ ] **Step 2: Update scheme tests**

Change existing import-link fixtures from `cccode://provider/import?...` to `cccode://provider/import?...` and add an assertion that `UpstreamImport.parse('cccode://provider/import?...')` returns `null`.

- [ ] **Step 3: Run focused scheme tests**

Run:

```bash
flutter test test/models/upstream_import_test.dart
```

Expected: PASS with only `cccode://` accepted.

---

### Task 7: Final targeted verification and handoff

**Files:**
- Modify only files required by failures from Tasks 1–6.

- [ ] **Step 1: Run formatter on changed Dart files**

Run:

```bash
dart format lib/models/cc_api_connector.dart lib/models/cc_api_store.dart \
  lib/settings/pages/cc_api_card.dart lib/settings/pages/models_page.dart \
  test/models/cc_api_connector_test.dart test/settings/models_page_test.dart
```

- [ ] **Step 2: Run targeted analyzer**

Run:

```bash
flutter analyze lib/models/cc_api_connector.dart lib/models/cc_api_store.dart \
  lib/settings/pages/cc_api_card.dart lib/settings/pages/models_page.dart
```

Expected: no errors in changed Dart files.

- [ ] **Step 3: Run only related tests**

Run:

```bash
flutter test \
  test/models/cc_api_connector_test.dart \
  test/channel/account_test.dart \
  test/settings/models_page_test.dart \
  test/models/upstream_import_test.dart \
  test/l10n_test.dart
```

Expected: PASS. Do not run the full repository test suite.

- [ ] **Step 4: Run final identity and secret-safety checks**

Run:

```bash
rg -n --hidden --glob '!.git/**' --glob '!pubspec.lock' \
  'ANTHROPIC_AUTH_TOKEN|ANTHROPIC_API_KEY|refresh_token|Authorization: Bearer' \
  lib/models/cc_api_connector.dart lib/models/cc_api_store.dart
```

Review output manually: secret names may appear in code paths that read/write them, but no debug print, exception text, test snapshot, or user-facing label may contain a secret value.

- [ ] **Step 5: Report verification truthfully**

Summarize changed files, targeted tests run, analyzer output, any platform builds not run due to local tool availability, and any remaining manual checks. Do not claim full-suite or release-build success unless those commands were actually run.
