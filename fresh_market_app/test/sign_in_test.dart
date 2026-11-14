import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/app_nav.dart';
import 'package:fresh_market_app/config/store_config.dart';
import 'package:fresh_market_app/profile/customer_details.dart';
import 'package:fresh_market_app/screens/account_screen.dart';
import 'package:fresh_market_app/screens/cart_screen.dart';
import 'package:fresh_market_app/screens/checkout_screen.dart';
import 'package:fresh_market_app/screens/my_orders_screen.dart';
import 'package:fresh_market_app/services/customer_auth.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/state/account_session.dart';
import 'package:fresh_market_app/state/cart_store.dart';
import 'package:fresh_market_app/state/profile_store.dart';
import 'package:fresh_market_app/theme/app_theme.dart';
import 'package:fresh_market_app/widgets/sign_in_sheet.dart';
import 'package:material_ui/material_ui.dart';

import 'support/order_fakes.dart';
import 'support/test_app.dart';

/// Records what is said to screen readers.
List<String> _announcements(WidgetTester tester) {
  final said = <String>[];
  tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(
    SystemChannels.accessibility,
    (message) async {
      final map = message as Map<Object?, Object?>;
      if (map['type'] == 'announce') {
        said.add((map['data']! as Map<Object?, Object?>)['message']! as String);
      }
      return null;
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

Finder get _checkoutButton => find.ancestor(
  of: find.textContaining('Checkout · '),
  matching: find.byType(FilledButton),
);

void main() {
  final kiwi = sampleProducts().first;
  late FakeOAuthClient oauth;
  late FakeOrderServer server;
  late FakeCustomerApi customer;

  setUp(() {
    oauth = FakeOAuthClient();
    server = FakeOrderServer();
    customer = FakeCustomerApi();
  });

  Future<void> cart(
    WidgetTester tester, {
    AccountSession? session,
    ProfileStore? profile,
  }) => pumpScreen(
    tester,
    const CartScreen(),
    cart: CartStore()..add(kiwi, kiwi.variants[0]),
    delivery: testDelivery(),
    profile: profile,
    session: session ?? signedOutSession(client: oauth),
    orderApi: server.api(),
    customerApi: customer.api(),
  );

  Future<void> tapCheckout(WidgetTester tester) async {
    await tester.tap(_checkoutButton);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  group('Checkout asks to sign in first', () {
    test('compulsory for orders', () {
      expect(StoreConfig.requireSignInToOrder, isTrue);
    });

    testWidgets('signed out: the sheet; "Not now" and its close button stay '
        'on the cart', (tester) async {
      await cart(tester);
      await tapCheckout(tester);
      expect(find.text(SignInSheet.title), findsOneWidget);
      expect(find.byType(CheckoutScreen), findsNothing);
      // Ink, not green: signing in is not buying.
      final signIn = tester.widget<FilledButton>(
        find.byKey(const ValueKey('sign-in-sheet-sign-in')),
      );
      expect(
        signIn.style!.backgroundColor!.resolve(const <WidgetState>{}),
        AppColors.ink,
      );
      await tester.tap(find.byKey(const ValueKey('sign-in-sheet-not-now')));
      await tester.pumpAndSettle();
      expect(find.byType(CheckoutScreen), findsNothing);
      expect(oauth.authorizeCalls, 0);

      await tapCheckout(tester);
      await tester.tap(find.byKey(const ValueKey('sign-in-sheet-close')));
      await tester.pumpAndSettle();
      expect(find.byType(CheckoutScreen), findsNothing);
      expect(oauth.authorizeCalls, 0);
    });

    testWidgets("Sign in with email opens Shopify's sign-in, then checkout "
        'by itself; said to screen readers', (tester) async {
      final said = _announcements(tester);
      final session = signedOutSession(client: oauth);
      await cart(tester, session: session);
      await tapCheckout(tester);
      await tester.tap(find.byKey(const ValueKey('sign-in-sheet-sign-in')));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(oauth.authorizeCalls, 1);
      expect(session.signedIn, isTrue);
      expect(said, contains(AppNav.signedInAnnouncement));
      expect(find.byType(CheckoutScreen), findsOneWidget);
    });

    testWidgets('closing the sign-in page stays on the cart, signed out and '
        'with nothing said', (tester) async {
      oauth.authorizeError = const SignInCancelled();
      await cart(tester);
      await tapCheckout(tester);
      await tester.tap(find.byKey(const ValueKey('sign-in-sheet-sign-in')));
      await tester.pumpAndSettle();
      expect(find.byType(CheckoutScreen), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('offline or refused: said on the cart', (tester) async {
      oauth.authorizeError = const AuthNetworkError();
      await cart(tester);
      await tapCheckout(tester);
      await tester.tap(find.byKey(const ValueKey('sign-in-sheet-sign-in')));
      await tester.pumpAndSettle();
      expect(find.text(AppNav.signInOfflineMessage), findsOneWidget);
      expect(find.byType(CheckoutScreen), findsNothing);

      oauth.authorizeError = const SignInFailed('access_denied');
      await tapCheckout(tester);
      await tester.tap(find.byKey(const ValueKey('sign-in-sheet-sign-in')));
      await tester.pumpAndSettle();
      expect(find.text(AppNav.signInFailedMessage), findsOneWidget);
    });

    testWidgets('no client ID in this build: said plainly, nothing opens', (
      tester,
    ) async {
      await cart(tester, session: AccountSession());
      await tapCheckout(tester);
      expect(find.text(SignInSheet.title), findsNothing);
      expect(find.text(AppNav.signInUnavailableMessage), findsOneWidget);
      expect(find.byType(CheckoutScreen), findsNothing);
    });

    testWidgets('signed in: checkout opens at once', (tester) async {
      await cart(tester, session: await signedInSession(client: oauth));
      await tapCheckout(tester);
      expect(find.text(SignInSheet.title), findsNothing);
      expect(find.byType(CheckoutScreen), findsOneWidget);
      expect(oauth.authorizeCalls, 0);
    });

    testWidgets('after signing in, empty "My details" fields are filled from '
        'the account; typed ones are kept', (tester) async {
      final profile = ProfileStore()
        ..saveContact(const ContactDetails(firstName: 'Sara'));
      customer.customer = {
        ...customer.customer,
        'firstName': 'Sarah',
        'phoneNumber': {'phoneNumber': '+971 50 123 4567'},
      };
      await cart(tester, profile: profile);
      await tapCheckout(tester);
      await tester.tap(find.byKey(const ValueKey('sign-in-sheet-sign-in')));
      await tester.pumpAndSettle();
      expect(profile.contact.firstName, 'Sara');
      expect(profile.contact.lastName, 'Ahmed');
      expect(profile.contact.mobile, '+971501234567');
      expect(profile.contact.email, 'sara@example.com');
    });
  });

  group('Account', () {
    testWidgets('signed out: "Sign in to order" and the ink button, which '
        'signs in', (tester) async {
      final session = signedOutSession(client: oauth);
      await pumpScreen(tester, const AccountScreen(), session: session);
      expect(find.text('Sign in to order'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('account-sign-in')));
      await tester.pumpAndSettle();
      expect(oauth.authorizeCalls, 1);
      expect(find.text('Signed in'), findsOneWidget);
      expect(find.text('sara@example.com'), findsOneWidget);
      expect(find.text('Sign in to order'), findsNothing);
    });

    testWidgets('no client ID: says sign-in is not available yet, no button', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const AccountScreen(),
        session: AccountSession(),
      );
      expect(
        find.byKey(const ValueKey('account-sign-in-unavailable')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('account-sign-in')), findsNothing);
    });

    testWidgets('signed in: the email, My orders, and Sign out (asks, then '
        'tells Shopify with the ID token)', (tester) async {
      final endSession = EndSessionRecorder();
      final session = await signedInSession(endSession: endSession);
      await pumpScreen(
        tester,
        const AccountScreen(),
        session: session,
        customerApi: customer.api(),
      );
      expect(find.text('Signed in'), findsOneWidget);
      expect(find.text('sara@example.com'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('account-orders')));
      await tester.pumpAndSettle();
      expect(find.byType(MyOrdersScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('sign-out')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byKey(const ValueKey('sign-out')));
      await tester.pumpAndSettle();
      expect(find.text(AppNav.signOutTitle), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('sign-out-confirm')));
      await tester.pumpAndSettle();
      expect(session.signedIn, isFalse);
      expect(find.text(AppNav.signedOutMessage), findsOneWidget);
      expect(
        endSession.calls.single.queryParameters['id_token_hint'],
        fakeIdToken(),
      );
      expect(find.text('Sign in to order'), findsOneWidget);
    });
  });

  group('Cart', () {
    testWidgets('signed in: a small green check and "Signed in as …" above '
        'Checkout', (tester) async {
      await cart(tester, session: await signedInSession());
      expect(find.text('Signed in as sara@example.com'), findsOneWidget);
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey('cart-account-line')),
          matching: find.byType(Icon),
        ),
      );
      expect(icon.color, AppColors.green);
      expect(
        tester.getTopLeft(find.text('Signed in as sara@example.com')).dy,
        lessThan(tester.getTopLeft(_checkoutButton).dy),
      );
    });

    testWidgets('signed out: a neutral "Sign in needed to order"', (
      tester,
    ) async {
      await cart(tester);
      expect(find.text(CartScreen.signInNeededLine), findsOneWidget);
      final icon = tester.widget<Icon>(
        find.descendant(
          of: find.byKey(const ValueKey('cart-account-line')),
          matching: find.byType(Icon),
        ),
      );
      expect(icon.color, AppColors.secondary);
    });
  });

  group('no path opens the old WebView checkout', () {
    test('no WebView package, import or Shopify web checkout link left', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(pubspec, isNot(contains('webview')));
      for (final file in Directory('lib').listSync(recursive: true)) {
        if (file is! File || !file.path.endsWith('.dart')) continue;
        final source = file.readAsStringSync();
        expect(source, isNot(contains('webview_flutter')), reason: file.path);
        expect(source, isNot(contains('WebView')), reason: file.path);
        expect(source, isNot(contains('/cart/')), reason: file.path);
        expect(
          source,
          isNot(contains('customer_authentication')),
          reason: file.path,
        );
      }
      for (final gone in [
        'lib/screens/shopify_account_screen.dart',
        'lib/services/shopify_web.dart',
        'lib/services/checkout_log.dart',
        'lib/profile/checkout_prefill.dart',
      ]) {
        expect(File(gone).existsSync(), isFalse, reason: gone);
      }
    });

    testWidgets("the cart's Checkout opens the app's own checkout", (
      tester,
    ) async {
      await cart(tester, session: await signedInSession());
      await tapCheckout(tester);
      expect(find.byType(CheckoutScreen), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text(CheckoutScreen.codTitle),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(CheckoutScreen.codTitle), findsOneWidget);
      expect(server.quoteRequests, hasLength(1));
    });
  });
}
