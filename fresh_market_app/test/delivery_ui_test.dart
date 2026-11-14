import 'dart:convert';

import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/services/order_api.dart';
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
import 'package:fresh_market_app/theme/app_theme.dart';
import 'package:fresh_market_app/widgets/app_search_field.dart';
import 'package:fresh_market_app/widgets/delivery_widgets.dart';
import 'package:fresh_market_app/widgets/floating_nav_bar.dart';
import 'package:fresh_market_app/widgets/product_card.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_app.dart';

const _settle = Duration(milliseconds: 600);

Finder _inKey(String key, Finder matching) =>
    find.descendant(of: find.byKey(ValueKey(key)), matching: matching);

/// A time or detail line of the picker's options, where a number and its
/// unit are joined by a non-breaking space ("6\u00A0hours", "11\u00A0AM")
/// and hyphens do not break ("same\u2011day").
Finder _when(String text) => find.byWidgetPredicate(
  (w) =>
      w is Text &&
      (w.data ?? w.textSpan?.toPlainText())
              ?.replaceAll('\u00A0', ' ')
              .replaceAll('\u2011', '-') ==
          text,
  description: 'option time "$text"',
);

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
        _when('Order now and it arrives by 4 PM · same-day cut-off 6 PM'),
        findsOneWidget,
      );
      // "same-day" and "cut-off" never break at their hyphens.
      expect(find.textContaining('same\u2011day cut\u2011off'), findsOneWidget);
      expect(_when('Today within 6 hours'), findsOneWidget);
      expect(find.text('Express · selected items'), findsOneWidget);
      expect(
        _when('7 km from our Ras Al Khor hub · open until 10 PM'),
        findsOneWidget,
      );
      expect(_when('25–35 min'), findsOneWidget);
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
        _when('Outside the 20 km Express zone (25 km from the hub)'),
        findsOneWidget,
      );
      expect(find.text('Not available'), findsOneWidget);
      expect(_when('Tomorrow morning before 11 AM'), findsOneWidget);
      expect(
        _when('Ordered after 6 PM, so it comes tomorrow morning'),
        findsOneWidget,
      );

      await _searchAndPick(tester, 'business', 'Business Bay');
      expect(_when('Closed now · runs 8 AM to 10 PM'), findsOneWidget);
      expect(_when('From 8 AM'), findsOneWidget);
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

  group('Home header and delivery line', () {
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
    // Times keep together with non-breaking spaces on screen.
    Finder line(String text) => _inKey('delivery-line', _when(text));

    /// The stacked delivery line: [lead] bold (ink, or green for Express)
    /// above [detail] in grey.
    void expectLine(
      WidgetTester tester,
      String lead,
      String detail, {
      Color boldColor = AppColors.ink,
    }) {
      expect(line(lead), findsOneWidget);
      expect(line(detail), findsOneWidget);
      final leadText = tester.widget<Text>(line(lead));
      expect(leadText.style!.fontWeight, FontWeight.w700);
      expect(leadText.style!.color, boldColor);
      expect(
        tester.widget<Text>(line(detail)).style!.color,
        AppColors.secondary,
      );
      expect(
        tester.getRect(line(detail)).top,
        greaterThanOrEqualTo(tester.getRect(line(lead)).bottom - 0.5),
      );
    }

    testWidgets('the header: wordmark left, location chip at the right end, '
        'then search, mode switch and the delivery line', (tester) async {
      await pumpHome(tester, at: uaeTime(10));

      final logo = tester.getRect(find.byKey(const ValueKey('home-logo')));
      final chip = tester.getRect(find.byKey(const ValueKey('location-chip')));
      expect(logo.left, 16);
      expect(logo.height, 30);
      expect(chip.right, moreOrLessEquals(390 - 16));
      expect(chip.center.dy, moreOrLessEquals(logo.center.dy, epsilon: 8));
      final search = tester.getRect(find.byType(SearchFieldButton));
      final modes = tester.getRect(find.byKey(const ValueKey('mode-market')));
      final deliveryLine = tester.getRect(
        find.byKey(const ValueKey('delivery-line')),
      );
      expect(search.top, greaterThan(chip.bottom));
      expect(modes.top, greaterThan(search.bottom));
      expect(deliveryLine.top, greaterThan(modes.bottom));
      // The compact line replaced the big delivery card.
      expect(find.byKey(const ValueKey('delivery-bar')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('10:00: same day, Express open', (tester) async {
      final store = await pumpHome(tester, at: uaeTime(10));

      expect(_inKey('location-chip', find.text('Deliver to')), findsOne);
      expect(_inKey('location-chip', find.text('Business Bay')), findsOne);
      expect(market('Fresh Market'), findsOneWidget);
      expect(market('Today by 4 PM'), findsOneWidget);
      expect(express('Express'), findsOneWidget);
      expect(express('30–40 min'), findsOneWidget);
      // Two planned lines: the bold time, then the detail.
      expectLine(tester, 'Today by 4 PM', 'Order within 8h 0m');
      expect(line(DeliveryLine.expressLabel('30–40 min')), findsOneWidget);
      expect(line(DeliveryLine.shopExpress), findsNothing);

      // The line's button switches to Express.
      await tester.tap(line(DeliveryLine.expressLabel('30–40 min')));
      await tester.pump();
      expect(store.mode, DeliveryMode.express);
      expectLine(
        tester,
        '30–40 min',
        'Open until 10 PM',
        boldColor: AppColors.green,
      );
      expect(line(DeliveryLine.shopExpress), findsOneWidget);

      // "Shop Express" opens the Express collection.
      await tester.tap(line(DeliveryLine.shopExpress));
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
      expectLine(tester, 'Tomorrow by 11 AM', 'Same-day orders closed at 6 PM');
      expect(line(DeliveryLine.expressLabel('30–40 min')), findsOneWidget);

      // The header switch too.
      await tester.tap(express('Express'));
      await tester.pump();
      expect(store.mode, DeliveryMode.express);
      expectLine(
        tester,
        '30–40 min',
        'Open until 10 PM',
        boldColor: AppColors.green,
      );
      await tester.tap(market('Fresh Market'));
      await tester.pump();
      expect(store.mode, DeliveryMode.market);
    });

    testWidgets('23:00: Express closed', (tester) async {
      final store = await pumpHome(tester, at: uaeTime(23));

      expect(market('Tomorrow by 11 AM'), findsOneWidget);
      expect(express('Opens 8 AM'), findsOneWidget);
      // Express cannot deliver now: no Express button on the line.
      expectLine(tester, 'Tomorrow by 11 AM', 'Same-day orders closed at 6 PM');
      expect(
        _inKey('delivery-line', find.textContaining('Express')),
        findsNothing,
      );

      // Express can still be chosen; the line and a notice say it is
      // closed.
      await tester.tap(express('Express'));
      await tester.pump();
      expect(store.mode, DeliveryMode.express);
      expectLine(tester, 'Express is closed right now.', 'Opens 8 AM');
      const closed =
          'Express is closed right now. It runs 8 AM to 10 PM. Fresh Market '
          'delivers tomorrow morning before 11 am.';
      expect(
        find.descendant(of: find.byType(SnackBar), matching: find.text(closed)),
        findsOneWidget,
      );
      await tester.tap(line(DeliveryLine.backToMarket));
      await tester.pump();
      expect(store.mode, DeliveryMode.market);
    });

    testWidgets('outside the Express zone Express is refused', (tester) async {
      final store = await pumpHome(tester, area: 'Jebel Ali', at: uaeTime(10));

      expect(express('Not in your area'), findsOneWidget);
      // No Express button on the line.
      expectLine(tester, 'Today by 4 PM', 'Order within 8h 0m');
      expect(
        _inKey('delivery-line', find.textContaining('Express')),
        findsNothing,
      );

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

    testWidgets('no area: the line and Express ask for the location first', (
      tester,
    ) async {
      final store = await pumpHome(tester, area: null, at: uaeTime(10));

      expect(_inKey('location-chip', find.text('Choose your area')), findsOne);
      expect(market('Full range · same day'), findsOneWidget);
      expect(express('In about 60 min'), findsOneWidget);
      expect(
        line(
          'Tell us where you are to see delivery times and Express '
          'availability.',
        ),
        findsOneWidget,
      );
      expect(line(DeliveryLine.setLocation), findsOneWidget);

      // "Set location" opens the picker; closing it changes nothing.
      await tester.tap(line(DeliveryLine.setLocation));
      await tester.pump();
      await tester.pump(_settle);
      expect(find.byType(LocationScreen), findsOneWidget);
      await tester.tap(find.byTooltip('Close'));
      await tester.pump();
      await tester.pump(_settle);
      expect(find.byType(LocationScreen), findsNothing);
      expect(store.hasArea, isFalse);

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
      // The bold Express time uses non-breaking spaces so it never splits.
      return tester
          .widget<Text>(text)
          .textSpan!
          .toPlainText()
          .replaceAll('\u00A0', ' ');
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
      // An Express item while Express is live: green bolt and its time.
      expect(textOf(tester, kiwi), '35 min');
      expect(iconOf(tester, kiwi), Icons.bolt);
      // Screen readers hear the rules' whole line.
      final semantics = tester.widget<Semantics>(
        find
            .descendant(of: lineOf(kiwi), matching: find.byType(Semantics))
            .first,
      );
      expect(semantics.properties.label, 'Within 6 hrs · or 35 min');
      expect(textOf(tester, beef), 'Within 6 hrs');
      expect(iconOf(tester, beef), Icons.local_shipping_outlined);
      expect(tester.takeException(), isNull);

      // Express closed: no Express time, the Fresh Market line instead.
      await pumpCards(tester, testDelivery(at: uaeTime(23)));
      expect(textOf(tester, kiwi), 'Tomorrow by 11 AM');
      expect(iconOf(tester, kiwi), Icons.local_shipping_outlined);
    });

    testWidgets('Express mode: bolt for Express items, Fresh Market for the '
        'rest', (tester) async {
      await pumpCards(tester, testDelivery(mode: DeliveryMode.express));
      expect(textOf(tester, kiwi), '30–40 min');
      expect(iconOf(tester, kiwi), Icons.bolt);
      // The storefront says "Fresh Market"; the text is the time, so it
      // fits the card. Screen readers hear the whole line.
      expect(textOf(tester, beef), 'Within 6 hrs');
      expect(iconOf(tester, beef), Icons.storefront_outlined);
      expect(
        tester
            .widget<Semantics>(
              find
                  .descendant(
                    of: lineOf(beef),
                    matching: find.byType(Semantics),
                  )
                  .first,
            )
            .properties
            .label,
        'Fresh Market · Within 6 hrs',
      );

      await pumpCards(
        tester,
        testDelivery(at: uaeTime(23), mode: DeliveryMode.express),
      );
      expect(textOf(tester, kiwi), 'From 8 AM');
      expect(textOf(tester, beef), 'Tomorrow by 11 AM');
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
          matching: _when('Today within 6 hours to Business Bay · by 7 PM'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: box,
          matching: _when('Express: Get it in 30–40 min to Business Bay'),
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
      expect(_when('Get it in 30–40 min to Business Bay'), findsOneWidget);

      final store = testDelivery(mode: DeliveryMode.express);
      await pumpScreen(
        tester,
        ProductDetailScreen(product: beef),
        delivery: store,
      );
      expect(
        _when(
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
      // "by 4 PM" is joined by non-breaking spaces so it never splits.
      expect(card('Today within 6 hours · by\u00A04\u00A0PM'), findsOneWidget);
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

    test('checkout in Express mode asks the order server for Express', () {
      final store = testDelivery(mode: DeliveryMode.express);
      final request = DeliveryRequest(
        mode: store.mode,
        area: store.area!,
        promise: store.express!.range,
        pin: store.area!.pin,
      ).toJson();
      expect(request, {
        'mode': 'express',
        'area': {
          'name': 'Business Bay',
          'emirate': 'dubai',
          'lat': 25.185,
          'lng': 55.265,
        },
        'promise': '30–40 min',
        'pin': '25.18500,55.26500',
      });
    });

    testWidgets('checkout without an area asks for one first', (tester) async {
      final store = testDelivery(area: null);
      final cart = CartStore()..add(kiwi, kiwi.variants[0]);
      await pumpScreen(tester, const CartScreen(), cart: cart, delivery: store);
      expect(card('Set location'), findsOneWidget);

      await tester.tap(
        find.ancestor(
          of: find.textContaining('Checkout · '),
          matching: find.byType(FilledButton),
        ),
      );
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
