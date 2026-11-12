import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../theme/app_theme.dart';

/// Shopify checkout for the cart, shown inside the app. Where a WebView
/// cannot be created the checkout opens in the device browser instead.
///
/// The cart is left as it is when the shopper leaves this screen.
class CheckoutScreen extends StatefulWidget {
  const CheckoutScreen({super.key, required this.url});

  /// The Shopify cart permalink (`CartStore.checkoutUrl`).
  final Uri url;

  @override
  State<CheckoutScreen> createState() => _CheckoutScreenState();
}

enum _BrowserState { opening, opened, failed }

class _CheckoutScreenState extends State<CheckoutScreen> {
  /// Null when the WebView could not be created (browser fallback).
  WebViewController? _controller;

  /// 0..1 while a page loads; null when idle.
  double? _progress = 0;

  /// Set when the checkout page itself failed to load.
  bool _pageFailed = false;

  _BrowserState _browser = _BrowserState.opening;

  @override
  void initState() {
    super.initState();
    _controller = _createWebView();
    if (_controller == null) _openInBrowser();
  }

  WebViewController? _createWebView() {
    try {
      final controller = WebViewController();
      controller
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageStarted: (_) => _setProgress(0),
            onProgress: (value) =>
                _setProgress(value >= 100 ? null : value / 100),
            onPageFinished: (_) => _setProgress(null),
            onWebResourceError: (error) {
              if (error.isForMainFrame != true || !mounted) return;
              setState(() {
                _pageFailed = true;
                _progress = null;
              });
            },
            onNavigationRequest: (request) {
              final target = Uri.tryParse(request.url);
              if (target == null) return NavigationDecision.prevent;
              if (target.scheme == 'http' ||
                  target.scheme == 'https' ||
                  target.scheme == 'about') {
                return NavigationDecision.navigate;
              }
              // Phone, mail and payment-app links belong to other apps.
              _launchExternally(target);
              return NavigationDecision.prevent;
            },
          ),
        )
        ..loadRequest(widget.url);
      return controller;
    } catch (_) {
      // No WebView on this device (or in tests).
      return null;
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
    _controller?.loadRequest(widget.url);
  }

  /// System back steps back inside checkout first, then leaves it.
  Future<void> _handleBack() async {
    final controller = _controller;
    final navigator = Navigator.of(context);
    try {
      if (controller != null && !_pageFailed && await controller.canGoBack()) {
        await controller.goBack();
        return;
      }
    } catch (_) {
      // Fall through and leave checkout.
    }
    if (mounted) navigator.pop();
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
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Checkout'),
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
