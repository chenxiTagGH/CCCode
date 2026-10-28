import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:baocode/notifications/bark_notifier.dart';

void main() {
  HttpServer? server;
  late List<List<String>> paths;

  setUp(() async {
    paths = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server!.listen((request) {
      paths.add(request.uri.pathSegments);
      request.response
        ..statusCode = 200
        ..close();
    });
  });

  tearDown(() => server?.close(force: true));

  test('skips empty URLs', () async {
    await BarkNotifier().send(Uri.parse(''), title: 'title', body: 'body');
    expect(paths, isEmpty);
  });

  test('encodes title and body as URL path segments', () async {
    await BarkNotifier().send(
      Uri.parse('http://127.0.0.1:${server!.port}/key'),
      title: 'title / 你好',
      body: 'body? & value',
    );
    expect(paths, [
      ['key', 'title / 你好', 'body? & value'],
    ]);
  });

  test(
    'rejects unsupported schemes, query, fragment, and missing hosts',
    () async {
      final invalid = [
        Uri.parse('ftp://127.0.0.1:${server!.port}/key'),
        Uri.parse('ws://127.0.0.1:${server!.port}/key'),
        Uri.parse('http://127.0.0.1:${server!.port}/key?secret=value'),
        Uri.parse('http://127.0.0.1:${server!.port}/key#fragment'),
        Uri.parse('http:///key'),
      ];
      for (final base in invalid) {
        await BarkNotifier().send(base, title: 'title', body: 'body');
      }
      expect(paths, isEmpty);
    },
  );

  test('swallows network failures', () async {
    await expectLater(
      BarkNotifier(timeout: const Duration(milliseconds: 20)).send(
        Uri.parse('http://127.0.0.1:1/key'),
        title: 'title',
        body: 'body',
      ),
      completes,
    );
  });
}
