# Task 3 report: CC API balance and wider card

## Status
Implemented Task 3 and final coordinator sign-out fixes. The CC API model card is responsive down to ultra-narrow parent widths, displays non-secret account balance metadata, preserves stale balance through refresh/failure and incomplete profiles, and cannot show stale balance after implicit or explicit sign-out—even when persistence cleanup fails.

## Final sign-out fixes
- Added shared signed-out handling that invalidates the in-memory account state and sets the target disconnected/needs-login status before any cleanup I/O.
- Explicit `signOut()` now invalidates balance and disconnects before remote/storage/provider cleanup; all cleanup attempts continue independently.
- Cleanup errors retain the first/root error rather than being overwritten by later provider-removal errors.
- `_accountStateInvalidated` is cleared only after a synchronization fully commits; failed reconnects cannot reveal old persisted metadata.
- Added regressions for failed metadata cleanup, explicit sign-out state safety, and failed reconnect after invalidation.

## Latest commit
- Follow-up commit includes `Co-Authored-By: Claude Code <noreply@anthropic.com>`.

## Relevant files
- `/Users/tangchenxi/Desktop/Chenxi/vibeCoding/CCCode/lib/models/cc_api_connector.dart`
- `/Users/tangchenxi/Desktop/Chenxi/vibeCoding/CCCode/lib/settings/pages/cc_api_card.dart`
- `/Users/tangchenxi/Desktop/Chenxi/vibeCoding/CCCode/lib/settings/pages/featured_upstreams_strip.dart`
- `/Users/tangchenxi/Desktop/Chenxi/vibeCoding/CCCode/test/models/cc_api_connector_test.dart`
- `/Users/tangchenxi/Desktop/Chenxi/vibeCoding/CCCode/test/settings/models_page_test.dart`
- `/Users/tangchenxi/Desktop/Chenxi/vibeCoding/CCCode/.superpowers/sdd/task-3-report.md`

## Commands and results
- `git diff --check`: passed with no output.
- `ruby -rjson -e 'ARGV.each { |path| JSON.parse(File.read(path)); puts "valid #{path}" }' lib/l10n/app_en.arb lib/l10n/app_zh.arb`: both ARB files parsed successfully.
- Targeted symbol inspection confirmed invalidation lifecycle, first-error retention, pre-cleanup disconnect, and regressions are wired.
- Flutter tests were not rerun because Flutter remains unavailable (`flutter: command not found`, exit code 127 in prior focused runs).

Flutter/Dart were unavailable, so no test pass is claimed.

## Concerns
- Flutter tests and formatter could not execute because Flutter is not installed or on `PATH`.
- Generated localization Dart files remain manually synchronized because `flutter gen-l10n` was unavailable.
