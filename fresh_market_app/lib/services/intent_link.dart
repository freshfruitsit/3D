import 'package:flutter/foundation.dart';

/// An Android `intent:` link, which payment and wallet pages use to open
/// an app:
/// `intent://HOST/PATH#Intent;scheme=SCHEME;package=PKG;S.browser_fallback_url=URL;end`.
///
/// Chrome opens these itself; a WebView does not, so checkout opens
/// [appUri] in its app, or loads [fallbackUrl] when no app can.
@immutable
class IntentLink {
  const IntentLink({this.appUri, this.fallbackUrl, this.package});

  /// The app's own link (`SCHEME://HOST/PATH?QUERY`), when the link names
  /// a scheme an app can be asked to open.
  final Uri? appUri;

  /// `S.browser_fallback_url`, only when it is a web address.
  final Uri? fallbackUrl;

  /// The app the link is for (`package=`).
  final String? package;

  /// Null when [url] is not an `intent:` link.
  static IntentLink? parse(String url) {
    final text = url.trim();
    if (!text.toLowerCase().startsWith(_prefix)) return null;
    final marker = text.indexOf(_extrasMarker);
    final data = text.substring(
      _prefix.length,
      marker < 0 ? text.length : marker,
    );
    final extras = <String, String>{};
    if (marker >= 0) {
      for (final field
          in text.substring(marker + _extrasMarker.length).split(';')) {
        if (field == 'end') break;
        final eq = field.indexOf('=');
        if (eq <= 0) continue;
        extras[field.substring(0, eq)] = _decode(field.substring(eq + 1));
      }
    }

    final scheme = extras['scheme']?.toLowerCase();
    final appUri =
        scheme != null &&
            _schemeName.hasMatch(scheme) &&
            !_notForApps.contains(scheme) &&
            data.isNotEmpty
        ? Uri.tryParse('$scheme:$data')
        : null;
    final fallback = Uri.tryParse(extras['S.browser_fallback_url'] ?? '');
    final web =
        fallback != null &&
        (fallback.scheme == 'https' || fallback.scheme == 'http') &&
        fallback.host.isNotEmpty;
    final package = extras['package'];
    return IntentLink(
      appUri: appUri,
      fallbackUrl: web ? fallback : null,
      package: package == null || package.isEmpty ? null : package,
    );
  }

  static const String _prefix = 'intent:';
  static const String _extrasMarker = '#Intent;';

  static final RegExp _schemeName = RegExp(r'^[a-z][a-z0-9+.-]*$');

  /// Schemes that name no app, or that would reach into the phone.
  static const Set<String> _notForApps = {
    'about',
    'blob',
    'content',
    'data',
    'file',
    'intent',
    'javascript',
  };

  /// Values are percent-encoded, as Android's `Intent.parseUri` reads
  /// them ("+" stays a plus).
  static String _decode(String value) {
    try {
      return Uri.decodeComponent(value);
    } on ArgumentError {
      return value;
    } on FormatException {
      return value;
    }
  }
}
