import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../services/customer_account.dart';
import '../services/intent_link.dart';
import '../services/shopify_web.dart';
import '../state/account_session.dart';
import '../theme/app_theme.dart';

/// What [ShopifyAccountScreen] shows.
enum ShopifyAccountMode {
  /// Shopify's sign-in page (email, then a 6-digit code). Closes by
  /// itself once signed in.
  signIn,

  /// The customer's orders (Shopify's account page).
  orders,
}

/// What the sign-in screen closes with (null: closed, not signed in).
enum SignInOutcome {
  /// Signed in.
  signedIn,

  /// This phone cannot show the sign-in page in the app. Checkout opens in
  /// the browser instead, and Shopify asks for the sign-in there.
  inBrowser,
}

/// Shopify's own customer account pages, inside the app: the sign-in
/// page ([ShopifyAccountMode.signIn]) or the customer's orders
/// ([ShopifyAccountMode.orders]).
///
/// Its WebView shares the cookies of checkout's, so signing in here signs
/// checkout in too. Sign-in has completed when Shopify shows the signed-in
/// account page, or sends to the store's `/account` after calling the
/// store back (see [SignInWatch]); the [AccountSession] is then signed in
/// and, in sign-in mode, the screen closes with [SignInOutcome.signedIn].
///
/// The email the shopper types on Shopify's sign-in page is passed to the
/// app through a JavaScript channel (only from Shopify's sign-in pages),
/// so the Account tab can say who is signed in. It is never logged; the
/// session keeps it encrypted.
class ShopifyAccountScreen extends StatefulWidget {
  const ShopifyAccountScreen({
    super.key,
    this.mode = ShopifyAccountMode.signIn,
    this.forCheckout = false,
  });

  final ShopifyAccountMode mode;

  /// Opened by checkout: when the phone has no WebView, checkout can go
  /// on in the browser ([SignInOutcome.inBrowser]).
  final bool forCheckout;

  static const String signInTitle = 'Sign in';
  static const String ordersTitle = 'My orders';
  static const String closeSignIn = 'Close sign-in';
  static const String closeOrders = 'Close my orders';
  static const String secureLabel = 'Secure Shopify page';

  /// How long the page may stay silent before the retry message shows.
  static const Duration loadTimeout = Duration(seconds: 12);

  /// How long a finished sign-in waits for the account page to give the
  /// email, when it was not seen typed.
  static const Duration emailWait = Duration(seconds: 3);

  static const String linkFailed = "Couldn't open that link.";
  static const String browserFailed = "Couldn't open your browser.";

  @override
  State<ShopifyAccountScreen> createState() => _ShopifyAccountScreenState();
}

class _ShopifyAccountScreenState extends State<ShopifyAccountScreen> {
  /// Null when the WebView could not be used.
  WebViewController? _controller;

  /// 0..1 while a page loads; null when idle.
  double? _progress = 0;

  bool _pageFailed = false;

  /// The optional WebView settings are made once.
  bool _prepared = false;

  /// Set once sign-in completed (see [SignInWatch]).
  bool _completed = false;

  /// Set once the screen started closing (pages can ask twice).
  bool _closing = false;

  final SignInWatch _watch = SignInWatch();

  /// The page shown, as last reported.
  String? _currentUrl;

  /// The email typed on Shopify's sign-in page (memory only).
  String? _typedEmail;

  /// The email read from the signed-in account page (null: none there).
  Completer<String?>? _pageEmail;

  /// Fires when the page never starts loading.
  Timer? _watchdog;

  final GlobalKey<ScaffoldMessengerState> _messenger =
      GlobalKey<ScaffoldMessengerState>();

  bool get _signInMode => widget.mode == ShopifyAccountMode.signIn;

  /// Signed in on the sign-in screen: it is closing.
  bool get _finishing => _completed && _signInMode;

  Uri get _startUrl =>
      _signInMode ? CustomerAccount.signInUrl : CustomerAccount.ordersUrl;

  @override
  void initState() {
    super.initState();
    _controller = _createWebView();
    final controller = _controller;
    if (controller != null) _start(controller);
  }

  @override
  void dispose() {
    _watchdog?.cancel();
    super.dispose();
  }

  WebViewController? _createWebView() {
    try {
      return WebViewController();
    } catch (_) {
      // No WebView on this device (or on the web).
      return null;
    }
  }

  /// Sets the WebView up and loads the page. Every step is a call to the
  /// platform that can fail (WebView disabled or being updated).
  Future<void> _start(WebViewController controller) async {
    _startWatchdog();
    final first = !_prepared;
    try {
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(_delegate());
      if (first) {
        _prepared = true;
        await _prepare(controller);
      }
      await controller.loadRequest(_startUrl);
    } catch (_) {
      _watchdog?.cancel();
      if (mounted) setState(() => _controller = null);
    }
  }

  /// Settings the pages work without; none of them may stop them loading.
  Future<void> _prepare(WebViewController controller) async {
    try {
      await ShopifyWeb.allowThirdPartyCookies(
        controller,
      ).timeout(ShopifyWeb.platformWait);
    } catch (_) {
      // Sign-in itself needs no third-party cookies.
    }
    try {
      // Before the first page: a channel works from the next page on.
      await controller
          .addJavaScriptChannel(
            CustomerAccount.emailChannel,
            onMessageReceived: _onEmailMessage,
          )
          .timeout(ShopifyWeb.platformWait);
    } catch (_) {
      // The email is then read from the account page, or stays unknown.
    }
  }

  NavigationDelegate _delegate() => NavigationDelegate(
    onPageStarted: (url) {
      _watchdog?.cancel();
      _shown(url);
      _setProgress(0);
    },
    onProgress: (value) {
      if (value > 0) _watchdog?.cancel();
      _setProgress(value >= 100 ? null : value / 100);
    },
    onPageFinished: (url) {
      _watchdog?.cancel();
      _shown(url);
      _setProgress(null);
      _pageReady(url);
    },
    onUrlChange: (change) {
      final url = change.url;
      if (url != null) _shown(url);
    },
    onWebResourceError: (error) {
      if (error.isForMainFrame == true) _showPageFailed();
    },
    onSslAuthError: (error) {
      // Never proceed on a bad certificate.
      error.cancel().catchError((Object _) {});
    },
    onNavigationRequest: _onNavigationRequest,
  );

  /// The page now shown (committed): Shopify's signed-in account page
  /// completes the sign-in.
  void _shown(String url) {
    _currentUrl = url;
    if (_watch.see(url, committed: true)) _complete();
  }

  NavigationDecision _onNavigationRequest(NavigationRequest request) {
    final url = request.url;
    // Payment and wallet apps (Shop): `intent://…#Intent;…;end`.
    if (url.toLowerCase().startsWith('intent:')) {
      _openIntent(url);
      return NavigationDecision.prevent;
    }
    final target = Uri.tryParse(url);
    if (target == null) return NavigationDecision.prevent;
    switch (target.scheme.toLowerCase()) {
      case 'http' || 'https':
        if (!request.isMainFrame) return NavigationDecision.navigate;
        // Shopify's call back to the store and the store's `/account`
        // after it pass here as redirects.
        if (_watch.see(url, committed: false)) {
          _complete();
          return NavigationDecision.navigate;
        }
        if (ShopifyWeb.isStorefrontPage(url)) {
          // Back to the store's website: the app has its own screens.
          if (_watch.sawCallback) _complete();
          if (!_signInMode || !_watch.sawCallback) _close();
          return NavigationDecision.prevent;
        }
        return NavigationDecision.navigate;
      case 'about':
        // A frame may be blank, the whole page never.
        return request.isMainFrame
            ? NavigationDecision.prevent
            : NavigationDecision.navigate;
      case 'javascript' || 'data' || 'blob' || 'file' || 'content':
        return NavigationDecision.prevent;
      default:
        // Phone, mail and app links belong to other apps.
        _openInOtherApp(target);
        return NavigationDecision.prevent;
    }
  }

  /// A page has loaded: Shopify's sign-in page gets the email listener; a
  /// signed-in account page may say the email.
  void _pageReady(String url) {
    final controller = _controller;
    if (controller == null) return;
    if (CustomerAccount.isSignInPage(url)) {
      controller
          .runJavaScript(CustomerAccount.emailListenerScript)
          .timeout(ShopifyWeb.platformWait)
          .catchError((Object _) {});
    } else if (CustomerAccount.isAccountPage(url)) {
      _readPageEmail(controller);
    }
  }

  /// What Shopify's sign-in page sends: the email field's value. Taken
  /// only while one of Shopify's sign-in pages is shown, and only when it
  /// is an email. Never logged.
  void _onEmailMessage(JavaScriptMessage message) {
    final url = _currentUrl;
    if (url == null || !CustomerAccount.isSignInPage(url)) return;
    final email = CustomerAccount.emailIn(message.message);
    if (email != null) _typedEmail = email;
  }

  /// The email on the signed-in account page, when the app does not know
  /// it yet.
  Future<void> _readPageEmail(WebViewController controller) async {
    final session = context.read<AccountSession>();
    String? found;
    if (_typedEmail == null && session.email == null) {
      try {
        found = CustomerAccount.emailIn(
          await controller
              .runJavaScriptReturningResult(CustomerAccount.pageEmailScript)
              .timeout(ShopifyWeb.platformWait),
        );
      } catch (_) {
        // Not there, or not readable: it stays unknown.
      }
    }
    if (found != null && mounted && session.signedIn) {
      session.signIn(email: found);
    }
    final waiting = _pageEmail ??= Completer<String?>();
    if (!waiting.isCompleted) waiting.complete(found);
  }

  /// Signed in: the session says so (with the email typed, when seen),
  /// and the sign-in screen closes, once the account page has had a
  /// moment to give the email if it is still unknown.
  Future<void> _complete() async {
    if (_completed || !mounted) return;
    final session = context.read<AccountSession>();
    session.signIn(email: _typedEmail);
    if (!_signInMode) {
      _completed = true;
      return;
    }
    setState(() => _completed = true);
    if (session.email == null) {
      final waiting = _pageEmail ??= Completer<String?>();
      final found = await waiting.future.timeout(
        ShopifyAccountScreen.emailWait,
        onTimeout: () => null,
      );
      if (found != null) session.signIn(email: found);
    }
    if (mounted) _close(SignInOutcome.signedIn);
  }

  /// An `intent:` link: its app when one can open it, otherwise its web
  /// address in the page (as checkout does).
  Future<void> _openIntent(String url) async {
    final link = IntentLink.parse(url);
    final app = link?.appUri;
    final webApp =
        app != null && (app.scheme == 'https' || app.scheme == 'http');
    if (app != null &&
        await ShopifyWeb.launchExternally(app, appOnly: webApp)) {
      return;
    }
    final fallback =
        link?.fallbackUrl ?? (webApp && app.host.isNotEmpty ? app : null);
    final controller = _controller;
    if (!mounted || _finishing) return;
    if (fallback == null || controller == null) {
      _notice(ShopifyAccountScreen.linkFailed);
      return;
    }
    if (ShopifyWeb.isStorefrontPage('$fallback')) {
      _close();
      return;
    }
    try {
      await controller.loadRequest(fallback);
    } catch (_) {
      if (mounted) _notice(ShopifyAccountScreen.linkFailed);
    }
  }

  Future<void> _openInOtherApp(Uri target) async {
    final opened = await ShopifyWeb.launchExternally(target);
    if (!opened && mounted) _notice(ShopifyAccountScreen.linkFailed);
  }

  /// No WebView: the same page in the phone's browser.
  Future<void> _openInBrowser() async {
    final opened = await ShopifyWeb.launchExternally(
      CustomerAccount.ordersUrl,
    );
    if (!opened && mounted) _notice(ShopifyAccountScreen.browserFailed);
  }

  void _notice(String message) {
    final messenger = _messenger.currentState;
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(
            AppDims.gutter,
            0,
            AppDims.gutter,
            AppDims.gutter,
          ),
        ),
      );
  }

  void _startWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(ShopifyAccountScreen.loadTimeout, _showPageFailed);
  }

  void _showPageFailed() {
    _watchdog?.cancel();
    if (!mounted || _finishing) return;
    setState(() {
      _pageFailed = true;
      _progress = null;
    });
  }

  void _reload() {
    setState(() {
      _pageFailed = false;
      _progress = 0;
    });
    final controller = _controller;
    if (controller != null) _start(controller);
  }

  void _setProgress(double? value) {
    if (!mounted) return;
    setState(() => _progress = value);
  }

  /// Closes the screen, once: with [outcome], or [SignInOutcome.signedIn]
  /// once sign-in has completed.
  void _close([SignInOutcome? outcome]) {
    if (!mounted || _closing) return;
    final route = ModalRoute.of(context);
    // Already closing (system back).
    if (route != null && !route.isActive) return;
    _closing = true;
    final navigator = Navigator.of(context);
    if (route != null && !route.isCurrent) {
      navigator.popUntil((r) => r == route);
    }
    navigator.pop(_finishing ? SignInOutcome.signedIn : outcome);
  }

  /// System back steps back in the page first, then closes.
  Future<void> _handleBack() async {
    final controller = _controller;
    try {
      if (controller != null &&
          !_pageFailed &&
          !_finishing &&
          await controller.canGoBack().timeout(ShopifyWeb.platformWait)) {
        await controller.goBack().timeout(ShopifyWeb.platformWait);
        return;
      }
    } catch (_) {
      // Close instead.
    }
    _close();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final progress = _progress;
    final loading =
        controller != null && !_pageFailed && progress != null;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: ScaffoldMessenger(
        key: _messenger,
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(
              icon: const Icon(Icons.close),
              tooltip: _signInMode
                  ? ShopifyAccountScreen.closeSignIn
                  : ShopifyAccountScreen.closeOrders,
              onPressed: _close,
            ),
            title: Text(
              _signInMode
                  ? ShopifyAccountScreen.signInTitle
                  : ShopifyAccountScreen.ordersTitle,
            ),
            actions: [
              // A secure page of Shopify's, as a padlock says in a
              // browser. Not a button.
              Tooltip(
                message: ShopifyAccountScreen.secureLabel,
                excludeFromSemantics: true,
                child: Semantics(
                  label: ShopifyAccountScreen.secureLabel,
                  child: const SizedBox(
                    width: AppDims.controlTarget,
                    height: AppDims.controlTarget,
                    child: Icon(
                      Icons.lock_outline,
                      size: 20,
                      color: AppColors.secondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(3),
              child: SizedBox(
                height: 3,
                child: loading || _finishing
                    ? LinearProgressIndicator(
                        value: progress != null && progress > 0 && !_finishing
                            ? progress
                            : null,
                        minHeight: 3,
                        backgroundColor: AppColors.subtle,
                      )
                    : const Align(
                        alignment: Alignment.bottomCenter,
                        child: Divider(height: 1),
                      ),
              ),
            ),
          ),
          body: SafeArea(top: false, child: _buildBody(controller)),
        ),
      ),
    );
  }

  Widget _buildBody(WebViewController? controller) {
    if (controller == null) return _buildNoWebView();
    if (_pageFailed) {
      return _PageMessage(
        icon: Icons.wifi_off_rounded,
        title: _signInMode
            ? "Couldn't load sign-in"
            : "Couldn't load your orders",
        message: 'Check your connection and try again.',
        primaryLabel: 'Try again',
        onPrimary: _reload,
        secondaryLabel: 'Close',
        onSecondary: _close,
      );
    }
    return Stack(
      children: [
        Positioned.fill(
          key: const ValueKey('account-webview'),
          child: WebViewWidget(controller: controller),
        ),
        // Signed in: the account page is not shown while the screen
        // closes.
        if (_finishing)
          const Positioned.fill(
            child: ColoredBox(
              key: ValueKey('account-signed-in-cover'),
              color: AppColors.canvas,
            ),
          ),
      ],
    );
  }

  /// No WebView on this phone. From checkout, checkout goes on in the
  /// browser, where Shopify asks for the sign-in itself.
  Widget _buildNoWebView() {
    if (_signInMode && widget.forCheckout) {
      return _PageMessage(
        icon: Icons.lock_outline,
        title: 'Sign in at checkout',
        message:
            "This phone can't show the sign-in page in the app. Checkout "
            'opens in your browser and asks you to sign in there.',
        primaryLabel: 'Continue to checkout',
        primaryIsCheckout: true,
        onPrimary: () => _close(SignInOutcome.inBrowser),
        secondaryLabel: 'Back to cart',
        onSecondary: _close,
      );
    }
    return _PageMessage(
      icon: Icons.open_in_new,
      title: 'Open it in your browser',
      message: _signInMode
          ? "This phone can't show the sign-in page in the app."
          : "This phone can't show your orders in the app.",
      primaryLabel: 'Open in browser',
      onPrimary: _openInBrowser,
      secondaryLabel: 'Close',
      onSecondary: _close,
    );
  }
}

/// A full-page message: grey icon circle, title, secondary text, an ink
/// button (green only when it continues to checkout) and an ink text
/// link.
class _PageMessage extends StatelessWidget {
  const _PageMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
    this.primaryIsCheckout = false,
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
                child: Text(primaryLabel, textAlign: TextAlign.center),
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
