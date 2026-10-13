import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import 'package:flutter_application_1/services/web_online_checker_stub.dart'
    if (dart.library.js_interop) 'web_online_checker_web.dart'
    as platform;

/// Real-internet watcher.
///
/// - Emits the FIRST status immediately (so starting the app offline shows
///   the banner right away), then ONLY when the status actually changes
///   (previously it emitted every 2s, which made every listener fire
///   continuously).
/// - Never runs two checks at the same time.
/// - Pings several endpoints in parallel, so one blocked/slow host
///   (e.g. api.ipify.org) can't make an online device look offline.
/// - Needs 2 failed checks in a row before reporting "offline" (avoids
///   banner flicker on one dropped request); "online" is reported at once.
class NetworkService {
  final _controller = StreamController<bool>.broadcast();
  Stream<bool> get onStatusChange => _controller.stream;

  static const _interval = Duration(seconds: 2);
  static const _timeout = Duration(seconds: 3);
  static const _failuresBeforeOffline = 2;

  static final List<Uri> _probes = [
    Uri.parse('https://www.gstatic.com/generate_204'),
    Uri.parse('https://api.ipify.org?format=json'),
    Uri.parse('https://1.1.1.1/cdn-cgi/trace'),
  ];

  Timer? _timer;
  bool? _lastEmitted;
  bool _checking = false;
  int _failures = 0;

  /// Last known status (assumed online until the first check finishes).
  bool get isOnline => _lastEmitted ?? true;

  NetworkService() {
    _check(); // immediate first check
    _timer = Timer.periodic(_interval, (_) => _check());
  }

  Future<void> _check() async {
    if (_checking || _controller.isClosed) return;
    _checking = true;
    try {
      final online = await hasInternet();

      if (online) {
        _failures = 0;
        _emitIfChanged(true);
      } else {
        _failures++;
        // First ever check offline → report immediately.
        // Otherwise wait for consecutive failures.
        if (_lastEmitted == null || _failures >= _failuresBeforeOffline) {
          _emitIfChanged(false);
        }
      }
    } finally {
      _checking = false;
    }
  }

  void _emitIfChanged(bool online) {
    if (_lastEmitted == online || _controller.isClosed) return;
    _lastEmitted = online;
    debugPrint('🌐 NetworkService status changed: online=$online');
    _controller.add(online);
  }

  Future<bool> hasInternet() async {
    try {
      // ----- WEB -----
      if (kIsWeb) {
        return platform.isBrowserOnline();
      }

      // ----- MOBILE (Android/iOS) -----
      final results = await Future.wait(_probes.map(_ping));
      return results.any((ok) => ok);
    } catch (_) {
      return false;
    }
  }

  Future<bool> _ping(Uri url) async {
    try {
      final res = await http.get(url).timeout(_timeout);
      return res.statusCode >= 200 && res.statusCode < 400;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _timer?.cancel();
    _controller.close();
  }
}