import 'package:baocode/settings/pages/general_page.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rejects attribution emails without a basic email shape', () {
    expect(GeneralSettingsPage.validAttributionEmail('name@example.com'), isTrue);
    expect(GeneralSettingsPage.validAttributionEmail('not-an-email'), isFalse);
    expect(GeneralSettingsPage.validAttributionEmail('name@example'), isFalse);
  });
}
