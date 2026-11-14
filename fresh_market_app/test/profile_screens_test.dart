import 'dart:async';
import 'dart:ui' show CheckedState;

import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/app_nav.dart';
import 'package:fresh_market_app/assistant/assistant_session.dart';
import 'package:fresh_market_app/delivery/delivery.dart';
import 'package:fresh_market_app/profile/customer_details.dart';
import 'package:fresh_market_app/profile/profile_vault.dart';
import 'package:fresh_market_app/screens/account_screen.dart';
import 'package:fresh_market_app/screens/address_screen.dart';
import 'package:fresh_market_app/screens/assistant_screen.dart';
import 'package:fresh_market_app/screens/cart_screen.dart';
import 'package:fresh_market_app/screens/checkout_screen.dart';
import 'package:fresh_market_app/screens/location_screen.dart';
import 'package:fresh_market_app/screens/my_details_screen.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/state/account_session.dart';
import 'package:fresh_market_app/state/cart_store.dart';
import 'package:fresh_market_app/state/profile_store.dart';
import 'package:fresh_market_app/theme/app_theme.dart';
import 'package:fresh_market_app/widgets/deliver_to.dart';
import 'package:fresh_market_app/widgets/details_fields.dart';
import 'package:material_ui/material_ui.dart';

import 'support/test_app.dart';

// Fictional demo data only.
const sara = ContactDetails(
  firstName: 'Sara',
  lastName: 'Ahmed',
  mobile: '+971501234567',
  email: 'sara@example.com',
);

DeliveryArea area(String name) => DeliveryConfig.areaNamed(name)!;

/// Sara's mobile as shown: non-breaking spaces keep it on one line.
const saraMobile = '+971\u00A050\u00A0123\u00A04567';

/// A vault whose read waits until [open] (a slow phone at start-up).
class GatedVault extends MemoryProfileVault {
  GatedVault(super.value);

  final Completer<void> _gate = Completer<void>();

  void open() => _gate.complete();

  @override
  Future<String?> read() async {
    await _gate.future;
    return super.read();
  }
}

SavedAddress homeIn(String areaName) => SavedAddress(
  id: 'home',
  label: AddressLabel.home,
  area: area(areaName),
  building: 'Bay Square, Building 5',
  flat: 'Flat 302',
  instructions: 'Call when you arrive',
);

final office = SavedAddress(
  id: 'office',
  label: AddressLabel.office,
  area: area('Dubai Marina'),
  building: 'Marina Plaza',
  flat: 'Office 1204',
);

/// Sara, Home in Business Bay (the default) and Office in Dubai Marina.
ProfileStore filledProfile({ProfileVault? vault}) => ProfileStore(vault: vault)
  ..saveContact(sara)
  ..saveAddress(homeIn('Business Bay'))
  ..saveAddress(office);

const _launcher = MethodChannel('plugins.flutter.io/url_launcher');

/// Answers url_launcher calls (checkout's browser fallback in tests) and
/// records the URLs.
List<String> mockLauncher(WidgetTester tester) {
  final launched = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(_launcher, (
    call,
  ) async {
    if (call.method == 'launch') {
      launched.add((call.arguments as Map)['url'] as String);
    }
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
List<String> captureAnnouncements(WidgetTester tester) {
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

/// The text box of the details field labelled [label].
Finder field(String label) => find.descendant(
  of: find.byWidgetPredicate((w) => w is DetailsField && w.label == label),
  matching: find.byType(EditableText),
);

Future<void> type(WidgetTester tester, String label, String text) async {
  await tester.ensureVisible(field(label));
  await tester.enterText(field(label), text);
  await tester.pump();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Finder get checkoutButton => find.ancestor(
  of: find.textContaining('Checkout · '),
  matching: find.byType(FilledButton),
);

/// Taps Checkout on the cart. The button spins while a sheet or checkout
/// is open, so no pumpAndSettle.
Future<void> tapCheckout(WidgetTester tester) async {
  await tester.tap(checkoutButton);
  await tester.pump();
  await tester.pump(const Duration(seconds: 1));
}

void main() {
  final products = sampleProducts();
  final kiwi = products[0];
  final beef = products[1];

  CartStore twoItemCart() => CartStore()
    ..add(kiwi, kiwi.variants[0], quantity: 2)
    ..add(beef, beef.variants[0]);

  group('Account: your details', () {
    testWidgets('empty: what they are for and an ink "Add details"', (
      tester,
    ) async {
      await pumpScreen(tester, const AccountScreen(), profile: ProfileStore());
      final card = find.byKey(const ValueKey('account-details'));
      expect(
        find.descendant(of: card, matching: find.text('Your details')),
        findsOneWidget,
      );
      expect(
        find.text('Add them once and checkout opens already filled in.'),
        findsOneWidget,
      );
      final add = find.widgetWithText(OutlinedButton, 'Add details');
      expect(add, findsOneWidget);
      expect(tester.getSize(add).height, greaterThanOrEqualTo(44));
      // No green on Account (the one filled button, "Sign in with
      // email", is ink); nothing to delete yet.
      final filled = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(
        filled.style!.backgroundColor!.resolve(const <WidgetState>{}),
        AppColors.ink,
      );
      expect(find.text(AccountScreen.deleteLabel), findsNothing);
      // Under the account card, above the addresses.
      expect(
        tester.getTopLeft(card).dy,
        greaterThan(
          tester.getBottomLeft(find.byKey(const ValueKey('account-session'))).dy,
        ),
      );
      expect(
        tester.getTopLeft(card).dy,
        lessThan(tester.getTopLeft(find.text('Delivery addresses')).dy),
      );
    });

    testWidgets('filled: name, mobile and email with Edit; the addresses, '
        'default first and marked', (tester) async {
      await pumpScreen(
        tester,
        const AccountScreen(),
        profile: filledProfile(),
        delivery: testDelivery(),
      );
      expect(find.text('Sara Ahmed'), findsOneWidget);
      expect(find.text(saraMobile), findsOneWidget);
      expect(find.text('sara@example.com'), findsOneWidget);
      expect(find.text('SA'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Edit'), findsOneWidget);

      final list = find.byKey(const ValueKey('account-addresses'));
      Finder inList(String text) =>
          find.descendant(of: list, matching: find.text(text));
      expect(inList('Bay Square, Building 5 · Flat 302'), findsOneWidget);
      expect(inList('Marina Plaza · Office 1204'), findsOneWidget);
      expect(inList('Business Bay, Dubai'), findsOneWidget);
      expect(inList('Dubai Marina'), findsOneWidget);
      expect(inList('Default'), findsOneWidget);
      expect(inList('Home'), findsOneWidget);
      expect(inList('Office'), findsOneWidget);
      expect(
        tester.getTopLeft(inList('Home')).dy,
        lessThan(tester.getTopLeft(inList('Office')).dy),
      );
      expect(
        tester.getTopLeft(inList('Default')).dy,
        tester.getTopLeft(inList('Home')).dy,
      );
      expect(inList('Add address'), findsOneWidget);
      // Each address is one button for screen readers.
      expect(
        find.bySemanticsLabel(
          RegExp(
            r'^Home address: Bay Square, Building 5, Flat 302, '
            r'Business Bay, Dubai, default\. Edit$',
          ),
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text(AccountScreen.deleteLabel),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text(AccountScreen.deleteLabel), findsOneWidget);
    });

    testWidgets('Add details opens My details; saving comes back filled '
        'and says so', (tester) async {
      final profile = ProfileStore(vault: MemoryProfileVault());
      await pumpScreen(tester, const AccountScreen(), profile: profile);
      await tester.tap(find.text('Add details'));
      await tester.pumpAndSettle();
      expect(find.byType(MyDetailsScreen), findsOneWidget);

      await type(tester, 'First name', '  سارة ');
      await type(tester, 'Last name', 'Ahmed');
      await type(tester, 'Mobile', '050 123 4567');
      await type(tester, 'Email', 'sara@example.com');
      await tester.tap(find.byKey(const ValueKey('details-save')));
      await tester.pumpAndSettle();

      expect(find.byType(MyDetailsScreen), findsNothing);
      expect(profile.contact.firstName, 'سارة');
      expect(profile.contact.mobile, '+971501234567');
      expect(find.text(MyDetailsScreen.savedMessage), findsOneWidget);
      expect(find.text('سارة Ahmed'), findsOneWidget);
      expect(find.text(saraMobile), findsOneWidget);
    });

    testWidgets('Delete my details asks first; Cancel keeps, Delete '
        'removes everything', (tester) async {
      final vault = MemoryProfileVault();
      final profile = filledProfile(vault: vault);
      await pumpScreen(
        tester,
        const AccountScreen(),
        profile: profile,
        delivery: testDelivery(),
      );
      final delete = find.byKey(const ValueKey('delete-details'));
      await tester.scrollUntilVisible(
        delete,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(tester.getSize(delete).height, greaterThanOrEqualTo(44));
      await tester.tap(delete);
      await tester.pumpAndSettle();
      expect(find.text(AccountScreen.deleteTitle), findsOneWidget);
      expect(find.text(AccountScreen.deleteMessage), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(profile.hasDetails, isTrue);

      await tester.ensureVisible(delete);
      await tester.tap(delete);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('delete-details-confirm')));
      await tester.pumpAndSettle();
      expect(profile.hasDetails, isFalse);
      expect(vault.value, isNull);
      expect(find.text(AccountScreen.deletedMessage), findsOneWidget);
      expect(find.text('Add details'), findsOneWidget);
      expect(find.text(AccountScreen.deleteLabel), findsNothing);
    });
  });

  group('My details', () {
    testWidgets('a bad mobile and a bad email are said in ink, announced, '
        'and nothing is saved', (tester) async {
      final said = captureAnnouncements(tester);
      final profile = ProfileStore();
      await pumpScreen(tester, const MyDetailsScreen(), profile: profile);

      // Labels, keyboards and autofill as a phone needs them.
      final mobile = tester.widget<EditableText>(field('Mobile'));
      expect(mobile.keyboardType, TextInputType.phone);
      expect(mobile.autofillHints, [AutofillHints.telephoneNumber]);
      expect(mobile.textInputAction, TextInputAction.next);
      final email = tester.widget<EditableText>(field('Email'));
      expect(email.keyboardType, TextInputType.emailAddress);
      expect(email.textInputAction, TextInputAction.done);
      expect(tester.widget<EditableText>(field('First name')).autofillHints, [
        AutofillHints.givenName,
      ]);
      expect(find.text(mobileHint), findsOneWidget);
      expect(find.text(PrivacyNote.text), findsOneWidget);

      await type(tester, 'Mobile', '050 123 45');
      await type(tester, 'Email', 'sara@example');
      await tester.tap(find.byKey(const ValueKey('details-save')));
      await tester.pump();

      expect(find.text(CustomerInput.mobileError), findsOneWidget);
      expect(find.text(CustomerInput.emailError), findsOneWidget);
      expect(said, [CustomerInput.mobileError]);
      expect(profile.hasDetails, isFalse);
      // Ink, not red.
      final error = tester.widget<Text>(find.text(CustomerInput.mobileError));
      expect(error.style!.color, AppColors.ink);
      expect(find.byIcon(Icons.error_outline), findsNWidgets(2));

      // Fixing them clears the errors as they are typed.
      await type(tester, 'Mobile', '+971 50 123 4567');
      await type(tester, 'Email', 'sara@example.com');
      expect(find.text(CustomerInput.mobileError), findsNothing);
      expect(find.text(CustomerInput.emailError), findsNothing);
    });

    testWidgets('Save is the green 52pt button, pinned at the bottom', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const MyDetailsScreen(),
        profile: ProfileStore(),
      );
      final save = find.byKey(const ValueKey('details-save'));
      expect(tester.widget<FilledButton>(save).style, isNull);
      expect(tester.getSize(save).height, greaterThanOrEqualTo(52));
      expect(tester.getBottomLeft(save).dy, greaterThan(844 - 120));
    });

    testWidgets('opens with what is saved, mobile written out', (tester) async {
      await pumpScreen(
        tester,
        const MyDetailsScreen(),
        profile: ProfileStore()..saveContact(sara),
      );
      expect(
        tester.widget<EditableText>(field('Mobile')).controller.text,
        '+971 50 123 4567',
      );
      expect(
        tester.widget<EditableText>(field('Email')).controller.text,
        'sara@example.com',
      );
    });
  });

  group('Address screen', () {
    testWidgets('starts in the delivery area as Home; the building is '
        'required', (tester) async {
      final said = captureAnnouncements(tester);
      final profile = ProfileStore();
      final delivery = testDelivery();
      await pumpScreen(
        tester,
        const AccountScreen(),
        profile: profile,
        delivery: delivery,
      );
      await tapVisible(tester, find.byKey(const ValueKey('add-address')));
      await tester.pumpAndSettle();
      expect(find.byType(AddressScreen), findsOneWidget);
      expect(find.text(AddressScreen.addTitle), findsOneWidget);
      final areaRow = find.byKey(const ValueKey('address-area'));
      expect(
        find.descendant(
          of: areaRow,
          matching: find.text('Business Bay, Dubai'),
        ),
        findsOneWidget,
      );
      expect(
        tester.getSemantics(find.widgetWithText(Semantics, 'Home').first),
        isSemantics(isSelected: true),
      );

      await tapVisible(tester, find.byKey(const ValueKey('address-save')));
      expect(find.text(CustomerInput.buildingError), findsOneWidget);
      expect(said, [CustomerInput.buildingError]);
      expect(profile.hasAddresses, isFalse);

      await type(tester, 'Building or villa', 'Bay Square, Building 5');
      await type(tester, 'Flat, floor', 'Flat 302');
      await type(tester, 'Delivery instructions', 'x' * 250);
      expect(find.text('200/200'), findsOneWidget, reason: 'stops at 200');
      await type(tester, 'Delivery instructions', 'Call when you arrive');
      await tapVisible(tester, find.byKey(const ValueKey('address-save')));
      await tester.pumpAndSettle();

      expect(find.byType(AddressScreen), findsNothing);
      final saved = profile.addresses.single;
      expect(saved.label, AddressLabel.home);
      expect(saved.area, area('Business Bay'));
      expect(saved.building, 'Bay Square, Building 5');
      expect(saved.flat, 'Flat 302');
      expect(saved.instructions, 'Call when you arrive');
      expect(profile.defaultAddress, saved);
      expect(find.text('Address saved.'), findsOneWidget);
    });

    testWidgets('Change picks the area with the location picker; the '
        'delivery location stays', (tester) async {
      final profile = ProfileStore()..saveAddress(homeIn('Business Bay'));
      final delivery = testDelivery();
      await pumpScreen(
        tester,
        AddressScreen(initialArea: delivery.area),
        profile: profile,
        delivery: delivery,
      );
      // The second address is the Office.
      expect(
        tester.getSemantics(find.widgetWithText(Semantics, 'Office').first),
        isSemantics(isSelected: true),
      );
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      final picker = tester.widget<LocationScreen>(find.byType(LocationScreen));
      expect(picker.pickOnly, isTrue);
      expect(find.text(LocationScreen.addressTitle), findsOneWidget);

      final row = find.descendant(
        of: find.byType(LocationScreen),
        matching: find.text('Dubai Marina'),
      );
      await tester.tap(row.first);
      await tester.pump();
      await tester.tap(find.text('Use Dubai Marina'));
      await tester.pumpAndSettle();

      expect(find.byType(LocationScreen), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('address-area')),
          matching: find.text('Dubai Marina'),
        ),
        findsOneWidget,
      );
      expect(delivery.area!.name, 'Business Bay', reason: 'unchanged');

      await type(tester, 'Building or villa', 'Marina Plaza');
      await tapVisible(tester, find.byKey(const ValueKey('address-default')));
      await tapVisible(tester, find.byKey(const ValueKey('address-save')));
      final added = profile.addresses.firstWhere((a) => a.id != 'home');
      expect(added.area.name, 'Dubai Marina');
      expect(added.area.emirate, Emirate.dubai);
      expect(added.label, AddressLabel.office);
      expect(profile.defaultAddress!.id, added.id, reason: 'made default');
    });

    testWidgets('editing: delete asks first', (tester) async {
      final profile = filledProfile();
      await pumpScreen(
        tester,
        const AccountScreen(),
        profile: profile,
        delivery: testDelivery(),
      );
      await tapVisible(
        tester,
        find.byKey(const ValueKey('account-address-office')),
      );
      await tester.pumpAndSettle();
      expect(find.text(AddressScreen.editTitle), findsOneWidget);
      await tapVisible(tester, find.byKey(const ValueKey('address-delete')));
      await tester.pumpAndSettle();
      expect(find.text('Delete this address?'), findsOneWidget);
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(profile.addressById('office'), isNull);
      expect(find.byType(AddressScreen), findsNothing);
      expect(find.text('Address deleted.'), findsOneWidget);
    });
  });

  group('Cart: Deliver to', () {
    testWidgets('nothing saved: a quiet row (no green) to My details', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const CartScreen(),
        cart: twoItemCart(),
        delivery: testDelivery(),
        profile: ProfileStore(),
      );
      expect(find.text(CartDeliverToCard.quietLabel), findsOneWidget);
      // The only green is Checkout.
      expect(find.byType(FilledButton), findsOneWidget);
      final row = find.byKey(const ValueKey('cart-deliver-to'));
      expect(tester.getSize(row).height, greaterThanOrEqualTo(48));
      // Under the delivery card.
      expect(
        tester.getTopLeft(row).dy,
        greaterThan(
          tester.getBottomLeft(find.byKey(const ValueKey('cart-delivery'))).dy,
        ),
      );
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(find.byType(MyDetailsScreen), findsOneWidget);
    });

    testWidgets('the address in the delivery area and the contact line, '
        'with Change', (tester) async {
      await pumpScreen(
        tester,
        const CartScreen(),
        cart: twoItemCart(),
        delivery: testDelivery(),
        profile: filledProfile(),
      );
      final card = find.byKey(const ValueKey('cart-deliver-to'));
      Finder inCard(String text) =>
          find.descendant(of: card, matching: find.text(text));
      expect(inCard('Deliver to'), findsOneWidget);
      expect(inCard('Home'), findsOneWidget);
      expect(inCard('Bay Square, Building 5 · Flat 302'), findsOneWidget);
      expect(inCard('Business Bay, Dubai'), findsOneWidget);
      expect(inCard('Sara Ahmed · $saraMobile'), findsOneWidget);
      expect(find.byKey(const ValueKey('deliver-to-change')), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('choosing an address in another area moves the delivery '
        'location and says so', (tester) async {
      final delivery = testDelivery();
      final profile = filledProfile();
      await pumpScreen(
        tester,
        const CartScreen(),
        cart: twoItemCart(),
        delivery: delivery,
        profile: profile,
      );
      await tester.tap(find.byKey(const ValueKey('deliver-to-change')));
      await tester.pumpAndSettle();
      expect(find.text(AddressSheet.title), findsWidgets);
      expect(find.text(AddressSheet.note), findsOneWidget);
      // Radio rows: Home is the one in use.
      final homeRow = find.byKey(const ValueKey('address-option-home'));
      final officeRow = find.byKey(const ValueKey('address-option-office'));
      expect(
        tester.getSemantics(homeRow).flagsCollection.isChecked,
        CheckedState.isTrue,
      );
      expect(
        tester.getSemantics(officeRow).flagsCollection.isChecked,
        CheckedState.isFalse,
      );
      expect(find.text('Add new address'), findsOneWidget);

      await tester.tap(officeRow);
      await tester.pumpAndSettle();
      expect(delivery.area!.name, 'Dubai Marina');
      expect(find.text('Delivering to Dubai Marina'), findsOneWidget);
      // The delivery card and the promise follow the new area.
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('cart-delivery')),
          matching: find.text('Dubai Marina'),
        ),
        findsOneWidget,
      );
      expect(find.text('Marina Plaza · Office 1204'), findsOneWidget);
    });

    testWidgets('no address in the area: "Your Home address is in Dubai '
        'Marina." with Deliver there and Add one here', (tester) async {
      final delivery = testDelivery(); // Business Bay
      final profile = ProfileStore()
        ..saveContact(sara)
        ..saveAddress(homeIn('Dubai Marina'));
      await pumpScreen(
        tester,
        const CartScreen(),
        cart: twoItemCart(),
        delivery: delivery,
        profile: profile,
      );
      expect(
        find.text('Your Home address is in Dubai Marina.'),
        findsOneWidget,
      );
      expect(find.text('Deliver there'), findsOneWidget);
      expect(find.text('Add one in Business Bay'), findsOneWidget);
      // Calm: ink outline and a text button, no green.
      expect(find.byType(FilledButton), findsOneWidget);
      expect(
        find.widgetWithText(OutlinedButton, 'Deliver there'),
        findsOneWidget,
      );

      await tester.tap(find.text('Deliver there'));
      await tester.pumpAndSettle();
      expect(delivery.area!.name, 'Dubai Marina');
      expect(find.text('Delivering to Dubai Marina'), findsOneWidget);
      expect(find.text('Bay Square, Building 5 · Flat 302'), findsOneWidget);
    });

    testWidgets('"Add one in Business Bay" adds an address there and '
        'delivers to it', (tester) async {
      final said = captureAnnouncements(tester);
      final delivery = testDelivery();
      final profile = ProfileStore()..saveAddress(homeIn('Dubai Marina'));
      await pumpScreen(
        tester,
        const CartScreen(),
        cart: twoItemCart(),
        delivery: delivery,
        profile: profile,
      );
      await tester.tap(find.text('Add one in Business Bay'));
      await tester.pumpAndSettle();
      expect(find.byType(AddressScreen), findsOneWidget);
      await type(tester, 'Building or villa', 'Bay Gate Tower');
      await tapVisible(tester, find.byKey(const ValueKey('address-save')));
      await tester.pumpAndSettle();
      expect(find.byType(AddressScreen), findsNothing);
      expect(find.text('Bay Gate Tower'), findsOneWidget);
      expect(delivery.area!.name, 'Business Bay');
      expect(said.last, startsWith('Delivering to your Office address'));
    });

    testWidgets('contact only: the contact line and a way to add the '
        'address', (tester) async {
      await pumpScreen(
        tester,
        const CartScreen(),
        cart: twoItemCart(),
        delivery: testDelivery(),
        profile: ProfileStore()..saveContact(sara),
      );
      expect(find.text('Sara Ahmed · $saraMobile'), findsOneWidget);
      expect(find.text('Add your address in Business Bay'), findsOneWidget);
    });
  });

  group('Checkout fills in the saved details', () {
    testWidgets('the cart opens checkout with the details and the delivery '
        'attributes', (tester) async {
      final launched = mockLauncher(tester);
      await pumpScreen(
        tester,
        const CartScreen(),
        cart: twoItemCart(),
        delivery: testDelivery(),
        profile: filledProfile(),
      );
      await tapCheckout(tester);
      expect(find.byType(CheckoutScreen), findsOneWidget);
      expect(find.text(CheckoutDetailsSheet.title), findsNothing);
      expect(launched.single, contains('attributes%5BDelivery%20mode%5D='));
      final url = Uri.parse(launched.single);
      expect(
        url.queryParameters['attributes[Delivery area]'],
        'Business Bay, Dubai',
      );
      expect(
        url.queryParameters['attributes[Delivery instructions]'],
        'Call when you arrive',
      );
      expect(url.queryParameters['checkout[email]'], 'sara@example.com');
      expect(
        url.queryParameters['checkout[shipping_address][address1]'],
        'Bay Square, Building 5',
      );
      expect(
        url.queryParameters['checkout[shipping_address][address2]'],
        'Flat 302',
      );
      expect(url.queryParameters['checkout[shipping_address][province]'], 'DU');
      expect(
        url.queryParameters['checkout[shipping_address][phone]'],
        '+971501234567',
      );
    });

    testWidgets('the assistant takes the same path', (tester) async {
      final launched = mockLauncher(tester);
      await pumpScreen(
        tester,
        AssistantScreen(
          session: AssistantSession(
            minReplyDelay: const Duration(milliseconds: 100),
          ),
        ),
        cart: twoItemCart(),
        delivery: testDelivery(),
        profile: filledProfile(),
      );
      await tester.enterText(find.byType(TextField), 'checkout');
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Go to checkout'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(CheckoutScreen), findsOneWidget);
      final url = Uri.parse(launched.single);
      expect(
        url.queryParameters['checkout[shipping_address][first_name]'],
        'Sara',
      );
      expect(
        url.queryParameters['checkout[shipping_address][city]'],
        'Business Bay',
      );
    });

    testWidgets('a delivery area with no saved address sends contact, city '
        'and emirate, never another building', (tester) async {
      final launched = mockLauncher(tester);
      await pumpScreen(
        tester,
        const CartScreen(),
        cart: twoItemCart(),
        delivery: testDelivery(area: 'Jumeirah'),
        profile: filledProfile(),
      );
      await tapCheckout(tester);
      final q = Uri.parse(launched.single).queryParameters;
      expect(q['checkout[shipping_address][city]'], 'Jumeirah');
      expect(q['checkout[shipping_address][country]'], 'AE');
      expect(q.containsKey('checkout[shipping_address][address1]'), isFalse);
      expect(q.containsKey('attributes[Delivery instructions]'), isFalse);
      expect(q['checkout[email]'], 'sara@example.com');
    });
  });

  group('First checkout: Fill in checkout faster', () {
    Future<List<String>> openSheet(
      WidgetTester tester,
      ProfileStore profile,
    ) async {
      final launched = mockLauncher(tester);
      await pumpScreen(
        tester,
        const CartScreen(),
        cart: twoItemCart(),
        delivery: testDelivery(),
        profile: profile,
      );
      await tapCheckout(tester);
      expect(find.text(CheckoutDetailsSheet.title), findsOneWidget);
      expect(find.byType(CheckoutScreen), findsNothing);
      return launched;
    }

    Future<void> fillSheet(WidgetTester tester) async {
      await type(tester, 'First name', 'Sara');
      await type(tester, 'Last name', 'Ahmed');
      await type(tester, 'Mobile', '0501234567');
      await type(tester, 'Email', 'sara@example.com');
      await type(tester, 'Building or villa', 'Bay Square, Building 5');
      await type(tester, 'Flat, floor', 'Flat 302');
    }

    Future<void> tapInSheet(WidgetTester tester, Key key) async {
      await tester.ensureVisible(find.byKey(key));
      await tester.pump();
      await tester.tap(find.byKey(key));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('Continue saves the details and opens checkout filled in', (
      tester,
    ) async {
      final vault = MemoryProfileVault();
      final profile = ProfileStore(vault: vault);
      final launched = await openSheet(tester, profile);
      expect(find.text('Your address in Business Bay'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('sheet-continue')))
            .style,
        isNull,
        reason: 'the green buying button',
      );
      await fillSheet(tester);
      await tapInSheet(tester, const ValueKey('sheet-continue'));

      expect(find.byType(CheckoutScreen), findsOneWidget);
      final q = Uri.parse(launched.single).queryParameters;
      expect(q['checkout[shipping_address][first_name]'], 'Sara');
      expect(q['checkout[shipping_address][phone]'], '+971501234567');
      expect(
        q['checkout[shipping_address][address1]'],
        'Bay Square, Building 5',
      );
      expect(profile.contact, sara);
      expect(profile.addresses.single.flat, 'Flat 302');
      await profile.idle;
      expect(vault.value, isNotNull);
    });

    testWidgets('Skip opens checkout as before and is remembered', (
      tester,
    ) async {
      final vault = MemoryProfileVault();
      final profile = ProfileStore(vault: vault);
      final launched = await openSheet(tester, profile);
      await tapInSheet(tester, const ValueKey('sheet-skip'));
      expect(find.byType(CheckoutScreen), findsOneWidget);
      expect(launched.single, isNot(contains('checkout%5B')));
      expect(profile.checkoutSheetSkipped, isTrue);

      await tester.tap(find.text('Back to cart'));
      await tester.pumpAndSettle();
      // The cart keeps the quiet row; the sheet is not shown again.
      expect(find.text(CartDeliverToCard.quietLabel), findsOneWidget);
      await tapCheckout(tester);
      expect(find.text(CheckoutDetailsSheet.title), findsNothing);
      expect(find.byType(CheckoutScreen), findsOneWidget);
      expect(launched, hasLength(2));

      // Remembered on the phone too.
      await profile.idle;
      final later = ProfileStore(vault: vault);
      await later.load();
      expect(later.offersCheckoutSheet, isFalse);
    });

    testWidgets('Continue with nothing typed is remembered like Skip', (
      tester,
    ) async {
      final vault = MemoryProfileVault();
      final profile = ProfileStore(vault: vault);
      final launched = await openSheet(tester, profile);
      await tapInSheet(tester, const ValueKey('sheet-continue'));
      expect(find.byType(CheckoutScreen), findsOneWidget);
      expect(launched.single, isNot(contains('checkout%5B')));

      await tester.tap(find.text('Back to cart'));
      await tester.pumpAndSettle();
      await tapCheckout(tester);
      expect(find.text(CheckoutDetailsSheet.title), findsNothing);
      expect(find.byType(CheckoutScreen), findsOneWidget);
      expect(launched, hasLength(2));
    });

    testWidgets('Save off: used for this checkout only', (tester) async {
      final vault = MemoryProfileVault();
      final profile = ProfileStore(vault: vault);
      final launched = await openSheet(tester, profile);
      await fillSheet(tester);
      await tapInSheet(tester, const ValueKey('sheet-save'));
      final toggle = tester.widget<Switch>(
        find.descendant(
          of: find.byKey(const ValueKey('sheet-save')),
          matching: find.byType(Switch),
        ),
      );
      expect(toggle.value, isFalse);
      await tapInSheet(tester, const ValueKey('sheet-continue'));

      final q = Uri.parse(launched.single).queryParameters;
      expect(q['checkout[email]'], 'sara@example.com');
      expect(q['checkout[shipping_address][address2]'], 'Flat 302');
      expect(profile.hasDetails, isFalse);
      await profile.idle;
      expect(vault.writes, isEmpty);
    });

    testWidgets('closing the sheet stays on the cart', (tester) async {
      final profile = ProfileStore();
      final launched = await openSheet(tester, profile);
      await tester.tapAt(const Offset(195, 40)); // the scrim
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(CheckoutDetailsSheet.title), findsNothing);
      expect(find.byType(CheckoutScreen), findsNothing);
      expect(launched, isEmpty);
      expect(profile.offersCheckoutSheet, isTrue);
    });

    testWidgets('a bad mobile, or a flat with no building, is said', (
      tester,
    ) async {
      final said = captureAnnouncements(tester);
      final profile = ProfileStore();
      final launched = await openSheet(tester, profile);
      await type(tester, 'Mobile', '12345');
      await type(tester, 'Flat, floor', 'Flat 302');
      await tapInSheet(tester, const ValueKey('sheet-continue'));
      expect(find.text(CustomerInput.mobileError), findsOneWidget);
      expect(
        find.text(CheckoutDetailsSheet.flatWithoutBuilding),
        findsOneWidget,
      );
      expect(said, [CustomerInput.mobileError]);
      expect(launched, isEmpty);
      expect(find.byType(CheckoutScreen), findsNothing);
    });
  });

  group('200% text', () {
    Future<void> atDoubleText(
      WidgetTester tester,
      Widget screen, {
      ProfileStore? profile,
      CartStore? cart,
      String? deliveryArea = 'Business Bay',
    }) async {
      await loadAppFonts(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpScreen(
        tester,
        screen,
        profile: profile ?? filledProfile(),
        cart: cart,
        delivery: testDelivery(area: deliveryArea),
      );
      tester.view.physicalSize = const Size(1080, 2340); // 360dp wide
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull, reason: '$screen');
    }

    testWidgets('Account, My details and the address form', (tester) async {
      await atDoubleText(tester, const AccountScreen());
      await atDoubleText(
        tester,
        const AccountScreen(),
        profile: ProfileStore(),
      );
      await atDoubleText(tester, const MyDetailsScreen());
      await atDoubleText(
        tester,
        AddressScreen(address: homeIn('Business Bay')),
      );
      // The name fields stack rather than squeeze.
      await atDoubleText(tester, const MyDetailsScreen());
      expect(
        tester.getTopLeft(field('Last name')).dy,
        greaterThan(tester.getBottomLeft(field('First name')).dy),
      );
    });

    testWidgets('the sign-in card keeps its width; its button is whole', (
      tester,
    ) async {
      await atDoubleText(tester, const AccountScreen());
      final line = find.textContaining("We'll send you a 6-digit code");
      // The text column is the card's width, not a one-word strip.
      expect(tester.getSize(line).width, greaterThan(220));
      final button = find.widgetWithText(FilledButton, 'Sign in with email');
      expect(tester.getTopLeft(button).dy, greaterThan(tester.getBottomLeft(line).dy));
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      final label = tester.renderObject<RenderParagraph>(
        find.descendant(of: button, matching: find.byType(RichText)),
      );
      expect(label.didExceedMaxLines, isFalse);
    });

    testWidgets('only Save is pinned: the privacy note scrolls with the '
        'form, and hints are not cut', (tester) async {
      await atDoubleText(
        tester,
        const MyDetailsScreen(),
        profile: ProfileStore(),
      );
      final save = find.byKey(const ValueKey('details-save'));
      // 360x780dp screen: the pinned bar is the button and its padding.
      expect(780 - tester.getTopLeft(save).dy, lessThan(110));
      await tester.scrollUntilVisible(
        find.byType(PrivacyNote),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(
        find.descendant(
          of: find.byType(ListView),
          matching: find.byType(PrivacyNote),
        ),
        findsOneWidget,
      );
      for (final decorator in tester.widgetList<InputDecorator>(
        find.byType(InputDecorator),
      )) {
        expect(decorator.decoration.hintMaxLines, 2);
      }
    });

    testWidgets('the mobile number stays on one line on Account and the '
        'cart', (tester) async {
      for (final screen in [const AccountScreen(), const CartScreen()]) {
        await atDoubleText(tester, screen, cart: twoItemCart());
        final number = find.textContaining(saraMobile);
        expect(number, findsOneWidget, reason: '$screen');
        final paragraph = tester.renderObject<RenderParagraph>(number);
        final lines = paragraph.getBoxesForSelection(
          TextSelection(
            baseOffset: 0,
            extentOffset: paragraph.text.toPlainText().length,
          ),
        );
        final start = paragraph.text.toPlainText().indexOf(saraMobile);
        final numberBoxes = paragraph.getBoxesForSelection(
          TextSelection(
            baseOffset: start,
            extentOffset: start + saraMobile.length,
          ),
        );
        expect(lines, isNotEmpty);
        expect(
          numberBoxes.map((b) => b.top).toSet(),
          hasLength(1),
          reason: 'not split across lines on $screen',
        );
      }
    });

    testWidgets('the cart in every Deliver to state', (tester) async {
      await atDoubleText(tester, const CartScreen(), cart: twoItemCart());
      await atDoubleText(
        tester,
        const CartScreen(),
        cart: twoItemCart(),
        deliveryArea: 'Jumeirah',
      );
      await atDoubleText(
        tester,
        const CartScreen(),
        cart: twoItemCart(),
        profile: ProfileStore()..saveContact(sara),
      );
      await atDoubleText(
        tester,
        const CartScreen(),
        cart: twoItemCart(),
        profile: ProfileStore(),
      );
    });

    testWidgets('the address sheet and the checkout sheet', (tester) async {
      await atDoubleText(tester, const CartScreen(), cart: twoItemCart());
      await tester.ensureVisible(
        find.byKey(const ValueKey('deliver-to-change')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('deliver-to-change')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Add new address'), findsOneWidget);
      Navigator.of(tester.element(find.text('Add new address'))).pop();
      await tester.pumpAndSettle();

      mockLauncher(tester);
      await atDoubleText(
        tester,
        const CartScreen(),
        cart: twoItemCart(),
        profile: ProfileStore(),
      );
      await tester.scrollUntilVisible(
        checkoutButton,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      await tapCheckout(tester);
      expect(find.text(CheckoutDetailsSheet.title), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Everything in the sheet can be reached by scrolling.
      await tester.ensureVisible(find.byKey(const ValueKey('sheet-skip')));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('Polish', () {
    testWidgets('the area picker for an address: an ink button and where '
        'the area is, no delivery promise', (tester) async {
      final profile = ProfileStore()..saveAddress(homeIn('Business Bay'));
      final delivery = testDelivery();
      await pumpScreen(
        tester,
        AddressScreen(initialArea: delivery.area),
        profile: profile,
        delivery: delivery,
      );
      await tester.tap(find.text('Change'));
      await tester.pumpAndSettle();
      final use = find.widgetWithText(FilledButton, 'Use Business Bay');
      expect(use, findsOneWidget);
      final style = tester.widget<FilledButton>(use).style;
      expect(style, isNotNull, reason: 'not the green buying style');
      expect(style!.backgroundColor!.resolve({}), AppColors.ink);
      expect(find.textContaining('What you get'), findsNothing);
      expect(find.textContaining('Express'), findsNothing);
      expect(find.text('Business Bay is in Dubai.'), findsOneWidget);
    });

    testWidgets('no address in the area: two actions, what checkout will '
        'ask, "Deliver there" on the text column', (tester) async {
      final profile = ProfileStore()
        ..saveContact(sara)
        ..saveAddress(homeIn('Dubai Marina'))
        ..saveAddress(office);
      await pumpScreen(
        tester,
        const CartScreen(),
        cart: twoItemCart(),
        delivery: testDelivery(),
        profile: profile,
      );
      final title = find.text('Your Home address is in Dubai Marina.');
      expect(title, findsOneWidget);
      expect(find.byKey(const ValueKey('deliver-to-change')), findsNothing);
      expect(
        find.text('Checkout will ask for your building in Business Bay.'),
        findsOneWidget,
      );
      expect(find.textContaining('Sara Ahmed'), findsNothing);
      expect(
        tester.getTopLeft(find.byKey(const ValueKey('deliver-there'))).dx,
        moreOrLessEquals(tester.getTopLeft(title).dx, epsilon: 0.5),
      );
    });

    testWidgets('an address labelled Other is "your saved address"', (
      tester,
    ) async {
      final other = SavedAddress(
        id: 'other',
        label: AddressLabel.other,
        area: area('Dubai Marina'),
        building: 'Marina Gate 2',
      );
      await pumpScreen(
        tester,
        const CartScreen(),
        cart: twoItemCart(),
        delivery: testDelivery(),
        profile: ProfileStore()..saveAddress(other),
      );
      expect(
        find.text('Your saved address is in Dubai Marina.'),
        findsOneWidget,
      );
      expect(
        AppNav.deliveringToAddress(other),
        'Delivering to your saved address, Marina Gate 2',
      );
    });

    testWidgets('My details: Save with nothing typed confirms nothing; '
        'clearing saved details says so', (tester) async {
      final profile = ProfileStore();
      await pumpScreen(tester, const AccountScreen(), profile: profile);
      await tester.tap(find.text('Add details'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('details-save')));
      await tester.pumpAndSettle();
      expect(find.byType(MyDetailsScreen), findsNothing);
      expect(find.text(MyDetailsScreen.savedMessage), findsNothing);
      expect(find.text('Add details'), findsOneWidget);

      profile.saveContact(sara);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('edit-details')));
      await tester.pumpAndSettle();
      for (final label in ['First name', 'Last name', 'Mobile', 'Email']) {
        await type(tester, label, '');
      }
      await tester.tap(find.byKey(const ValueKey('details-save')));
      await tester.pumpAndSettle();
      expect(find.text(MyDetailsScreen.clearedMessage), findsOneWidget);
      expect(find.text(MyDetailsScreen.savedMessage), findsNothing);
      expect(profile.hasContact, isFalse);
    });

    testWidgets('the default switch shows only from the second address', (
      tester,
    ) async {
      Future<void> pumpAddress(ProfileStore profile, SavedAddress? a) async {
        await pumpScreen(
          tester,
          AddressScreen(
            key: UniqueKey(),
            address: a,
            initialArea: area('Business Bay'),
          ),
          profile: profile,
          delivery: testDelivery(),
        );
        await tester.scrollUntilVisible(
          find.byType(PrivacyNote),
          200,
          scrollable: find.byType(Scrollable).first,
        );
      }

      final defaultSwitch = find.byKey(const ValueKey('address-default'));
      // The first address, and the only one when edited: always default.
      await pumpAddress(ProfileStore(), null);
      expect(defaultSwitch, findsNothing);
      final only = homeIn('Business Bay');
      await pumpAddress(ProfileStore()..saveAddress(only), only);
      expect(defaultSwitch, findsNothing);
      // A second one, or either of two when edited.
      await pumpAddress(ProfileStore()..saveAddress(only), null);
      expect(defaultSwitch, findsOneWidget);
      await pumpAddress(filledProfile(), office);
      expect(defaultSwitch, findsOneWidget);
      // The group heading, and hints that show the format.
      expect(find.text(AddressScreen.labelHeading), findsOneWidget);
      expect(find.text('Label'), findsNothing);
    });

    testWidgets('focus is the heaviest edge, also among errors', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const MyDetailsScreen(),
        profile: ProfileStore(),
      );
      await type(tester, 'Mobile', '050 123 45');
      await type(tester, 'Email', 'sara@example');
      await tester.tap(find.byKey(const ValueKey('details-save')));
      await tester.pump();
      InputDecorator decoratorOf(String label) => tester.widget<InputDecorator>(
        find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is DetailsField && w.label == label,
          ),
          matching: find.byType(InputDecorator),
        ),
      );
      final mobile = decoratorOf('Mobile');
      final email = decoratorOf('Email');
      expect(mobile.isFocused, isTrue, reason: 'the first error');
      expect(email.isFocused, isFalse);
      double width(InputBorder? b) =>
          (b! as OutlineInputBorder).borderSide.width;
      expect(width(mobile.decoration.focusedErrorBorder), 2.5);
      expect(width(mobile.decoration.focusedBorder), 2.5);
      expect(width(email.decoration.errorBorder), 1.5);
    });

    testWidgets('Account: the rows under the cards share their columns; '
        'one name for Edit; the mobile on one line', (tester) async {
      await pumpScreen(
        tester,
        const AccountScreen(),
        profile: filledProfile(),
        delivery: testDelivery(),
        session: AccountSession()..signIn(email: 'sara@example.com'),
      );
      expect(find.bySemanticsLabel('Edit my details'), findsOneWidget);
      expect(find.text(saraMobile), findsOneWidget);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('delete-details')),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pump();
      final iconX = tester
          .getTopLeft(find.byIcon(Icons.support_agent_outlined))
          .dx;
      final textX = tester.getTopLeft(find.text(AccountScreen.helpLabel)).dx;
      expect(tester.getTopLeft(find.byIcon(Icons.logout)).dx, iconX);
      expect(tester.getTopLeft(find.byIcon(Icons.delete_outline)).dx, iconX);
      expect(
        tester.getTopLeft(find.text(AccountScreen.signOutLabel)).dx,
        textX,
      );
      expect(tester.getTopLeft(find.text(AccountScreen.deleteLabel)).dx, textX);
    });

    testWidgets('a returning shopper whose details are still being read is '
        'not asked, and checkout gets the details', (tester) async {
      final saved = MemoryProfileVault();
      final writer = ProfileStore(vault: saved)
        ..saveContact(sara)
        ..saveAddress(homeIn('Business Bay'));
      await writer.idle;
      expect(saved.value, isNotNull);
      final vault = GatedVault(saved.value);
      final profile = ProfileStore(vault: vault);
      unawaited(profile.load());
      final launched = mockLauncher(tester);
      await pumpScreen(
        tester,
        const CartScreen(),
        cart: twoItemCart(),
        delivery: testDelivery(),
        profile: profile,
      );
      await tester.tap(checkoutButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(CheckoutDetailsSheet.title), findsNothing);
      vault.open();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text(CheckoutDetailsSheet.title), findsNothing);
      expect(find.byType(CheckoutScreen), findsOneWidget);
      final q = Uri.parse(launched.single).queryParameters;
      expect(q['checkout[email]'], 'sara@example.com');
      expect(
        q['checkout[shipping_address][address1]'],
        'Bay Square, Building 5',
      );
    });

    testWidgets('checkout moves the delivery pin to the address it sends', (
      tester,
    ) async {
      final launched = mockLauncher(tester);
      final delivery = testDelivery()
        // Business Bay by name, 1 km from where Home was saved.
        ..setArea(
          const DeliveryArea(
            name: 'Business Bay',
            emirate: Emirate.dubai,
            lat: 25.194,
            lng: 55.265,
          ),
        );
      await pumpScreen(
        tester,
        const CartScreen(),
        cart: twoItemCart(),
        delivery: delivery,
        profile: filledProfile(),
      );
      await tapCheckout(tester);
      final q = Uri.parse(launched.single).queryParameters;
      expect(
        q['checkout[shipping_address][address1]'],
        'Bay Square, Building 5',
      );
      expect(q['attributes[Delivery pin]'], '25.18500,55.26500');
      expect(delivery.area, area('Business Bay'));
    });
  });
}
