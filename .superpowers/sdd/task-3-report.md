# Task 3 report: CC API balance and wider card

## Status
Implemented Task 3 and final coordinator state-machine fixes. The CC API model card is responsive down to ultra-narrow parent widths, displays non-secret account balance metadata, preserves stale balance through refresh/failure and incomplete profiles, and cannot show stale balance after implicit or explicit sign-out or a missing-session refresh.

## Final state-machine fixes
- Added an epoch/generation guard to `_synchronize`; sign-out invalidates the epoch, and an in-flight synchronization aborts before committing provider, session, metadata, or connected status.
- Explicit `signOut()` invalidates state and sets disconnected before `readSession`, so read failures cannot leave the provider or balance visible.
- Refresh with no session now runs signed-out cleanup and clears stale provider/account state before returning needs-login.
- Reconnects after invalidation do not merge persisted prior balance when the new profile omits balance; only a new numeric profile balance restores account state.
- The card only infers connected from provider models when connector error is clear, and explicit needs-login/disconnected status takes precedence.
- Added concurrency, missing-session, and stale-state regressions.

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
- Targeted symbol inspection confirmed epoch guards, pre-read invalidation, missing-session cleanup, balance merge rules, and card status precedence.
- Flutter tests were not rerun because Flutter remains unavailable (`flutter: command not found`, exit code 127 in prior focused runs).

Flutter/Dart were unavailable, so no test pass is claimed.
