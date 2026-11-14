import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/app_nav.dart';
import 'package:fresh_market_app/delivery/delivery.dart';
import 'package:fresh_market_app/screens/cart_screen.dart';
import 'package:fresh_market_app/screens/checkout_screen.dart';
import 'package:fresh_market_app/services/checkout_log.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/services/intent_link.dart';
import 'package:fresh_market_app/state/cart_store.dart';
import 'package:fresh_market_app/widgets/deliver_to.dart';
import 'package:fresh_market_app/widgets/details_fields.dart';
import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'support/fake_webview.dart';
import 'support/test_app.dart';

const _launcher = MethodChannel('plugins.flutter.io/url_launcher');

/// Answers url_launcher calls with [result] (per URL when it is a
/// function) and records the URLs asked for; those that only an app, not
/// a browser, may open are also added to [appOnly].
List<String> mockLauncher(
  WidgetTester tester, {
  bool Function(String url)? result,
  List<String>? appOnly,
}) {
  final launched = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_launcher, (
    call,
  ) async {
    if (call.method != 'launch') return true;
    final args = call.arguments as Map;
    final url = args['url'] as String;
    launched.add(url);
    if (args['universalLinksOnly'] == true) appOnly?.add(url);
    return result?.call(url) ?? true;
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _launcher,
      null,
    ),
  );
  return launched;
}

/// Records what is copied to the clipboard.
List<String> mockClipboard(WidgetTester tester) {
  final copied = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == 'Clipboard.setData') {
        copied.add((call.arguments as Map)['text'] as String);
      }
      return null;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    ),
  );
  return copied;
}

/// The app-built link: cart attributes and the shopper's details.
final Uri prefilledUrl = Uri.parse(
  'https://testtfm.myshopify.com/cart/2001:1,2002:3'
  '?attributes%5BDelivery%20mode%5D=Fresh%20Market'
  '&attributes%5BDelivery%20pin%5D=25.18712%2C55.27961'
  '&checkout%5Bemail%5D=sara.ahmed%40example.com'
  '&checkout%5Bshipping_address%5D%5Bfirst_name%5D=Sara'
  '&checkout%5Bshipping_address%5D%5Blast_name%5D=Ahmed'
  '&checkout%5Bshipping_address%5D%5Baddress1%5D=Bay%20Square%20Building%205'
  '&checkout%5Bshipping_address%5D%5Bphone%5D=%2B971501234567',
);

const String checkoutPage =
    'https://testtfm.myshopify.com/checkouts/cn/hWNJ7zC7Jr4xwcCNwVOzY4lF/'
    'en-ae?_r=AQABDNxcy&checkout%5Bemail%5D=sara.ahmed%40example.com'
    '#contact';

const String thankYouPage =
    'https://testtfm.myshopify.com/checkouts/cn/hWNJ7zC7Jr4xwcCNwVOzY4lF/'
    'en-ae/thank-you';

/// A screen with an "Open checkout" button, so checkout can be closed.
class _Host extends StatelessWidget {
  const _Host(this.url);

  final Uri url;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => CheckoutScreen(url: url)),
        ),
        child: const Text('Open checkout'),
      ),
    ),
  );
}

/// Lets taps, routes and notices finish. Not pumpAndSettle: the progress
/// bar of a page still loading never stops moving.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

class _CountingCart extends CartStore {
  int clears = 0;

  @override
  void clear() {
    clears++;
    super.clear();
  }
}

void main() {
  group('CheckoutLog.safeUrl', () {
    test('keeps scheme, host and path; never the query or fragment', () {
      expect(
        CheckoutLog.safeUrl(checkoutPage),
        'https://testtfm.myshopify.com/checkouts/cn/<id>/en-ae',
      );
      expect(
        CheckoutLog.safeUrl(prefilledUrl.toString()),
        'https://testtfm.myshopify.com/cart/2001:1,2002:3',
      );
      expect(
        CheckoutLog.safeUrl('https://www.paypal.com/checkoutnow?token=EC-1'),
        'https://www.paypal.com/checkoutnow',
      );
      expect(
        CheckoutLog.safeUrl(
          'https://testtfm.myshopify.com/79173124173/orders/'
          '0b1e2f3a4c5d6e7f8a9b0c1d2e3f4a5b/authenticate?key=abc',
        ),
        'https://testtfm.myshopify.com/79173124173/orders/<id>/authenticate',
      );
    });

    test('phone, mail and app links keep their scheme only', () {
      expect(CheckoutLog.safeUrl('tel:+971501234567'), 'tel:');
      expect(CheckoutLog.safeUrl('mailto:sara@example.com'), 'mailto:');
      expect(
        CheckoutLog.safeUrl(
          'intent://pay?pa=sara@okbank&pn=Sara#Intent;scheme=upi;end',
        ),
        'intent://pay',
      );
      expect(CheckoutLog.safeUrl('about:blank'), 'about:blank');
      expect(CheckoutLog.safeUrl('data:text/html,<b>Sara</b>'), 'data:');
      expect(CheckoutLog.safeUrl(null), '-');
      expect(CheckoutLog.safeUrl('not a link'), '<link>');
    });

    test('an email or phone number in a path is removed', () {
      expect(
        CheckoutLog.safeUrl('https://example.com/u/sara%40example.com/x'),
        'https://example.com/u/[email]/x',
      );
      expect(
        CheckoutLog.safeUrl('https://example.com/call/0501234567'),
        'https://example.com/call/[phone]',
      );
    });
  });

  group('CheckoutLog.scrub', () {
    test('removes emails and phone numbers in every usual form', () {
      for (final text in [
        'sara.ahmed@example.com',
        'sara.ahmed%40example.com',
        '+971 50 123 4567',
        '+971501234567',
        '%2B971501234567',
        '00971501234567',
        '050 123 4567',
        '0501234567',
        '971501234567',
        '501234567',
      ]) {
        final out = CheckoutLog.scrub('value: $text.');
        expect(out, anyOf('value: [email].', 'value: [phone].'), reason: text);
      }
      // Variant ids, prices and times stay.
      expect(
        CheckoutLog.scrub('variant 47123456789012 AED 25.00 at 10:32'),
        'variant 47123456789012 AED 25.00 at 10:32',
      );
    });

    test('links inside a message lose their query', () {
      expect(
        CheckoutLog.scrub('Failed to load $checkoutPage now'),
        'Failed to load '
        'https://testtfm.myshopify.com/checkouts/cn/<id>/en-ae now',
      );
    });

    test('the values checkout was filled in with are removed', () {
      final log = CheckoutLog(checkoutUrl: prefilledUrl);
      expect(
        log.clean('Hello Sara Ahmed, Bay Square Building 5'),
        'Hello [removed] [removed], [removed]',
      );
      expect(log.clean('pin 25.18712,55.27961'), 'pin [removed]');
    });
  });

  group('CheckoutLog', () {
    test('keeps the last events with the time since checkout opened', () {
      var now = DateTime(2026, 11, 14, 10, 32, 5);
      final log = CheckoutLog(now: () => now, capacity: 3);
      log.add('page', 'started', link: checkoutPage);
      now = now.add(const Duration(milliseconds: 1500));
      log.add('load', '50%+');
      log.add('load', '50%+'); // the same again: a repeat
      now = now.add(const Duration(seconds: 1));
      log.add('page', 'finished', link: checkoutPage);
      log.add('url', '', link: thankYouPage);

      expect(log.events.map((e) => e.kind), ['load', 'page', 'url']);
      final report = log.report();
      expect(report, startsWith('Fresh Market checkout log\n'));
      expect(report, contains('Checkout opened 2026-11-14 10:32:05 (UTC'));
      expect(report, contains('   +1.5s  load   50%+ (x2)'));
      expect(
        report,
        contains(
          '   +2.5s  page   finished '
          'https://testtfm.myshopify.com/checkouts/cn/<id>/en-ae',
        ),
      );
      expect(report, isNot(contains('?')));
    });

    test('a noisy page cannot fill the log', () {
      final log = CheckoutLog(capacity: 200);
      for (var i = 0; i < 100; i++) {
        log.add('js', 'error $i', noisy: true);
      }
      log.add('page', 'finished', link: checkoutPage);
      expect(
        log.events.where((e) => e.kind == 'js'),
        hasLength(CheckoutLog.noisyLimit),
      );
      expect(
        log.events.map((e) => e.text),
        contains(
          'more page errors not '
          'recorded',
        ),
      );
      expect(log.events.last.kind, 'page');
    });

    test('long messages are cut', () {
      final log = CheckoutLog();
      log.add('js', 'x' * 500);
      expect(log.events.single.text.length, CheckoutLog.maxText + 1);
    });

    test('the copied text has this checkout and the one before', () {
      CheckoutLog.forget();
      addTearDown(CheckoutLog.forget);
      expect(CheckoutLog.supportReport(), contains('No checkout yet'));
      CheckoutLog.begin(prefilledUrl).add('app', 'first');
      CheckoutLog.begin(prefilledUrl).add('app', 'second');
      final report = CheckoutLog.supportReport();
      expect(report.indexOf('second'), lessThan(report.indexOf('first')));
      expect(report, contains('The checkout before:'));
    });

    test('the WebView version, not the phone model', () {
      expect(
        CheckoutLog.describeUserAgent(
          'Mozilla/5.0 (Linux; Android 14; SM-S918B Build/UP1A; wv) '
          'AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 '
          'Chrome/131.0.6778.39 Mobile Safari/537.36',
        ),
        'Android 14 · Chrome 131 · WebView',
      );
    });
  });

  group('CheckoutLog: what else is removed, and at what cost', () {
    test('a host can be a phone number too', () {
      expect(CheckoutLog.safeUrl('tel://0501234567'), 'tel://[phone]');
      expect(CheckoutLog.safeUrl('sms://+971501234567'), 'sms://[phone]');
      expect(
        CheckoutLog.safeUrl('intent://pay#Intent;scheme=upi;end'),
        'intent://pay',
      );
    });

    test('the query of an address that is not a whole link goes', () {
      expect(
        CheckoutLog.scrub(
          'POST /checkouts/unstable/graphql?firstName=Omar'
          '&address1=Villa%2012 failed',
        ),
        'POST /checkouts/unstable/graphql?… failed',
      );
      // A question in a sentence stays.
      expect(CheckoutLog.scrub('Is it ok? Yes'), 'Is it ok? Yes');
    });

    test('phone numbers written with brackets', () {
      expect(CheckoutLog.scrub('call (050) 123-4567.'), 'call [phone].');
      expect(CheckoutLog.scrub('call (04) 123 4567.'), 'call [phone].');
    });

    test('filled-in values written with lower-case escapes', () {
      final url = Uri.parse('https://testtfm.myshopify.com/cart/2001:1')
          .replace(
            queryParameters: {
              'checkout[shipping_address][first_name]': 'سارة',
              'checkout[shipping_address][address1]': 'Villa 12 شارع',
            },
          );
      final log = CheckoutLog(checkoutUrl: url);
      final name = Uri.encodeComponent('سارة');
      final street = Uri.encodeQueryComponent('Villa 12 شارع')
          .replaceAllMapped(RegExp('%[0-9A-F]{2}'), (m) => m[0]!.toLowerCase());
      expect(name, contains('%D8'));
      expect(street, startsWith('Villa+12+%d8'));
      expect(
        log.clean('a=${name.toLowerCase()} b=$name c=سارة d=$street'),
        'a=[removed] b=[removed] c=[removed] d=[removed]',
      );
    });

    test('the report says what is removed, no more', () {
      expect(
        CheckoutLog().report(),
        contains(
          'Links show site and path only. Emails, phone numbers and your '
          'saved details are removed.',
        ),
      );
    });

    test('a very long text is cut, never in the middle of a value', () {
      final out = CheckoutLog.scrub('${'a ' * 999}Sara%20Ahmed rest');
      expect(out, endsWith(' …'));
      expect(out, isNot(contains('Sa')));
      expect(out.length, lessThanOrEqualTo(CheckoutLog.maxScrubbed + 1));
      // A link at the start is still reduced first.
      expect(
        CheckoutLog.scrub('$checkoutPage ${'b' * 5000}'),
        startsWith('https://testtfm.myshopify.com/checkouts/cn/<id>/en-ae '),
      );
    });

    test('a long token or run of dots costs little', () {
      final log = CheckoutLog(checkoutUrl: prefilledUrl);
      final watch = Stopwatch()..start();
      // Each took seconds before (patterns that start over at every
      // letter of a long run).
      log.add('js', 'Failed: ${'aB3_-' * 4000}', noisy: true);
      log.add('js', 'x ${'a.' * 10000}', noisy: true);
      log.add('js', 'page data ${'word ' * 30000}', noisy: true);
      expect(watch.elapsedMilliseconds, lessThan(1000));
      expect(log.events, hasLength(3));
      expect(log.events.first.text, startsWith('Failed: aB3_-'));
    });

    test('past the limit, page errors are not even read', () {
      final log = CheckoutLog();
      for (var i = 0; i <= CheckoutLog.noisyLimit; i++) {
        log.add('js', 'error $i', noisy: true);
      }
      final big = 'https://example.com/x ${'word ' * 30000}';
      final watch = Stopwatch()..start();
      for (var i = 0; i < 300; i++) {
        log.add('js', big, noisy: true);
      }
      expect(watch.elapsedMilliseconds, lessThan(300));
      expect(
        log.events.where((e) => e.kind == 'js'),
        hasLength(CheckoutLog.noisyLimit),
      );
    });
  });

  group('IntentLink', () {
    test('reads the app link, its package and its web address', () {
      final link = IntentLink.parse(
        'intent://pay?pa=shop%40bank&am=25#Intent;scheme=upi;'
        'package=com.example.wallet;'
        'S.browser_fallback_url=https%3A%2F%2Fexample.com%2Fpay%3Fid%3D1;end',
      )!;
      expect(link.appUri, Uri.parse('upi://pay?pa=shop%40bank&am=25'));
      expect(link.package, 'com.example.wallet');
      expect(link.fallbackUrl, Uri.parse('https://example.com/pay?id=1'));
    });

    test('without a scheme there is only the web address', () {
      final link = IntentLink.parse(
        'intent:#Intent;action=android.intent.action.VIEW;'
        'S.browser_fallback_url=https%3A%2F%2Fexample.com%2F;end',
      )!;
      expect(link.appUri, isNull);
      expect(link.fallbackUrl, Uri.parse('https://example.com/'));
      expect(link.package, isNull);
    });

    test('never a script, a file or a non-web fallback', () {
      final link = IntentLink.parse(
        'intent://x#Intent;scheme=javascript;'
        'S.browser_fallback_url=javascript%3Aalert(1);end',
      )!;
      expect(link.appUri, isNull);
      expect(link.fallbackUrl, isNull);
      expect(
        IntentLink.parse('intent://x#Intent;scheme=file;end')!.appUri,
        isNull,
      );
    });

    test('other links are not intent links; bad encoding is kept', () {
      expect(IntentLink.parse('https://example.com'), isNull);
      expect(IntentLink.parse('tel:123'), isNull);
      final odd = IntentLink.parse(
        'INTENT://scan/#Intent;scheme=zxing;package=a%zz;end',
      )!;
      expect(odd.appUri, Uri.parse('zxing://scan/'));
      expect(odd.package, 'a%zz');
    });
  });

  group('CheckoutScreen in the WebView', () {
    late FakeWebViewPlatform webView;

    setUp(() {
      webView = FakeWebViewPlatform.install();
      CheckoutLog.forget();
    });

    Future<FakeWebViewController> open(
      WidgetTester tester, {
      Uri? url,
      CartStore? cart,
    }) async {
      await pumpScreen(tester, _Host(url ?? prefilledUrl), cart: cart);
      await tester.tap(find.text('Open checkout'));
      await settle(tester);
      expect(find.byType(CheckoutScreen), findsOneWidget);
      return webView.controller;
    }

    Future<void> chooseFromMenu(WidgetTester tester, String label) async {
      await tester.tap(find.byTooltip(CheckoutScreen.menuTooltip));
      await settle(tester);
      await tester.tap(find.text(label));
      await settle(tester);
    }

    testWidgets('loads the checkout link; the menu continues it in the '
        'browser', (tester) async {
      final launched = mockLauncher(tester);
      final page = await open(tester);
      expect(page.loaded, [prefilledUrl]);
      expect(find.byKey(const ValueKey('fake-webview')), findsOneWidget);

      await tester.tap(find.byTooltip(CheckoutScreen.menuTooltip));
      await settle(tester);
      expect(find.text(CheckoutScreen.openInBrowserLabel), findsOneWidget);
      expect(find.text(CheckoutScreen.copyLogLabel), findsOneWidget);
      await tester.tap(find.text(CheckoutScreen.openInBrowserLabel));
      await settle(tester);

      // The same link, cart kept; checkout says to finish there.
      expect(launched, [prefilledUrl.toString()]);
      expect(find.text('Checkout opened in your browser'), findsOneWidget);
      expect(find.byKey(const ValueKey('fake-webview')), findsNothing);
      await tester.tap(find.text('Back to cart'));
      await settle(tester);
      expect(find.text('Open checkout'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('no browser: says so and stays in checkout', (tester) async {
      mockLauncher(tester, result: (_) => false);
      await open(tester);
      await chooseFromMenu(tester, CheckoutScreen.openInBrowserLabel);
      expect(find.text(CheckoutScreen.browserFailed), findsOneWidget);
      expect(find.byKey(const ValueKey('fake-webview')), findsOneWidget);
    });

    testWidgets('Copy checkout log copies what happened, without the '
        "shopper's details", (tester) async {
      mockLauncher(tester, result: (url) => !url.startsWith('mailto'));
      final copied = mockClipboard(tester);
      final page = await open(tester);

      page.pageStarted(checkoutPage);
      page.progress(10);
      page.progress(70);
      page.progress(100);
      page.pageFinished(checkoutPage);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('fake-webview')));
      await tester.tap(find.byKey(const ValueKey('fake-webview')));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      page.console(
        'Failed for sara.ahmed@example.com +971 50 123 4567 at $checkoutPage',
      );
      page.console('just a log line', level: JavaScriptLogLevel.log);
      page.httpError(
        'https://testtfm.myshopify.com/api/unstable/graphql.json?q=Sara',
        404,
      );
      page.resourceError('https://analytics.example/x?e=1', mainFrame: false);
      expect(
        await page.request('tel:+971501234567'),
        NavigationDecision.prevent,
      );
      expect(
        await page.request('mailto:sara.ahmed@example.com'),
        NavigationDecision.prevent,
      );
      await settle(tester);
      // The mail app did not open.
      expect(find.text(CheckoutScreen.linkFailed), findsOneWidget);
      page.urlChanged(thankYouPage);
      await tester.pump();

      await chooseFromMenu(tester, CheckoutScreen.copyLogLabel);
      expect(find.text(CheckoutScreen.logCopied), findsOneWidget);
      final log = copied.single;
      expect(log, startsWith('Fresh Market checkout log'));
      expect(
        log,
        contains(
          'checkout opened, 5 fields filled in '
          'https://testtfm.myshopify.com/cart/2001:1,2002:3',
        ),
      );
      // An Android-only setting: not tried on the fake WebView.
      expect(log, isNot(contains('third-party')));
      expect(log, contains('WebView: Android 14 · Chrome 131 · WebView'));
      expect(
        log,
        contains(
          'page   started https://testtfm.myshopify.com/checkouts/cn/<id>/'
          'en-ae',
        ),
      );
      expect(log, contains('touch  tap/scroll (x2)'));
      expect(log, contains('app    app inactive'));
      expect(log, contains('app    app resumed'));
      expect(log, contains('load   10%+'));
      expect(log, contains('load   50%+'));
      expect(log, contains('load   100%'));
      expect(
        log,
        contains(
          // The shopper's own email is one of the filled-in values.
          'js     Failed for [removed] [phone] at '
          'https://testtfm.myshopify.com/checkouts/cn/<id>/en-ae',
        ),
      );
      expect(log, isNot(contains('just a log line')));
      expect(
        log,
        contains(
          'http   404 https://testtfm.myshopify.com/api/unstable/graphql.json',
        ),
      );
      expect(log, contains('(part of page) https://analytics.example/x'));
      expect(log, contains('nav    other app (page) tel:'));
      expect(log, contains('nav    other app (page) mailto:'));
      expect(log, contains('nav    no app could open it'));
      expect(
        log,
        contains(
          'order  order placed, cart emptied '
          'https://testtfm.myshopify.com/checkouts/cn/<id>/en-ae/thank-you',
        ),
      );
      expect(log, contains('app    log copied'));
      for (final private in [
        'sara',
        'Sara',
        'Ahmed',
        'example.com',
        '971',
        '50 123',
        'Bay Square',
        '25.18712',
        '55.27961',
        'checkout[',
        'checkout%5B',
        'attributes',
        '_r=',
        '#contact',
      ]) {
        expect(log, isNot(contains(private)), reason: private);
      }
    });

    testWidgets('the thank-you page empties the cart once and says Order '
        'placed', (tester) async {
      final cart = _CountingCart();
      final page = await open(tester, cart: cart);

      page.pageStarted(checkoutPage);
      page.pageFinished(checkoutPage);
      await tester.pump();
      expect(cart.clears, 0);
      expect(find.text('Checkout'), findsOneWidget);

      // Shopify moves to the thank-you page without loading a page.
      page.urlChanged(thankYouPage);
      await tester.pump();
      expect(cart.clears, 1);
      expect(find.text('Order placed'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);

      page.pageStarted(thankYouPage);
      page.pageFinished(thankYouPage);
      page.urlChanged('$thankYouPage?ref=1');
      await tester.pump();
      expect(cart.clears, 1);

      // After the order the menu no longer offers a second checkout.
      await tester.tap(find.byTooltip(CheckoutScreen.menuTooltip));
      await settle(tester);
      expect(find.text(CheckoutScreen.openInBrowserLabel), findsNothing);
      expect(find.text(CheckoutScreen.copyLogLabel), findsOneWidget);
      await tester.tapAt(const Offset(20, 400));
      await settle(tester);

      await tester.tap(find.text('Done'));
      await settle(tester);
      expect(find.byType(CheckoutScreen), findsNothing);
      expect(find.text('Open checkout'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an intent link opens its app, or else loads its web '
        'address', (tester) async {
      var appOpens = true;
      final launched = mockLauncher(tester, result: (_) => appOpens);
      final page = await open(tester);
      const intent =
          'intent://pay?am=25#Intent;scheme=upi;package=com.example.wallet;'
          'S.browser_fallback_url=https%3A%2F%2Fexample.com%2Fpay;end';

      expect(await page.request(intent), NavigationDecision.prevent);
      await settle(tester);
      expect(launched, ['upi://pay?am=25']);
      expect(page.loaded, [prefilledUrl]);

      appOpens = false;
      expect(await page.request(intent), NavigationDecision.prevent);
      await settle(tester);
      expect(launched, ['upi://pay?am=25', 'upi://pay?am=25']);
      expect(page.loaded, [prefilledUrl, Uri.parse('https://example.com/pay')]);
      expect(find.text(CheckoutScreen.linkFailed), findsNothing);

      // No app and nowhere to go: said, checkout stays.
      expect(
        await page.request('intent://scan/#Intent;scheme=zxing;end'),
        NavigationDecision.prevent,
      );
      await settle(tester);
      expect(find.text(CheckoutScreen.linkFailed), findsOneWidget);
      expect(page.loaded, hasLength(2));
      expect(find.byType(CheckoutScreen), findsOneWidget);
    });

    testWidgets('the whole page is never made blank; a frame may be', (
      tester,
    ) async {
      final page = await open(tester);
      expect(await page.request('about:blank'), NavigationDecision.prevent);
      expect(
        await page.request('about:blank', mainFrame: false),
        NavigationDecision.navigate,
      );
      expect(
        await page.request('https://www.paypal.com/checkoutnow?token=EC-1'),
        NavigationDecision.navigate,
      );
      expect(
        await page.request('javascript:void(0)'),
        NavigationDecision.prevent,
      );
    });

    testWidgets('two store links in a row close checkout once', (tester) async {
      final page = await open(tester);
      expect(
        await page.request('https://testtfm.myshopify.com/cart'),
        NavigationDecision.prevent,
      );
      expect(
        await page.request('https://testtfm.myshopify.com/'),
        NavigationDecision.prevent,
      );
      await settle(tester);
      expect(find.byType(CheckoutScreen), findsNothing);
      expect(find.text('Open checkout'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets("an HTTP error from the page's own requests never replaces "
        'a live checkout', (tester) async {
      final page = await open(tester);
      page.pageStarted(checkoutPage);
      page.pageFinished(checkoutPage);
      page.httpError('https://testtfm.myshopify.com/cart/2001:1', 410);
      await tester.pump();
      expect(find.text('Could not load checkout'), findsNothing);
      expect(find.byKey(const ValueKey('fake-webview')), findsOneWidget);
    });

    testWidgets('the cart link failing shows the retry page', (tester) async {
      final launched = mockLauncher(tester);
      final page = await open(tester);
      page.httpError(prefilledUrl.toString(), 410);
      await tester.pump();
      expect(find.text('Could not load checkout'), findsOneWidget);

      // "Open in browser" there continues the same checkout.
      await tester.tap(find.text(CheckoutScreen.openInBrowserLabel));
      await settle(tester);
      expect(launched, [prefilledUrl.toString()]);
      expect(find.text('Checkout opened in your browser'), findsOneWidget);
    });

    testWidgets('a page outside checkout offers the browser, above the '
        'page', (tester) async {
      final launched = mockLauncher(tester);
      final page = await open(tester);
      final hint = find.byKey(const ValueKey('checkout-offsite-hint'));
      final webViewBox = find.byKey(const ValueKey('fake-webview'));

      page.pageStarted(checkoutPage);
      await tester.pump();
      expect(hint, findsNothing);
      final fullTop = tester.getTopLeft(webViewBox).dy;

      // PayPal replaces checkout in the WebView.
      page.pageStarted('https://www.paypal.com/checkoutnow?token=EC-1');
      await tester.pump();
      expect(hint, findsOneWidget);
      expect(
        find.text(CheckoutScreen.offSiteHint('www.paypal.com')),
        findsOneWidget,
      );
      expect(
        CheckoutScreen.offSiteHint('www.paypal.com'),
        startsWith("You're on paypal.com."),
      );
      // The hint sits above the page, not over it.
      expect(tester.getTopLeft(webViewBox).dy, greaterThan(fullTop));
      expect(
        tester.getBottomLeft(hint).dy,
        lessThanOrEqualTo(tester.getTopLeft(webViewBox).dy),
      );

      // Back on Shopify: gone.
      page.urlChanged(checkoutPage);
      await tester.pump();
      expect(hint, findsNothing);

      page.pageStarted('https://www.paypal.com/signin');
      await tester.pump();
      await tester.tap(
        find.descendant(
          of: hint,
          matching: find.text(CheckoutScreen.openInBrowserLabel),
        ),
      );
      await settle(tester);
      expect(launched, [prefilledUrl.toString()]);
      expect(find.text('Checkout opened in your browser'), findsOneWidget);
    });

    test('pages outside checkout', () {
      expect(offCheckoutHost('https://www.paypal.com/x?y=1'), 'www.paypal.com');
      expect(offCheckoutHost('https://shop.app/pay'), 'shop.app');
      expect(offCheckoutHost(checkoutPage), isNull);
      expect(
        offCheckoutHost('https://checkout.shopify.com/1/sandboxes'),
        isNull,
      );
      expect(offCheckoutHost('https://other.myshopify.com/'), isNull);
      expect(offCheckoutHost('about:blank'), isNull);
      expect(offCheckoutHost(null), isNull);
    });

    testWidgets('system back steps back in the page, then leaves', (
      tester,
    ) async {
      final page = await open(tester);
      page.canGoBackValue = true;
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(page.goBackCalls, 1);
      expect(find.byType(CheckoutScreen), findsOneWidget);

      page.canGoBackValue = false;
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(CheckoutScreen), findsNothing);
    });

    testWidgets('a notice left on the cart is not shown over checkout', (
      tester,
    ) async {
      mockLauncher(tester);
      final cart = CartStore()
        ..add(sampleProducts()[0], sampleProducts()[0].variants[0]);
      await pumpScreen(
        tester,
        const CartScreen(),
        cart: cart,
        delivery: testDelivery(),
      );
      // A "Removed … Undo" notice never times out by itself.
      AppNav.showNotice(
        tester.element(find.byType(CartScreen)),
        'Removed Kiwi from your cart.',
        actionLabel: 'Undo',
        onAction: () {},
      );
      await settle(tester);
      expect(find.text('Undo'), findsOneWidget);

      await tester.tap(
        find.ancestor(
          of: find.textContaining('Checkout · '),
          matching: find.byType(FilledButton),
        ),
      );
      await settle(tester);
      expect(find.byType(CheckoutScreen), findsOneWidget);
      expect(find.text('Undo'), findsNothing);
      expect(find.byType(SnackBar), findsNothing);

      // And it is gone when checkout closes: its Undo would refill the
      // cart after an order.
      await tester.tap(find.byTooltip('Close checkout'));
      await settle(tester);
      expect(find.byType(CheckoutScreen), findsNothing);
      expect(find.text('Undo'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an app notice shown while checkout is open stays off it', (
      tester,
    ) async {
      await open(tester);
      AppNav.showNotice(
        tester.element(find.text('Open checkout', skipOffstage: false)),
        'Delivering to Mirdif',
      );
      await tester.pump();
      expect(find.text('Delivering to Mirdif'), findsNothing);
    });

    testWidgets('no WebView: the browser takes over as before', (tester) async {
      webView.available = false;
      final launched = mockLauncher(tester);
      await pumpScreen(tester, CheckoutScreen(url: prefilledUrl));
      await settle(tester);
      expect(launched, [prefilledUrl.toString()]);
      expect(find.text('Checkout opened in your browser'), findsOneWidget);
      // The log can still be copied.
      final copied = mockClipboard(tester);
      await tester.tap(find.byTooltip(CheckoutScreen.menuTooltip));
      await settle(tester);
      expect(find.text(CheckoutScreen.openInBrowserLabel), findsNothing);
      await tester.tap(find.text(CheckoutScreen.copyLogLabel));
      await settle(tester);
      expect(copied.single, contains('no WebView: opening the browser'));
    });

    testWidgets('an order the page left behind places after Open in '
        'browser is said, and the browser is never offered again', (
      tester,
    ) async {
      final launched = mockLauncher(tester);
      final cart = _CountingCart();
      final page = await open(tester, cart: cart);
      page.pageStarted(checkoutPage);
      page.pageFinished(checkoutPage);
      await chooseFromMenu(tester, CheckoutScreen.openInBrowserLabel);
      expect(find.text('Checkout opened in your browser'), findsOneWidget);

      // The page still running in the app finishes the order.
      page.urlChanged(thankYouPage);
      await tester.pump();
      expect(cart.clears, 1);
      expect(find.text('Order placed'), findsOneWidget);
      expect(find.text(CheckoutScreen.orderPlacedHereTitle), findsOneWidget);
      expect(find.text(CheckoutScreen.orderPlacedHereMessage), findsOneWidget);
      expect(find.text('Open again'), findsNothing);
      expect(find.textContaining('Finish your order there'), findsNothing);
      expect(launched, [prefilledUrl.toString()]);

      await tester.tap(find.text(CheckoutScreen.continueShoppingLabel));
      await settle(tester);
      expect(find.byType(CheckoutScreen), findsNothing);
      expect(find.text('Open checkout'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('after an order placed that way, system back goes on like '
        'Done', (tester) async {
      mockLauncher(tester);
      final page = await open(tester);
      await chooseFromMenu(tester, CheckoutScreen.openInBrowserLabel);
      page.urlChanged(thankYouPage);
      await tester.pump();
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(CheckoutScreen), findsNothing);
      expect(find.text('Open checkout'), findsOneWidget);
    });

    testWidgets('the page left behind for the browser opens no app and '
        'does not close checkout; back still does', (tester) async {
      final launched = mockLauncher(tester);
      final page = await open(tester);
      await chooseFromMenu(tester, CheckoutScreen.openInBrowserLabel);
      expect(
        await page.request('tel:+971501234567'),
        NavigationDecision.prevent,
      );
      expect(
        await page.request(
          'intent://pay#Intent;scheme=upi;'
          'S.browser_fallback_url=https%3A%2F%2Fexample.com%2F;end',
        ),
        NavigationDecision.prevent,
      );
      expect(
        await page.request('https://testtfm.myshopify.com/cart'),
        NavigationDecision.prevent,
      );
      // Its own pages may still load (an order it finishes is caught).
      expect(
        await page.request('https://www.paypal.com/checkoutnow?token=EC-1'),
        NavigationDecision.navigate,
      );
      await settle(tester);
      expect(launched, [prefilledUrl.toString()]);
      expect(page.loaded, [prefilledUrl]);
      expect(find.text('Checkout opened in your browser'), findsOneWidget);

      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(CheckoutScreen), findsNothing);
      expect(find.text('Open checkout'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a store link while the menu is open closes checkout, not '
        'just the menu', (tester) async {
      final page = await open(tester);
      await tester.tap(find.byTooltip(CheckoutScreen.menuTooltip));
      await settle(tester);
      expect(find.text(CheckoutScreen.copyLogLabel), findsOneWidget);

      expect(
        await page.request('https://testtfm.myshopify.com/cart'),
        NavigationDecision.prevent,
      );
      await settle(tester);
      expect(find.text(CheckoutScreen.copyLogLabel), findsNothing);
      expect(find.byType(CheckoutScreen), findsNothing);
      expect(find.text('Open checkout'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a store link while checkout is already closing leaves the '
        'screen under it', (tester) async {
      final page = await open(tester);
      // Something else closes checkout (the app going to a tab).
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pump();
      expect(find.byType(CheckoutScreen), findsOneWidget); // closing
      expect(
        await page.request('https://testtfm.myshopify.com/'),
        NavigationDecision.prevent,
      );
      await settle(tester);
      expect(find.byType(CheckoutScreen), findsNothing);
      expect(find.text('Open checkout'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an app link that is a web address goes to an app only, '
        'else loads in checkout', (tester) async {
      var appOpens = false;
      final appOnly = <String>[];
      final launched = mockLauncher(
        tester,
        result: (_) => appOpens,
        appOnly: appOnly,
      );
      final page = await open(tester);

      expect(
        await page.request(
          'intent://shop.app/pay/123#Intent;scheme=https;'
          'package=com.shopify.arrive;'
          'S.browser_fallback_url=https%3A%2F%2Fshop.app%2Fpay%2F123%3Fw%3D1;'
          'end',
        ),
        NavigationDecision.prevent,
      );
      await settle(tester);
      // Never handed to a browser: no app took it, so its web address
      // loads here, as in Chrome.
      expect(appOnly, ['https://shop.app/pay/123']);
      expect(page.loaded.last, Uri.parse('https://shop.app/pay/123?w=1'));

      // With no web address, the link itself loads here.
      expect(
        await page.request('intent://shop.app/pay/456#Intent;scheme=https;end'),
        NavigationDecision.prevent,
      );
      await settle(tester);
      expect(page.loaded.last, Uri.parse('https://shop.app/pay/456'));

      // An app that takes it: nothing loads here.
      appOpens = true;
      expect(
        await page.request('intent://shop.app/pay/789#Intent;scheme=https;end'),
        NavigationDecision.prevent,
      );
      await settle(tester);
      expect(page.loaded, hasLength(3));

      // Other app links may still go to any app.
      expect(
        await page.request('intent://pay#Intent;scheme=upi;end'),
        NavigationDecision.prevent,
      );
      await settle(tester);
      expect(launched.last, 'upi://pay');
      expect(appOnly, hasLength(3));
      expect(find.text(CheckoutScreen.linkFailed), findsNothing);
      expect(find.byType(CheckoutScreen), findsOneWidget);
    });

    testWidgets('an app link whose web address is a store page closes '
        'checkout', (tester) async {
      mockLauncher(tester, result: (_) => false);
      final page = await open(tester);
      expect(
        await page.request(
          'intent://scan#Intent;scheme=zxing;'
          'S.browser_fallback_url=https%3A%2F%2Ftesttfm.myshopify.com%2Fcart;'
          'end',
        ),
        NavigationDecision.prevent,
      );
      await settle(tester);
      expect(page.loaded, [prefilledUrl]);
      expect(find.byType(CheckoutScreen), findsNothing);
      expect(find.text('Open checkout'), findsOneWidget);
    });

    testWidgets('an order placed while an app was asked is not covered by '
        'its web address', (tester) async {
      final answer = Completer<bool>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        _launcher,
        (call) => answer.future,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          _launcher,
          null,
        ),
      );
      final page = await open(tester);
      expect(
        await page.request(
          'intent://pay#Intent;scheme=upi;'
          'S.browser_fallback_url=https%3A%2F%2Fexample.com%2Fpay;end',
        ),
        NavigationDecision.prevent,
      );
      await tester.pump();
      page.urlChanged(thankYouPage);
      await tester.pump();
      answer.complete(false);
      await settle(tester);
      expect(page.loaded, [prefilledUrl]);
      expect(find.text('Order placed'), findsOneWidget);
      expect(find.text(CheckoutScreen.linkFailed), findsNothing);
    });

    testWidgets('scripts, files and data never load or go to another app', (
      tester,
    ) async {
      final launched = mockLauncher(tester);
      final page = await open(tester);
      for (final url in [
        'javascript:void(0)',
        'JAVASCRIPT:alert(1)',
        'data:text/html;base64,PGI+eDwvYj4=',
        'file:///sdcard/Download/x.html',
        'blob:https://testtfm.myshopify.com/7d1c2b3a',
        'content://com.android.contacts/contacts/1',
        'about:blank',
      ]) {
        expect(
          await page.request(url),
          NavigationDecision.prevent,
          reason: url,
        );
      }
      await settle(tester);
      expect(launched, isEmpty);
      expect(page.loaded, [prefilledUrl]);
      expect(find.byType(CheckoutScreen), findsOneWidget);
    });

    testWidgets("checkout's notices show at the top and leave the page's "
        'Pay now bar clear', (tester) async {
      mockLauncher(tester, result: (_) => false);
      final page = await open(tester);
      expect(
        await page.request('tel:+971501234567'),
        NavigationDecision.prevent,
      );
      await settle(tester);
      final notice = find.byKey(const ValueKey('checkout-notice'));
      final webViewBox = find.byKey(const ValueKey('fake-webview'));
      expect(
        find.descendant(
          of: notice,
          matching: find.text(CheckoutScreen.linkFailed),
        ),
        findsOneWidget,
      );
      expect(find.byType(SnackBar), findsNothing);
      final box = tester.getRect(notice);
      final pageBox = tester.getRect(webViewBox);
      expect(box.top, lessThan(pageBox.top + 16));
      expect(box.bottom, lessThan(pageBox.top + 100));
      // It takes no touches: the page under it gets them.
      final hit = tester.hitTestOnBinding(box.center);
      final pageRender = tester.renderObject(webViewBox);
      expect(hit.path.any((entry) => entry.target == pageRender), isTrue);

      await tester.pump(CheckoutScreen.noticeTime);
      await tester.pump();
      expect(notice, findsNothing);
      expect(find.text(CheckoutScreen.linkFailed), findsNothing);
    });

    testWidgets('third-party cookies are allowed before checkout loads', (
      tester,
    ) async {
      final original = CheckoutScreen.allowThirdPartyCookies;
      addTearDown(() => CheckoutScreen.allowThirdPartyCookies = original);
      int? loadedWhenAsked;
      CheckoutScreen.allowThirdPartyCookies = (_) async {
        loadedWhenAsked = webView.controller.loaded.length;
        return true;
      };
      final copied = mockClipboard(tester);
      final page = await open(tester);
      expect(loadedWhenAsked, 0);
      expect(page.loaded, [prefilledUrl]);
      await chooseFromMenu(tester, CheckoutScreen.copyLogLabel);
      expect(copied.single, contains('app    third-party cookies allowed'));
    });

    testWidgets('checkout loads even when cookies cannot be allowed', (
      tester,
    ) async {
      final original = CheckoutScreen.allowThirdPartyCookies;
      addTearDown(() => CheckoutScreen.allowThirdPartyCookies = original);
      // Never answers.
      CheckoutScreen.allowThirdPartyCookies = (_) => Completer<bool>().future;
      final copied = mockClipboard(tester);
      final page = await open(tester);
      expect(page.loaded, isEmpty);
      await tester.pump(CheckoutScreen.platformWait);
      await tester.pump();
      expect(page.loaded, [prefilledUrl]);
      await chooseFromMenu(tester, CheckoutScreen.copyLogLabel);
      expect(
        copied.single,
        contains('third-party cookies not allowed (TimeoutException)'),
      );

      CheckoutScreen.allowThirdPartyCookies = (_) async =>
          throw StateError('no');
      CheckoutLog.forget();
      webView.controllers.clear();
      await tester.tap(find.byTooltip('Close checkout'));
      await settle(tester);
      final again = await open(tester);
      expect(again.loaded, [prefilledUrl]);
    });
  });

  testWidgets('the details sheet asks Android not to offer its own save '
      'over checkout', (tester) async {
    await pumpScreen(
      tester,
      Scaffold(
        body: CheckoutDetailsSheet(
          area: DeliveryConfig.areaNamed('Business Bay')!,
        ),
      ),
    );
    final group = tester.widget<AutofillGroup>(find.byType(AutofillGroup));
    expect(group.onDisposeAction, AutofillContextAction.cancel);
  });

  group('Opening checkout and the keyboard', () {
    late FocusNode field;
    late FocusNode button;

    setUp(() {
      FakeWebViewPlatform.install();
      CheckoutLog.forget();
      field = FocusNode();
      button = FocusNode();
    });

    tearDown(() {
      field.dispose();
      button.dispose();
    });

    /// A screen with a text field and a button; returns its context for
    /// [AppNav.openCheckout]. The keyboard is up.
    Future<BuildContext> pumpHost(WidgetTester tester) async {
      final cart = CartStore()
        ..add(sampleProducts()[0], sampleProducts()[0].variants[0]);
      await pumpScreen(
        tester,
        Scaffold(
          body: Column(
            children: [
              TextField(focusNode: field),
              FilledButton(
                focusNode: button,
                onPressed: () {},
                child: const Text('Go'),
              ),
            ],
          ),
        ),
        cart: cart,
        delivery: testDelivery(),
      );
      tester.view.viewInsets = const FakeViewPadding(bottom: 900);
      await tester.pump();
      return tester.element(find.byType(TextField));
    }

    testWidgets('a text field lets go at once; checkout opens as soon as '
        'the keyboard has gone', (tester) async {
      final context = await pumpHost(tester);
      field.requestFocus();
      await tester.pump();
      expect(field.hasFocus, isTrue);

      unawaited(AppNav.openCheckout(context));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(field.hasFocus, isFalse);
      expect(find.byType(CheckoutScreen), findsNothing);

      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pump();
      expect(find.byType(CheckoutScreen), findsOneWidget);
    });

    testWidgets('a focused button keeps its focus; checkout waits for the '
        'keyboard no longer than 600 ms', (tester) async {
      final context = await pumpHost(tester);
      button.requestFocus();
      await tester.pump();

      unawaited(AppNav.openCheckout(context));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(button.hasFocus, isTrue);

      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(CheckoutScreen), findsNothing);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump();
      expect(find.byType(CheckoutScreen), findsOneWidget);
    });
  });

  testWidgets('Continue in the details sheet lets go of the keyboard at '
      'once, before checkout opens', (tester) async {
    final area = DeliveryConfig.areaNamed('Business Bay')!;
    await pumpScreen(
      tester,
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => showCheckoutDetailsSheet(context, area: area),
              child: const Text('Open sheet'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open sheet'));
    await tester.pumpAndSettle();
    final first = find.descendant(
      of: find.byWidgetPredicate(
        (w) => w is DetailsField && w.label == 'First name',
      ),
      matching: find.byType(EditableText),
    );
    await tester.enterText(first, 'Sara');
    await tester.pump();
    final focused = FocusManager.instance.primaryFocus;
    expect(
      focused?.context?.findAncestorWidgetOfExactType<EditableText>(),
      isNotNull,
    );

    final go = find.text(CheckoutDetailsSheet.continueLabel);
    await tester.ensureVisible(go);
    await tester.pump();
    await tester.tap(go);
    // Before the sheet has gone.
    await tester.pump();
    expect(find.byType(CheckoutDetailsSheet), findsOneWidget);
    expect(focused!.hasFocus, isFalse);
    await tester.pumpAndSettle();
    expect(find.byType(CheckoutDetailsSheet), findsNothing);
  });
}
