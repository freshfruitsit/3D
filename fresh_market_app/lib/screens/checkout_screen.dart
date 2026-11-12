import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app.dart';
import '../app_nav.dart';
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

/// Shopify checkout for the cart, shown inside the app. Where a WebView
/// cannot be used the checkout opens in the device browser instead.
///
/// The cart is kept while the shopper is in checkout and emptied once the
/// order confirmation page is reached.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, required this.url});

  /// The Shopify cart permalink (`CartStore.checkoutUrl`).
  final Uri url;

  /// How long the page may stay silent before the retry message shows.
  static const Duration loadTimeout = Duration(seconds: 12);

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

enum _BrowserState { opening, opened, failed }

class _CheckoutScreenState extends State<CheckoutScreen> {
  /// Null when the WebView could not be used (browser fallback).
  WebViewController? _controller;

  /// 0..1 while a page loads; null when idle.
  double? _progress = 0;

  /// Set when the checkout page itself failed to load.
  bool _pageFailed = false;

  /// Set once the order confirmation page was reached (cart emptied).
  bool _orderPlaced = false;

  /// Fires when the page never starts loading.
  Timer? _watchdog;

  _BrowserState _browser = _BrowserState.opening;

  @override
  void initState() {
    super.initState();
    _controller = _createWebView();
    if (_controller == null) {
      _openInBrowser();
    } else {
      _start(_controller!);
    }
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
      // No WebView on this device (or in tests).
      return null;
    }
  }

  /// Sets the WebView up and loads the checkout. Every step is a call to
  /// the platform that can fail (WebView disabled or being updated); then
  /// the browser takes over.
  Future<void> _start(WebViewController controller) async {
    _startWatchdog();
    try {
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      await controller.setNavigationDelegate(_delegate());
      await controller.loadRequest(widget.url);
    } catch (_) {
      _watchdog?.cancel();
      if (!mounted) return;
      setState(() => _controller = null);
      _openInBrowser();
    }
  }

  NavigationDelegate _delegate() => NavigationDelegate(
    onPageStarted: (url) {
      _watchdog?.cancel();
      _checkOrderPlaced(url);
      _setProgress(0);
    },
    onProgress: (value) {
      if (value > 0) _watchdog?.cancel();
      _setProgress(value >= 100 ? null : value / 100);
    },
    onPageFinished: (url) {
      _watchdog?.cancel();
      _checkOrderPlaced(url);
      _setProgress(null);
    },
    onUrlChange: (change) => _checkOrderPlaced(change.url),
    onWebResourceError: (error) {
      if (error.isForMainFrame != true) return;
      _showPageFailed();
    },
    onHttpError: (error) {
      // Shopify answers the cart link itself with an error page (410)
      // when it cannot build the checkout.
      final status = error.response?.statusCode ?? 0;
      final uri = error.request?.uri ?? error.response?.uri;
      if (status < 400 || uri == null) return;
      final isCartLink =
          uri == widget.url ||
          (uri.host == widget.url.host && uri.path.startsWith('/cart/'));
      if (isCartLink) _showPageFailed();
    },
    onNavigationRequest: (request) {
      final target = Uri.tryParse(request.url);
      if (target == null) return NavigationDecision.prevent;
      if (target.scheme == 'http' ||
          target.scheme == 'https' ||
          target.scheme == 'about') {
        if (request.isMainFrame && leavesCheckoutUrl(request.url)) {
          // A link back to the web storefront: return to the app.
          _leave();
          return NavigationDecision.prevent;
        }
        return NavigationDecision.navigate;
      }
      // Phone, mail and payment-app links belong to other apps.
      _launchExternally(target);
      return NavigationDecision.prevent;
    },
  );

  void _startWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer(CheckoutScreen.loadTimeout, _showPageFailed);
  }

  void _showPageFailed() {
    _watchdog?.cancel();
    if (!mounted || _orderPlaced) return;
    setState(() {
      _pageFailed = true;
      _progress = null;
    });
  }

  /// Empties the cart, once, when the order confirmation page shows.
  void _checkOrderPlaced(String? url) {
    if (_orderPlaced || url == null || !mounted) return;
    if (!isOrderConfirmationUrl(url)) return;
    context.read<CartStore>().clear();
    setState(() => _orderPlaced = true);
  }

  /// Closes checkout: back to the cart, or to Home once the order is
  /// placed (the cart is empty then).
  void _leave() {
    if (!mounted) return;
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
    if (!mounted) return;
    setState(() {
      _browser = opened ? _BrowserState.opened : _BrowserState.failed;
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

  /// System back steps back inside checkout first, then leaves it.
  Future<void> _handleBack() async {
    final controller = _controller;
    try {
      if (controller != null &&
          !_pageFailed &&
          !_orderPlaced &&
          await controller.canGoBack()) {
        await controller.goBack();
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
    final progress = _progress;
    final loading = controller != null && !_pageFailed && progress != null;

    return PopScope(
      canPop: controller == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: Scaffold(
        backgroundColor: controller != null && !_pageFailed
            ? AppColors.surface
            : null,
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
                      backgroundColor: AppColors.tile,
                    )
                  : null,
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: controller == null
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
                  secondaryLabel: 'Open in browser',
                  onSecondary: () => _launchExternally(widget.url),
                )
              : WebViewWidget(controller: controller),
        ),
      ),
    );
  }

  Widget _buildBrowserFallback() {
    void backToCart() => Navigator.of(context).pop();
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
        secondaryLabel: 'Back to cart',
        onSecondary: backToCart,
      ),
      _BrowserState.failed => _CheckoutMessage(
        icon: Icons.error_outline,
        title: 'Could not open checkout',
        message:
            'No browser could be opened on this device. '
            'Your cart is saved.',
        primaryLabel: 'Try again',
        onPrimary: _openInBrowser,
        secondaryLabel: 'Back to cart',
        onSecondary: backToCart,
      ),
    };
  }
}

class _CheckoutMessage extends StatelessWidget {
  const _CheckoutMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColors.tile,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: AppColors.tileLabel),
            ),
            const SizedBox(height: 16),
            Text(title, textAlign: TextAlign.center, style: AppText.heading),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center, style: AppText.body),
            const SizedBox(height: 20),
            FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
            const SizedBox(height: 4),
            TextButton(onPressed: onSecondary, child: Text(secondaryLabel)),
          ],
        ),
      ),
    );
  }
}
