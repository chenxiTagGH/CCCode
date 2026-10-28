import 'dart:io';

/// Sends optional Bark notifications without affecting agent execution.
class BarkNotifier {
  const BarkNotifier({this.timeout = const Duration(seconds: 5)});

  final Duration timeout;

  Future<void> send(
    Uri base, {
    required String title,
    required String body,
  }) async {
    if ((base.scheme != 'http' && base.scheme != 'https') ||
        base.host.isEmpty ||
        base.hasQuery ||
        base.hasFragment) {
      return;
    }
    final pathSegments = [...base.pathSegments];
    while (pathSegments.isNotEmpty && pathSegments.last.isEmpty) {
      pathSegments.removeLast();
    }
    final uri = base.replace(
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
    final response = await request.close();
    await response.drain<void>();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      stderr.writeln('Bark notification failed: HTTP ${response.statusCode}');
    }
  }
}
