import 'dart:io';

/// Sends optional Bark notifications without affecting agent execution.
class BarkNotifier {
  const BarkNotifier({this.timeout = const Duration(seconds: 5)});

  final Duration timeout;

  /// Parses and validates a configured Bark base URL without making a request.
  static Uri? parseBase(String value) {
    final base = Uri.tryParse(value.trim());
    if (base == null ||
        (base.scheme != 'http' && base.scheme != 'https') ||
        base.host.isEmpty ||
        base.hasQuery ||
        base.hasFragment) {
      return null;
    }
    return base;
  }

  Future<void> send(
    Uri base, {
    required String title,
    required String body,
  }) async {
    final validated = parseBase(base.toString());
    if (validated == null) return;
    final pathSegments = [...validated.pathSegments];
    while (pathSegments.isNotEmpty && pathSegments.last.isEmpty) {
      pathSegments.removeLast();
    }
    final uri = validated.replace(
      pathSegments: [...pathSegments, title, body],
      query: null,
      fragment: null,
    );
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      await _request(client, uri).timeout(timeout);
    } catch (error) {
      // Never include the URL or request content: the URL may contain a key.
      stderr.writeln('Bark notification failed: ${error.runtimeType}');
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _request(HttpClient client, Uri uri) async {
    final request = await client.getUrl(uri);
    request.followRedirects = false;
    final response = await request.close();
    await response.drain<void>().timeout(timeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      stderr.writeln('Bark notification failed: HTTP ${response.statusCode}');
    }
  }
}
