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

  test('rejects malformed base URI strings', () {
    for (final value in [
      'http://[invalid/key',
      'https://%zz/key',
      '://missing-scheme/key',
    ]) {
      expect(BarkNotifier.parseBase(value), isNull);
    }
  });

  test('does not follow redirects', () async {
    final redirected = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => redirected.close(force: true));
    redirected.listen((request) {
      fail('Bark request followed redirect to another host');
    });
    final redirectPort = redirected.port;
    server!.close(force: true);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server!.listen((request) {
      request.response
        ..statusCode = HttpStatus.found
        ..headers.set(
          HttpHeaders.locationHeader,
          'http://127.0.0.1:$redirectPort/capture',
        )
        ..close();
    });
    await BarkNotifier().send(
      Uri.parse('http://127.0.0.1:${server!.port}/key'),
      title: 'title',
      body: 'body',
    );
  });

  test('times out when response body never completes', () async {
    await server!.close(force: true);
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server!.listen((request) {
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.chunkedTransferEncoding = true
        ..write('headers arrived');
      // Deliberately leave the response open so the body never completes.
    });
    final stopwatch = Stopwatch()..start();
    await BarkNotifier(timeout: const Duration(milliseconds: 40)).send(
      Uri.parse('http://127.0.0.1:${server!.port}/key'),
      title: 'title',
      body: 'body',
    );
    stopwatch.stop();
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
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
