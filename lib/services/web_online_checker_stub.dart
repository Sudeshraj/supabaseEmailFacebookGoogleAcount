bool isBrowserOnline() {
  // This is never actually called on Android/iOS since NetworkService
  // checks kIsWeb before calling this function.
  throw UnsupportedError('isBrowserOnline() is only supported on web');
}