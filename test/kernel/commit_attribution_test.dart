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

  test('rejects malformed email values and falls back to default', () {
    for (final email in [
      'not-an-email',
      'name<>@example.com',
      'name,other@example.com',
    ]) {
      expect(CommitAttribution.isValidEmail(email), isFalse);
      expect(
        CommitAttribution.normalized({
          CommitAttribution.emailSettingKey: email,
        }).email,
        'noreply@ccapitoken.cc',
      );
    }
  });

  test('rejects control characters in custom names', () {
    expect(CommitAttribution.isValidName('Ada\nLovelace'), isFalse);
    expect(
      CommitAttribution.commitTrailer({
        CommitAttribution.nameSettingKey: 'Ada\nLovelace',
      }),
      'Co-Authored-By: CCCode <noreply@ccapitoken.cc>',
    );
  });

  test('transport trailer uses the current custom attribution', () {
    CommitAttribution.currentValue =
        () => (name: 'Custom Name', email: 'custom@example.com');
    addTearDown(() {
      CommitAttribution.currentValue =
          () => (name: CommitAttribution.defaultName,
              email: CommitAttribution.defaultEmail);
    });
    expect(
      CommitAttribution.currentCommitTrailer(),
      'Co-Authored-By: Custom Name <custom@example.com>',
    );
  });

  test('clearing custom email restores the default', () {
    expect(
      CommitAttribution.normalized({
        CommitAttribution.emailSettingKey: '',
      }).email,
      'noreply@ccapitoken.cc',
    );
  });
}
