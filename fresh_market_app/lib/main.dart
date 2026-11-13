import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'delivery/delivery_store.dart';
import 'delivery/place_search.dart';
import 'profile/profile_vault.dart';
import 'services/location_services.dart';
import 'services/shopify_api.dart';
import 'state/cart_store.dart';
import 'state/favourites_store.dart';
import 'state/profile_store.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(appOverlayStyle);
  // No orientation lock: every screen also works in landscape (WCAG
  // 1.3.4), where the Home header scrolls away and the pages scroll.

  // If device storage cannot be opened the app still runs; the cart,
  // favourites and delivery area then last only until the app is closed.
  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
  } catch (_) {
    prefs = null;
  }

  // The shopper's details for checkout, encrypted on the phone. If they
  // cannot be read in time the app starts without them (they arrive when
  // the read finishes).
  final profile = ProfileStore(vault: const SecureProfileVault());
  try {
    await profile.load().timeout(const Duration(seconds: 3));
  } catch (_) {
    // Carried on in the background, or dropped.
  }

  runApp(
    FreshMarketApp(
      api: HttpShopifyApi(),
      cart: CartStore(prefs: prefs),
      favourites: FavouritesStore(prefs: prefs),
      deliveryStore: DeliveryStore(prefs: prefs),
      profile: profile,
      // Address search like the website's (Photon); the phone's location
      // and the OpenStreetMap map are on by default.
      locationServices: LocationServices(search: PlaceSearch()),
    ),
  );
}
