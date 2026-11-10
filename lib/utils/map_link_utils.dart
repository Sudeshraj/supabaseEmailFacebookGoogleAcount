import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// ====================================================================
// MAP LINK UTILS  (put this file in lib/utils/map_link_utils.dart)
//
// Safe handling of map links that business owners paste:
//
//  - MapLinkUtils.check(text)   validates a pasted link (allow-list) and
//                               reads the coordinates out of it if it can
//  - MapLinkUtils.openLocation  opens the business in Google Maps / the
//                               default map app or the browser
//  - OpenInMapsButton           ready-made button for customer screens
//
// SECURITY RULES (the SAME rules run in the database trigger
// validate_salon_map_url, section 94.3 - the database is the check that
// cannot be bypassed, this file gives the owner instant feedback and
// protects customers a second time before a link is opened):
//
//  1. https only. No http:, javascript:, data:, intent:, file: ...
//  2. Host must be on the allow-list (exact match, no wildcards).
//  3. No user-info ("https://maps.google.com@evil.com"), no port, no
//     non-ASCII / punycode host (look-alike letters), no trailing dot.
//  4. Google hosts: path must start with /maps  (google.com/url?q=... is
//     an open redirect and is refused).
//  5. No ".." / "." segments or encoded dots / slashes in the path
//     (/maps/../url is normalised by browsers to /url).
//  6. When the coordinates are known the app NEVER opens the stored link:
//     it builds the Google Maps URL itself from the numbers.
//  7. Links are always opened in an external app / browser, never inside
//     a WebView of this app.
//  8. The app never follows redirects of a pasted short link itself.
// ====================================================================

/// Result of checking a pasted map link.
class MapLinkCheck {
  final bool ok;
  final String? error;

  /// Normalised link (null when the field was empty).
  final Uri? uri;

  /// Coordinates found inside the link (null for short links etc.).
  final double? latitude;
  final double? longitude;

  const MapLinkCheck._({
    required this.ok,
    this.error,
    this.uri,
    this.latitude,
    this.longitude,
  });

  const MapLinkCheck.empty() : this._(ok: true);

  const MapLinkCheck.invalid(String message)
      : this._(ok: false, error: message);

  const MapLinkCheck.valid(Uri uri, {double? latitude, double? longitude})
      : this._(ok: true, uri: uri, latitude: latitude, longitude: longitude);

  bool get isEmpty => ok && uri == null;
  bool get hasCoordinates => latitude != null && longitude != null;
}

class MapLinkUtils {
  MapLinkUtils._();

  static const int maxUrlLength = 500;

  static const String notAllowedMessage =
      'This map link is not allowed. Use a Google Maps, Apple Maps, '
      'OpenStreetMap or Waze link.';

  /// Google Maps country domains (exact, with or without "www.")
  static const Set<String> _googleBaseHosts = {
    'google.com',
    'google.lk',
    'google.co.in',
    'google.co.uk',
    'google.com.au',
    'google.ca',
    'google.ae',
    'google.com.sg',
    'google.de',
    'google.fr',
    'google.co.jp',
  };

  // ------------------------------------------------------------------
  // Coordinates
  // ------------------------------------------------------------------
  static bool isValidLatitude(double? v) =>
      v != null && v.isFinite && v >= -90 && v <= 90;

  static bool isValidLongitude(double? v) =>
      v != null && v.isFinite && v >= -180 && v <= 180;

  static bool hasValidCoordinates(double? lat, double? lng) =>
      isValidLatitude(lat) && isValidLongitude(lng);

  static double _round6(double v) => double.parse(v.toStringAsFixed(6));

  /// 6.934567 → "6.934567"
  static String formatCoordinate(double v) => v.toStringAsFixed(6);

  // ------------------------------------------------------------------
  // Check a pasted link
  // ------------------------------------------------------------------
  static MapLinkCheck check(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return const MapLinkCheck.empty();

    if (text.length > maxUrlLength) {
      return const MapLinkCheck.invalid('Map link is too long');
    }

    // no spaces, control characters or backslashes
    if (RegExp(r'[\s\u0000-\u001F\u007F\\]').hasMatch(text)) {
      return const MapLinkCheck.invalid(
        'Map link cannot contain spaces or special characters',
      );
    }

    if (!text.toLowerCase().startsWith('https://')) {
      return const MapLinkCheck.invalid('Map link must start with https://');
    }

    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasAuthority || uri.userInfo.isNotEmpty) {
      return const MapLinkCheck.invalid('Invalid map link');
    }
    // any explicit port (https://host:8443/) is refused
    if (uri.hasPort) {
      return const MapLinkCheck.invalid('Invalid map link');
    }

    final host = uri.host.toLowerCase();
    if (!RegExp(r'^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$').hasMatch(host) ||
        host.contains('..') ||
        host.contains('xn--')) {
      return const MapLinkCheck.invalid('Invalid map link');
    }

    final path = uri.path.isEmpty ? '/' : uri.path.toLowerCase();
    if (path.contains('..') ||
        path.contains('/./') ||
        path.contains('%2e') ||
        path.contains('%2f') ||
        path.contains('%5c')) {
      return const MapLinkCheck.invalid('Invalid map link');
    }

    if (!_isAllowed(host, path)) {
      return const MapLinkCheck.invalid(notAllowedMessage);
    }

    final coords = _extractCoordinates(uri);
    return MapLinkCheck.valid(
      uri,
      latitude: coords?[0],
      longitude: coords?[1],
    );
  }

  static bool _isAllowed(String host, String path) {
    bool pathIs(String base) => path == base || path.startsWith('$base/');

    final base = host.startsWith('www.') ? host.substring(4) : host;

    // Google Maps (country domains): only the /maps path
    if (_googleBaseHosts.contains(base) && (host == base || host == 'www.$base')) {
      return pathIs('/maps');
    }

    switch (host) {
      case 'maps.google.com':
        // WhatsApp / old style: https://maps.google.com/?q=lat,lng
        return path == '/' || pathIs('/maps');
      case 'maps.app.goo.gl':
        return true; // Google Maps short links
      case 'goo.gl':
        return pathIs('/maps');
      case 'maps.apple.com':
        return true;
      case 'openstreetmap.org':
      case 'www.openstreetmap.org':
        return true;
      case 'waze.com':
      case 'www.waze.com':
        return pathIs('/ul');
    }
    return false;
  }

  // ------------------------------------------------------------------
  // Read coordinates out of a (valid) link
  //   .../@6.9341,79.8506,17z      ...!3d6.9341!4d79.8506
  //   ?q=6.9341,79.8506   ?ll= ?query= ?destination= ?center=
  //   ?mlat=6.9341&mlon=79.8506 (OpenStreetMap)
  // ------------------------------------------------------------------
  static List<double>? _extractCoordinates(Uri uri) {
    List<double>? make(String? a, String? b) {
      final lat = double.tryParse(a ?? '');
      final lng = double.tryParse(b ?? '');
      if (!isValidLatitude(lat) || !isValidLongitude(lng)) return null;
      return [_round6(lat!), _round6(lng!)];
    }

    final path = uri.path;

    final at = RegExp(r'@(-?\d{1,2}(?:\.\d+)?),(-?\d{1,3}(?:\.\d+)?)')
        .firstMatch(path);
    if (at != null) {
      final r = make(at.group(1), at.group(2));
      if (r != null) return r;
    }

    final data = RegExp(r'!3d(-?\d+(?:\.\d+)?)!4d(-?\d+(?:\.\d+)?)')
        .firstMatch(path);
    if (data != null) {
      final r = make(data.group(1), data.group(2));
      if (r != null) return r;
    }

    try {
      final qp = uri.queryParameters;

      final mlat = qp['mlat'];
      final mlon = qp['mlon'];
      if (mlat != null && mlon != null) {
        final r = make(mlat, mlon);
        if (r != null) return r;
      }

      final pair = RegExp(r'^\s*(-?\d+(?:\.\d+)?)\s*,\s*(-?\d+(?:\.\d+)?)\s*$');
      for (final key in const ['q', 'query', 'll', 'destination', 'center']) {
        final v = qp[key];
        if (v == null) continue;
        final m = pair.firstMatch(v);
        if (m != null) {
          final r = make(m.group(1), m.group(2));
          if (r != null) return r;
        }
      }
    } catch (_) {
      // malformed query string → no coordinates
    }
    return null;
  }

  // ------------------------------------------------------------------
  // URLs built by the app itself (fixed host, only numbers inside)
  // https://developers.google.com/maps/documentation/urls  (free, no key)
  // ------------------------------------------------------------------
  static Uri searchUri(double lat, double lng) => Uri.https(
        'www.google.com',
        '/maps/search/',
        {'api': '1', 'query': '${formatCoordinate(lat)},${formatCoordinate(lng)}'},
      );

  static Uri directionsUri(double lat, double lng) => Uri.https(
        'www.google.com',
        '/maps/dir/',
        {
          'api': '1',
          'destination': '${formatCoordinate(lat)},${formatCoordinate(lng)}',
        },
      );

  /// Is there anything to open?
  static bool hasLocation({double? latitude, double? longitude, String? mapUrl}) {
    if (hasValidCoordinates(latitude, longitude)) return true;
    final c = check(mapUrl);
    return c.ok && c.uri != null;
  }

  // ------------------------------------------------------------------
  // Open
  // ------------------------------------------------------------------

  /// Show the business on the map.
  /// Coordinates → the app builds the URL itself (the stored link is
  /// NOT used). Otherwise the stored link is opened, but only if it still
  /// passes the allow-list (defence in depth: old / edited rows).
  static Future<bool> openLocation({
    double? latitude,
    double? longitude,
    String? mapUrl,
  }) async {
    if (hasValidCoordinates(latitude, longitude)) {
      return _launch(searchUri(latitude!, longitude!));
    }
    final c = check(mapUrl);
    if (c.ok && c.uri != null) return _launch(c.uri);
    return false;
  }

  /// Directions to the business.
  static Future<bool> openDirections({
    double? latitude,
    double? longitude,
    String? mapUrl,
  }) async {
    if (hasValidCoordinates(latitude, longitude)) {
      return _launch(directionsUri(latitude!, longitude!));
    }
    // only a link: open it (the map app shows the place + a Directions button)
    return openLocation(mapUrl: mapUrl);
  }

  static Future<bool> _launch(Uri? uri) async {
    if (uri == null || uri.scheme != 'https') return false;
    try {
      // external app (Google Maps if installed) or the browser,
      // never an in-app WebView
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

// ====================================================================
// Ready-made button for customer screens (salon details, booking
// confirmation ...). Shows nothing when the business has no location.
//
//   OpenInMapsButton(
//     latitude: salon['latitude'] as double?,
//     longitude: salon['longitude'] as double?,
//     mapUrl: salon['map_url'] as String?,
//   )
// ====================================================================
class OpenInMapsButton extends StatelessWidget {
  final double? latitude;
  final double? longitude;
  final String? mapUrl;

  /// true → "Directions", false → "Open in Maps"
  final bool directions;
  final String? label;

  const OpenInMapsButton({
    super.key,
    this.latitude,
    this.longitude,
    this.mapUrl,
    this.directions = false,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    if (!MapLinkUtils.hasLocation(
      latitude: latitude,
      longitude: longitude,
      mapUrl: mapUrl,
    )) {
      return const SizedBox.shrink();
    }

    return OutlinedButton.icon(
      icon: Icon(directions ? Icons.directions : Icons.map, size: 18),
      label: Text(label ?? (directions ? 'Directions' : 'Open in Maps')),
      onPressed: () async {
        final ok = directions
            ? await MapLinkUtils.openDirections(
                latitude: latitude,
                longitude: longitude,
                mapUrl: mapUrl,
              )
            : await MapLinkUtils.openLocation(
                latitude: latitude,
                longitude: longitude,
                mapUrl: mapUrl,
              );
        if (!ok && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not open the map'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      },
    );
  }
}