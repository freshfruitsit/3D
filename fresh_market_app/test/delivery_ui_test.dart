import 'dart:convert';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fresh_market_app/app.dart';
import 'package:fresh_market_app/delivery/delivery.dart';
import 'package:fresh_market_app/models/product.dart';
import 'package:fresh_market_app/screens/cart_screen.dart';
import 'package:fresh_market_app/screens/home_screen.dart';
import 'package:fresh_market_app/screens/location_screen.dart';
import 'package:fresh_market_app/screens/product_detail_screen.dart';
import 'package:fresh_market_app/screens/product_list_screen.dart';
import 'package:fresh_market_app/services/device_location.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/services/location_services.dart';
import 'package:fresh_market_app/state/cart_store.dart';
import 'package:fresh_market_app/state/favourites_store.dart';
import 'package:fresh_market_app/widgets/delivery_widgets.dart';
import 'package:fresh_market_app/widgets/floating_nav_bar.dart';
import 'package:fresh_market_app/widgets/product_card.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_app.dart';

const _settle = Duration(milliseconds: 600);

Finder _inKey(String key, Finder matching) =>
    find.descendant(of: find.byKey(ValueKey(key)), matching: matching);

Finder get _confirm => find.descendant(
  of: find.byType(LocationScreen),
  matching: find.byType(FilledButton),
);

String _confirmLabel(WidgetTester tester) {
  final text = find.descendant(of: _confirm, matching: find.byType(Text));
  return tester.widget<Text>(text).data!;
}

bool _confirmEnabled(WidgetTester tester) =>
    tester.widget<FilledButton>(_confirm).onPressed != null;

/// Types [term] into the picker's search and taps the row named [name].
Future<void> _searchAndPick(
  WidgetTester tester,
  String term,
  String name,
) async {
  await tester.enterText(
    find.descendant(
      of: find.byType(LocationScreen),
      matching: find.byType(TextField),
    ),
    term,
  );
  await tester.pump();
  final row = find.descendant(
    of: find.byType(LocationScreen),
    matching: find.text(name),
  );
  await tester.ensureVisible(row.first);
  await tester.pump();
  await tester.tap(row.first);
  await tester.pump();
}

Future<void> _tapConfirm(WidgetTester tester) async {
  await tester.tap(_confirm);
  await tester.pump();
  await tester.pump(_settle);
}

void main() {
  final products = sampleProducts();
  final kiwi = products[0]; // 1hr-delivery
  final beef = products[1]; // not on Express
  final cucumber = products[2]; // 1hr-delivery

  group('location picker', () {
    testWidgets('searching the website areas and picking one', (tester) async {
      final store = testDelivery(area: null);
      final picked = <String>[];
      await pumpScreen(
        tester,
        LocationScreen(firstLaunch: true, onPicked: picked.add),
        delivery: store,
      );

      expect(find.text('Where should we deliver?'), findsOneWidget);
      expect(find.text(LocationScreen.subtitle), findsOneWidget);
      expect(find.text('Use my current location'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).decoration?.hintText,
        'Search area, street or building',
      );
      // First launch: no way to close it without choosing.
      expect(find.byTooltip('Close'), findsNothing);
      // Nothing picked yet.
      expect(_confirmLabel(tester), 'Deliver here');
      expect(_confirmEnabled(tester), isFalse);
      expect(find.text('Pick an area first'), findsOneWidget);
      // The website's first four areas before typing.
      expect(find.text('Dubai Marina'), findsOneWidget);
      expect(find.text('Business Bay'), findsOneWidget);

      await _searchAndPick(tester, 'mirdif', 'Mirdif');
      // The row has the Express tag (Mirdif is inside the 20 km zone).
      expect(find.byType(ExpressTag), findsOneWidget);
      expect(find.text('What you get in Mirdif, Dubai'), findsOneWidget);
      expect(find.text('Fresh Market · full range'), findsOneWidget);
      expect(
        find.text('Order now and it arrives by 4 PM · same-day cut-off 6 PM'),
        findsOneWidget,
      );
      expect(find.text('Today within 6 hours'), findsOneWidget);
      expect(find.text('Express · selected items'), findsOneWidget);
      expect(
        find.text('7 km from our Ras Al Khor hub · open until 10 PM'),
        findsOneWidget,
      );
      expect(find.text('25–35 min'), findsOneWidget);
      expect(_confirmLabel(tester), 'Deliver to Mirdif');
      expect(_confirmEnabled(tester), isTrue);

      await _tapConfirm(tester);
      expect(store.area, DeliveryConfig.areaNamed('Mirdif'));
      expect(picked, ['Delivering to Mirdif']);
      expect(tester.takeException(), isNull);
    });

    testWidgets('outside the Express zone and Express closed', (tester) async {
      final store = testDelivery(area: null, at: uaeTime(23));
      await pumpScreen(
        tester,
        LocationScreen(firstLaunch: true, onPicked: (_) {}),
        delivery: store,
      );

      await _searchAndPick(tester, 'marina', 'Dubai Marina');
      expect(find.byType(ExpressTag), findsNothing);
      expect(find.text('What you get in Dubai Marina'), findsOneWidget);
      expect(
        find.text('Outside the 20 km Express zone (25 km from the hub)'),
        findsOneWidget,
      );
      expect(find.text('Not available'), findsOneWidget);
      expect(find.text('Tomorrow morning before 11 AM'), findsOneWidget);
      expect(
        find.text('Ordered after 6 PM, so it comes tomorrow morning'),
        findsOneWidget,
      );

      await _searchAndPick(tester, 'business', 'Business Bay');
      expect(find.text('Closed now · runs 8 AM to 10 PM'), findsOneWidget);
      expect(find.text('From 8 AM'), findsOneWidget);
    });

    testWidgets('addresses from the geocoder join the website areas', (
      tester,
    ) async {
      final asked = <Uri>[];
      final client = MockClient((request) async {
        asked.add(request.url);
        return http.Response(
          jsonEncode({
            'type': 'FeatureCollection',
            'features': [
              {
                'type': 'Feature',
                'geometry': {
                  'type': 'Point',
                  'coordinates': [55.2507, 25.1932],
                },
                'properties': {
                  'name': 'Al Wasl Road',
                  'district': 'Al Wasl',
                  'city': 'Dubai',
                  'state': 'Dubai',
                  'countrycode': 'AE',
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final store = testDelivery(area: null);
      await pumpScreen(
        tester,
        LocationScreen(firstLaunch: true, onPicked: (_) {}),
        delivery: store,
        locationServices: LocationServices(
          device: FakeDeviceLocation(),
          search: PlaceSearch(client: client),
          showMap: false,
        ),
      );

      await tester.enterText(find.byType(TextField), 'al wasl');
      await tester.pump();
      expect(asked, isEmpty); // the website waits 320 ms after typing
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(asked.single.host, 'photon.komoot.io');
      expect(find.text('Al Wasl Road'), findsOneWidget);
      expect(find.text('Al Wasl, Dubai'), findsOneWidget);
      expect(find.byType(ExpressTag), findsOneWidget);

      await tester.tap(find.text('Al Wasl Road'));
      await tester.pump();
      await _tapConfirm(tester);
      expect(store.area?.label, 'Al Wasl Road, Dubai');
      expect(store.area?.pin, '25.19320,55.25070');
    });

    testWidgets('the phone location names the nearest area', (tester) async {
      final store = testDelivery(area: null);
      final device = FakeDeviceLocation(const LocationFix(25.19, 55.30));
      await pumpScreen(
        tester,
        LocationScreen(firstLaunch: true, onPicked: (_) {}),
        delivery: store,
        locationServices: testLocationServices(device),
      );

      await tester.tap(find.text('Use my current location'));
      await tester.pump();
      await tester.pump();
      expect(device.locateCalls, 1);
      expect(find.text('What you get in Near Downtown Dubai'), findsOneWidget);
      expect(_confirmLabel(tester), 'Deliver to Near Downtown Dubai');

      await _tapConfirm(tester);
      expect(store.area?.name, 'Near Downtown Dubai');
      expect(store.area?.emirate, Emirate.dubai);
      expect(store.area?.pin, '25.19000,55.30000');
    });

    testWidgets('a spot outside the UAE cannot be chosen', (tester) async {
      final store = testDelivery(area: null);
      // Muscat, far from every area.
      final device = FakeDeviceLocation(const LocationFix(23.58, 58.38));
      await pumpScreen(
        tester,
        LocationScreen(firstLaunch: true, onPicked: (_) {}),
        delivery: store,
        locationServices: testLocationServices(device),
      );

      await tester.tap(find.text('Use my current location'));
      await tester.pump();
      await tester.pump();
      expect(find.text('What you get in This spot'), findsOneWidget);
      expect(find.text("We don't deliver here yet"), findsOneWidget);
      expect(
        find.text(
          'We deliver across the seven emirates of the UAE. Move the pin or '
          'search another area.',
        ),
        findsOneWidget,
      );
      expect(find.text('This spot is outside our delivery area.'), findsOne);
      expect(_confirmLabel(tester), 'Deliver here');
      expect(_confirmEnabled(tester), isFalse);
      expect(store.hasArea, isFalse);
    });

    testWidgets('location refused, refused for good, or switched off', (
      tester,
    ) async {
      final device = FakeDeviceLocation(
        const LocationFailure(LocationProblem.denied),
      );
      await pumpScreen(
        tester,
        LocationScreen(firstLaunch: true, onPicked: (_) {}),
        delivery: testDelivery(area: null),
        locationServices: testLocationServices(device),
      );
      Future<void> useLocation() async {
        await tester.tap(find.text('Use my current location'));
        await tester.pump();
        await tester.pump();
      }

      await useLocation();
      expect(
        find.text('Location wasn’t shared. Search for your area.'),
        findsOneWidget,
      );
      // "Try again" asks again.
      await tester.tap(find.text('Try again'));
      await tester.pump();
      await tester.pump();
      expect(device.locateCalls, 2);

      device.outcome = const LocationFailure(LocationProblem.deniedForever);
      await useLocation();
      expect(find.text(LocationScreen.deniedForeverMessage), findsOneWidget);
      await tester.tap(find.text('Open settings'));
      await tester.pump();
      expect(device.appSettingsOpened, 1);

      device.outcome = const LocationFailure(LocationProblem.serviceOff);
      await useLocation();
      expect(find.text(LocationScreen.serviceOffMessage), findsOneWidget);
      await tester.tap(find.text('Turn on location'));
      await tester.pump();
      expect(device.locationSettingsOpened, 1);

      device.outcome = const LocationFailure(LocationProblem.timeout);
      await useLocation();
      expect(find.text(LocationScreen.timeoutMessage), findsOneWidget);
      expect(_confirmEnabled(tester), isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('choosing a place outside the zone while on Express goes '
        'back to Fresh Market', (tester) async {
      final store = testDelivery(mode: DeliveryMode.express);
      await pumpScreen(tester, const HomeScreen(), delivery: store);
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('location-chip')));
      await tester.pump();
      await tester.pump(_settle);
      expect(find.text('Change delivery location'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);
      // It starts on the current area.
      expect(_confirmLabel(tester), 'Deliver to Business Bay');

      await _searchAndPick(tester, 'jebel', 'Jebel Ali');
      await _tapConfirm(tester);
      expect(find.byType(LocationScreen), findsNothing);
      expect(store.area?.name, 'Jebel Ali');
      expect(store.mode, DeliveryMode.market);
      expect(
        find.text(
          "Express isn't available in Jebel Ali. Switched to Fresh Market.",
        ),
        findsOneWidget,
      );
    });

    testWidgets('the close button leaves the area as it was', (tester) async {
      final store = testDelivery();
      await pumpScreen(tester, const HomeScreen(), delivery: store);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('location-chip')));
      await tester.pump();
      await tester.pump(_settle);
      await _searchAndPick(tester, 'deira', 'Deira');
      await tester.tap(find.byTooltip('Close'));
      await tester.pump();
      await tester.pump(_settle);
      expect(find.byType(LocationScreen), findsNothing);
      expect(store.area?.name, 'Business Bay');
    });

    testWidgets('the map: a tap brings the pin, a drag moves it', (
      tester,
    ) async {
      final store = testDelivery();
      await pumpScreen(
        tester,
        LocationScreen(firstLaunch: true, onPicked: (_) {}),
        delivery: store,
        // The map on, as in the app (its tiles cannot load in tests).
        locationServices: LocationServices(
          device: FakeDeviceLocation(),
          showMap: true,
        ),
      );
      await tester.pump();
      final map = find.byType(FlutterMap);
      await tester.scrollUntilVisible(
        map,
        200,
        scrollable: find
            .descendant(
              of: find.byKey(const ValueKey('location-list')),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(map, findsOneWidget);
      expect(find.text(LocationScreen.attribution), findsOneWidget);
      await tester.ensureVisible(map);
      await tester.pump();

      // West of Business Bay, at zoom 13.
      await tester.tapAt(tester.getCenter(map) + const Offset(-60, 0));
      await tester.pump(const Duration(seconds: 1));
      await tester.drag(map, const Offset(150, 0));
      await tester.pump(const Duration(seconds: 1));
      await _tapConfirm(tester);

      final area = store.area!;
      expect(area.lng, lessThan(55.265 - 0.02));
      expect(area.lat, closeTo(25.185, 0.01));
      // Named like the website names a pin: the nearest area.
      expect(area.name, DeliveryRules.placeFromPoint(area.lat, area.lng).name);
      expect(area.name, isNot('Business Bay'));
      expect(tester.takeException(), isNull);
    });
  });

  group('first launch', () {
    testWidgets('the picker comes first and must be completed', (tester) async {
      usePhoneSize(tester);
      final store = testDelivery(area: null);
      await tester.pumpWidget(
        FreshMarketApp(
          api: FakeShopifyApi.sample(),
          cart: CartStore(),
          favourites: FavouritesStore(),
          deliveryStore: store,
          locationServices: testLocationServices(),
          showIntro: false,
        ),
      );
      await tester.pump();

      expect(find.byType(LocationScreen), findsOneWidget);
      expect(find.text('Where should we deliver?'), findsOneWidget);
      expect(find.byTooltip('Close'), findsNothing);
      // The shop loads underneath but cannot be seen or used.
      expect(find.byType(FloatingNavBar), findsNothing);
      expect(find.byType(FloatingNavBar, skipOffstage: false), findsOneWidget);

      // System back does not skip it.
      await tester.binding.handlePopRoute();
      await tester.pump();
      expect(find.byType(LocationScreen), findsOneWidget);

      await _searchAndPick(tester, 'business', 'Business Bay');
      await _tapConfirm(tester);
      expect(find.byType(LocationScreen), findsNothing);
      expect(find.byType(FloatingNavBar), findsOneWidget);
      expect(store.area?.name, 'Business Bay');
      expect(
        _inKey('location-chip', find.text('Business Bay')),
        findsOneWidget,
      );
      expect(find.text('Delivering to Business Bay'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('after the intro, the picker; a saved area goes straight to '
        'Home', (tester) async {
      usePhoneSize(tester);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      Widget app() => FreshMarketApp(
        key: UniqueKey(),
        api: FakeShopifyApi.sample(),
        cart: CartStore(),
        favourites: FavouritesStore(),
        deliveryStore: DeliveryStore(prefs: prefs, refreshEvery: null),
        locationServices: testLocationServices(),
      );

      await tester.pumpWidget(app());
      await tester.pump();
      await tester.tap(find.text('Start shopping'));
      await tester.pump();
      await tester.pump(_settle);
      expect(find.byType(LocationScreen), findsOneWidget);
      await _searchAndPick(tester, 'mirdif', 'Mirdif');
      await _tapConfirm(tester);
      expect(find.byType(FloatingNavBar), findsOneWidget);
      // Saved the way the website saves it.
      final saved = jsonDecode(prefs.getString(DeliveryStore.prefsKey)!);
      expect(saved['mode'], 'market');
      expect(saved['area']['name'], 'Mirdif');
      expect(saved['area']['em'], 'dubai');

      // Next launch: the intro, then Home.
      await tester.pumpWidget(app());
      await tester.pump();
      await tester.tap(find.text('Start shopping'));
      await tester.pump();
      await tester.pump(_settle);
      expect(find.byType(LocationScreen), findsNothing);
      expect(find.byType(FloatingNavBar), findsOneWidget);
      expect(_inKey('location-chip', find.text('Mirdif')), findsOneWidget);
    });
  });

  group('Home header and delivery bar', () {
    Future<DeliveryStore> pumpHome(
      WidgetTester tester, {
      String? area = 'Business Bay',
      required DateTime at,
      DeliveryMode mode = DeliveryMode.market,
    }) async {
      final store = testDelivery(area: area, at: at, mode: mode);
      await pumpScreen(tester, const HomeScreen(), delivery: store);
      await tester.pump();
      return store;
    }

    Finder market(String text) => _inKey('mode-market', find.text(text));
    Finder express(String text) => _inKey('mode-express', find.text(text));
    Finder bar(String text) => _inKey('delivery-bar', find.text(text));

    testWidgets('10:00: same day, Express open', (tester) async {
      final store = await pumpHome(tester, at: uaeTime(10));

      expect(_inKey('location-chip', find.text('Deliver to')), findsOne);
      expect(_inKey('location-chip', find.text('Business Bay')), findsOne);
      expect(market('Fresh Market'), findsOneWidget);
      expect(market('Today by 4 PM'), findsOneWidget);
      expect(express('Express'), findsOneWidget);
      expect(express('30–40 min'), findsOneWidget);
      expect(bar('Order now, get it today by 4 PM'), findsOneWidget);
      expect(bar('Same-day closes in 8h 0m'), findsOneWidget);
      expect(bar('Need it sooner? Express in 30–40 min'), findsOneWidget);
      expect(bar(DeliveryBarView.shopExpress), findsNothing);

      // The bar's button switches to Express.
      await tester.tap(bar('Need it sooner? Express in 30–40 min'));
      await tester.pump();
      expect(store.mode, DeliveryMode.express);
      expect(
        bar('Express: items marked 30–40 min reach you in under an hour'),
        findsOneWidget,
      );
      expect(bar('Open until 10 PM'), findsOneWidget);
      expect(bar('Full range: Today by 4 PM'), findsOneWidget);
      expect(bar(DeliveryBarView.shopExpress), findsOneWidget);

      // "Shop Express items" opens the Express collection.
      await tester.tap(bar(DeliveryBarView.shopExpress));
      await tester.pump();
      await tester.pump(_settle);
      final list = tester.widget<ProductListScreen>(
        find.byType(ProductListScreen),
      );
      expect(list.handle, 'express');

      expect(tester.takeException(), isNull);
    });

    testWidgets('18:30: same day closed, Express still open', (tester) async {
      final store = await pumpHome(tester, at: uaeTime(18, 30));

      expect(market('Tomorrow by 11 AM'), findsOneWidget);
      expect(express('30–40 min'), findsOneWidget);
      expect(
        bar(
          'Same-day orders closed at 6 PM. Order now, get it tomorrow '
          'morning before 11 AM',
        ),
        findsOneWidget,
      );
      expect(bar('Need it sooner? Express in 30–40 min'), findsOneWidget);

      // The header switch too.
      await tester.tap(express('Express'));
      await tester.pump();
      expect(store.mode, DeliveryMode.express);
      expect(bar('Full range: Tomorrow by 11 AM'), findsOneWidget);
      await tester.tap(market('Fresh Market'));
      await tester.pump();
      expect(store.mode, DeliveryMode.market);
    });

    testWidgets('23:00: Express closed', (tester) async {
      final store = await pumpHome(tester, at: uaeTime(23));

      expect(market('Tomorrow by 11 AM'), findsOneWidget);
      expect(express('Opens 8 AM'), findsOneWidget);
      expect(bar('Express opens 8 AM'), findsOneWidget);

      // Express can still be chosen; the bar and a notice say it is closed.
      await tester.tap(express('Express'));
      await tester.pump();
      expect(store.mode, DeliveryMode.express);
      const closed =
          'Express is closed right now. It runs 8 AM to 10 PM. Fresh Market '
          'delivers tomorrow morning before 11 am.';
      expect(bar(closed), findsOneWidget);
      expect(
        find.descendant(of: find.byType(SnackBar), matching: find.text(closed)),
        findsOneWidget,
      );
      await tester.tap(bar('Switch to Fresh Market'));
      await tester.pump();
      expect(store.mode, DeliveryMode.market);
    });

    testWidgets('outside the Express zone Express is refused', (tester) async {
      final store = await pumpHome(tester, area: 'Jebel Ali', at: uaeTime(10));

      expect(express('Not in your area'), findsOneWidget);
      // No Express button in the bar.
      expect(bar('Order now, get it today by 4 PM'), findsOneWidget);
      expect(find.textContaining('Need it sooner'), findsNothing);

      await tester.tap(express('Express'));
      await tester.pump();
      expect(store.mode, DeliveryMode.market);
      expect(
        find.text(
          "Express isn't available in Jebel Ali yet. Fresh Market delivers "
          'today within 6 hours.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('no area: Express asks for the location first', (tester) async {
      final store = await pumpHome(tester, area: null, at: uaeTime(10));

      expect(_inKey('location-chip', find.text('Choose your area')), findsOne);
      expect(market('Full range · same day'), findsOneWidget);
      expect(express('In about 60 min'), findsOneWidget);
      expect(
        bar(
          'Tell us where you are to see delivery times and Express '
          'availability.',
        ),
        findsOneWidget,
      );

      await tester.tap(express('Express'));
      await tester.pump();
      await tester.pump(_settle);
      expect(find.byType(LocationScreen), findsOneWidget);
      expect(find.text('Set your location to check Express'), findsOneWidget);

      await _searchAndPick(tester, 'mirdif', 'Mirdif');
      await _tapConfirm(tester);
      expect(store.area?.name, 'Mirdif');
      expect(store.mode, DeliveryMode.express);
      expect(express('25–35 min'), findsOneWidget);
    });
  });

  group('products', () {
    Future<void> pumpCards(WidgetTester tester, DeliveryStore? store) =>
        pumpScreen(
          tester,
          Scaffold(
            body: Builder(
              builder: (context) => GridView(
                padding: const EdgeInsets.all(16),
                gridDelegate: ProductCard.gridDelegate(context),
                children: [
                  ProductCard(product: kiwi),
                  ProductCard(product: beef),
                ],
              ),
            ),
          ),
          delivery: store,
        );

    Finder lineOf(Product product) => find.descendant(
      of: find.widgetWithText(ProductCard, product.title),
      matching: find.byType(DeliveryPromiseLine),
    );

    String textOf(WidgetTester tester, Product product) {
      final text = find.descendant(
        of: lineOf(product),
        matching: find.byType(Text),
      );
      return tester.widget<Text>(text).textSpan!.toPlainText();
    }

    IconData iconOf(WidgetTester tester, Product product) => tester
        .widget<Icon>(
          find.descendant(of: lineOf(product), matching: find.byType(Icon)),
        )
        .icon!;

    testWidgets('no line before an area is set', (tester) async {
      await pumpCards(tester, testDelivery(area: null));
      expect(find.byKey(const ValueKey('promise-line')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Fresh Market mode: the promise, and Express time for an '
        'Express item', (tester) async {
      await pumpCards(tester, testDelivery());
      expect(textOf(tester, kiwi), 'Within 6 hrs · or 35 min');
      expect(iconOf(tester, kiwi), Icons.local_shipping_outlined);
      expect(textOf(tester, beef), 'Within 6 hrs');
      expect(tester.takeException(), isNull);
    });

    testWidgets('Express mode: bolt for Express items, Fresh Market for the '
        'rest', (tester) async {
      await pumpCards(tester, testDelivery(mode: DeliveryMode.express));
      expect(textOf(tester, kiwi), '30–40 min');
      expect(iconOf(tester, kiwi), Icons.bolt);
      expect(textOf(tester, beef), 'Fresh Market · Within 6 hrs');
      expect(iconOf(tester, beef), Icons.storefront_outlined);

      await pumpCards(
        tester,
        testDelivery(at: uaeTime(23), mode: DeliveryMode.express),
      );
      expect(textOf(tester, kiwi), 'From 8 AM');
      expect(textOf(tester, beef), 'Fresh Market · Tomorrow by 11 AM');
      expect(tester.takeException(), isNull);
    });

    testWidgets('product detail gives the fuller promise', (tester) async {
      await pumpScreen(
        tester,
        ProductDetailScreen(product: kiwi),
        delivery: testDelivery(at: uaeTime(12, 50)),
      );
      final box = find.byKey(const ValueKey('product-delivery'));
      expect(
        find.descendant(
          of: box,
          matching: find.text('Today within 6 hours to Business Bay · by 7 PM'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: box,
          matching: find.text('Express: Get it in 30–40 min to Business Bay'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: box, matching: find.text('Change')),
        findsOneWidget,
      );
    });

    testWidgets('product detail in Express mode', (tester) async {
      await pumpScreen(
        tester,
        ProductDetailScreen(product: kiwi),
        delivery: testDelivery(mode: DeliveryMode.express),
      );
      expect(find.text('Get it in 30–40 min to Business Bay'), findsOneWidget);

      final store = testDelivery(mode: DeliveryMode.express);
      await pumpScreen(
        tester,
        ProductDetailScreen(product: beef),
        delivery: store,
      );
      expect(
        find.text(
          "This item isn't on Express. Fresh Market delivers it today within "
          '6 hours.',
        ),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Switch to Fresh Market'));
      await tester.tap(find.text('Switch to Fresh Market'));
      await tester.pump();
      expect(store.mode, DeliveryMode.market);
    });

    testWidgets('product detail without an area offers to set it', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        ProductDetailScreen(product: kiwi),
        delivery: testDelivery(area: null),
      );
      expect(
        find.text('Set your delivery location to see when this arrives.'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Set location'));
      await tester.tap(find.text('Set location'));
      await tester.pump();
      await tester.pump(_settle);
      expect(find.byType(LocationScreen), findsOneWidget);
    });
  });

  group('cart', () {
    Finder card(String text) => _inKey('cart-delivery', find.text(text));

    testWidgets('the delivery card shows mode, place and promise', (
      tester,
    ) async {
      final cart = CartStore()..add(kiwi, kiwi.variants[0]);
      await pumpScreen(
        tester,
        const CartScreen(),
        cart: cart,
        delivery: testDelivery(),
      );
      expect(card('Fresh Market delivery'), findsOneWidget);
      expect(card('Business Bay, Dubai'), findsOneWidget);
      expect(card('Today within 6 hours · by 4 PM'), findsOneWidget);
      expect(card('Change'), findsOneWidget);

      await tester.tap(card('Change'));
      await tester.pump();
      await tester.pump(_settle);
      expect(find.text('Change delivery location'), findsOneWidget);
    });

    testWidgets('Express mode names the items that are not on Express', (
      tester,
    ) async {
      final cart = CartStore()
        ..add(kiwi, kiwi.variants[0])
        ..add(cucumber, cucumber.variants[0])
        ..add(beef, beef.variants[0], quantity: 2);
      final store = testDelivery(mode: DeliveryMode.express);
      await pumpScreen(tester, const CartScreen(), cart: cart, delivery: store);

      expect(card('Express delivery'), findsOneWidget);
      expect(card('Express in 30–40 min'), findsOneWidget);
      expect(
        card(
          "2 items aren't on Express. They come with Fresh Market: Today "
          'within 6 hours.',
        ),
        findsOneWidget,
      );

      cart.decrement(beef.variants[0].id);
      await tester.pump();
      expect(
        card(
          "1 item isn't on Express. It comes with Fresh Market: Today within "
          '6 hours.',
        ),
        findsOneWidget,
      );

      cart.remove(beef.variants[0].id);
      await tester.pump();
      expect(find.textContaining("aren't on Express"), findsNothing);
      expect(find.textContaining("isn't on Express"), findsNothing);

      // In Fresh Market mode there is nothing to say.
      cart.add(beef, beef.variants[0]);
      store.setMode(DeliveryMode.market);
      await tester.pump();
      expect(find.textContaining("isn't on Express"), findsNothing);
    });

    testWidgets('checkout in Express mode sends the Express attributes', (
      tester,
    ) async {
      final store = testDelivery(mode: DeliveryMode.express);
      final cart = CartStore()..add(kiwi, kiwi.variants[0]);
      final url = cart.checkoutUrlWith(store.cartAttributes!)!;
      expect(url.queryParameters, {
        'attributes[Delivery mode]': 'Express',
        'attributes[Delivery area]': 'Business Bay, Dubai',
        'attributes[Delivery promise]': '30–40 min',
        'attributes[Delivery pin]': '25.18500,55.26500',
      });
      expect(url.path, '/cart/${kiwi.variants[0].id}:1');
      expect(
        url.toString(),
        contains('attributes%5BDelivery%20promise%5D=30%E2%80%9340%20min'),
      );
    });

    testWidgets('checkout without an area asks for one first', (tester) async {
      final store = testDelivery(area: null);
      final cart = CartStore()..add(kiwi, kiwi.variants[0]);
      await pumpScreen(tester, const CartScreen(), cart: cart, delivery: store);
      expect(card('Set location'), findsOneWidget);

      await tester.tap(find.widgetWithText(FilledButton, 'Checkout'));
      await tester.pump();
      await tester.pump(_settle);
      expect(find.byType(LocationScreen), findsOneWidget);
      expect(
        find.text('Tell us where to deliver before you check out.'),
        findsOneWidget,
      );
      // Closing it leaves the shopper on the cart.
      await tester.tap(find.byTooltip('Close'));
      await tester.pump();
      await tester.pump(_settle);
      expect(find.byType(LocationScreen), findsNothing);
      expect(find.byType(CartScreen), findsOneWidget);
      expect(store.hasArea, isFalse);
    });
  });
}
