# CCCode 任务进度与品牌设置 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement structured task progress plus CCCode branding, settings, Bark notifications, visible-domain migration, CC API balance, and sidebar logo.

**Architecture:** Reuse existing Workspace/AgentThread/kernel lifecycle as the execution source. Add a small task-plan state/controller and presentation layer, with persistence independent of execution success. Extend existing settings stores and l10n rather than introducing parallel configuration systems. Keep internal release/CDN URLs separate from user-facing website URLs through explicit constants.

**Tech Stack:** Flutter/Dart, existing settings JSONC storage, Flutter widgets, platform notification host, existing localization generation, existing tests.

## Global Constraints

- Keep `package:baocode/...` and Dart package name `baocode`.
- Auto-start the generated plan; no confirmation gate before step one.
- First release supports one current Agent and sequential steps only.
- Pause lets the current command finish; it does not start the next step.
- Stop requires confirmation and preserves completed steps.
- Bark failures never block Agent execution or system notifications.
- Visible website URLs migrate to `ccapitoken.cc`; internal CDN/update/CI/release URLs stay unchanged.
- After changing code, run only related tests; report unavailable Flutter/Dart honestly.

---

### Task 1: Theme and commit-attribution migration

**Files:**
- Modify: `lib/theme/workbench_theme.dart`
- Modify: `lib/kernel/commit_attribution.dart`
- Modify: `lib/settings/pages/general_page.dart`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_zh.arb`
- Regenerate: `lib/l10n/app_localizations.dart`, `app_localizations_en.dart`, `app_localizations_zh.dart`
- Test: `test/theme/workbench_theme_test.dart`, `test/settings/general_page_test.dart`, `test/kernel/commit_attribution_test.dart`

**Interfaces:**
- Keep `CommitAttribution` enum options `cccode`, `agent`, `none`.
- Add persisted custom attribution fields under `chat.commitAttributionName` and `chat.commitAttributionEmail`.
- Expose a normalized attribution value used by transport, defaulting to `CCCode` and `noreply@ccapitoken.cc`.

- [ ] Add failing tests for Bao theme migration, default/custom attribution and invalid email rejection.
- [ ] Implement `CC Light`/`CC Dark` defaults and migrate both old and new names.
- [ ] Extend General settings with editable name/email fields while retaining dropdown options.
- [ ] Update `CommitAttribution.baoCodeCommit` generation to use normalized custom values and new email.
- [ ] Add l10n in English/Chinese and regenerate generated localization files.
- [ ] Run focused theme/settings/attribution tests and `dart format` on touched Dart files.
- [ ] Commit with `feat: customize CCCode attribution and theme names`.

---

### Task 2: Bark notification integration

**Files:**
- Modify: `lib/notifications/attention_settings.dart`
- Modify: `lib/notifications/attention_service.dart`
- Modify: `lib/settings/pages/notifications_page.dart`
- Add: `lib/notifications/bark_notifier.dart`
- Modify: `lib/l10n/app_en.arb`, `lib/l10n/app_zh.arb` and generated files
- Test: `test/notifications/attention_service_test.dart`, `test/notifications/bark_notifier_test.dart`, `test/settings/notifications_page_test.dart`

**Interfaces:**
- Persist one optional `notifications.barkUrl` string.
- `BarkNotifier.send(Uri base, {required String title, required String body})` returns `Future<void>` and swallows/logs its own network failure without throwing to Agent code.

- [ ] Add tests for empty URL skip, URL encoding, successful send and failure isolation.
- [ ] Add URL field to attention settings normalization and notifications settings UI.
- [ ] Implement a bounded HTTP request with encoded title/body and no secret logging.
- [ ] Call Bark alongside existing `host.notify` for enabled needs-input/finished events.
- [ ] Run focused notification/settings tests and formatting.
- [ ] Commit with `feat: add configurable Bark notifications`.

---

### Task 3: CC API balance and wider card

**Files:**
- Modify: `lib/settings/pages/cc_api_card.dart`
- Modify: `lib/settings/pages/models_page.dart` if card width layout requires it
- Modify: l10n ARB and generated files
- Test: `test/settings/models_page_test.dart`, `test/models/cc_api_connector_test.dart`

**Interfaces:**
- Read account balance from `CcApiStore` state (`account.balance`) without exposing account secrets.
- Preserve stale balance while refresh is in flight or fails.

- [ ] Add widget tests for positive, zero, missing and stale balances.
- [ ] Add a wider card width and localized balance formatter.
- [ ] Ensure connector state updates account metadata before card rebuilds and stale values are retained on failure.
- [ ] Run focused model-page/connector tests and formatting.
- [ ] Commit with `feat: show CC API balance in model card`.

---

### Task 4: Visible domain migration and sidebar logo

**Files:**
- Modify only user-facing URL definitions in README translations, About page, docs/site links, featured feed/join URLs and l10n.
- Keep internal release/update/CDN URLs unchanged.
- Modify: sidebar widget file identified from `lib/sidebar/` and app navigation/About route.
- Test: `test/l10n_test.dart`, About/sidebar tests, targeted URL tests.

**Interfaces:**
- Define a single visible website origin constant `https://ccapitoken.cc` for user-facing links.
- Use existing `assets/branding/cccode_logo.svg` for sidebar branding.

- [ ] Inventory all `baocode.dev` occurrences and classify visible versus internal before editing.
- [ ] Add tests that visible URLs use `ccapitoken.cc` and internal release endpoints remain unchanged.
- [ ] Update visible links and docs; do not mass-replace internal infrastructure URLs.
- [ ] Add the clickable logo to the bottom of the main sidebar, with tooltip and About navigation.
- [ ] Run targeted URL/l10n/sidebar tests and static scans.
- [ ] Commit with `feat: update visible CCCode branding and website links`.

---

### Task 5: Task plan domain model and persistence

**Files:**
- Add: `lib/tasks/task_plan.dart`
- Add: `lib/tasks/task_plan_controller.dart`
- Add: `lib/tasks/task_plan_store.dart`
- Modify: Workspace/AgentThread integration files after inspecting lifecycle seam
- Test: `test/tasks/task_plan_test.dart`, `test/tasks/task_plan_store_test.dart`

**Interfaces:**
- `enum TaskPlanStatus { pending, running, completed, failed, paused, cancelled }`.
- `enum TaskStepStatus { pending, running, completed, failed, paused, cancelled }`.
- Immutable JSON-safe `TaskPlan`/`TaskStep` with title, estimate, timestamps, elapsed and error.
- Controller methods: `create`, `start`, `completeStep`, `failStep`, `pause`, `resume`, `cancel`, `retryFailed`.

- [ ] Write model transition tests including elapsed-time injection through a clock callback.
- [ ] Implement immutable model serialization and tolerant restoration.
- [ ] Implement controller transitions; pause blocks next step, resume skips completed steps, retry resets only failed step.
- [ ] Implement best-effort persistence that never throws into Agent execution.
- [ ] Integrate with current Agent session lifecycle without replacing kernel execution.
- [ ] Run focused task-domain tests and formatting.
- [ ] Commit with `feat: add task plan state model`.

---

### Task 6: Task-plan extraction and automatic execution projection

**Files:**
- Modify: existing chat/kernel turn lifecycle seam identified in Task 5
- Add/modify: task-plan parser/adapter
- Test: `test/tasks/task_plan_execution_test.dart`

**Interfaces:**
- Parse only validated structured plan data; on parse failure return null and leave ordinary chat unchanged.
- Start step one automatically after a valid plan is accepted.
- Map real Agent/kernel events to step transitions; do not invent completion from timers.

- [ ] Add tests for valid plan, malformed plan fallback, automatic start and failure pause.
- [ ] Implement parser/adapter and connect it to the existing Agent execution lifecycle.
- [ ] Ensure ordinary messages with no plan have no task-plan UI/state.
- [ ] Run focused execution projection tests.
- [ ] Commit with `feat: auto-start structured agent task plans`.

---

### Task 7: Task-plan compact status and right drawer UI

**Files:**
- Add: `lib/tasks/task_plan_indicator.dart`
- Add: `lib/tasks/task_plan_drawer.dart`
- Modify: main workspace/window overlay composition
- Modify: l10n ARB and generated files
- Test: `test/tasks/task_plan_widgets_test.dart`

**Interfaces:**
- Indicator consumes a `ValueListenable<TaskPlan?>` and exposes tap/open callback.
- Drawer consumes the same plan/controller and emits pause/resume/cancel/retry actions.

- [ ] Add widget tests for all statuses, estimates, elapsed time, drawer opening and controls.
- [ ] Place compact indicator in the upper-right workspace toolbar without covering existing controls.
- [ ] Implement 320–380px right drawer, 1–2 second initial reveal, failure keep-open behavior.
- [ ] Add confirmation dialog for stop and localized labels.
- [ ] Run focused task widget tests and formatting.
- [ ] Commit with `feat: add task plan progress UI`.

---

### Task 8: Integrated verification and release readiness

**Files:**
- No changes unless verification finds a defect.

- [ ] Run all directly related tests for tasks 1–7.
- [ ] Run `dart format` on all touched Dart files and `git diff --check`.
- [ ] Run static scans for stale visible `baocode.dev`, `Bao Light`, `Bao Dark`, and old attribution defaults.
- [ ] Confirm internal CDN/update/CI URLs remain unchanged.
- [ ] If Flutter/Dart is unavailable, record exact failures and use CI for compilation.
- [ ] Review final diff and commit any verification fixes.
