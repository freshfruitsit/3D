import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../app.dart';
import '../app_nav.dart';
import '../services/checkout_log.dart';
import '../services/intent_link.dart';
import '../state/cart_store.dart';
import '../theme/app_theme.dart';

/// True for Shopify's order confirmation ("thank you") and order status
/// pages: the order has been placed.
bool isOrderConfirmationUrl(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || !_isShopifyHost(uri.host)) return false;
  final path = uri.path.toLowerCase();
  // Looking at an earlier order in the customer account is not a new order.
  if (path.startsWith('/account')) return false;
  return path.contains('/thank_you') ||
      path.contains('/thank-you') ||
      _orderPath.hasMatch(path);
}

final RegExp _orderPath = RegExp(r'/orders/[^/]+');

bool _isShopifyHost(String host) =>
    host == CartStore.storeHost ||
    host.endsWith('.myshopify.com') ||
    host.endsWith('.shopify.com') ||
    host == 'shop.app';

/// True for the web storefront pages that the checkout page links to (the
/// store logo, "return to cart", product links). The app has its own
/// screens for those, so checkout closes instead of showing the website.
bool leavesCheckoutUrl(String url) {
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

/// The host of a web page outside Shopify's checkout ("www.paypal.com", a
/// bank's page), or null for checkout's own pages and for anything that
/// is not a web page. A payment page can replace checkout in the WebView
/// (Android loads a window the page opens in the WebView itself), so a
/// way to continue in the browser is offered there.
String? offCheckoutHost(String? url) {
  final uri = url == null ? null : Uri.tryParse(url);
  if (uri == null || (uri.scheme != 'https' && uri.scheme != 'http')) {
    return null;
  }
  final host = uri.host.toLowerCase();
  if (host.isEmpty ||
      host == CartStore.storeHost ||
      host.endsWith('.myshopify.com') ||
      host == 'shopify.com' ||
      host.endsWith('.shopify.com')) {
    return null;
  }
  return host;
}

/// Shopify checkout for the cart, shown inside the app. Where a WebView
/// cannot be used the checkout opens in the device browser instead.
///
/// The cart is kept while the shopper is in checkout and emptied once the
/// order confirmation page is reached.
///
/// The menu (top right) can always continue the same checkout in the
/// phone's browser, and copies the checkout log ([CheckoutLog]) for the
/// store to look at when checkout misbehaves on a phone.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, required this.url});

  /// The Shopify cart permalink (`CartStore.checkoutUrl`).
  final Uri url;

  /// How long the page may stay silent before the retry message shows.
  static const Duration loadTimeout = Duration(seconds: 12);

  /// The longest checkout waits for an optional WebView setting.
  static const Duration platformWait = Duration(seconds: 2);

  static const String menuTooltip = 'Checkout options';
  static const String openInBrowserLabel = 'Open in browser';
  static const String copyLogLabel = 'Copy checkout log';
  static const String logCopied =
      'Checkout log copied. Paste it in a message to us.';
  static const String logNotCopied = "Couldn't copy the checkout log.";
  static const String linkFailed = "Couldn't open that link.";
  static const String browserFailed = "Couldn't open your browser.";

  /// Shown above a page outside checkout (see [offCheckoutHost]).
  static String offSiteHint(String host) =>
      "You're on ${host.startsWith('www.') ? host.substring(4) : host}. "
      "If it doesn't return to checkout, open checkout in your browser.";

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

enum _BrowserState { opening, opened, failed }

enum _MenuAction { openInBrowser, copyLog }

class _CheckoutScreenState extends State<CheckoutScreen> {
  /// Null when the WebView could not be used (browser fallback).
  WebViewController? _controller;

  /// 0..1 while a page loads; null when idle.
  double? _progress = 0;

  /// Set when the checkout page itself failed to load.
  bool _pageFailed = false;

  /// Set once the order confirmation page was reached (cart emptied).
  bool _orderPlaced = false;

  /// Set once a page has finished loading: from then on an HTTP error is
  /// one of the page's own requests, never the cart link.
  bool _pageFinished = false;

  /// Set when the shopper continued this checkout in the browser.
  bool _inBrowser = false;

  /// Set once checkout started closing (pages can ask twice).
  bool _leaving = false;

  /// The optional WebView settings are made once.
  bool _prepared = false;

  /// The host of the page outside checkout being shown, if any.
  String? _offSiteHost;

  /// The last progress step written to the log for this page.
  int _progressLogged = 0;

  /// Fires when the page never starts loading.
  Timer? _watchdog;

  _BrowserState _browser = _BrowserState.opening;

  /// Checkout's own notices ("Checkout log copied."). Its own messenger
  /// also keeps the app's notices (a "Removed … Undo" from the cart) off
  /// the checkout page.
  final _messenger = GlobalKey<ScaffoldMessengerState>();

  late final CheckoutLog _log = CheckoutLog.begin(widget.url);

  /// Writes the app going to the background and back to the log (the
  /// phone's browser, a payment app, a system dialog over checkout).
  late final AppLifecycleListener _lifecycle = AppLifecycleListener(
    onStateChange: (state) => _log.add('app', 'app ${state.name}'),
  );

  @override
  void initState() {
    super.initState();
    _log.add(
      'app',
      'checkout opened, $_prefilledFields fields filled in',
      link: widget.url.toString(),
    );
    _lifecycle;
    _controller = _createWebView();
    if (_controller == null) {
      _log.add('app', 'no WebView: opening the browser');
      _openInBrowser();
    } else {
      _start(_controller!);
    }
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    _lifecycle.dispose();
    _log.add('app', 'checkout screen closed');
    super.dispose();
  }

  int get _prefilledFields {
    try {
      return widget.url.queryParameters.keys
          .where((key) => key.startsWith('checkout['))
          .length;
    } on FormatException {
      return 0;
    }
  }

  WebViewController? _createWebView() {
    try {
      return WebViewController();
    } catch (_) {
      // No WebView on this device (or in tests).
      return null;
    }
  }

  /// Sets the WebView up and loads the checkout. Every step is a call to
  /// the platform that can fail (WebView disabled or being updated); then
  /// the browser takes over.
  Future<void> _start(WebViewController controller) async {
    _startWatchdog();
    _pageFinished = false;
    final first = !_prepared;
    try {
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(_delegate());
      if (first) {
        _prepared = true;
        await _prepare(controller);
      }
      _log.add('app', 'loading checkout');
      await controller.loadRequest(widget.url);
    } catch (e) {
      _watchdog?.cancel();
      _log.add('app', 'WebView failed (${e.runtimeType}): opening the browser');
      if (!mounted) return;
      setState(() => _controller = null);
      _openInBrowser();
      return;
    }
    if (first) unawaited(_logWebViewVersion(controller));
  }

  /// Settings checkout works without; none of them may stop it loading.
  Future<void> _prepare(WebViewController controller) async {
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      // PayPal and Shop Pay run in frames from their own sites inside
      // checkout and need their cookies there. Android's WebView blocks
      // such third-party cookies unless asked (Chrome allows them).
      try {
        final cookies = WebViewCookieManager().platform;
        if (cookies is AndroidWebViewCookieManager) {
          await cookies
              .setAcceptThirdPartyCookies(platform, true)
              .timeout(CheckoutScreen.platformWait);
          _log.add('app', 'third-party cookies allowed');
        }
      } catch (e) {
        _log.add('app', 'third-party cookies not allowed (${e.runtimeType})');
      }
    }
    try {
      await controller
          .setOnConsoleMessage(_onConsoleMessage)
          .timeout(CheckoutScreen.platformWait);
    } catch (_) {
      // No console messages in the log.
    }
  }

  Future<void> _logWebViewVersion(WebViewController controller) async {
    try {
      final agent = await controller.getUserAgent().timeout(
        CheckoutScreen.platformWait,
      );
      if (agent != null && agent.isNotEmpty) {
        _log.add('app', 'WebView: ${CheckoutLog.describeUserAgent(agent)}');
      }
    } catch (_) {
      // Not known.
    }
  }

  void _onConsoleMessage(JavaScriptConsoleMessage message) {
    if (message.level != JavaScriptLogLevel.error) return;
    _log.add('js', message.message, noisy: true);
  }

  NavigationDelegate _delegate() => NavigationDelegate(
    onPageStarted: (url) {
      _watchdog?.cancel();
      _log.add('page', 'started', link: url);
      _progressLogged = 0;
      _trackPage(url);
      _checkOrderPlaced(url);
      _setProgress(0);
    },
    onProgress: (value) {
      if (value > 0) _watchdog?.cancel();
      _logProgress(value);
      _setProgress(value >= 100 ? null : value / 100);
    },
    onPageFinished: (url) {
      _watchdog?.cancel();
      _pageFinished = true;
      _log.add('page', 'finished', link: url);
      _trackPage(url);
      _checkOrderPlaced(url);
      _setProgress(null);
    },
    onUrlChange: (change) {
      _log.add('url', '', link: change.url);
      _trackPage(change.url);
      _checkOrderPlaced(change.url);
    },
    onWebResourceError: (error) {
      final page = error.isForMainFrame == true;
      _log.add(
        'error',
        '${error.errorCode} ${error.errorType?.name ?? ''} '
            '"${error.description}" (${page ? 'page' : 'part of page'})',
        link: error.url,
        noisy: !page,
      );
      if (!page) return;
      _showPageFailed('the page did not load');
    },
    onHttpError: (error) {
      // Shopify answers the cart link itself with an error page (410)
      // when it cannot build the checkout. Android reports the page's
      // every request (frames, scripts, data) without saying which one
      // is the page, so only errors before the first page finished can
      // be the cart link: a later one never replaces a live checkout.
      final status = error.response?.statusCode ?? 0;
      final uri = error.request?.uri ?? error.response?.uri;
      if (status < 400 || uri == null) return;
      final isCartLink =
          !_pageFinished &&
          (uri == widget.url ||
              (uri.host == widget.url.host && uri.path.startsWith('/cart/')));
      _log.add('http', '$status', link: uri.toString(), noisy: !isCartLink);
      if (isCartLink) _showPageFailed('the cart link answered $status');
    },
    onSslAuthError: (error) {
      final platform = error.platform;
      _log.add(
        'ssl',
        platform.description,
        link: platform is AndroidSslAuthError ? platform.url : null,
      );
      // Never proceed on a bad certificate (what happens without this
      // callback too).
      error.cancel().catchError((Object _) {});
    },
    onNavigationRequest: _onNavigationRequest,
  );

  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final where = request.isMainFrame ? 'page' : 'frame';
    final url = request.url;
    // Payment and wallet apps: `intent://…#Intent;scheme=…;end`.
    if (url.toLowerCase().startsWith('intent:')) {
      _log.add('nav', 'app link ($where)', link: url);
      _openIntent(url);
      return NavigationDecision.prevent;
    }
    final target = Uri.tryParse(url);
    if (target == null) {
      _log.add('nav', 'blocked, not a link ($where)', link: url);
      return NavigationDecision.prevent;
    }
    switch (target.scheme.toLowerCase()) {
      case 'http' || 'https':
        if (request.isMainFrame && leavesCheckoutUrl(url)) {
          // A link back to the web storefront: return to the app.
          _log.add('nav', 'store page: closing checkout', link: url);
          _leave();
          return NavigationDecision.prevent;
        }
        _log.add('nav', 'allowed ($where)', link: url);
        return NavigationDecision.navigate;
      case 'about':
        // A frame may be blank, but the whole page never is: a window the
        // page opens (PayPal) would otherwise blank checkout.
        if (!request.isMainFrame) return NavigationDecision.navigate;
        _log.add('nav', 'blocked blank page', link: url);
        return NavigationDecision.prevent;
      case 'javascript' || 'data' || 'blob' || 'file' || 'content':
        _log.add('nav', 'blocked ($where)', link: url);
        return NavigationDecision.prevent;
      default:
        // Phone, mail and payment-app links belong to other apps.
        _log.add('nav', 'other app ($where)', link: url);
        _openInOtherApp(target);
        return NavigationDecision.prevent;
    }
  }

  Future<void> _openInOtherApp(Uri target) async {
    final opened = await _launchExternally(target);
    _log.add('nav', opened ? 'opened in its app' : 'no app could open it');
    if (!opened && mounted) _notice(CheckoutScreen.linkFailed);
  }

  /// An `intent:` link: its app when one can open it, otherwise its web
  /// address (`S.browser_fallback_url`) in checkout.
  Future<void> _openIntent(String url) async {
    final link = IntentLink.parse(url);
    final app = link?.appUri;
    if (app != null && await _launchExternally(app)) {
      _log.add('nav', 'app link opened in its app');
      return;
    }
    final fallback = link?.fallbackUrl;
    final controller = _controller;
    if (!mounted) return;
    if (fallback == null || controller == null || _inBrowser) {
      _log.add('nav', 'app link: no app and no web address');
      _notice(CheckoutScreen.linkFailed);
      return;
    }
    _log.add(
      'nav',
      "app link: its app didn't open, loading",
      link: '$fallback',
    );
    if (leavesCheckoutUrl('$fallback')) {
      _leave();
      return;
    }
    try {
      await controller.loadRequest(fallback);
    } catch (_) {
      if (mounted) _notice(CheckoutScreen.linkFailed);
    }
  }

  void _logProgress(int value) {
    final step = value >= 100
        ? 100
        : value >= 50
        ? 50
        : value > 0
        ? 10
        : 0;
    if (step <= _progressLogged) return;
    _progressLogged = step;
    _log.add('load', step == 100 ? '100%' : '$step%+');
  }

  /// Notes whether the page shown is outside checkout (see
  /// [offCheckoutHost]).
  void _trackPage(String? url) {
    final host = offCheckoutHost(url);
    if (host == _offSiteHost || !mounted) return;
    if (host != null) _log.add('app', 'page outside checkout: hint shown');
    setState(() => _offSiteHost = host);
  }

  void _startWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(
      CheckoutScreen.loadTimeout,
      () => _showPageFailed('nothing loaded in time'),
    );
  }

  void _showPageFailed(String reason) {
    _watchdog?.cancel();
    if (!mounted || _orderPlaced) return;
    _log.add('app', 'could not load checkout: $reason');
    setState(() {
      _pageFailed = true;
      _progress = null;
    });
  }

  /// Empties the cart, once, when the order confirmation page shows.
  void _checkOrderPlaced(String? url) {
    if (_orderPlaced || url == null || !mounted) return;
    if (!isOrderConfirmationUrl(url)) return;
    _log.add('order', 'order placed, cart emptied', link: url);
    context.read<CartStore>().clear();
    setState(() => _orderPlaced = true);
  }

  /// Closes checkout: back to the cart, or to Home once the order is
  /// placed (the cart is empty then). Only once: a page can send two
  /// store links in a row, and a second pop would close the app's home.
  void _leave() {
    if (!mounted || _leaving) return;
    _leaving = true;
    _log.add('app', _orderPlaced ? 'done: back to Home' : 'back to the cart');
    if (_orderPlaced) {
      AppNav.goToTab(context, AppTab.home);
    } else {
      Navigator.of(context).pop();
    }
  }

  void _setProgress(double? value) {
    if (!mounted) return;
    setState(() => _progress = value);
  }

  Future<bool> _launchExternally(Uri target) async {
    try {
      return await launchUrl(target, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  Future<void> _openInBrowser() async {
    if (mounted) setState(() => _browser = _BrowserState.opening);
    final opened = await _launchExternally(widget.url);
    _log.add('app', opened ? 'browser opened' : 'no browser could be opened');
    if (!mounted) return;
    setState(() {
      _browser = opened ? _BrowserState.opened : _BrowserState.failed;
    });
  }

  /// "Open in browser": the same checkout link in the phone's browser
  /// (the cart is kept). Checkout then says to finish there, so the order
  /// is not also placed here.
  Future<void> _continueInBrowser() async {
    _log.add('app', 'open in browser chosen');
    final opened = await _launchExternally(widget.url);
    _log.add('app', opened ? 'browser opened' : 'no browser could be opened');
    if (!mounted) return;
    if (!opened) {
      _notice(CheckoutScreen.browserFailed);
      return;
    }
    _watchdog?.cancel();
    setState(() {
      _inBrowser = true;
      _browser = _BrowserState.opened;
      _progress = null;
    });
  }

  /// "Copy checkout log": this checkout's log and the one before, as
  /// plain text, for the shopper to paste in a message to the store.
  Future<void> _copyLog() async {
    _log.add('app', 'log copied');
    try {
      await Clipboard.setData(ClipboardData(text: CheckoutLog.supportReport()));
    } catch (_) {
      if (mounted) _notice(CheckoutScreen.logNotCopied);
      return;
    }
    if (mounted) _notice(CheckoutScreen.logCopied);
  }

  void _notice(String message) => AppNav.showNotice(
    context,
    message,
    bottomMargin: AppDims.gutter,
    messenger: _messenger.currentState,
  );

  void _reload() {
    _log.add('app', 'try again');
    setState(() {
      _pageFailed = false;
      _progress = 0;
    });
    final controller = _controller;
    if (controller != null) _start(controller);
  }

  /// System back steps back inside checkout first, then leaves it.
  Future<void> _handleBack() async {
    final controller = _controller;
    try {
      if (controller != null &&
          !_pageFailed &&
          !_orderPlaced &&
          !_inBrowser &&
          await controller.canGoBack().timeout(CheckoutScreen.platformWait)) {
        _log.add('app', 'back: previous page');
        await controller.goBack().timeout(CheckoutScreen.platformWait);
        return;
      }
    } catch (_) {
      // Fall through and leave checkout.
    }
    _leave();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final inApp = controller != null && !_inBrowser;
    final progress = _progress;
    final loading = inApp && !_pageFailed && progress != null;
    final offSiteHost = inApp && !_pageFailed && !_orderPlaced
        ? _offSiteHost
        : null;

    return PopScope(
      canPop: !inApp,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: ScaffoldMessenger(
        key: _messenger,
        child: Scaffold(
          backgroundColor: inApp && !_pageFailed ? AppColors.surface : null,
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close checkout',
              onPressed: _leave,
            ),
            title: Text(_orderPlaced ? 'Order placed' : 'Checkout'),
            actions: [
              if (_orderPlaced)
                TextButton(onPressed: _leave, child: const Text('Done')),
              _buildMenu(canOpenBrowser: inApp && !_orderPlaced),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(3),
              child: SizedBox(
                height: 3,
                child: loading
                    ? LinearProgressIndicator(
                        // Indeterminate until the page reports progress.
                        value: progress > 0 ? progress : null,
                        minHeight: 3,
                        backgroundColor: AppColors.subtle,
                      )
                    // A hairline under the bar once the page is in.
                    : const Align(
                        alignment: Alignment.bottomCenter,
                        child: Divider(height: 1),
                      ),
              ),
            ),
          ),
          body: SafeArea(
            top: false,
            child: !inApp
                ? _buildBrowserFallback()
                : _pageFailed
                ? _CheckoutMessage(
                    icon: Icons.wifi_off_rounded,
                    title: 'Could not load checkout',
                    message:
                        'Check your connection and try again. '
                        'Your cart is saved.',
                    primaryLabel: 'Try again',
                    onPrimary: _reload,
                    primaryIsCheckout: false,
                    secondaryLabel: CheckoutScreen.openInBrowserLabel,
                    onSecondary: _continueInBrowser,
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (offSiteHost != null)
                        _OffSiteHint(
                          host: offSiteHost,
                          onOpenInBrowser: _continueInBrowser,
                        ),
                      Expanded(
                        key: const ValueKey('checkout-webview'),
                        // Notes touches (never where) so the log shows
                        // whether the page was used before it stopped.
                        // A Listener takes no part in the page's gestures.
                        child: Listener(
                          onPointerUp: (_) => _log.add('touch', 'tap/scroll'),
                          child: WebViewWidget(controller: controller),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildMenu({required bool canOpenBrowser}) =>
      PopupMenuButton<_MenuAction>(
        tooltip: CheckoutScreen.menuTooltip,
        icon: const Icon(Icons.more_vert),
        onSelected: (action) {
          switch (action) {
            case _MenuAction.openInBrowser:
              _continueInBrowser();
            case _MenuAction.copyLog:
              _copyLog();
          }
        },
        itemBuilder: (_) => [
          if (canOpenBrowser)
            const PopupMenuItem(
              value: _MenuAction.openInBrowser,
              child: _MenuRow(
                icon: Icons.open_in_new,
                label: CheckoutScreen.openInBrowserLabel,
              ),
            ),
          const PopupMenuItem(
            value: _MenuAction.copyLog,
            child: _MenuRow(
              icon: Icons.content_copy_outlined,
              label: CheckoutScreen.copyLogLabel,
            ),
          ),
        ],
      );

  Widget _buildBrowserFallback() {
    return switch (_browser) {
      _BrowserState.opening => const Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(strokeWidth: 3),
        ),
      ),
      _BrowserState.opened => _CheckoutMessage(
        icon: Icons.open_in_new,
        title: 'Checkout opened in your browser',
        message: 'Finish your order there. Your cart is saved.',
        primaryLabel: 'Open again',
        onPrimary: _openInBrowser,
        primaryIsCheckout: true,
        secondaryLabel: 'Back to cart',
        onSecondary: _leave,
      ),
      _BrowserState.failed => _CheckoutMessage(
        icon: Icons.error_outline,
        title: 'Could not open checkout',
        message:
            'No browser could be opened on this device. '
            'Your cart is saved.',
        primaryLabel: 'Try again',
        onPrimary: _openInBrowser,
        primaryIsCheckout: false,
        secondaryLabel: 'Back to cart',
        onSecondary: _leave,
      ),
    };
  }
}

/// A menu entry: icon and label.
class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 20, color: AppColors.ink),
      const SizedBox(width: 12),
      Flexible(child: Text(label)),
    ],
  );
}

/// A calm line above a page outside checkout (see [offCheckoutHost]),
/// with a way to continue in the browser should that page not return.
class _OffSiteHint extends StatelessWidget {
  const _OffSiteHint({required this.host, required this.onOpenInBrowser});

  final String host;
  final VoidCallback onOpenInBrowser;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        key: const ValueKey('checkout-offsite-hint'),
        color: AppColors.subtle,
        padding: const EdgeInsets.fromLTRB(AppDims.gutter, 8, 8, 8),
        child: Row(
          children: [
            const Icon(
              Icons.info_outline,
              size: 20,
              color: AppColors.secondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                CheckoutScreen.offSiteHint(host),
                style: AppText.bodySmall.copyWith(color: AppColors.ink),
              ),
            ),
            const SizedBox(width: 4),
            TextButton(
              onPressed: onOpenInBrowser,
              child: const Text(CheckoutScreen.openInBrowserLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// A full-page message in checkout: grey icon circle, title, secondary
/// text, a primary button and an ink text link. The primary button is the
/// green buying button only when it continues the checkout
/// ([primaryIsCheckout]); a retry after a failure is ink.
class _CheckoutMessage extends StatelessWidget {
  const _CheckoutMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    required this.primaryIsCheckout,
    required this.secondaryLabel,
    required this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final bool primaryIsCheckout;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: AppColors.subtle,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 32, color: AppColors.ink),
                ),
              ),
              const SizedBox(height: 16),
              Semantics(
                header: true,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppText.heading,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: AppText.body.copyWith(color: AppColors.secondary),
              ),
              const SizedBox(height: 24),
              FilledButton(
                style: primaryIsCheckout ? null : AppButtons.dark,
                onPressed: onPrimary,
                child: Text(primaryLabel),
              ),
              const SizedBox(height: 4),
              TextButton(onPressed: onSecondary, child: Text(secondaryLabel)),
            ],
          ),
        ),
      ),
    );
  }
}
