import '../state/cart_store.dart';

/// The store's Shopify customer accounts ("new customer accounts":
/// passwordless, an email and a 6-digit code), as the app reaches them in
/// a WebView.
///
/// Verified on the store:
/// - `https://<store>/customer_authentication/login?return_to=%2Faccount`
///   sends to Shopify's sign-in page on `shopify.com/authentication/<shop
///   id>/…` (email, then the code);
/// - after the code, Shopify calls
///   `https://<store>/customer_authentication/callback?code=…`, which goes
///   on to `return_to`;
/// - `https://<store>/account` is the customer's orders page on
///   `shopify.com/<shop id>/account` once signed in, and Shopify's sign-in
///   page otherwise.
///
/// The shop id is never written into the app: the store's own links lead
/// to it.
abstract final class CustomerAccount {
  /// Shopify's own host for sign-in and the account pages.
  static const String accountHost = 'shopify.com';

  /// Sign-in, then the customer's account page.
  static Uri get signInUrl => Uri.parse(
    'https://${CartStore.storeHost}/customer_authentication/login'
    '?return_to=%2Faccount',
  );

  /// The customer's orders (Shopify's account page).
  static Uri get ordersUrl => Uri.parse('https://${CartStore.storeHost}/account');

  static const String _callbackPath = '/customer_authentication/callback';

  /// `shopify.com/<shop id>/account…`: the signed-in account pages.
  static final RegExp _accountPath = RegExp(r'^/\d+/account(?:/|$)');

  static Uri? _web(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
      return null;
    }
    return uri;
  }

  /// Shopify calling the store back after a successful code: the
  /// customer is signed in. An answer without a code (`error=…`) is not.
  static bool isSignInCallback(String url) {
    final uri = _web(url);
    if (uri == null ||
        uri.host.toLowerCase() != CartStore.storeHost ||
        uri.path != _callbackPath) {
      return false;
    }
    try {
      final query = uri.queryParameters;
      return (query['code'] ?? '').isNotEmpty && !query.containsKey('error');
    } on FormatException {
      return false;
    }
  }

  /// A signed-in account page on Shopify (`shopify.com/<shop id>/account`,
  /// the orders list and its sub-pages). Never a sign-in page
  /// (`shopify.com/authentication/…`).
  static bool isAccountPage(String url) {
    final uri = _web(url);
    return uri != null &&
        uri.host.toLowerCase() == accountHost &&
        _accountPath.hasMatch(uri.path);
  }

  /// The store's own `/account` link (it leads to [isAccountPage] when
  /// signed in, to sign-in otherwise).
  static bool isStoreAccountLink(String url) {
    final uri = _web(url);
    if (uri == null || uri.host.toLowerCase() != CartStore.storeHost) {
      return false;
    }
    return uri.path == '/account' || uri.path.startsWith('/account/');
  }

  /// Shopify's sign-in pages (`shopify.com/authentication/…`), where the
  /// shopper types their email.
  static bool isSignInPage(String url) {
    final uri = _web(url);
    return uri != null &&
        uri.host.toLowerCase() == accountHost &&
        uri.path.startsWith('/authentication/');
  }

  /// The name of the WebView channel the email arrives on.
  static const String emailChannel = 'FreshMarketEmail';

  /// Run on Shopify's sign-in pages: sends what is in the email field to
  /// [emailChannel] as it is typed, so the Account tab can say who is
  /// signed in. Nothing else on the page is read.
  static const String emailListenerScript = '''
(function () {
  if (window.__freshMarketEmail) return;
  window.__freshMarketEmail = true;
  function send(field) {
    try {
      if (field && field.matches && field.matches('input[type=email]')) {
        $emailChannel.postMessage(String(field.value || '').trim());
      }
    } catch (e) {}
  }
  ['input', 'change', 'blur'].forEach(function (type) {
    document.addEventListener(type, function (event) {
      send(event.target);
    }, true);
  });
  document.addEventListener('submit', function () {
    send(document.querySelector('input[type=email]'));
  }, true);
})();
''';

  /// Run on a signed-in account page when the email is not known yet:
  /// the first email address in the page's text, or ''.
  static const String pageEmailScript = '''
(function () {
  var text = (document.body && document.body.innerText) || '';
  var match = text.match(/[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(?:\\.[A-Za-z0-9-]+)*\\.[A-Za-z]{2,}/);
  return match ? match[0] : '';
})();
''';

  static final RegExp _email = RegExp(
    r'[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9-]{1,63}(?:\.[A-Za-z0-9-]{1,63})*'
    r'\.[A-Za-z]{2,24}',
  );

  /// The email address in [value] (a channel message, a page's answer,
  /// a saved record), or null when there is none.
  static String? emailIn(Object? value) {
    if (value is! String) return null;
    var text = value.trim();
    // Android hands a page's string answer back JSON-quoted.
    if (text.length >= 2 && text.startsWith('"') && text.endsWith('"')) {
      text = text.substring(1, text.length - 1);
    }
    if (text.isEmpty || text.length > 1000) return null;
    final match = _email.firstMatch(text);
    if (match == null) return null;
    final email = match[0]!;
    return email.length <= 254 ? email : null;
  }
}

/// Follows the pages a sign-in goes through and says when it has
/// completed: on Shopify's signed-in account page, or on the store's
/// `/account` link (or a store page) after Shopify called the store back
/// with a code.
class SignInWatch {
  bool _sawCallback = false;

  /// Shopify called the store back with a code.
  bool get sawCallback => _sawCallback;

  /// Notes [url], a page the WebView asks to open or a redirect
  /// ([committed] false) or the page it now shows ([committed] true).
  /// True once sign-in has completed.
  ///
  /// Shopify's account page counts only once shown: on its way to the
  /// sign-in page a signed-out visit may pass through it.
  bool see(String url, {required bool committed}) {
    if (CustomerAccount.isSignInCallback(url)) {
      _sawCallback = true;
      return false;
    }
    if (committed && CustomerAccount.isAccountPage(url)) return true;
    return _sawCallback && CustomerAccount.isStoreAccountLink(url);
  }
}
