import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/platform/open_requests.dart';
import 'package:baocode/window/code_args.dart';

const _open = MethodChannel('cccode/open');

/// What the system asks the app to open comes to the one listener: first
/// what the window kept, then each as the window sends it.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<String> calls;
  late List<Object?> pending;

  setUp(() {
    calls = [];
    pending = [];
    messenger.setMockMethodCallHandler(_open, (call) async {
      calls.add(call.method);
      if (call.method == 'takePending') {
        final taken = pending;
        pending = [];
        return taken;
      }
      return null;
    });
  });
  tearDown(() {
    OpenRequests.stop();
    messenger.setMockMethodCallHandler(_open, null);
  });

  /// The window sending [paths], as it does once the app is ready.
  Future<void> send(Object? paths) async {
    await messenger.handlePlatformMessage(
      _open.name,
      const StandardMethodCodec().encodeMethodCall(MethodCall('open', paths)),
      (_) {},
    );
  }

  test('takes what came before it listened, then what comes', () async {
    pending = ['/Users/me/project', '/Users/me/notes.md'];
    final opened = <List<String>>[];
    OpenRequests.listen(opened.add);
    await pumpEventQueue();
    expect(calls, ['takePending']);
    expect(opened, [
      ['/Users/me/project', '/Users/me/notes.md'],
    ]);

    await send([r'C:\work\app', r'\\server\share\file.txt']);
    expect(opened.last, [r'C:\work\app', r'\\server\share\file.txt']);
  });

  test('nothing kept, nothing delivered', () async {
    final opened = <List<String>>[];
    OpenRequests.listen(opened.add);
    await pumpEventQueue();
    expect(opened, isEmpty);
  });

  test('drops malformed import requests before listening', () async {
    OpenRequests.deliver(const [
      CodeArgs.importRequestMarker,
      'cccode://provider/import',
    ]);
    final opened = <List<String>>[];
    OpenRequests.listen(opened.add);
    await pumpEventQueue();
    expect(opened, isEmpty);
  });

  test('passes over what is not an absolute path', () async {
    final opened = <List<String>>[];
    OpenRequests.listen(opened.add);
    await pumpEventQueue();
    await send(['relative/file', '', 42, '/abs/file']);
    expect(opened, [
      ['/abs/file'],
    ]);
    await send(['relative']);
    await send('not a list');
    expect(opened, hasLength(1));
  });

  test('requests of the `code` command go each as they came, after the '
      'paths kept', () async {
    const marker = OpenRequests.codeRequestMarker;
    pending = [
      r'C:\notes.md',
      marker,
      r'C:\work',
      '-n',
      '.',
      marker,
      r'C:\other',
    ];
    final opened = <List<String>>[];
    OpenRequests.listen(opened.add);
    await pumpEventQueue();
    expect(opened, [
      [r'C:\notes.md'],
      [marker, r'C:\work', '-n', '.'],
      [marker, r'C:\other'],
    ]);

    await send([marker, r'C:\work', '-g', 'a.dart:3']);
    expect(opened.last, [marker, r'C:\work', '-g', 'a.dart:3']);
  });

  test('Open with CCCode goes as a request of its own, beside those of '
      'the `code` command', () async {
    const code = OpenRequests.codeRequestMarker;
    const agent = CodeArgs.agentRequestMarker;
    pending = [agent, r'C:\work\a.dart', code, r'C:\work', '.', agent, r'C:\x'];
    final opened = <List<String>>[];
    OpenRequests.listen(opened.add);
    await pumpEventQueue();
    expect(opened, [
      [agent, r'C:\work\a.dart'],
      [code, r'C:\work', '.'],
      [agent, r'C:\x'],
    ]);
  });

  test("a site's valid import goes as a request of its own, the link as it "
      'came', () async {
    const link = 'cccode://provider/import?v=1&url=https%3A%2F%2Fapi.x.com';
    pending = [r'C:\a.txt', CodeArgs.importRequestMarker, link];
    final opened = <List<String>>[];
    OpenRequests.listen(opened.add);
    await pumpEventQueue();
    expect(opened, [
      [r'C:\a.txt'],
      [CodeArgs.importRequestMarker, link],
    ]);
  });

  test('drops malformed queued marker payloads', () async {
    pending = [
      CodeArgs.importRequestMarker,
      'cccode://provider/import?url=%',
      CodeArgs.importRequestMarker,
      'cccode://provider/import?url=https%3A%2F%2Fapi.x.com',
    ];
    final opened = <List<String>>[];
    OpenRequests.listen(opened.add);
    await pumpEventQueue();
    expect(opened, [
      [
        CodeArgs.importRequestMarker,
        'cccode://provider/import?url=https%3A%2F%2Fapi.x.com',
      ],
    ]);
  });

  test('delivers multiple queued requests in order', () async {
    const first = 'cccode://provider/import?url=https%3A%2F%2Ffirst.example';
    const second = 'cccode://activate?i=install&s=channel';
    pending = [
      CodeArgs.importRequestMarker,
      first,
      CodeArgs.importRequestMarker,
      second,
    ];
    final opened = <List<String>>[];
    OpenRequests.listen(opened.add);
    await pumpEventQueue();
    expect(opened, [
      [CodeArgs.importRequestMarker, first],
      [CodeArgs.importRequestMarker, second],
    ]);
  });

  test('drops malformed live import links', () async {
    final opened = <List<String>>[];
    OpenRequests.listen(opened.add);
    await pumpEventQueue();
    await send(['cccode://provider/import']);
    await send(['cccode://provider/import?url=%']);
    expect(opened, isEmpty);
  });

  test('forwards activate links as link requests', () async {
    final opened = <List<String>>[];
    OpenRequests.listen(opened.add);
    await pumpEventQueue();
    const link = 'cccode://activate?i=install&s=channel';
    await send([link]);
    expect(opened, [[CodeArgs.importRequestMarker, link]]);
  });

  test('delivers valid live import links', () async {
    final opened = <List<String>>[];
    OpenRequests.listen(opened.add);
    await pumpEventQueue();
    const link = 'cccode://provider/import?url=https%3A%2F%2Fapi.x.com';
    await send([link]);
    expect(opened, [[CodeArgs.importRequestMarker, link]]);
  });

  test('stopped, it retains requests for the next listener', () async {
    final opened = <List<String>>[];
    OpenRequests.listen(opened.add);
    await pumpEventQueue();
    OpenRequests.stop();
    await pumpEventQueue();
    expect(calls, ['takePending', 'stop']);
    await send(['/abs/file']);
    expect(opened, isEmpty);

    final resumed = <List<String>>[];
    OpenRequests.listen(resumed.add);
    await pumpEventQueue();
    expect(resumed, [['/abs/file']]);
  });

  test('requeues later snapshot requests when listener stops during drain', () async {
    pending = ['/first', '/second'];
    final opened = <List<String>>[];
    OpenRequests.listen((request) {
      opened.add(request);
      OpenRequests.stop();
    });
    await pumpEventQueue();
    expect(opened, [['/first']]);

    final resumed = <List<String>>[];
    OpenRequests.listen(resumed.add);
    await pumpEventQueue();
    expect(resumed, [['/second']]);
  });

  test('queues takePending result when stopped while invocation is in flight', () async {
    final result = Completer<Object?>();
    var takePendingCalls = 0;
    messenger.setMockMethodCallHandler(_open, (call) async {
      calls.add(call.method);
      if (call.method == 'takePending' && takePendingCalls++ == 0) {
        return result.future;
      }
      return <Object?>[];
    });
    final first = <List<String>>[];
    OpenRequests.listen(first.add);
    OpenRequests.stop();
    result.complete(['/arrived-during-take']);
    await pumpEventQueue();
    expect(first, isEmpty);

    final resumed = <List<String>>[];
    OpenRequests.listen(resumed.add);
    await pumpEventQueue();
    expect(resumed, [['/arrived-during-take']]);
  });

  test('a host without the channel is no error', () async {
    messenger.setMockMethodCallHandler(_open, null);
    OpenRequests.listen((_) => fail('nothing to open'));
    await pumpEventQueue();
    expect(await OpenRequests.launchRequest(), LaunchRequest.none);
  });

  test('what the macOS app was launched for, as the window says (Finder\'s '
      'Open with CCCode, an agent; anything else, the IDE)', () async {
    for (final (answer, request) in [
      ('agent', LaunchRequest.agent),
      ('ide', LaunchRequest.ide),
      (null, LaunchRequest.none),
    ]) {
      messenger.setMockMethodCallHandler(_open, (call) async {
        calls.add(call.method);
        return answer;
      });
      expect(await OpenRequests.launchRequest(), request);
    }
    expect(calls, everyElement('launchRequest'));
  });
}
