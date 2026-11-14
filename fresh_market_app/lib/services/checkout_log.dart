import 'package:flutter/foundation.dart';

/// One line of a [CheckoutLog]: when it happened (time since checkout
/// opened), what kind of thing it was and what happened, already made
/// safe to share.
@immutable
class CheckoutEvent {
  const CheckoutEvent(this.at, this.kind, this.text, {this.repeats = 1});

  final Duration at;

  /// `app`, `page`, `load`, `url`, `nav`, `touch`, `error`, `http`,
  /// `ssl`, `js` or `order`.
  final String kind;
  final String text;

  /// How many times in a row the same thing happened.
  final int repeats;
}

/// What one in-app checkout did, so a shopper whose checkout misbehaves
/// can send it to the store ("Copy checkout log" in the checkout menu):
/// the last [capacity] events with the time since checkout opened.
///
/// Privacy: the checkout link and the pages it moves through carry the
/// shopper's name, email, phone, address and delivery pin in their query
/// strings, so an address is only ever kept as scheme, host and path
/// (long tokens in the path are shortened, and links such as `tel:` and
/// `mailto:` keep their scheme only); the query of an address inside a
/// message is shown as `?…`. Every text is also cleared of whatever
/// looks like an email address or a phone number and of the values the
/// checkout link was filled in with. What the shopper types on the
/// checkout page itself is not known to the app, so only the patterns
/// above catch it.
///
/// Kept in memory only, never on disk: the checkout open now (or the
/// last one) and the one before it.
class CheckoutLog {
  CheckoutLog({
    Uri? checkoutUrl,
    DateTime Function()? now,
    this.capacity = defaultCapacity,
  }) : _now = now ?? DateTime.now,
       _private = _privateValues(checkoutUrl) {
    opened = _now();
  }

  /// Starts the log of a checkout opening [checkoutUrl]. The log of the
  /// checkout before it is kept as [earlier].
  factory CheckoutLog.begin(Uri checkoutUrl, {DateTime Function()? now}) {
    final log = CheckoutLog(checkoutUrl: checkoutUrl, now: now);
    earlier = latest;
    latest = log;
    return log;
  }

  /// The checkout open now, or the last one.
  static CheckoutLog? latest;

  /// The checkout before [latest].
  static CheckoutLog? earlier;

  /// Forgets both logs (tests).
  @visibleForTesting
  static void forget() {
    latest = null;
    earlier = null;
  }

  /// What "Copy checkout log" copies: [latest], then [earlier].
  static String supportReport() {
    final now = latest;
    if (now == null) return 'Fresh Market checkout log\nNo checkout yet.';
    final before = earlier;
    return before == null
        ? now.report()
        : '${now.report()}\n\nThe checkout before:\n${before.report()}';
  }

  static const int defaultCapacity = 80;

  /// How many page errors and console messages one checkout keeps, so a
  /// noisy page cannot push its own navigation out of the log.
  static const int noisyLimit = 40;

  /// The longest text kept for one event.
  static const int maxText = 200;

  /// How much of a long text [scrub] looks at after its links are
  /// reduced (a console message can be a whole page of data).
  static const int maxScrubbed = 2000;

  final int capacity;
  final DateTime Function() _now;
  final List<String> _private;
  late final DateTime opened;

  final List<CheckoutEvent> _events = [];
  int _noisy = 0;
  bool _noisyCut = false;

  List<CheckoutEvent> get events => List.unmodifiable(_events);

  /// Records [text], followed by [link] when given, both made safe first
  /// ([clean], [url]). [noisy] events (page errors, console messages)
  /// stop being recorded after [noisyLimit] of them. The same event again
  /// straight after counts as a repeat.
  void add(String kind, String text, {String? link, bool noisy = false}) {
    // A noisy page past its limit costs nothing more.
    if (noisy && _noisyCut) return;
    final at = _now().difference(opened);
    final words = _truncate(clean(text));
    final safe = link == null
        ? words
        : words.isEmpty
        ? url(link)
        : '$words ${url(link)}';
    final last = _events.isEmpty ? null : _events.last;
    if (last != null && last.kind == kind && last.text == safe) {
      _events[_events.length - 1] = CheckoutEvent(
        last.at,
        kind,
        safe,
        repeats: last.repeats + 1,
      );
      return;
    }
    if (noisy) {
      if (_noisy >= noisyLimit) {
        if (_noisyCut) return;
        _noisyCut = true;
        _push(CheckoutEvent(at, 'app', 'more page errors not recorded'));
        return;
      }
      _noisy++;
    }
    _push(CheckoutEvent(at, kind, safe));
  }

  void _push(CheckoutEvent event) {
    _events.add(event);
    if (_events.length > capacity) _events.removeAt(0);
  }

  /// [url] as this log keeps it (see [safeUrl]).
  String url(String? url) => safeUrl(url, private: _private);

  /// [text] as this log keeps it (see [scrub]).
  String clean(String text) => scrub(text, private: _private);

  /// The plain-text log: when checkout opened, then one line per event.
  String report() {
    final lines = <String>[
      'Fresh Market checkout log',
      'Checkout opened ${_clock(opened)}',
      'Links show site and path only. Emails, phone numbers and your saved '
          'details are removed.',
      for (final e in _events)
        '${_elapsed(e.at).padLeft(8)}  ${e.kind.padRight(5)}  ${e.text}'
            '${e.repeats > 1 ? ' (x${e.repeats})' : ''}',
    ];
    return lines.join('\n');
  }

  // ------------------------------------------------------------ privacy --

  /// [url] reduced to what is safe to share: `scheme://host/path` for web
  /// addresses, with no query string or fragment (they carry the
  /// shopper's details), long tokens in the path shown as `<id>`, and
  /// emails, phone numbers and [private] values removed; the scheme only
  /// (plus the host, if there is one, cleared the same way) for every
  /// other kind of link, as a `tel:` or `mailto:` link is itself a phone
  /// number or an email.
  static String safeUrl(String? url, {List<String> private = const []}) {
    if (url == null || url.trim().isEmpty) return '-';
    final text = url.trim();
    final uri = Uri.tryParse(text);
    if (uri == null || !uri.hasScheme) {
      final scheme = _schemeOnly.firstMatch(text)?.group(1);
      return scheme == null ? '<link>' : '${scheme.toLowerCase()}:';
    }
    final scheme = uri.scheme.toLowerCase();
    // `tel://0501234567`: a host can be a phone number or an email too.
    final host = scrub(uri.host, private: private, urls: false);
    if (_webSchemes.contains(scheme)) {
      final port = uri.hasPort ? ':${uri.port}' : '';
      final path = uri.path
          .split('/')
          .map((part) => _token.hasMatch(part) ? '<id>' : part)
          .join('/');
      final safePath = scrub(path, private: private, urls: false);
      return '$scheme://$host$port$safePath';
    }
    if (scheme == 'about' && _word.hasMatch(uri.path)) {
      return 'about:${uri.path}';
    }
    return host.isEmpty ? '$scheme:' : '$scheme://$host';
  }

  /// [text] with every link in it reduced by [safeUrl] and the query of
  /// every other address (`/graphql?firstName=…`) shown as `?…` (unless
  /// [urls] is false), then [private] values, email addresses and phone
  /// numbers replaced by `[removed]`, `[email]` and `[phone]`.
  ///
  /// Only the first [maxScrubbed] characters are kept once the links are
  /// reduced (a log shows far less), so a long text costs little. Every
  /// pattern here takes time in step with the text's length.
  static String scrub(
    String text, {
    List<String> private = const [],
    bool urls = true,
  }) {
    var out = text;
    if (urls) {
      out = out
          .replaceAllMapped(_link, (m) => safeUrl(m[0], private: private))
          .replaceAll(_query, '?…');
    }
    if (out.length > maxScrubbed) {
      // The cut can split a value: the end of the last word goes too.
      out = '${out.substring(0, maxScrubbed).replaceFirst(_lastWord, '')}…';
    }
    for (final value in private) {
      out = out.replaceAll(value, '[removed]');
    }
    return out.replaceAll(_email, '[email]').replaceAll(_phone, '[phone]');
  }

  /// The values the checkout link was filled in with (names, email,
  /// phone, address, delivery pin), as typed and as they appear encoded
  /// in links, longest first. Very short values ("AE") are left.
  static List<String> _privateValues(Uri? url) {
    if (url == null) return const [];
    final values = <String>{};
    try {
      for (final list in url.queryParametersAll.values) {
        for (final raw in list) {
          final value = raw.trim();
          if (value.length < 3) continue;
          for (final encoded in [
            Uri.encodeQueryComponent(value),
            Uri.encodeComponent(value),
          ]) {
            // Pages also write the escapes in lower case (`%d8%b3`).
            values
              ..add(encoded)
              ..add(
                encoded.replaceAllMapped(_escape, (m) => m[0]!.toLowerCase()),
              );
          }
          values.add(value);
        }
      }
    } on FormatException {
      return const [];
    }
    return values.toList()..sort((a, b) => b.length.compareTo(a.length));
  }

  /// "Android 14 · Chrome 131 · WebView" from the WebView's user agent
  /// (nothing else from it: it also names the phone model).
  static String describeUserAgent(String userAgent) {
    final android = RegExp(r'Android ([\d.]+)').firstMatch(userAgent);
    final chrome = RegExp(r'Chrome/(\d+)').firstMatch(userAgent);
    return [
      if (android != null) 'Android ${android[1]}',
      if (chrome != null) 'Chrome ${chrome[1]}',
      if (userAgent.contains('; wv)')) 'WebView',
    ].join(' · ');
  }

  static const Set<String> _webSchemes = {'http', 'https', 'ws', 'wss'};

  /// A path segment that is an id or a token (checkout and order
  /// tokens): 16 or more letters and digits with at least one of each.
  static final RegExp _token = RegExp(
    r'^(?=.*\d)(?=.*[A-Za-z])[A-Za-z0-9_-]{16,}$',
  );
  static final RegExp _word = RegExp(r'^[a-z]{1,16}$');
  static final RegExp _schemeOnly = RegExp(r'^([A-Za-z][A-Za-z0-9+.-]*):');
  static final RegExp _escape = RegExp(r'%[0-9A-F]{2}');
  static final RegExp _lastWord = RegExp(r'\S{1,100}$');

  // The patterns below have bounded repeats where a match could start
  // over and over inside one long run of letters (a token in a console
  // message): unbounded, they took seconds on a 10,000-character token.

  static final RegExp _link = RegExp(
    r'''\b[A-Za-z][A-Za-z0-9+.-]{0,31}://[^\s"'<>`]+''',
  );

  /// The query of an address that is not a whole link (`/x?a=1`).
  static final RegExp _query = RegExp(r'''(?<=[\w/.%-])\?[^\s"'<>`]+''');

  static final RegExp _email = RegExp(
    r'[A-Za-z0-9._%+-]{1,64}(?:@|%40)'
    r'[A-Za-z0-9-]{1,63}(?:\.[A-Za-z0-9-]{1,63})*\.[A-Za-z]{2,24}',
  );

  /// International (+971 50 123 4567, 00971…), national (050 123 4567,
  /// (050) 123-4567) and bare UAE mobile numbers (971501234567,
  /// 501234567).
  static final RegExp _phone = RegExp(
    r'(?:\+|%2B|\b00)\s?\d[\d\s().-]{6,}\d'
    r'|\(\d{2,3}\)\s?\d{3}[\s.-]?\d{4}\b'
    r'|\b0\d(?:[\s.-]?\d){7,10}\b'
    r'|\b971(?:[\s.-]?\d){8,9}\b'
    r'|\b5\d(?:[\s.-]?\d){7}\b',
    caseSensitive: false,
  );

  static String _truncate(String text) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return flat.length <= maxText ? flat : '${flat.substring(0, maxText)}…';
  }

  static String _elapsed(Duration at) =>
      '+${(at.inMilliseconds / 1000).toStringAsFixed(1)}s';

  static String _clock(DateTime time) {
    String two(int n) => n.toString().padLeft(2, '0');
    final offset = time.timeZoneOffset;
    final sign = offset.isNegative ? '-' : '+';
    final minutes = offset.inMinutes.abs();
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)} '
        '(UTC$sign${two(minutes ~/ 60)}:${two(minutes % 60)})';
  }
}
