import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/app.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
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
/// in-memory default (`FakeShopifyApi.sample()`, empty stores).
Future<void> pumpScreen(
  WidgetTester tester,
  Widget screen, {
  ShopifyApi? api,
  CartStore? cart,
  FavouritesStore? favourites,
  ShellController? shell,
}) async {
  usePhoneSize(tester);
  await tester.pumpWidget(
    AppScope(
      api: api ?? FakeShopifyApi.sample(),
      cart: cart ?? CartStore(),
      favourites: favourites ?? FavouritesStore(),
      shell: shell,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: screen,
      ),
    ),
  );
}

/// Reads a JSON fixture from test/fixtures (real store responses).
dynamic loadFixture(String name) =>
    jsonDecode(File('test/fixtures/$name').readAsStringSync());
