# Task 2: Bark Notification Integration Report

## Status

Implemented and committed configurable Bark notifications, including URI hardening and focused test coverage follow-ups.

- Initial commit: `5bc16f264898c7323dd659641e758f925f22d8f0`
- URI validation commit: `5a7c04bbb0b572c4adf153329214e3ec4362e0a6`
- Malformed URI and diagnostics test commit: `2fc2b6280078f61d8dff43349a7841c2172bf661`
- Request/redirect/gating hardening commit: `82b4aec96e0c73328f0fd388e50bd8a009b02d0c`
- Final timeout/enabled-gating regression commit: recorded after commit creation
- Commit message: `feat: add configurable Bark notifications`
- Working tree after commit: clean

## Changes

- Added optional `notifications.barkUrl` parsing/normalization to `AttentionSettings`.
- Added a Bark URL text field to notification settings. A non-empty value is persisted; clearing it removes the optional setting.
- Added `BarkNotifier.send(Uri base, {required String title, required String body})`. It accepts only `http`/`https` bases with a host and no query or fragment, appends title/body through `Uri.replace(pathSegments: ...)` for correct segment encoding, disables redirects, bounds the full request and response-body drain to five seconds by default, and swallows failures. Failure logging contains only the error type or HTTP status, never the URL/key/title/body.
- Added `BarkNotifier.parseBase(String)` so raw malformed configured URL strings can be tested and rejected before dispatch.
- Integrated Bark dispatch alongside the existing `host.notify` for enabled attention events. Existing system notifications, sounds, and Agent execution flow remain in place. Service-level exception handling also isolates injected notifier failures.
- Added English and Chinese localization entries and updated generated localization APIs.
- Added tests for empty URL skip, encoded path segments, successful local HTTP response, unsupported schemes, query/fragment/missing-host rejection, raw malformed URI strings, redirects not being followed, response bodies that never complete, network failure isolation, diagnostics redaction, URL settings normalization/persistence, and AttentionService gates for disabled notifications/events with a configured URL, archived threads, and unfocused/in-view behavior.

## Files

- `lib/notifications/attention_settings.dart`
- `lib/notifications/attention_service.dart`
- `lib/notifications/bark_notifier.dart`
- `lib/settings/pages/notifications_page.dart`
- `lib/l10n/app_en.arb`
- `lib/l10n/app_zh.arb`
- `lib/l10n/app_localizations.dart`
- `lib/l10n/app_localizations_en.dart`
- `lib/l10n/app_localizations_zh.dart`
- `test/notifications/attention_service_test.dart`
- `test/notifications/bark_notifier_test.dart`
- `test/settings/notifications_page_test.dart`

## Commands and Results

- `command -v flutter || true; command -v dart || true`: neither executable was found (no output).
- `flutter test test/notifications/bark_notifier_test.dart test/notifications/attention_service_test.dart`: could not start; exit code 127, `command not found: flutter`.
- `flutter test test/notifications/attention_service_test.dart test/notifications/bark_notifier_test.dart test/settings/notifications_page_test.dart`: could not start; exit code 127, `command not found: flutter` (initial implementation verification).
- `flutter test test/notifications/bark_notifier_test.dart test/notifications/attention_service_test.dart test/settings/notifications_page_test.dart`: could not start; exit code 127, `command not found: flutter` (after URI validation fix).
- `flutter test test/notifications/bark_notifier_test.dart`: could not start; exit code 127, `command not found: flutter` (after malformed URI and diagnostics-redaction tests).
- `flutter test test/notifications/bark_notifier_test.dart test/notifications/attention_service_test.dart`: could not start; exit code 127, `command not found: flutter` (after response timeout, redirect, parser seam, and gating changes).
- `flutter test test/notifications/bark_notifier_test.dart test/notifications/attention_service_test.dart`: could not start; exit code 127, `command not found: flutter` (after stalled-response-body and configured-URL enabled=false regressions).
- `git diff --check`: passed with exit code 0 (no output).
- `git status --short` after commit: clean (no output).
- `git show --stat --oneline --summary HEAD`: confirmed commit `5bc16f26` with 12 files changed, 212 insertions and 7 deletions.

## Concerns / Verification Gaps

- Flutter/Dart formatting, analyzer, localization generation, and focused tests could not be run because the SDK executables are unavailable. No test pass is claimed.
- TDD tests were added before production implementation, but the RED run could not execute for the same missing-SDK reason; runtime RED/GREEN evidence is unavailable.
- The Bark URL contains its credential by design and is persisted in project `settings.json`; the UI describes this. Runtime logs do not include that URL or any request content.
