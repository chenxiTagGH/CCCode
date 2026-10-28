import 'dart:async';
import 'dart:convert';
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

  test('rejects malformed base URI strings', () async {
    for (final value in [
      'http://[invalid/key',
      'https://%zz/key',
      '://missing-scheme/key',
    ]) {
      final base = Uri.tryParse(value);
      if (base != null) {
        await BarkNotifier().send(base, title: 'title', body: 'body');
      }
    }
    expect(paths, isEmpty);
  });

  test('swallows network failures without logging URL or message content', () async {
    final diagnostics = <int>[];
    final output = StreamController<List<int>>();
    output.stream.listen(diagnostics.addAll);
    final sink = IOSink(output);
    await IOOverrides.runZoned(
      () => BarkNotifier(timeout: const Duration(milliseconds: 20)).send(
        Uri.parse('http://127.0.0.1:1/BARK-SECRET-KEY'),
        title: 'PRIVATE-TITLE',
        body: 'PRIVATE-BODY',
      ),
      stderr: () => sink,
    );
    await sink.flush();
    await sink.close();
    await output.close();
    final message = utf8.decode(diagnostics);
    expect(message, contains('Bark notification failed'));
    expect(message, isNot(contains('127.0.0.1')));
    expect(message, isNot(contains('BARK-SECRET-KEY')));
    expect(message, isNot(contains('PRIVATE-TITLE')));
    expect(message, isNot(contains('PRIVATE-BODY')));
  });
}
