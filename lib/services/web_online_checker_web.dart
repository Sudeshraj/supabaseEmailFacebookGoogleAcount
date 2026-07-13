import 'package:web/web.dart' as web;

bool isBrowserOnline() {
  return web.window.navigator.onLine;
}