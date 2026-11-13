import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/app.dart';
import 'package:fresh_market_app/delivery/delivery.dart';
import 'package:fresh_market_app/services/device_location.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/services/location_services.dart';
import 'package:fresh_market_app/services/shopify_api.dart';
import 'package:fresh_market_app/state/cart_store.dart';
import 'package:fresh_market_app/state/favourites_store.dart';
import 'package:fresh_market_app/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';

/// Makes the test surface a 390x844 phone at 3x. Call first in a widget
/// test; it is undone automatically when the test ends.
void usePhoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

/// Pumps one screen inside the app theme with the API and stores above it,
/// the way the real app provides them. Anything not passed gets a fresh
/// in-memory default (`FakeShopifyApi.sample()`, empty stores, a delivery
/// store with no area, [testLocationServices]).
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  ShopifyApi? api,
  CartStore? cart,
  FavouritesStore? favourites,
  DeliveryStore? delivery,
  LocationServices? locationServices,
  ShellController? shell,
}) async {
  usePhoneSize(tester);
  await tester.pumpWidget(
    AppScope(
      api: api ?? FakeShopifyApi.sample(),
      cart: cart ?? CartStore(),
      favourites: favourites ?? FavouritesStore(),
      delivery: delivery,
      locationServices: locationServices ?? testLocationServices(),
      shell: shell,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: screen,
      ),
    ),
  );
}

/// Registers the bundled Inter (all five weights) and Dirham fonts, so
/// text in the test measures as on a phone rather than in the square test
/// font. Call at the start of a test that checks text layout.
Future<void> loadAppFonts(WidgetTester tester) async {
  if (_appFontsLoaded) return;
  Future<ByteData> bytes(String file) => Future.value(
    ByteData.sublistView(File('assets/fonts/$file').readAsBytesSync()),
  );
  await tester.runAsync(() async {
    final inter = FontLoader('Inter');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold', 'ExtraBold']) {
      inter.addFont(bytes('Inter-$weight.otf'));
    }
    await inter.load();
    await (FontLoader('Dirham')..addFont(bytes('Dirham.ttf'))).load();
  });
  _appFontsLoaded = true;
}

bool _appFontsLoaded = false;

/// Reads a JSON fixture from test/fixtures (real store responses).
dynamic loadFixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync());

/// 13 Nov 2026 at [hour]:[minute] UAE time (UTC+4, no daylight saving).
DateTime uaeTime(int hour, [int minute = 0]) =>
    DateTime.utc(2026, 11, 13, hour - 4, minute);

/// A delivery store with a fixed clock ([at], 10:00 UAE time by default),
/// no refresh ticker and, unless [area] is null, one of the website's
/// areas (Business Bay: inside the Express zone).
DeliveryStore testDelivery({
  String? area = 'Business Bay',
  DateTime? at,
  DeliveryMode mode = DeliveryMode.market,
}) {
  final time = at ?? uaeTime(10);
  final store = DeliveryStore(now: () => time, refreshEvery: null);
  if (area != null) store.setArea(DeliveryConfig.areaNamed(area)!);
  if (mode == DeliveryMode.express) store.setMode(DeliveryMode.express);
  return store;
}

/// The phone's location in tests: answers [outcome] and records calls.
class FakeDeviceLocation extends DeviceLocation {
  FakeDeviceLocation([this.outcome = const LocationFix(25.2, 55.27)]);

  LocationOutcome outcome;
  int locateCalls = 0;
  int appSettingsOpened = 0;
  int locationSettingsOpened = 0;

  @override
  Future<LocationOutcome> locate() async {
    locateCalls++;
    return outcome;
  }

  @override
  Future<bool> openAppSettings() async {
    appSettingsOpened++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettingsOpened++;
    return true;
  }
}

/// No network in tests: a fake phone location, the website's own areas
/// only (no remote search) and no map.
LocationServices testLocationServices([DeviceLocation? device]) =>
    LocationServices(device: device ?? FakeDeviceLocation(), showMap: false);
