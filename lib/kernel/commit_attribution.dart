/// Who the commits and pull requests an agent writes credit: the
/// `chat.commitAttribution` setting. Read as each agent starts, so a change
/// applies to the agents started after it.
typedef CommitAttributionValue = ({String name, String email});

enum CommitAttribution {
  /// CCCode: a `Co-Authored-By` trailer for its GitHub account, and a line
  /// naming it under a pull request.
  cccode,

  /// What the agent adds of its own (Claude Code: itself), as its own
  /// settings have it.
  agent,

  /// None.
  none;

  static const settingKey = 'chat.commitAttribution';
  static const nameSettingKey = 'chat.commitAttributionName';
  static const emailSettingKey = 'chat.commitAttributionEmail';

  /// When the setting is unset, or not one of these.
  static const fallback = cccode;
  static const defaultName = 'CCCode';
  static const defaultEmail = 'noreply@ccapitoken.cc';

  static final _emailPattern = RegExp(
    r'^[A-Za-z0-9.!#$%&*+/=?^_`{|}~-]+@'
    r'[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?'
    r'(?:\.[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$',
  );
  static final _controlCharacters = RegExp(r'[\p{Cc}\p{Cf}]', unicode: true);

  /// The current CCCode commit trailer, resolved from the active settings.
  static String get baoCodeCommit => currentCommitTrailer();
  static const baoCodePullRequest =
      '🤖 Generated with [CCCode](https://github.com/chenxiTagGH/CCCode)';

  static CommitAttribution parse(Object? setting) =>
      values.where((value) => value.name == setting).firstOrNull ?? fallback;

  static bool isValidEmail(String value) => _emailPattern.hasMatch(value.trim());

  static bool isValidName(String value) {
    final trimmed = value.trim();
    return trimmed.isNotEmpty && !_controlCharacters.hasMatch(trimmed);
  }

  static CommitAttributionValue normalized(Map<String, Object?> settings) {
    final name = switch (settings[nameSettingKey]) {
      final String value when isValidName(value) => value.trim(),
      _ => defaultName,
    };
    final email = switch (settings[emailSettingKey]) {
      final String value when value.trim().isEmpty => defaultEmail,
      final String value when isValidEmail(value) => value.trim(),
      _ => defaultEmail,
    };
    return (name: name, email: email);
  }

  static String commitTrailer(Map<String, Object?> settings) {
    final value = normalized(settings);
    return 'Co-Authored-By: ${value.name} <${value.email}>';
  }

  static String currentCommitTrailer() {
    final value = currentValue();
    return 'Co-Authored-By: ${value.name} <${value.email}>';
  }

  /// The setting as it is now; main() points it at settings.json.
  static CommitAttribution Function() current = () => fallback;

  /// The normalized CCCode name and email; main() points it at settings.json.
  static CommitAttributionValue Function() currentValue =
      () => (name: defaultName, email: defaultEmail);
}
