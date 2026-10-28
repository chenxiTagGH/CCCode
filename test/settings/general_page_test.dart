import 'package:baocode/settings/pages/general_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rejects attribution emails without a basic email shape', () {
    expect(GeneralSettingsPage.validAttributionEmail('name@example.com'), isTrue);
    expect(GeneralSettingsPage.validAttributionEmail(''), isTrue);
    expect(GeneralSettingsPage.validAttributionEmail('not-an-email'), isFalse);
    expect(GeneralSettingsPage.validAttributionEmail('name<>@example.com'), isFalse);
    expect(GeneralSettingsPage.validAttributionEmail('name,other@example.com'), isFalse);
    expect(GeneralSettingsPage.validAttributionEmail('name@example'), isFalse);
  });

  test('rejects attribution names with control characters but allows clear', () {
    expect(GeneralSettingsPage.validAttributionName('Ada Lovelace'), isTrue);
    expect(GeneralSettingsPage.validAttributionName('Ada\nLovelace'), isFalse);
    expect(GeneralSettingsPage.validAttributionName(''), isTrue);
  });
}
