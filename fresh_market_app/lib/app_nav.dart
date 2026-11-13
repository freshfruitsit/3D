import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'delivery/delivery.dart';
import 'models/product.dart';
import 'profile/checkout_prefill.dart';
import 'profile/customer_details.dart';
import 'screens/address_screen.dart';
import 'screens/checkout_screen.dart';
import 'screens/location_screen.dart';
import 'screens/my_details_screen.dart';
import 'screens/product_detail_screen.dart';
import 'screens/product_list_screen.dart';
import 'screens/search_screen.dart';
import 'services/shopify_api.dart';
import 'state/cart_store.dart';
import 'state/profile_store.dart';
import 'theme/app_theme.dart';
import 'widgets/a11y.dart';
import 'widgets/deliver_to.dart';

/// Every way of moving between screens. Screens call these instead of
/// building routes themselves, so the bottom bar rules stay in one place:
/// lists and search open inside the current tab (bar visible, tab stays
/// highlighted); product detail and checkout cover the whole screen.
abstract final class AppNav {
  /// A collection's product list (category tile, banner, "View all",
  /// "Discover now").
  /// With [onSaleOnly] only its products that are really on sale are
  /// shown, biggest saving first ("Best Deals").
  static Future<void> openCollection(
    BuildContext context, {
    required String handle,
    required String title,
    bool onSaleOnly = false,
  }) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ProductListScreen.collection(
            handle: handle,
            title: title,
            onSaleOnly: onSaleOnly,
          ),
        ),
      );

  /// The favourites list (Account).
  static Future<void> openFavourites(BuildContext context) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const ProductListScreen.favourites(),
        ),
      );

  /// Search, optionally pre-filled (brands, popular chips).
  static Future<void> openSearch(BuildContext context, {String? initialQuery}) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SearchScreen(initialQuery: initialQuery),
        ),
      );

  /// Product detail, full screen (no bottom bar).
  static Future<void> openProduct(BuildContext context, Product product) =>
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => ProductDetailScreen(product: product),
        ),
      );

  /// Shown when cart lines had to be removed because the store no longer
  /// has them.
  static const String removedItemsMessage =
      'Some items are no longer available and were removed.';

  /// Says [message] above the floating bottom bar and the Ask button, or
  /// [bottomMargin] above the bottom of a screen that has neither. With
  /// [actionLabel] and [onAction] the notice carries a button ("Undo").
  static void showNotice(
    BuildContext context,
    String message, {
    double? bottomMargin,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          action: actionLabel == null || onAction == null
              ? null
              : SnackBarAction(label: actionLabel, onPressed: onAction),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.fromLTRB(
            AppDims.gutter,
            0,
            AppDims.gutter,
            bottomMargin ?? AppDims.floatingSpace(context),
          ),
        ),
      );
  }

  /// Shown above the location picker when checkout needs an area first.
  static const String areaBeforeCheckout =
      'Tell us where to deliver before you check out.';

  /// The delivery location picker, full screen (it covers the bottom bar).
  /// [reason] is shown at its top ("Set your location to check Express").
  ///
  /// Returns true when a place was chosen; the website's message about it
  /// ("Delivering to Mirdif") is then shown (see [showNotice] for
  /// [noticeBottomMargin]).
  static Future<bool> openLocationPicker(
    BuildContext context, {
    String? reason,
    double? noticeBottomMargin,
  }) async {
    final message = await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<String>(
        fullscreenDialog: true,
        builder: (_) => LocationScreen(reason: reason),
      ),
    );
    if (message == null) return false;
    if (context.mounted) {
      showNotice(context, message, bottomMargin: noticeBottomMargin);
    }
    return true;
  }

  /// Switches between Fresh Market and Express like the website: Express
  /// with no area first asks for the location (and switches if the chosen
  /// area has Express); Express outside the Express zone is refused with
  /// the website's message; Express while closed is chosen and the closed
  /// notice is shown.
  static Future<void> chooseDeliveryMode(
    BuildContext context,
    DeliveryMode mode, {
    double? noticeBottomMargin,
  }) async {
    final store = context.read<DeliveryStore>();
    void say(String message) =>
        showNotice(context, message, bottomMargin: noticeBottomMargin);
    void sayIfClosed() {
      final closed = store.expressClosedNotice;
      if (closed != null) say(closed);
    }

    final before = store.mode;
    final refusal = store.setMode(mode);
    if (refusal == null) {
      // The closed notice is read out by itself; otherwise say the switch
      // once (the delivery line is not a live region, as it counts down).
      if (store.expressClosedNotice != null) {
        sayIfClosed();
      } else if (store.mode != before && context.mounted) {
        announce(context, '${store.mode.label} delivery selected');
      }
      return;
    }
    if (store.hasArea) {
      say(refusal);
      return;
    }
    final picked = await openLocationPicker(
      context,
      reason: refusal,
      noticeBottomMargin: noticeBottomMargin,
    );
    if (!picked || !context.mounted) return;
    final again = store.setMode(mode);
    if (again != null) {
      say(again);
    } else {
      sayIfClosed();
    }
  }

  /// "My details", full screen. Says [MyDetailsScreen.savedMessage] when
  /// saved (see [showNotice] for [noticeBottomMargin]); returns true then.
  static Future<bool> openMyDetails(
    BuildContext context, {
    double? noticeBottomMargin,
  }) async {
    final saved = await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<bool>(builder: (_) => const MyDetailsScreen()),
    );
    if (saved != true) return false;
    if (context.mounted) {
      showNotice(
        context,
        MyDetailsScreen.savedMessage,
        bottomMargin: noticeBottomMargin,
      );
    }
    return true;
  }

  /// Adds an address (starting in [area]) or edits [address], full
  /// screen. Returns the saved address; says "Address saved." or, when it
  /// was deleted, "Address deleted.".
  static Future<SavedAddress?> openAddress(
    BuildContext context, {
    SavedAddress? address,
    DeliveryArea? area,
    double? noticeBottomMargin,
  }) async {
    final profile = context.read<ProfileStore>();
    final saved = await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<SavedAddress>(
        builder: (_) => AddressScreen(address: address, initialArea: area),
      ),
    );
    if (!context.mounted) return saved;
    final deleted = address != null && profile.addressById(address.id) == null;
    if (saved != null || deleted) {
      showNotice(
        context,
        deleted ? addressDeleted : addressSaved,
        bottomMargin: noticeBottomMargin,
      );
    }
    return saved;
  }

  static const String addressSaved = 'Address saved.';
  static const String addressDeleted = 'Address deleted.';

  /// The location picker for an address's area: returns the area picked
  /// (the delivery location does not change), or null.
  static Future<DeliveryArea?> pickAddressArea(
    BuildContext context, {
    DeliveryArea? initial,
  }) => Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<DeliveryArea>(
      fullscreenDialog: true,
      builder: (_) => LocationScreen(pickOnly: true, initialArea: initial),
    ),
  );

  /// Delivers the order to [address]: it becomes the cart's address, and
  /// when it is in another area the delivery location (and with it the
  /// delivery promise) moves there, which is said ("Delivering to Dubai
  /// Marina").
  static void deliverTo(
    BuildContext context,
    SavedAddress address, {
    double? noticeBottomMargin,
  }) {
    final delivery = context.read<DeliveryStore>();
    context.read<ProfileStore>().choose(address.id);
    final area = delivery.area;
    if (area == null || !CustomerInput.sameArea(area, address.area)) {
      final message = delivery.setArea(address.area);
      showNotice(context, message, bottomMargin: noticeBottomMargin);
    } else {
      announce(
        context,
        'Delivering to your ${address.label.label} address, '
        '${address.firstLine}',
      );
    }
  }

  /// Checkout for the current cart, full screen. Does nothing when the
  /// cart is empty.
  ///
  /// With no delivery area yet the location picker opens first. The cart
  /// is then checked against the store, because Shopify refuses a
  /// checkout that contains a variant it no longer has. If lines had to
  /// be removed the shopper stays on the cart and is told so, above the
  /// bottom bar, or [noticeBottomMargin] above the bottom of a screen that
  /// has none (see [showNotice]). The checkout link carries the website's
  /// delivery cart attributes.
  ///
  /// Checkout opens with the shopper's saved details filled in (see
  /// [CheckoutPrefill]). With nothing saved, the first checkout offers the
  /// "Fill in checkout faster" sheet; closing it stays on the cart.
  /// Every way into checkout (the cart, the assistant) comes here.
  static Future<void> openCheckout(
    BuildContext context, {
    double? noticeBottomMargin,
  }) async {
    final cart = context.read<CartStore>();
    if (cart.isEmpty) return;
    final delivery = context.read<DeliveryStore>();
    if (!delivery.hasArea) {
      final picked = await openLocationPicker(
        context,
        reason: areaBeforeCheckout,
        noticeBottomMargin: noticeBottomMargin,
      );
      if (!picked || !context.mounted || !delivery.hasArea) return;
    }
    final removed = await cart
        .revalidate(context.read<ShopifyApi>())
        .timeout(const Duration(seconds: 8), onTimeout: () => 0);
    if (!context.mounted) return;
    if (removed > 0) {
      showNotice(
        context,
        removedItemsMessage,
        bottomMargin: noticeBottomMargin,
      );
      return;
    }
    // Express is chosen but closed: say so before the order goes to the
    // store as Express, and offer Fresh Market.
    final closed = delivery.isExpress ? delivery.expressClosedNotice : null;
    if (closed != null) {
      final choice = await showDialog<_ClosedChoice>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text(expressClosedTitle),
          content: Text(closed),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_ClosedChoice.express),
              child: const Text(keepExpress),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_ClosedChoice.market),
              child: const Text(switchToMarket),
            ),
          ],
        ),
      );
      if (choice == null || !context.mounted) return;
      if (choice == _ClosedChoice.market) {
        delivery.setMode(DeliveryMode.market);
      }
    }
    final profile = context.read<ProfileStore>();
    if (profile.offersCheckoutSheet && delivery.area != null) {
      final area = delivery.area!;
      final answer = await showCheckoutDetailsSheet(
        context,
        area: area,
        initial: profile.oneTime,
      );
      if (answer == null || !context.mounted) return;
      profile.applyCheckoutSheet(answer, area);
    }
    final url = checkoutUrlFor(
      cart: cart,
      delivery: delivery,
      profile: profile,
    );
    if (url == null) {
      if (cart.soldOutLines > 0) {
        showNotice(context, soldOutOnly, bottomMargin: noticeBottomMargin);
      }
      return;
    }
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(builder: (_) => CheckoutScreen(url: url)),
    );
  }

  /// The checkout link for [cart]: the website's delivery cart attributes
  /// (plus the address's delivery instructions) and the shopper's details
  /// for the current delivery area. Null when nothing can be bought.
  static Uri? checkoutUrlFor({
    required CartStore cart,
    required DeliveryStore delivery,
    required ProfileStore profile,
  }) {
    final area = delivery.area;
    final details = profile.checkoutDetails(area);
    return cart.checkoutUrlWith(
      {
        ...?delivery.cartAttributes,
        ...CheckoutPrefill.attributes(address: details.address, area: area),
      },
      prefill: CheckoutPrefill.params(
        contact: details.contact,
        // One in another area still gives checkout the city and emirate
        // (never its building).
        address: details.address ?? profile.addressElsewhere(area),
        area: area,
      ),
    );
  }

  /// The checkout question while Express is chosen but closed.
  static const String expressClosedTitle = 'Express is closed';
  static const String keepExpress = 'Keep Express';
  static const String switchToMarket = 'Switch to Fresh Market';

  /// Checkout with nothing but sold-out lines.
  static const String soldOutOnly =
      'Everything in your cart is sold out. Remove it to check out.';

  /// Closes any full-screen page (product detail, checkout) and shows
  /// [tab]. Choosing the tab that is already showing returns it to its
  /// first screen. Use for "View cart" and "Start shopping".
  static void goToTab(BuildContext context, AppTab tab) {
    final shell = context.read<ShellController>();
    Navigator.of(context, rootNavigator: true)
        .popUntil((route) => route.isFirst);
    shell.select(tab);
  }
}

enum _ClosedChoice { express, market }
