import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:web/web.dart' as web;

class NetworkService {
  final _controller = StreamController<bool>.broadcast();
  Stream<bool> get onStatusChange => _controller.stream;

  Timer? _timer;

  NetworkService() {
    _startChecking();
  }

  void _startChecking() {
    _timer = Timer.periodic(const Duration(seconds: 2), (_) async {
      bool online = await hasInternet();
      _controller.add(online);
    });
  }

  Future<bool> hasInternet() async {
    try {
      // ----- WEB -----
      if (kIsWeb) {
        final navigator = web.window.navigator;
        final online = navigator.onLine;
        return online;
      }

      // ----- MOBILE (Android/iOS) -----
      final url = Uri.parse("https://api.ipify.org?format=json");
      final res =
          await http.get(url).timeout(const Duration(seconds: 4));

      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _timer?.cancel();
    _controller.close();
  }
}
