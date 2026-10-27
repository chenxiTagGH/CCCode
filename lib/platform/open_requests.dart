import 'package:flutter/services.dart';

import '../window/code_args.dart';

/// Files and folders the system asks the app to open, from outside it: the
/// `code` command (see shell_command.dart), Finder's Open With, an item of
/// the macOS File menu's Open Recent, the context menu's Open with CCCode
/// and Open with Fast Ide (see context_menu.dart), or the Windows app
/// started again with paths (it hands them to the one already running).
///
/// The window keeps what comes before the app is ready for it — the paths
/// it was started with among them — until [listen] takes them (see
/// AppDelegate.swift and windows/runner/open_requests.cpp).
abstract final class OpenRequests {
  static const _channel = MethodChannel('cccode/open');

  /// Starts delivering paths the system asks the app to open (the `code`
  /// command, Finder's Open With, a recent item of the macOS File menu):
  /// first those that came before (at launch), then each as it comes.
  ///
  /// The paths are absolute, or a request of the `code` command
  /// ([CodeArgs.isRequest]); there is one listener, the last to listen.
  static void listen(void Function(List<String> paths) onOpen) {
    final generation = ++_generation;
    _onOpen = onOpen;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'open') _deliver(call.arguments);
      return null;
    });
    final pending = List<List<String>>.of(_pending);
    _pending.clear();
    for (var index = 0; index < pending.length; index++) {
      if (_generation != generation || _onOpen == null) {
        _pending.insertAll(0, pending.sublist(index));
        return;
      }
      _deliver(pending[index]);
    }
    _takePending(generation);
  }

  /// Delivers a request supplied by a desktop entry point, before the window
  /// has started listening. It follows the same path as host-pending requests
  /// once [listen] is ready.
  static void deliver(List<String> request) {
    if (request.isEmpty) return;
    if (request.first == CodeArgs.importRequestMarker &&
        !CodeArgs.isLinkRequest(request)) {
      return;
    }
    _deliverRequest(request);
  }

  static void _deliverRequest(List<String> request) {
    if (request.isEmpty) return;
    final listener = _onOpen;
    if (listener == null) {
      _pending.add(List.of(request));
    } else {
      listener(List.of(request));
    }
  }

  static void _queue(Object? arguments) {
    if (arguments is! List) return;
    final request = [
      for (final argument in arguments)
        if (argument is String) argument,
    ];
    if (request.isNotEmpty) _pending.add(request);
  }

  /// Stops delivering them; the window keeps what comes meanwhile for the
  /// next [listen].
  static void stop() {
    ++_generation;
    _onOpen = null;
    _channel.setMethodCallHandler(null);
    _tell('stop');
  }

  static void Function(List<String> paths)? _onOpen;
  static final _pending = <List<String>>[];
  static int _generation = 0;

  /// What the macOS app was launched for: the first of what the system
  /// asked it to open before now (Finder's Open with CCCode, an agent;
  /// anything else, the IDE), which [listen] then delivers; none, launched
  /// as itself. The Windows app has it on its command line instead (see
  /// [LaunchRequest.of]). Asked once, before what shows at launch is
  /// decided: what comes after is no longer the launch's.
  static Future<LaunchRequest> launchRequest() async {
    try {
      return switch (await _channel.invokeMethod<String>('launchRequest')) {
        'agent' => LaunchRequest.agent,
        'ide' => LaunchRequest.ide,
        _ => LaunchRequest.none,
      };
    } on MissingPluginException {
      // A host without the channel (the web, tests).
      return LaunchRequest.none;
    } on PlatformException {
      return LaunchRequest.none;
    }
  }

  static const codeRequestMarker = CodeArgs.requestMarker;

  /// Asks for what the window kept, which also tells it the app now takes
  /// each as it comes.
  static Future<void> _takePending(int generation) async {
    try {
      final result = await _channel.invokeMethod<Object?>('takePending');
      if (_generation != generation || _onOpen == null) {
        _queue(result);
      } else {
        _deliver(result);
      }
    } on MissingPluginException {
      // A host without the channel (the web, tests).
    } on PlatformException {
      // A window that has none to give.
    }
  }

  static Future<void> _tell(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // A host without the channel (the web, tests).
    }
  }

  static void _deliver(Object? arguments) {
    if (arguments is! List) return;
    final all = [
      for (final argument in arguments)
        if (argument is String) argument,
    ];
    final paths = <String>[];
    void flushPaths() {
      if (paths.isNotEmpty) {
        _deliverRequest(List.of(paths));
        paths.clear();
      }
    }

    for (var index = 0; index < all.length;) {
      final value = all[index];
      if (value.startsWith('cccode://')) {
        flushPaths();
        final request = [CodeArgs.importRequestMarker, value];
        if (CodeArgs.isLinkRequest(request)) deliver(request);
        index++;
        continue;
      }
      if (!CodeArgs.isMarker(value)) {
        if (_isAbsolute(value)) paths.add(value);
        index++;
        continue;
      }

      flushPaths();
      var end = index + 1;
      while (end < all.length && !CodeArgs.isMarker(all[end])) end++;
      final request = all.sublist(index, end);
      if (request.first != CodeArgs.importRequestMarker ||
          CodeArgs.isLinkRequest(request)) {
        _deliverRequest(request);
      }
      index = end;
    }
    flushPaths();
  }

  /// `/…` on macOS; `C:\…` or `\\server\…` on Windows.
  static bool _isAbsolute(String path) =>
      path.startsWith('/') ||
      path.startsWith(r'\\') ||
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
}
