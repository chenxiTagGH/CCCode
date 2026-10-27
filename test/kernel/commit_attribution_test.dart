import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/kernel/commit_attribution.dart';

void main() {
  test('normalizes default and custom CCCode attribution', () {
    expect(
      CommitAttribution.normalized({}),
      (name: 'CCCode', email: 'noreply@ccapitoken.cc'),
    );
    expect(CommitAttribution.normalized({
      CommitAttribution.nameSettingKey: '  Ada Lovelace ',
      CommitAttribution.emailSettingKey: 'ada@example.com',
    }), (name: 'Ada Lovelace', email: 'ada@example.com'));
  });

  test('rejects invalid custom email and falls back to default', () {
    expect(CommitAttribution.normalized({
      CommitAttribution.nameSettingKey: 'Custom',
      CommitAttribution.emailSettingKey: 'not-an-email',
    }), (name: 'Custom', email: 'noreply@ccapitoken.cc'));
  });
}
