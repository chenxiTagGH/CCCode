# Task 3 report: CC API balance and wider card

## Status
Implemented Task 3 and follow-up review fixes. The CC API model card is wider when space permits, shrinks responsively in narrow layouts, and displays the latest account balance from existing non-secret account metadata. Positive, zero, missing, in-flight refresh, failed refresh, stale balance, semantics, metadata ordering, and secret-boundary coverage were added.

## Commits
- `127f4bb87b0e7918130cb0a1e96031058e3b17d7` — `feat: show CC API balance in model card`
- Follow-up review fixes are committed separately after this report update.
- Both commits include `Co-Authored-By: Claude Code <noreply@anthropic.com>`.

## Review fixes
- The fake connector now awaits a pending refresh result and transitions to failed/returns false when completion is unsuccessful; the stale-balance test asserts the failed detail and unchanged balance.
- Semantics includes the rendered balance/status detail when a balance exists.
- Currency symbol and balance/status formatting are localization contract entries; the card no longer hardcodes `$`. The account balance remains explicitly USD in l10n metadata.
- The card width is clamped to both parent constraints and available screen width, with a minimum usable width, avoiding fixed-width overflow.
- Status detail is preserved and balance appended, such as `暂时无法连接 · 余额 $8.50` or `已连接 · 余额 $12.50`.

## Files changed
- `/Users/tangchenxi/Desktop/Chenxi/vibeCoding/CCCode/lib/models/cc_api_connector.dart`
  - Added `CcApiConnector.accountBalance`, reading only `store.readState()['account']['balance']`.
  - Does not expose session tokens or whole API keys.
- `/Users/tangchenxi/Desktop/Chenxi/vibeCoding/CCCode/lib/settings/pages/cc_api_card.dart`
  - Widened the CC API card from 196px to 248px when room permits.
  - Clamps width for narrow layouts.
  - Displays localized currency and preserves status detail while appending the last known balance.
  - Includes the balance in the semantics label.
- `/Users/tangchenxi/Desktop/Chenxi/vibeCoding/CCCode/lib/l10n/app_en.arb`
- `/Users/tangchenxi/Desktop/Chenxi/vibeCoding/CCCode/lib/l10n/app_zh.arb`
- `/Users/tangchenxi/Desktop/Chenxi/vibeCoding/CCCode/lib/l10n/app_localizations.dart`
- `/Users/tangchenxi/Desktop/Chenxi/vibeCoding/CCCode/lib/l10n/app_localizations_en.dart`
- `/Users/tangchenxi/Desktop/Chenxi/vibeCoding/CCCode/lib/l10n/app_localizations_zh.dart`
  - Added localized currency symbol, amount formatter, and status-with-balance formatter.
- `/Users/tangchenxi/Desktop/Chenxi/vibeCoding/CCCode/test/settings/models_page_test.dart`
  - Added widget coverage for positive, zero, missing, in-flight, failed-refresh stale balances, and semantics.
  - Fake connector now models failed pending refresh completion.
- `/Users/tangchenxi/Desktop/Chenxi/vibeCoding/CCCode/test/models/cc_api_connector_test.dart`
  - Verifies successful synchronization commits account balance metadata before consumers rebuild.
  - Verifies metadata contains no access token or whole API key.
  - Verifies failed model refresh preserves the previous account balance.

## Commands and results

### Focused Flutter tests
- `flutter test test/settings/models_page_test.dart --plain-name 'CC API card shows localized positive and zero balances'`
- `flutter test test/models/cc_api_connector_test.dart`
- Follow-up: `flutter test test/settings/models_page_test.dart --plain-name 'CC API card omits a missing balance and keeps stale balance'`
- Result for all: could not start; exit code `127`, shell reported `command not found: flutter`.

Flutter/Dart were unavailable in the environment, so no test pass is claimed.

### Static and repository checks
- `git diff --check`: passed with no output.
- `ruby -rjson -e 'ARGV.each { |path| JSON.parse(File.read(path)); puts "valid #{path}" }' lib/l10n/app_en.arb lib/l10n/app_zh.arb`: both ARB files parsed successfully.
- `rg -n 'modelsCcApiBalance\\b|modelsCcApiCurrencySymbol|modelsCcApiBalanceAmount|modelsCcApiDetailWithBalance' lib test`: localization interface and implementations are consistently wired.
- Post-commit `git status --short`: clean after the follow-up commit.

## Concerns
- Focused Flutter tests and formatter could not be executed because the Flutter SDK is not installed or on `PATH`.
- Generated localization Dart files were updated consistently with the ARB entries manually because `flutter gen-l10n` was unavailable.
- No secrets are read by the card or exposed by `accountBalance`; whole API key and session values remain in their existing secret/storage paths.
