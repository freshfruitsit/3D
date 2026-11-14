import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

/// Stands in for the phone's WebView in tests: records what checkout
/// (or the account pages) load and lets a test play the page's callbacks
/// (page started, URL changes, navigation requests, errors, console
/// messages, JavaScript channel messages).
///
/// Install with [FakeWebViewPlatform.install]; once installed, a test
/// that needs the browser fallback sets [available] to false.
class FakeWebViewPlatform extends WebViewPlatform {
  FakeWebViewPlatform._();

  static final FakeWebViewPlatform instance = FakeWebViewPlatform._();

  /// Makes [instance] the WebView of the tests in this file and resets
  /// it before each test.
  static FakeWebViewPlatform install() {
    WebViewPlatform.instance = instance;
    instance
      ..controllers.clear()
      ..available = true;
    return instance;
  }

  /// False: creating a WebView fails, as on a phone with none.
  bool available = true;

  final List<FakeWebViewController> controllers = [];

  FakeWebViewController get controller => controllers.single;

  @override
  PlatformWebViewController createPlatformWebViewController(
    PlatformWebViewControllerCreationParams params,
  ) {
    if (!available) throw StateError('No WebView');
    final controller = FakeWebViewController(params);
    controllers.add(controller);
    return controller;
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(
    PlatformNavigationDelegateCreationParams params,
  ) => FakeNavigationDelegate(params);

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(
    PlatformWebViewWidgetCreationParams params,
  ) => _FakeWebViewWidget(params);
}

class FakeWebViewController extends PlatformWebViewController {
  FakeWebViewController(super.params) : super.implementation();

  FakeNavigationDelegate? delegate;
  final List<Uri> loaded = [];
  void Function(JavaScriptConsoleMessage)? onConsoleMessage;
  bool canGoBackValue = false;
  int goBackCalls = 0;

  /// The JavaScript channels added, by name.
  final Map<String, void Function(JavaScriptMessage)> channels = {};

  /// Every script run in the page, in order.
  final List<String> scripts = [];

  /// What `runJavaScriptReturningResult` answers.
  Object scriptResult = '';

  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}

  @override
  Future<void> setPlatformNavigationDelegate(
    PlatformNavigationDelegate handler,
  ) async {
    delegate = handler as FakeNavigationDelegate;
  }

  @override
  Future<void> loadRequest(LoadRequestParams params) async {
    loaded.add(params.uri);
  }

  @override
  Future<void> setOnConsoleMessage(
    void Function(JavaScriptConsoleMessage consoleMessage) onConsoleMessage,
  ) async {
    this.onConsoleMessage = onConsoleMessage;
  }

  @override
  Future<String?> getUserAgent() async =>
      'Mozilla/5.0 (Linux; Android 14; SM-S918B Build/UP1A; wv) '
      'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 '
      'Chrome/131.0.6778.39 Mobile Safari/537.36';

  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams params) async {
    channels[params.name] = params.onMessageReceived;
  }

  @override
  Future<void> runJavaScript(String javaScript) async {
    scripts.add(javaScript);
  }

  @override
  Future<Object> runJavaScriptReturningResult(String javaScript) async {
    scripts.add(javaScript);
    return scriptResult;
  }

  /// The page sends [message] on the channel [name].
  void post(String name, String message) =>
      channels[name]!(JavaScriptMessage(message: message));

  @override
  Future<bool> canGoBack() async => canGoBackValue;

  @override
  Future<void> goBack() async => goBackCalls++;

  /// The page asks to open [url]; returns checkout's answer.
  Future<NavigationDecision> request(String url, {bool mainFrame = true}) =>
      Future.value(
        delegate!.onNavigationRequest!(
          NavigationRequest(url: url, isMainFrame: mainFrame),
        ),
      );

  void pageStarted(String url) => delegate!.onPageStarted!(url);
  void pageFinished(String url) => delegate!.onPageFinished!(url);
  void progress(int value) => delegate!.onProgress!(value);
  void urlChanged(String url) => delegate!.onUrlChange!(UrlChange(url: url));

  void httpError(String url, int status) => delegate!.onHttpError!(
    HttpResponseError(
      request: WebResourceRequest(uri: Uri.parse(url)),
      response: WebResourceResponse(uri: null, statusCode: status),
    ),
  );

  void resourceError(String url, {required bool mainFrame}) =>
      delegate!.onWebResourceError!(
        WebResourceError(
          errorCode: -2,
          description: 'net::ERR_NAME_NOT_RESOLVED',
          url: url,
          isForMainFrame: mainFrame,
        ),
      );

  void console(String message, {JavaScriptLogLevel? level}) =>
      onConsoleMessage!(
        JavaScriptConsoleMessage(
          level: level ?? JavaScriptLogLevel.error,
          message: message,
        ),
      );
}

class FakeNavigationDelegate extends PlatformNavigationDelegate {
  FakeNavigationDelegate(super.params) : super.implementation();

  NavigationRequestCallback? onNavigationRequest;
  PageEventCallback? onPageStarted;
  PageEventCallback? onPageFinished;
  ProgressCallback? onProgress;
  WebResourceErrorCallback? onWebResourceError;
  UrlChangeCallback? onUrlChange;
  HttpResponseErrorCallback? onHttpError;
  SslAuthErrorCallback? onSslAuthError;

  @override
  Future<void> setOnNavigationRequest(NavigationRequestCallback cb) async =>
      onNavigationRequest = cb;
  @override
  Future<void> setOnPageStarted(PageEventCallback cb) async =>
      onPageStarted = cb;
  @override
  Future<void> setOnPageFinished(PageEventCallback cb) async =>
      onPageFinished = cb;
  @override
  Future<void> setOnProgress(ProgressCallback cb) async => onProgress = cb;
  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback cb) async =>
      onWebResourceError = cb;
  @override
  Future<void> setOnUrlChange(UrlChangeCallback cb) async => onUrlChange = cb;
  @override
  Future<void> setOnHttpError(HttpResponseErrorCallback cb) async =>
      onHttpError = cb;
  @override
  Future<void> setOnSSlAuthError(SslAuthErrorCallback cb) async =>
      onSslAuthError = cb;
}

class _FakeWebViewWidget extends PlatformWebViewWidget {
  _FakeWebViewWidget(super.params) : super.implementation();

  /// Fills its box and, like a platform view, takes touches.
  @override
  Widget build(BuildContext context) => const ColoredBox(
    key: ValueKey('fake-webview'),
    color: Color(0x00000000),
    child: SizedBox.expand(),
  );
}
