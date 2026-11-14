import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../state/cart_store.dart';

/// What the app's Shopify WebViews share: checkout (`CheckoutScreen`) and
/// the customer account pages (`ShopifyAccountScreen`).
///
/// Android WebViews in one app share one cookie store, so signing in on
/// one Shopify page signs every other one in (checkout opens signed in).
abstract final class ShopifyWeb {
  /// Allows the cookies PayPal and Shop Pay need in their frames inside
  /// [controller]'s pages (Android only). True when it was done. Tests
  /// replace it.
  static Future<bool> Function(WebViewController controller)
  allowThirdPartyCookies = _allowThirdPartyCookies;

  static Future<bool> _allowThirdPartyCookies(
    WebViewController controller,
  ) async {
    final platform = controller.platform;
    // PayPal and Shop Pay run in frames from their own sites inside
    // checkout and need their cookies there. Android's WebView blocks
    // such third-party cookies unless asked (Chrome allows them).
    if (platform is! AndroidWebViewController) return false;
    final cookies = WebViewCookieManager().platform;
    if (cookies is! AndroidWebViewCookieManager) return false;
    await cookies.setAcceptThirdPartyCookies(platform, true);
    return true;
  }

  /// Removes every cookie of the app's WebViews (signing out of Shopify
  /// there). True when there were some. Tests replace it.
  static Future<bool> Function() clearCookies = _clearCookies;

  static Future<bool> _clearCookies() => WebViewCookieManager().clearCookies();

  /// The longest a WebView setting may take before the page loads without
  /// it.
  static const Duration platformWait = Duration(seconds: 2);

  /// True for the web storefront pages Shopify's pages link to (the store
  /// logo, "return to cart", product links). The app has its own screens
  /// for those, so the WebView closes instead of showing the website.
  static bool isStorefrontPage(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host != CartStore.storeHost) return false;
    final path = uri.path;
    return path.isEmpty ||
        path == '/' ||
        path == '/cart' ||
        path == '/cart/' ||
        path.startsWith('/collections') ||
        path.startsWith('/products');
  }

  /// Opens [target] in another app; with [appOnly], never in a browser
  /// (Android 11 and later). False when nothing could open it.
  static Future<bool> launchExternally(
    Uri target, {
    bool appOnly = false,
  }) async {
    try {
      return await launchUrl(
        target,
        mode: appOnly
            ? LaunchMode.externalNonBrowserApplication
            : LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }
}
