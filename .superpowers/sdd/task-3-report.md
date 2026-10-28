# Task 3 report: CC API balance and wider card

## Status
Implemented Task 3 and final concurrency barrier fixes. The CC API card remains responsive and explicit-status driven. All active connect/refresh operations are tracked and awaited before either automatic or explicit sign-out cleanup, preventing stale writes from overlapping cleanup or a later reconnect.

## Latest concurrency fixes
- Track every active connect/refresh Future in a Set rather than only the latest operation.
- Sign-out cleanup waits in a loop until all operations started before invalidation have completed, including operations that were active concurrently.
- Automatic `_handleSignedOut()` uses the same signing-out lock and cleanup Future as explicit `signOut()`, waiting for other active operations while excluding its own caller operation to avoid self-deadlock; cleanup still invalidates state before writes.
- A fresh connect with no previous session invalidates persisted account metadata before synchronization, so an omitted profile balance cannot reuse the prior user's balance.
- New connect/refresh calls return false immediately while cleanup is active instead of registering and deadlocking the cleanup barrier.
- Stale catch handlers remain epoch guarded and cannot overwrite a newer disconnected or reconnecting state.
- Existing guards remain before provider/session/state/default commits, rollback writes, key creation/reveal, and connected status.

## Latest commit
- Follow-up commit includes `Co-Authored-By: Claude Code <noreply@anthropic.com>`.

## Relevant files
- `/Users/tangchenxi/Desktop/Chenxi/vibeCoding/CCCode/lib/models/cc_api_connector.dart`
- `/Users/tangchenxi/Desktop/Chenxi/vibeCoding/CCCode/lib/settings/pages/cc_api_card.dart`
- `/Users/tangchenxi/Desktop/Chenxi/vibeCoding/CCCode/test/models/cc_api_connector_test.dart`
- `/Users/tangchenxi/Desktop/Chenxi/vibeCoding/CCCode/test/settings/models_page_test.dart`
- `/Users/tangchenxi/Desktop/Chenxi/vibeCoding/CCCode/.superpowers/sdd/task-3-report.md`

## Commands and results
- `git diff --check`: passed with no output.
- `ruby -rjson -e 'ARGV.each { |path| JSON.parse(File.read(path)); puts "valid #{path}" }' lib/l10n/app_en.arb lib/l10n/app_zh.arb`: both ARB files parsed successfully.
- Targeted symbol inspection confirmed active-operation Set tracking, automatic/explicit cleanup lock sharing, wait-barrier looping, stale catch guards, and explicit card status.
- Flutter tests were not rerun because Flutter remains unavailable (`flutter: command not found`, exit code 127 in prior focused runs).

Flutter/Dart were unavailable, so no test pass is claimed.
