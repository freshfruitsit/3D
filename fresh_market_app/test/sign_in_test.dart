import 'dart:async';
import 'dart:convert';

import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/app_nav.dart';
import 'package:fresh_market_app/config/store_config.dart';
import 'package:fresh_market_app/profile/customer_details.dart';
import 'package:fresh_market_app/profile/profile_vault.dart';
import 'package:fresh_market_app/screens/account_screen.dart';
import 'package:fresh_market_app/screens/cart_screen.dart';
import 'package:fresh_market_app/screens/checkout_screen.dart';
import 'package:fresh_market_app/screens/shopify_account_screen.dart';
import 'package:fresh_market_app/services/checkout_log.dart';
import 'package:fresh_market_app/services/customer_account.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/services/shopify_web.dart';
import 'package:fresh_market_app/state/account_session.dart';
import 'package:fresh_market_app/state/cart_store.dart';
import 'package:fresh_market_app/state/profile_store.dart';
import 'package:fresh_market_app/theme/app_theme.dart';
import 'package:fresh_market_app/widgets/sign_in_sheet.dart';
import 'package:material_ui/material_ui.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

import 'support/fake_webview.dart';
import 'support/test_app.dart';

const String shopId = '79173124173';
const String signInPage =
    'https://shopify.com/authentication/$shopId/login'
    '?client_id=abc&locale=en&redirect_uri=https%3A%2F%2Ftesttfm.myshopify.com'
    '%2Fcustomer_authentication%2Fcallback';
const String accountPage = 'https://shopify.com/$shopId/account';
const String callback =
    'https://testtfm.myshopify.com/customer_authentication/callback'
    '?code=c0de&state=s1';
const String storeAccount = 'https://testtfm.myshopify.com/account';

const _launcher = MethodChannel('plugins.flutter.io/url_launcher');

/// Answers url_launcher calls with true and records the URLs.
List<String> mockLauncher(WidgetTester tester) {
  final launched = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_launcher, (
    call,
  ) async {
    if (call.method != 'launch') return true;
    launched.add((call.arguments as Map)['url'] as String);
    return true;
  });
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _launcher,
      null,
    ),
  );
  return launched;
}

/// Records what is said to screen readers.
List<String> recordAnnouncements(WidgetTester tester) {
  final said = <String>[];
  tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
    SystemChannels.accessibility,
    (message) async {
      final map = message as Map<Object?, Object?>;
      if (map['type'] == 'announce') {
        said.add((map['data']! as Map<Object?, Object?>)['message']! as String);
      }
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger
        .setMockDecodedMessageHandler<dynamic>(
          SystemChannels.accessibility,
          null,
        ),
  );
  return said;
}

/// Lets taps, routes and sheets finish. Not pumpAndSettle: a page's
/// progress bar never stops moving.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

const ContactDetails sara = ContactDetails(
  firstName: 'Sara',
  lastName: 'Ahmed',
  mobile: '+971501234567',
  email: 'sara@example.com',
);

/// A session that asks to sign in before checkout, saved in [vault].
AccountSession gatedSession({MemoryProfileVault? vault}) =>
    AccountSession(vault: vault ?? MemoryProfileVault());

/// A screen with a button that opens [open] and keeps what it returns.
class _Host extends StatelessWidget {
  const _Host(this.open, this.results);

  final Future<Object?> Function(BuildContext context) open;
  final List<Object?> results;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () async => results.add(await open(context)),
        child: const Text('Open'),
      ),
    ),
  );
}

void main() {
  final kiwi = sampleProducts()[0];

  group('AccountSession', () {
    test('signing in is saved encrypted on the phone and read back', () async {
      final vault = MemoryProfileVault();
      final session = AccountSession(vault: vault)
        ..signIn(email: ' sara@example.com ');
      await session.idle;
      expect(session.signedIn, isTrue);
      expect(session.email, 'sara@example.com');
      expect(jsonDecode(vault.value!), {
        'v': 1,
        'signedIn': true,
        'email': 'sara@example.com',
      });

      final again = AccountSession(vault: vault);
      expect(again.signedIn, isFalse);
      await again.load();
      expect(again.signedIn, isTrue);
      expect(again.email, 'sara@example.com');
      expect(again.signInNeededToOrder, isFalse);
    });

    test('signing out removes the record', () async {
      final vault = MemoryProfileVault();
      final session = AccountSession(vault: vault)..signIn(email: null);
      await session.idle;
      expect(jsonDecode(vault.value!), {'v': 1, 'signedIn': true});
      await session.signOut();
      expect(session.signedIn, isFalse);
      expect(session.email, isNull);
      expect(vault.value, isNull);
      expect(session.signInNeededToOrder, StoreConfig.requireSignInToOrder);
    });

    test('an email already known is kept; one that is not an email is not '
        'taken', () async {
      final session = AccountSession()..signIn(email: 'sara@example.com');
      session.signIn();
      expect(session.email, 'sara@example.com');
      session.signIn(email: 'not an email');
      expect(session.email, 'sara@example.com');
      session.signIn(email: 'omar@example.com');
      expect(session.email, 'omar@example.com');
    });

    for (final (name, raw) in [
      ('not JSON', '{"signedIn": tr'),
      ('a list', '[1, 2]'),
      ('not signed in', '{"v":1,"signedIn":"yes"}'),
      ('a number', '42'),
    ]) {
      test('a damaged record ($name) is signed out and removed', () async {
        final vault = MemoryProfileVault(raw);
        final session = AccountSession(vault: vault);
        await session.load();
        await session.idle;
        expect(session.signedIn, isFalse);
        expect(session.email, isNull);
        expect(vault.value, isNull);
      });
    }

    test('a saved email that is not an email is dropped, the sign-in kept',
        () async {
      final vault = MemoryProfileVault('{"v":1,"signedIn":true,"email":7}');
      final session = AccountSession(vault: vault);
      await session.load();
      expect(session.signedIn, isTrue);
      expect(session.email, isNull);
    });

    test('storage that cannot be opened is signed out, never a crash',
        () async {
      final vault = MemoryProfileVault('{"v":1,"signedIn":true}')
        ..broken = true;
      final session = AccountSession(vault: vault);
      await session.load();
      expect(session.signedIn, isFalse);
      session.signIn(email: 'sara@example.com');
      await session.idle;
      expect(session.signedIn, isTrue);
      await session.signOut();
      expect(session.signedIn, isFalse);
    });

    test('a sign-out before the record was read wins over it', () async {
      final read = Completer<String?>();
      final vault = _SlowVault(read.future);
      final session = AccountSession(vault: vault);
      final loading = session.load();
      session.signIn(email: 'sara@example.com');
      final out = session.signOut();
      read.complete('{"v":1,"signedIn":true,"email":"omar@example.com"}');
      await loading;
      await out;
      expect(session.signedIn, isFalse);
      expect(vault.deleted, isTrue);
    });

    test('with no vault it never asks when told not to (tests)', () {
      expect(AccountSession(asksAtCheckout: false).signInNeededToOrder,
          isFalse);
      expect(AccountSession().signInNeededToOrder,
          StoreConfig.requireSignInToOrder);
    });
  });

  group('Sign-in pages', () {
    test('the sign-in link returns to the account page', () {
      expect(
        CustomerAccount.signInUrl.toString(),
        'https://testtfm.myshopify.com/customer_authentication/login'
        '?return_to=%2Faccount',
      );
      expect(
        CustomerAccount.ordersUrl.toString(),
        'https://testtfm.myshopify.com/account',
      );
    });

    test("Shopify's signed-in account page", () {
      for (final url in [
        accountPage,
        '$accountPage/',
        '$accountPage/orders/5550001',
        '$accountPage?locale=en',
        'https://shopify.com/1/account',
      ]) {
        expect(CustomerAccount.isAccountPage(url), isTrue, reason: url);
      }
      for (final url in [
        signInPage,
        'https://shopify.com/authentication/$shopId/account',
        'https://shopify.com/$shopId/accounts',
        'https://shopify.com/shop/account',
        'https://shopify.com/account',
        'https://example.com/$shopId/account',
        'https://shop.app/$shopId/account',
        'https://shopify.com.example.com/$shopId/account',
        storeAccount,
        'shopify://$shopId/account',
        'not a link',
      ]) {
        expect(CustomerAccount.isAccountPage(url), isFalse, reason: url);
      }
    });

    test("Shopify's call back to the store, with a code only", () {
      expect(CustomerAccount.isSignInCallback(callback), isTrue);
      for (final url in [
        'https://testtfm.myshopify.com/customer_authentication/callback',
        'https://testtfm.myshopify.com/customer_authentication/callback'
            '?error=access_denied&state=s1',
        'https://testtfm.myshopify.com/customer_authentication/callback'
            '?code=c0de&error=x',
        'https://example.com/customer_authentication/callback?code=c0de',
        'https://testtfm.myshopify.com/customer_authentication/login?code=1',
      ]) {
        expect(CustomerAccount.isSignInCallback(url), isFalse, reason: url);
      }
    });

    test('completion: the account page once shown, or the store\'s '
        '/account after the call back', () {
      expect(SignInWatch().see(accountPage, committed: true), isTrue);
      // On its way to the sign-in page a signed-out visit can pass it.
      expect(SignInWatch().see(accountPage, committed: false), isFalse);
      expect(SignInWatch().see(signInPage, committed: true), isFalse);
      expect(
        SignInWatch().see(
          'https://shopify.com/authentication/$shopId/login/verify',
          committed: true,
        ),
        isFalse,
      );
      // The store's /account without the call back: not signed in yet.
      expect(SignInWatch().see(storeAccount, committed: false), isFalse);
      expect(SignInWatch().see(storeAccount, committed: true), isFalse);

      final watch = SignInWatch();
      expect(watch.see(signInPage, committed: true), isFalse);
      expect(watch.see(callback, committed: false), isFalse);
      expect(watch.sawCallback, isTrue);
      expect(watch.see('https://example.com/account', committed: false),
          isFalse);
      expect(watch.see(storeAccount, committed: false), isTrue);
    });

    test('an email is taken from a message or a page, never anything else',
        () {
      expect(CustomerAccount.emailIn('sara@example.com'), 'sara@example.com');
      expect(CustomerAccount.emailIn('"sara@example.com"'), 'sara@example.com');
      expect(
        CustomerAccount.emailIn('Orders\nsara@example.com\nSign out'),
        'sara@example.com',
      );
      expect(CustomerAccount.emailIn('sara@example'), isNull);
      expect(CustomerAccount.emailIn(''), isNull);
      expect(CustomerAccount.emailIn('""'), isNull);
      expect(CustomerAccount.emailIn(42), isNull);
      expect(CustomerAccount.emailIn(null), isNull);
    });
  });

  group('ShopifyAccountScreen', () {
    late FakeWebViewPlatform webView;

    setUp(() {
      webView = FakeWebViewPlatform.install();
    });

    /// Opens the sign-in (or orders) screen from a host; returns the
    /// fake page and the list the screen's result lands in.
    Future<(FakeWebViewController, List<Object?>)> open(
      WidgetTester tester, {
      AccountSession? session,
      ShopifyAccountMode mode = ShopifyAccountMode.signIn,
    }) async {
      final results = <Object?>[];
      await pumpScreen(
        tester,
        _Host(
          (context) => Navigator.of(context).push(
            MaterialPageRoute<SignInOutcome>(
              builder: (_) => ShopifyAccountScreen(mode: mode),
            ),
          ),
          results,
        ),
        session: session,
      );
      await tester.tap(find.text('Open'));
      await settle(tester);
      expect(find.byType(ShopifyAccountScreen), findsOneWidget);
      return (webView.controller, results);
    }

    testWidgets("loads the store's sign-in link with the email channel "
        'ready, under a "Sign in" bar', (tester) async {
      final original = ShopifyWeb.allowThirdPartyCookies;
      addTearDown(() => ShopifyWeb.allowThirdPartyCookies = original);
      var cookiesAsked = 0;
      ShopifyWeb.allowThirdPartyCookies = (_) async {
        cookiesAsked++;
        return true;
      };
      final (page, _) = await open(tester);
      expect(page.loaded, [CustomerAccount.signInUrl]);
      expect(page.channels.keys, [CustomerAccount.emailChannel]);
      expect(cookiesAsked, 1);
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.byTooltip('Close sign-in'), findsOneWidget);
      expect(
        find.bySemanticsLabel(ShopifyAccountScreen.secureLabel),
        findsOneWidget,
      );
      expect(
        tester.getSize(find.byTooltip('Close sign-in')).height,
        greaterThanOrEqualTo(44),
      );
    });

    testWidgets('the email typed on the sign-in page is kept; the screen '
        'closes by itself once Shopify calls the store back', (tester) async {
      final vault = MemoryProfileVault();
      final session = gatedSession(vault: vault);
      final (page, results) = await open(tester, session: session);

      page.pageStarted(signInPage);
      page.pageFinished(signInPage);
      await tester.pump();
      expect(page.scripts, [CustomerAccount.emailListenerScript]);
      page.post(CustomerAccount.emailChannel, 'sara@exam');
      page.post(CustomerAccount.emailChannel, 'sara@example.com');

      expect(await page.request(callback), NavigationDecision.navigate);
      expect(session.signedIn, isFalse);
      expect(find.byType(ShopifyAccountScreen), findsOneWidget);
      expect(await page.request(storeAccount), NavigationDecision.navigate);
      await settle(tester);

      expect(find.byType(ShopifyAccountScreen), findsNothing);
      expect(results, [SignInOutcome.signedIn]);
      expect(session.signedIn, isTrue);
      expect(session.email, 'sara@example.com');
      await session.idle;
      // Encrypted storage only; the checkout log never sees it.
      expect(vault.value, contains('sara@example.com'));
      expect(CheckoutLog.supportReport(), isNot(contains('sara@')));
    });

    testWidgets('an email from a page that is not Shopify sign-in is '
        'ignored', (tester) async {
      final session = gatedSession();
      final (page, _) = await open(tester, session: session);
      page.pageStarted('https://shop.app/pay/login');
      page.post(CustomerAccount.emailChannel, 'mallory@example.com');
      page.pageStarted(accountPage);
      await tester.pump(ShopifyAccountScreen.emailWait);
      await settle(tester);
      expect(session.signedIn, isTrue);
      expect(session.email, isNull);
    });

    testWidgets("Shopify's account page shown completes the sign-in; the "
        'email is read from it when it was not seen', (tester) async {
      final session = gatedSession();
      final (page, results) = await open(tester, session: session);
      page.scriptResult = '"sara@example.com"';
      page.pageStarted(accountPage);
      await tester.pump();
      // Covered while it closes: the account page is not shown.
      expect(
        find.byKey(const ValueKey('account-signed-in-cover')),
        findsOneWidget,
      );
      expect(session.signedIn, isTrue);
      page.pageFinished(accountPage);
      await settle(tester);
      expect(page.scripts, [CustomerAccount.pageEmailScript]);
      expect(results, [SignInOutcome.signedIn]);
      expect(session.email, 'sara@example.com');
    });

    testWidgets('no email anywhere: signed in all the same, after a short '
        'wait', (tester) async {
      final session = gatedSession();
      final (page, results) = await open(tester, session: session);
      page.urlChanged(accountPage);
      await tester.pump(const Duration(seconds: 1));
      expect(results, isEmpty);
      await tester.pump(ShopifyAccountScreen.emailWait);
      await settle(tester);
      expect(results, [SignInOutcome.signedIn]);
      expect(session.signedIn, isTrue);
      expect(session.email, isNull);
    });

    testWidgets('closing, or a store page before signing in, closes with '
        'nothing', (tester) async {
      final session = gatedSession();
      var (page, results) = await open(tester, session: session);
      page.pageStarted(signInPage);
      await tester.tap(find.byTooltip('Close sign-in'));
      await settle(tester);
      expect(results, [null]);
      expect(session.signedIn, isFalse);

      await tester.pumpWidget(const SizedBox());
      webView.controllers.clear();
      (page, results) = await open(tester, session: session);
      // The store's /account without Shopify's call back.
      expect(await page.request(storeAccount), NavigationDecision.navigate);
      expect(
        await page.request('https://testtfm.myshopify.com/'),
        NavigationDecision.prevent,
      );
      await settle(tester);
      expect(results, [null]);
      expect(session.signedIn, isFalse);
    });

    testWidgets('scripts, files and blank pages never load; other apps\' '
        'links go to their app', (tester) async {
      final launched = mockLauncher(tester);
      final (page, _) = await open(tester);
      for (final url in [
        'javascript:alert(1)',
        'data:text/html,hi',
        'file:///etc/hosts',
        'about:blank',
      ]) {
        expect(await page.request(url), NavigationDecision.prevent);
      }
      expect(
        await page.request('about:blank', mainFrame: false),
        NavigationDecision.navigate,
      );
      expect(
        await page.request('mailto:care@freshmarket.ae'),
        NavigationDecision.prevent,
      );
      expect(
        await page.request(
          'intent://pay#Intent;scheme=shopapp;package=com.shopify.arrive;end',
        ),
        NavigationDecision.prevent,
      );
      await settle(tester);
      expect(launched, ['mailto:care@freshmarket.ae', 'shopapp://pay']);
      expect(find.byType(ShopifyAccountScreen), findsOneWidget);
    });

    testWidgets('a page that does not load offers Try again', (tester) async {
      final (page, _) = await open(tester);
      page.resourceError(signInPage, mainFrame: true);
      await settle(tester);
      expect(find.text("Couldn't load sign-in"), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await settle(tester);
      expect(page.loaded, [CustomerAccount.signInUrl, CustomerAccount.signInUrl]);
    });

    testWidgets('My orders: the account page, which marks the session '
        'signed in; a store page closes it', (tester) async {
      final session = gatedSession();
      final (page, results) = await open(
        tester,
        session: session,
        mode: ShopifyAccountMode.orders,
      );
      expect(page.loaded, [CustomerAccount.ordersUrl]);
      expect(find.text('My orders'), findsOneWidget);
      page.pageStarted(accountPage);
      page.scriptResult = 'sara@example.com';
      page.pageFinished(accountPage);
      await settle(tester);
      expect(session.signedIn, isTrue);
      expect(session.email, 'sara@example.com');
      expect(find.byType(ShopifyAccountScreen), findsOneWidget);

      expect(
        await page.request('https://testtfm.myshopify.com/collections/fruits'),
        NavigationDecision.prevent,
      );
      await settle(tester);
      expect(find.byType(ShopifyAccountScreen), findsNothing);
      expect(results, [null]);
    });

    testWidgets('no WebView, from checkout: checkout goes on in the browser',
        (tester) async {
      webView.available = false;
      final results = <Object?>[];
      await pumpScreen(
        tester,
        _Host(
          (context) => AppNav.openSignIn(context, forCheckout: true),
          results,
        ),
      );
      await tester.tap(find.text('Open'));
      await settle(tester);
      expect(find.text('Sign in at checkout'), findsOneWidget);
      await tester.tap(find.text('Continue to checkout'));
      await settle(tester);
      expect(results, [SignInOutcome.inBrowser]);
    });
  });

  group('Checkout asks to sign in first', () {
    late FakeWebViewPlatform webView;

    setUp(() {
      webView = FakeWebViewPlatform.install();
      CheckoutLog.forget();
    });

    Future<void> pumpCart(
      WidgetTester tester,
      AccountSession session, {
      CartStore? cart,
    }) async {
      await pumpScreen(
        tester,
        const CartScreen(),
        cart: cart ?? (CartStore()..add(kiwi, kiwi.variants[0])),
        delivery: testDelivery(),
        profile: ProfileStore()..saveContact(sara),
        session: session,
      );
      await tester.pump(const Duration(milliseconds: 300));
    }

    Future<void> tapCheckout(WidgetTester tester) async {
      await tester.tap(
        find.ancestor(
          of: find.textContaining('Checkout · '),
          matching: find.byType(FilledButton),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('signed in: checkout opens at once', (tester) async {
      final session = gatedSession()..signIn(email: 'sara@example.com');
      await pumpCart(tester, session);
      await tapCheckout(tester);
      expect(find.byType(SignInSheet), findsNothing);
      expect(find.byType(CheckoutScreen), findsOneWidget);
    });

    testWidgets('signed out: the sheet; "Not now" and its close button stay '
        'on the cart', (tester) async {
      final session = gatedSession();
      final cart = CartStore()..add(kiwi, kiwi.variants[0]);
      await pumpCart(tester, session, cart: cart);
      await tapCheckout(tester);

      expect(find.text(SignInSheet.title), findsOneWidget);
      expect(find.text(SignInSheet.message), findsOneWidget);
      expect(find.text(SignInSheet.ordersLine), findsOneWidget);
      final signIn = find.widgetWithText(FilledButton, SignInSheet.signInLabel);
      final material = tester.widget<Material>(
        find.descendant(of: signIn, matching: find.byType(Material)).first,
      );
      expect(material.color, AppColors.ink);
      for (final target in [
        signIn,
        find.byKey(const ValueKey('sign-in-sheet-not-now')),
        find.byKey(const ValueKey('sign-in-sheet-close')),
      ]) {
        expect(tester.getSize(target).height, greaterThanOrEqualTo(44));
      }

      await tester.tap(find.text(SignInSheet.notNowLabel));
      await settle(tester);
      expect(find.byType(SignInSheet), findsNothing);
      expect(find.byType(ShopifyAccountScreen), findsNothing);
      expect(find.byType(CheckoutScreen), findsNothing);
      expect(find.byType(CartScreen), findsOneWidget);
      expect(cart.itemCount, 1);

      await tapCheckout(tester);
      await tester.tap(find.byTooltip(SignInSheet.closeTooltip));
      await settle(tester);
      expect(find.byType(SignInSheet), findsNothing);
      expect(find.byType(CheckoutScreen), findsNothing);
      expect(webView.controllers, isEmpty);
    });

    testWidgets('signing in from the sheet opens checkout with the same link '
        'as a shopper already signed in', (tester) async {
      // Already signed in: the link checkout opens.
      await pumpCart(tester, gatedSession()..signIn(email: 'sara@example.com'));
      await tapCheckout(tester);
      final expected = webView.controllers.single.loaded.single;
      expect(expected.toString(), contains('checkout%5Bemail%5D=sara'));

      // Signed out: sheet, sign-in, then checkout.
      await tester.pumpWidget(const SizedBox());
      webView.controllers.clear();
      final said = recordAnnouncements(tester);
      final session = gatedSession();
      await pumpCart(tester, session);
      await tapCheckout(tester);
      await tester.tap(find.text(SignInSheet.signInLabel));
      await settle(tester);
      expect(find.byType(ShopifyAccountScreen), findsOneWidget);
      final signInPage = webView.controllers.single;
      expect(signInPage.loaded, [CustomerAccount.signInUrl]);
      expect(find.byType(CheckoutScreen), findsNothing);

      signInPage.pageStarted(
        'https://shopify.com/authentication/$shopId/login?client_id=abc',
      );
      signInPage.post(CustomerAccount.emailChannel, 'sara@example.com');
      signInPage.pageStarted(accountPage);
      await settle(tester);
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(ShopifyAccountScreen), findsNothing);
      expect(find.byType(CheckoutScreen), findsOneWidget);
      expect(webView.controllers, hasLength(2));
      expect(webView.controllers.last.loaded, [expected]);
      expect(session.signedIn, isTrue);
      expect(said, contains(AppNav.signedInAnnouncement));
    });

    testWidgets('closing the sign-in page stays on the cart, signed out',
        (tester) async {
      final session = gatedSession();
      await pumpCart(tester, session);
      await tapCheckout(tester);
      await tester.tap(find.text(SignInSheet.signInLabel));
      await settle(tester);
      await tester.tap(find.byTooltip(ShopifyAccountScreen.closeSignIn));
      await settle(tester);
      expect(find.byType(ShopifyAccountScreen), findsNothing);
      expect(find.byType(CheckoutScreen), findsNothing);
      expect(find.byType(CartScreen), findsOneWidget);
      expect(session.signedIn, isFalse);
      expect(webView.controllers, hasLength(1));
    });

    testWidgets('every way in asks: openCheckout from any screen (the '
        'assistant uses it too)', (tester) async {
      final session = gatedSession();
      await pumpScreen(
        tester,
        _Host((context) => AppNav.openCheckout(context), []),
        cart: CartStore()..add(kiwi, kiwi.variants[0]),
        delivery: testDelivery(),
        session: session,
      );
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(SignInSheet), findsOneWidget);
      expect(find.byType(CheckoutScreen), findsNothing);
    });

    testWidgets('no WebView: the sheet, then checkout goes to the browser',
        (tester) async {
      webView.available = false;
      final launched = mockLauncher(tester);
      await pumpCart(tester, gatedSession());
      await tapCheckout(tester);
      await tester.tap(find.text(SignInSheet.signInLabel));
      await settle(tester);
      await tester.tap(find.text('Continue to checkout'));
      await settle(tester);
      expect(find.byType(CheckoutScreen), findsOneWidget);
      expect(launched.single, startsWith('https://testtfm.myshopify.com/cart/'));
    });
  });

  group('Checkout notices a sign-in made on its own page', () {
    late FakeWebViewPlatform webView;

    setUp(() {
      webView = FakeWebViewPlatform.install();
      CheckoutLog.forget();
    });

    Future<FakeWebViewController> openCheckout(
      WidgetTester tester,
      AccountSession session,
    ) async {
      await pumpScreen(
        tester,
        _Host(
          (context) => Navigator.of(context).push<Object?>(
            MaterialPageRoute<Object?>(
              builder: (_) => CheckoutScreen(
                url: Uri.parse('https://testtfm.myshopify.com/cart/2001:1'),
              ),
            ),
          ),
          [],
        ),
        session: session,
      );
      await tester.tap(find.text('Open'));
      await settle(tester);
      return webView.controller;
    }

    testWidgets("Shopify's call back marks the session signed in; checkout "
        'goes on', (tester) async {
      final session = gatedSession();
      final page = await openCheckout(tester, session);
      // Checkout's own "Sign in" link is allowed.
      expect(
        await page.request(
          'https://testtfm.myshopify.com/customer_authentication/login'
          '?return_to=/checkouts/cn/abc',
        ),
        NavigationDecision.navigate,
      );
      expect(session.signedIn, isFalse);
      expect(await page.request(callback), NavigationDecision.navigate);
      expect(session.signedIn, isTrue);
      expect(session.email, isNull);
      await settle(tester);
      expect(find.byType(CheckoutScreen), findsOneWidget);
    });

    testWidgets('a known email is kept; an error answer signs nobody in',
        (tester) async {
      final known = gatedSession()..signIn(email: 'sara@example.com');
      var page = await openCheckout(tester, known);
      page.pageStarted(callback);
      expect(known.email, 'sara@example.com');

      await tester.pumpWidget(const SizedBox());
      webView.controllers.clear();
      final session = gatedSession();
      page = await openCheckout(tester, session);
      await page.request(
        'https://testtfm.myshopify.com/customer_authentication/callback'
        '?error=access_denied',
      );
      expect(session.signedIn, isFalse);
    });
  });

  group('Account', () {
    late FakeWebViewPlatform webView;

    setUp(() {
      webView = FakeWebViewPlatform.install();
    });

    testWidgets('signed in: the initials, "Signed in" and the email, and My '
        'orders', (tester) async {
      await pumpScreen(
        tester,
        const AccountScreen(),
        profile: ProfileStore()..saveContact(sara),
        session: gatedSession()..signIn(email: 'sara@example.com'),
      );
      final card = find.byKey(const ValueKey('account-session'));
      expect(
        find.descendant(of: card, matching: find.text('SA')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Signed in')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('sara@example.com')),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('Signed in as sara@example.com'),
          findsOneWidget);
      // One avatar: the details card leaves it to the account card.
      expect(find.text('SA'), findsOneWidget);
      expect(find.text('Sign in with email'), findsNothing);
      expect(find.byType(FilledButton), findsNothing);

      final orders = find.byKey(const ValueKey('account-orders'));
      expect(
        find.descendant(of: orders, matching: find.text('My orders')),
        findsOneWidget,
      );
      expect(tester.getSize(orders).height, greaterThanOrEqualTo(56));
      await tester.tap(orders);
      await settle(tester);
      expect(find.byType(ShopifyAccountScreen), findsOneWidget);
      expect(webView.controller.loaded, [CustomerAccount.ordersUrl]);
      await tester.tap(find.byTooltip(ShopifyAccountScreen.closeOrders));
      await settle(tester);
      expect(find.byType(ShopifyAccountScreen), findsNothing);
    });

    testWidgets("no names saved: the email's first letter; no email: a "
        'plain "Signed in"', (tester) async {
      await pumpScreen(
        tester,
        const AccountScreen(),
        session: gatedSession()..signIn(email: 'omar@example.com'),
      );
      expect(find.text('O'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await pumpScreen(
        tester,
        const AccountScreen(),
        session: gatedSession()..signIn(),
      );
      expect(find.text('Your Fresh Market account'), findsOneWidget);
      expect(find.bySemanticsLabel('Signed in'), findsOneWidget);
    });

    testWidgets('signed out: "Sign in with email" opens the sign-in page and '
        'says when signed in', (tester) async {
      final said = recordAnnouncements(tester);
      final session = gatedSession();
      await pumpScreen(tester, const AccountScreen(), session: session);
      await tester.tap(find.text('Sign in with email'));
      await settle(tester);
      expect(webView.controller.loaded, [CustomerAccount.signInUrl]);
      webView.controller.post(CustomerAccount.emailChannel, 'x');
      webView.controller.pageStarted(signInPage);
      webView.controller.post(CustomerAccount.emailChannel, 'sara@example.com');
      await webView.controller.request(callback);
      await webView.controller.request(storeAccount);
      await settle(tester);
      expect(find.byType(ShopifyAccountScreen), findsNothing);
      expect(said, [AppNav.signedInAnnouncement]);
      expect(find.text('sara@example.com'), findsOneWidget);
      expect(find.text('My orders'), findsOneWidget);
    });

    testWidgets('Sign out asks, then clears the WebView cookies and the '
        'session; My details stay', (tester) async {
      final original = ShopifyWeb.clearCookies;
      addTearDown(() => ShopifyWeb.clearCookies = original);
      var cleared = 0;
      ShopifyWeb.clearCookies = () async {
        cleared++;
        return true;
      };
      final vault = MemoryProfileVault();
      final session = gatedSession(vault: vault)
        ..signIn(email: 'sara@example.com');
      await session.idle;
      final profile = ProfileStore()..saveContact(sara);
      await pumpScreen(
        tester,
        const AccountScreen(),
        profile: profile,
        session: session,
      );
      final signOut = find.byKey(const ValueKey('sign-out'));
      await tester.scrollUntilVisible(
        signOut,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(signOut).height, greaterThanOrEqualTo(48));
      // Ink, not green.
      expect(
        tester.widget<Icon>(
          find.descendant(of: signOut, matching: find.byType(Icon)),
        ).icon,
        Icons.logout,
      );

      await tester.tap(signOut);
      await tester.pumpAndSettle();
      expect(find.text('Sign out?'), findsOneWidget);
      expect(find.text("You'll need to sign in again to order."),
          findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(session.signedIn, isTrue);
      expect(cleared, 0);

      await tester.tap(signOut);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sign-out-confirm')));
      await tester.pumpAndSettle();
      expect(cleared, 1);
      expect(session.signedIn, isFalse);
      expect(session.email, isNull);
      expect(vault.value, isNull);
      expect(profile.contact, sara);
      expect(find.text("You're signed out."), findsOneWidget);
      expect(find.text('Sign in to order'), findsOneWidget);
      expect(find.byKey(const ValueKey('sign-out')), findsNothing);
    });

    testWidgets('a cookie store that fails still signs out', (tester) async {
      final original = ShopifyWeb.clearCookies;
      addTearDown(() => ShopifyWeb.clearCookies = original);
      ShopifyWeb.clearCookies = () async => throw StateError('no WebView');
      final session = gatedSession()..signIn(email: 'sara@example.com');
      await pumpScreen(tester, const AccountScreen(), session: session);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('sign-out')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sign-out')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('sign-out-confirm')));
      await tester.pumpAndSettle();
      expect(session.signedIn, isFalse);
    });
  });

  group('Cart', () {
    Future<void> pumpCart(WidgetTester tester, AccountSession session) =>
        pumpScreen(
          tester,
          const CartScreen(),
          cart: CartStore()..add(kiwi, kiwi.variants[0]),
          delivery: testDelivery(),
          session: session,
        );

    Icon lineIcon(WidgetTester tester) => tester.widget<Icon>(
      find.descendant(
        of: find.byKey(const ValueKey('cart-account-line')),
        matching: find.byType(Icon),
      ),
    );

    testWidgets('signed in: a small green check and the email above '
        'Checkout', (tester) async {
      await pumpCart(tester, gatedSession()..signIn(email: 'sara@example.com'));
      final line = find.text('Signed in as sara@example.com');
      expect(line, findsOneWidget);
      expect(lineIcon(tester).color, AppColors.green);
      expect(
        tester.getBottomLeft(line).dy,
        lessThan(tester.getTopLeft(find.textContaining('Checkout · ')).dy),
      );
    });

    testWidgets('signed in, email unknown: "Signed in"', (tester) async {
      await pumpCart(tester, gatedSession()..signIn());
      expect(find.text('Signed in'), findsOneWidget);
    });

    testWidgets('signed out: a neutral "Sign in needed to order", no green',
        (tester) async {
      await pumpCart(tester, gatedSession());
      expect(find.text('Sign in needed to order'), findsOneWidget);
      expect(lineIcon(tester).color, AppColors.secondary);
    });

    testWidgets('sign-in not asked for: no line', (tester) async {
      await pumpCart(tester, AccountSession(asksAtCheckout: false));
      expect(find.byKey(const ValueKey('cart-account-line')), findsNothing);
    });
  });

  group('200% text', () {
    testWidgets('the sheet, the signed-in Account and the cart line fit',
        (tester) async {
      await loadAppFonts(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await pumpScreen(
        tester,
        const Scaffold(body: SignInSheet()),
      );
      tester.view.physicalSize = const Size(1080, 2340); // 360dp wide
      await tester.pump();
      expect(tester.takeException(), isNull);
      final button = find.widgetWithText(FilledButton, SignInSheet.signInLabel);
      final label = tester.renderObject<RenderParagraph>(
        find.descendant(of: button, matching: find.byType(RichText)),
      );
      expect(label.didExceedMaxLines, isFalse);

      await tester.pumpWidget(const SizedBox());
      await pumpScreen(
        tester,
        const AccountScreen(),
        profile: ProfileStore()..saveContact(sara),
        session: gatedSession()..signIn(email: 'sara.ahmed.long@example.com'),
      );
      tester.view.physicalSize = const Size(1080, 2340);
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.pumpWidget(const SizedBox());
      await pumpScreen(
        tester,
        const CartScreen(),
        cart: CartStore()..add(kiwi, kiwi.variants[0]),
        delivery: testDelivery(),
        session: gatedSession()..signIn(email: 'sara.ahmed.long@example.com'),
      );
      tester.view.physicalSize = const Size(1080, 2340);
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}

/// A vault whose read waits for [_read]; records a delete.
class _SlowVault implements ProfileVault {
  _SlowVault(this._read);

  final Future<String?> _read;
  bool deleted = false;
  String? value;

  @override
  Future<String?> read() => _read;

  @override
  Future<void> write(String value) async => this.value = value;

  @override
  Future<void> delete() async {
    deleted = true;
    value = null;
  }
}
