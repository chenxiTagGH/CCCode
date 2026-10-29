import 'dart:io';

/// Sends optional Bark notifications without affecting agent execution.
typedef BarkRequest = Future<int> Function(Uri uri);

class BarkNotifier {
  BarkNotifier({
    this.timeout = const Duration(seconds: 5),
    this.request,
    this.iconUrl = defaultIconUrl,
  });

  /// The public CC AI API logo shown by Bark as the notification avatar.
  static const defaultIconUrl =
      'https://ccapitoken.cc/assets/cc-ai-api-logo.svg';

  final Duration timeout;
  final BarkRequest? request;
  final String iconUrl;
  bool _busy = false;

  /// Parses and validates a configured Bark base URL without making a request.
  static Uri? parseBase(String value) {
    final trimmed = value.trim();
    if (trimmed.endsWith('?') || trimmed.endsWith('#')) return null;
    final base = Uri.tryParse(trimmed);
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
    if (validated == null || _busy) return;
    _busy = true;
    final pathSegments = [...validated.pathSegments];
    while (pathSegments.isNotEmpty && pathSegments.last.isEmpty) {
      pathSegments.removeLast();
    }
    final icon = iconUrl.trim();
    final uri = validated.replace(
      pathSegments: [...pathSegments, title, body],
      queryParameters: {if (icon.isNotEmpty) 'icon': icon},
      fragment: null,
    );
    final client = HttpClient()..connectionTimeout = timeout;
    try {
      final statusCode = request == null
          ? await _request(client, uri).timeout(timeout)
          : await request!(uri).timeout(timeout);
      if (statusCode < 200 || statusCode >= 300) {
        stderr.writeln('Bark notification failed: HTTP $statusCode');
      }
    } catch (error) {
      // Never include the URL or request content: the URL may contain a key.
      stderr.writeln('Bark notification failed: ${error.runtimeType}');
    } finally {
      client.close(force: true);
      _busy = false;
    }
  }

  Future<int> _request(HttpClient client, Uri uri) async {
    final request = await client.getUrl(uri);
    request.followRedirects = false;
    final response = await request.close();
    await response.drain<void>().timeout(timeout);
    return response.statusCode;
  }
}
