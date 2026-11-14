import 'dart:ui' show Tristate;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/app.dart';
import 'package:fresh_market_app/delivery/delivery.dart';
import 'package:fresh_market_app/models/product.dart';
import 'package:fresh_market_app/screens/account_screen.dart';
import 'package:fresh_market_app/screens/cart_screen.dart';
import 'package:fresh_market_app/screens/categories_screen.dart';
import 'package:fresh_market_app/screens/home_screen.dart';
import 'package:fresh_market_app/screens/product_detail_screen.dart';
import 'package:fresh_market_app/screens/product_list_screen.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/state/cart_store.dart';
import 'package:fresh_market_app/state/favourites_store.dart';
import 'package:fresh_market_app/theme/app_theme.dart';
import 'package:fresh_market_app/widgets/a11y.dart';
import 'package:fresh_market_app/widgets/add_control.dart';
import 'package:fresh_market_app/widgets/ask_button.dart';
import 'package:fresh_market_app/widgets/brand_tile.dart';
import 'package:fresh_market_app/widgets/category_tile.dart';
import 'package:fresh_market_app/widgets/delivery_widgets.dart';
import 'package:fresh_market_app/widgets/floating_nav_bar.dart';
import 'package:fresh_market_app/widgets/product_card.dart';
import 'package:fresh_market_app/widgets/section_header.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/test_app.dart';

/// Every node that says it is a button but cannot be pressed through
/// accessibility services (Switch Access, Voice Access, TalkBack): a
/// button without a tap action that is not disabled.
List<String> _deadButtons(WidgetTester tester) {
  final dead = <String>[];
  void visit(SemanticsNode node) {
    final data = node.getSemanticsData();
    final flags = data.flagsCollection;
    if (flags.isButton &&
        flags.isEnabled != Tristate.isFalse &&
        !data.hasAction(SemanticsAction.tap)) {
      dead.add(data.label.isEmpty ? '#${node.id}' : data.label);
    }
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  for (final view in tester.binding.renderViews) {
    final root = view.owner?.semanticsOwner?.rootSemanticsNode;
    if (root != null) visit(root);
  }
  return dead;
}

/// The text of the [Text] widgets under [of], with non-breaking spaces read
/// as spaces.
Finder _plain(String text) => find.byWidgetPredicate(
  (w) =>
      w is Text &&
      (w.data ?? w.textSpan?.toPlainText())?.replaceAll(' ', ' ') == text,
  description: 'text "$text"',
);

/// The spans of a rich [Text] whose colour is [color].
List<String> _spansIn(Text text, Color color) {
  final out = <String>[];
  text.textSpan!.visitChildren((span) {
    if (span is TextSpan && span.text != null && span.style?.color == color) {
      out.add(span.text!.replaceAll(' ', ' '));
    }
    return true;
  });
  return out;
}

Future<void> _pumpApp(
  WidgetTester tester, {
  CartStore? cart,
  DeliveryStore? delivery,
  ShellController? shell,
}) async {
  usePhoneSize(tester);
  SharedPreferences.setMockInitialValues({});
  await tester.pumpWidget(
    FreshMarketApp(
      api: FakeShopifyApi.sample(),
      cart: cart ?? CartStore(),
      favourites: FavouritesStore(),
      deliveryStore: delivery ?? testDelivery(),
      locationServices: testLocationServices(),
      shell: shell,
      showIntro: false,
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

void main() {
  final products = sampleProducts();
  final kiwi = products[0]; // 500 GM 19.95, 1 KG 39.75, Express
  final beef = products[1]; // 62.50, was 115.00

  group('sizes', () {
    test('store units are written the shop-floor way', () {
      expect(formatSize('500 GM'), '500 g');
      expect(formatSize('1 KG'), '1 kg');
      expect(formatSize('250 GMS'), '250 g');
      expect(formatSize('750ML'), '750 ml');
      expect(formatSize('1.5 LTR'), '1.5 L');
      expect(formatSize('6 PCS'), '6 pcs');
      expect(formatSize('Large'), 'Large');
      expect(formatSize('Pack of 6'), 'Pack of 6');
      expect(formatSize(null), isNull);
    });

    test('the size comes first; a product without options takes the size '
        'its title or (only one) its description gives', () {
      expect(kiwi.sizeLine(), '500 g · New Zealand');
      Product plain(String title, String html) => Product(
        id: 1,
        title: title,
        handle: 'x',
        descriptionHtml: html,
        tags: const ['origin:Australia'],
        variants: const [
          Variant(id: 1, title: 'Default Title', priceCents: 100),
        ],
      );
      expect(plain('Mango Kesar 500 GM', '').sizeLine(), '500 g · Australia');
      expect(
        plain(
          'Australian Beef Cubes',
          '<p>Tender cubes, 1 Kg pack.</p>',
        ).sizeLine(),
        '1 kg · Australia',
      );
      // Two different sizes in the text: nothing is guessed.
      expect(
        plain('Beef Mince', '<p>Packs of 500g or 1kg.</p>').sizeText(),
        isNull,
      );
      expect(plain('Beef Mince', '').sizeLine(), 'Australia');
      // "Buy 1 Get 1" is not a size.
      expect(plain('Buy 1 Get 1 Mango 2 KG', '').sizeText(), '2 kg');
    });

    testWidgets('variant buttons and cart lines show "500 g", not "500 GM"', (
      tester,
    ) async {
      await pumpScreen(tester, ProductDetailScreen(product: kiwi));
      expect(find.text('500 g'), findsOneWidget);
      expect(find.text('1 kg'), findsOneWidget);
      expect(find.text('500 GM'), findsNothing);
    });
  });

  group('delivery mode switch', () {
    Text title(WidgetTester tester, String key, String text) =>
        tester.widget<Text>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.text(text),
          ),
        );

    testWidgets('the chosen segment reads without colour: ink 700 against '
        'grey 600', (tester) async {
      final store = testDelivery();
      await pumpScreen(
        tester,
        const Scaffold(body: DeliveryModeSwitch()),
        delivery: store,
      );
      var market = title(tester, 'mode-market', 'Fresh Market');
      var express = title(tester, 'mode-express', 'Express');
      expect(market.style!.color, AppColors.ink);
      expect(market.style!.fontWeight, FontWeight.w700);
      expect(express.style!.color, AppColors.secondary);
      expect(express.style!.fontWeight, FontWeight.w600);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.storefront)).color,
        AppColors.ink,
      );
      // The Express bolt keeps its live green.
      expect(
        tester.widget<Icon>(find.byIcon(Icons.bolt)).color,
        AppColors.green,
      );

      store.setMode(DeliveryMode.express);
      await tester.pump(const Duration(milliseconds: 300));
      market = title(tester, 'mode-market', 'Fresh Market');
      express = title(tester, 'mode-express', 'Express');
      expect(market.style!.color, AppColors.secondary);
      expect(express.style!.color, AppColors.ink);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.storefront)).color,
        AppColors.secondary,
      );
      for (final key in ['mode-market', 'mode-express']) {
        expect(
          tester.getSize(find.byKey(ValueKey(key))).height,
          greaterThanOrEqualTo(AppDims.touch),
        );
      }
    });

    testWidgets('a segment can be pressed through accessibility services', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final store = testDelivery();
      await pumpScreen(
        tester,
        const Scaffold(body: DeliveryModeSwitch()),
        delivery: store,
      );
      tester.semantics.tap(find.semantics.byLabel(RegExp('^Express delivery')));
      await tester.pump();
      expect(store.mode, DeliveryMode.express);
      handle.dispose();
    });
  });

  group('Express in green, the rest in ink', () {
    testWidgets('product detail: only the bolt and the ETA are green', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        ProductDetailScreen(product: kiwi),
        delivery: testDelivery(at: uaeTime(10)),
      );
      final line = tester.widget<Text>(
        _plain('Express: Get it in 30–40 min to Business Bay'),
      );
      expect(_spansIn(line, AppColors.green), ['30–40 min']);
      expect(line.style!.color, AppColors.ink);
      expect(
        line.semanticsLabel,
        'Express: Get it in 30–40 min to Business Bay',
      );
    });

    testWidgets('product detail in Express mode, and the cart card', (
      tester,
    ) async {
      final delivery = testDelivery(mode: DeliveryMode.express);
      await pumpScreen(
        tester,
        ProductDetailScreen(product: kiwi),
        delivery: delivery,
      );
      final line = tester.widget<Text>(
        _plain('Get it in 30–40 min to Business Bay'),
      );
      expect(_spansIn(line, AppColors.green), ['30–40 min']);

      final cart = CartStore()..add(kiwi, kiwi.variants[0]);
      await pumpScreen(
        tester,
        const CartScreen(),
        cart: cart,
        delivery: testDelivery(mode: DeliveryMode.express),
      );
      final promise = tester.widget<Text>(_plain('Express in 30–40 min'));
      expect(_spansIn(promise, AppColors.green), ['30–40 min']);
      expect(promise.style!.color, AppColors.secondary);
    });
  });

  group('theme', () {
    test('standard density everywhere, and the green CTA presses darker '
        'green, not with a white overlay', () {
      final theme = buildAppTheme();
      expect(theme.visualDensity, VisualDensity.standard);
      final style = AppButtons.primary;
      expect(style.backgroundColor!.resolve({}), AppColors.green);
      for (final state in [
        WidgetState.pressed,
        WidgetState.hovered,
        WidgetState.focused,
      ]) {
        expect(style.backgroundColor!.resolve({state}), AppColors.greenPressed);
      }
      expect(
        style.backgroundColor!.resolve({WidgetState.disabled}),
        AppColors.disabledFill,
      );
      expect(
        style.overlayColor!.resolve({WidgetState.pressed}),
        Colors.transparent,
      );
    });

    test('text styles carry no inherited tracking', () {
      for (final style in [
        AppText.body,
        AppText.bodySmall,
        AppText.caption,
        AppText.tileLabel,
        AppText.price,
        AppText.label,
      ]) {
        expect(style.letterSpacing, 0);
      }
    });
  });

  group('Home', () {
    testWidgets('the header ends at most 215pt down, with real fonts', (
      tester,
    ) async {
      await loadAppFonts(tester);
      await pumpScreen(tester, const HomeScreen(), delivery: testDelivery());
      await tester.pump();
      final header = find
          .ancestor(
            of: find.byKey(const ValueKey('home-logo')),
            matching: find.byType(DecoratedBox),
          )
          .first;
      expect(tester.getRect(header).bottom, lessThanOrEqualTo(215));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the delivery line is not a live region (it counts down)', (
      tester,
    ) async {
      await pumpScreen(tester, const HomeScreen(), delivery: testDelivery());
      await tester.pump();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('delivery-line')),
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true,
          ),
        ),
        findsNothing,
      );
      // "8h 0m" and "30–40 min" never break inside.
      expect(
        ProductDeliveryInfo.keepTogether('Order within 8h 0m', null),
        'Order within 8h 0m',
      );
    });

    testWidgets('banners advance by themselves until touched', (tester) async {
      await pumpScreen(tester, const HomeScreen());
      await tester.pump();
      // The active dot is 18 wide (plus its 3px margins).
      double dot(int i) =>
          tester.getSize(find.byKey(ValueKey('banner-dot-$i'))).width - 6;
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(dot(1), 18);

      // The shopper swipes back: from then on the banners stay put.
      await tester.drag(
        find.byKey(const ValueKey('banner-1')),
        const Offset(400, 0),
      );
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(dot(0), 18);
      await tester.pump(const Duration(seconds: 12));
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(dot(0), 18);
    });

    testWidgets('with reduce motion the banners never move by themselves', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue,
      );
      await pumpScreen(tester, const HomeScreen());
      await tester.pump();
      await tester.pump(const Duration(seconds: 12));
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tester.getSize(find.byKey(const ValueKey('banner-dot-0'))).width - 6,
        18,
      );
    });

    testWidgets('category and brand grids never overflow or break a word, '
        'at common widths and font sizes (real fonts)', (tester) async {
      await loadAppFonts(tester);
      for (final width in [360.0, 375.0, 390.0, 412.0]) {
        for (final scale in [1.0, 1.1, 1.15, 1.2, 1.3, 2.0]) {
          tester.view.physicalSize = Size(width * 3, 2532);
          tester.view.devicePixelRatio = 3;
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            MaterialApp(
              theme: buildAppTheme(),
              home: MediaQuery.withClampedTextScaling(
                minScaleFactor: scale,
                maxScaleFactor: scale,
                child: const Scaffold(
                  body: SingleChildScrollView(
                    child: Column(
                      children: [
                        Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: AppDims.gutter,
                          ),
                          child: CategoryGrid(),
                        ),
                        SizedBox(height: 16),
                        BrandRail(onSelected: _ignore),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump();
          expect(tester.takeException(), isNull, reason: '$width x $scale');
          // Every label fits its two lines: no word is cut or ellipsized.
          for (final element
              in find
                  .descendant(
                    of: find.byType(SquareTile),
                    matching: find.byType(RichText),
                  )
                  .evaluate()) {
            final paragraph = element.renderObject! as RenderParagraph;
            expect(
              paragraph.didExceedMaxLines,
              isFalse,
              reason: '${paragraph.text.toPlainText()} $width x $scale',
            );
          }
        }
      }
    });
  });

  group('large text (WCAG 1.4.4)', () {
    testWidgets('at 200% the detail CTA and the price keep the full size', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpScreen(
        tester,
        ProductDetailScreen(product: beef),
        delivery: testDelivery(),
      );
      tester.view.physicalSize = const Size(1080, 2340);
      await tester.pump();
      expect(tester.takeException(), isNull);
      final cta = find.text('Add to cart · ⃃ 62.50');
      expect(
        find.ancestor(of: cta, matching: find.byType(FittedBox)),
        findsNothing,
      );
      // The sale price: 24/800 at 2x, line height 1.2, not shrunk.
      expect(
        tester.getRect(find.text('⃃ 62.50')).height,
        greaterThanOrEqualTo(24 * 2 * 1.2 * 0.98),
      );
    });

    testWidgets('at 200% the cart subtotal and Checkout are not capped; the '
        'summary scrolls with the lines', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final cart = CartStore();
      for (final p in products) {
        for (final v in p.variants) {
          cart.add(p, v, quantity: 12);
        }
      }
      await pumpScreen(
        tester,
        const CartScreen(),
        cart: cart,
        delivery: testDelivery(),
      );
      tester.view.physicalSize = const Size(1080, 2340);
      await tester.pump();
      expect(tester.takeException(), isNull);
      final checkout = find.textContaining('Checkout · ');
      await tester.scrollUntilVisible(checkout, 300);
      final paragraph = tester.renderObject<RenderParagraph>(
        find.descendant(of: checkout, matching: find.byType(RichText)),
      );
      expect(paragraph.textScaler.scale(10), 20);
      expect(tester.takeException(), isNull);
    });

    testWidgets('at 200% the screens do not overflow', (tester) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final cart = CartStore()
        ..add(kiwi, kiwi.variants[0], quantity: 2)
        ..add(beef, beef.variants[0]);
      for (final screen in <Widget>[
        const HomeScreen(),
        const CategoriesScreen(),
        const ProductListScreen.collection(handle: 'fruits', title: 'Fruits'),
        ProductDetailScreen(product: kiwi),
        const CartScreen(),
        const AccountScreen(),
      ]) {
        await pumpScreen(tester, screen, cart: cart, delivery: testDelivery());
        tester.view.physicalSize = const Size(1080, 2340);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(tester.takeException(), isNull, reason: '$screen');
      }
    });
  });

  group('cart', () {
    Product soldOutKiwi() => Product(
      id: kiwi.id,
      title: kiwi.title,
      handle: kiwi.handle,
      tags: kiwi.tags,
      variants: [
        const Variant(
          id: 2001,
          title: '500 GM',
          priceCents: 1995,
          available: false,
        ),
        kiwi.variants[1],
      ],
      images: kiwi.images,
      options: kiwi.options,
    );

    testWidgets('a line the store sold out since is marked, left out of '
        'the total and of checkout, and can be removed with Undo', (
      tester,
    ) async {
      final api = FakeShopifyApi(
        collections: {
          'fruits': [soldOutKiwi(), beef],
        },
      );
      final cart = CartStore()
        ..add(kiwi, kiwi.variants[0], quantity: 2)
        ..add(beef, beef.variants[0]);
      await pumpScreen(
        tester,
        const CartScreen(),
        api: api,
        cart: cart,
        delivery: testDelivery(),
      );
      await tester.pump();
      await tester.pump();

      expect(cart.lineOf(2001)!.available, isFalse);
      expect(cart.subtotalCents, 6250);
      expect(find.text('Sold out'), findsOneWidget);
      expect(find.byType(QuantityStepper), findsOneWidget); // beef only
      expect(find.text('Checkout · ⃃ 62.50'), findsOneWidget);
      expect(find.textContaining(CartScreen.soldOutNote), findsOneWidget);
      expect(find.text(soldOutMessage), findsOneWidget);
      // Only the line that can be bought goes to the order.
      expect(
        [
          for (final l in cart.lines)
            if (l.available) l.variantId,
        ],
        [2003],
      );

      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await tester.pump();
      expect(cart.lineOf(2001), isNull);
      expect(
        find.text('Removed Zespri Kiwi Sungold from your cart.'),
        findsOneWidget,
      );
      // Once the notice has slid in.
      await tester.pump(const Duration(milliseconds: 750));
      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(cart.lineOf(2001), isNotNull);
      expect(cart.lines.first.variantId, 2001); // back in its place
    });

    testWidgets('only sold-out lines: Checkout is disabled and says why', (
      tester,
    ) async {
      final api = FakeShopifyApi(
        collections: {
          'fruits': [soldOutKiwi()],
        },
      );
      final cart = CartStore()..add(kiwi, kiwi.variants[0]);
      await pumpScreen(
        tester,
        const CartScreen(),
        api: api,
        cart: cart,
        delivery: testDelivery(),
      );
      await tester.pump();
      await tester.pump();
      final button = tester.widget<FilledButton>(
        find.ancestor(
          of: find.text('Remove sold-out items to check out'),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNull);
    });

    testWidgets('the bin removes a line with Undo, and the cart is said to '
        'screen readers', (tester) async {
      final cart = CartStore()
        ..add(kiwi, kiwi.variants[0])
        ..add(beef, beef.variants[0]);
      await pumpScreen(
        tester,
        const CartScreen(),
        cart: cart,
        delivery: testDelivery(),
      );
      // The quantity is a live region.
      expect(
        find.ancestor(
          of: find.text('1').first,
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.liveRegion == true,
          ),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pump();
      expect(cart.lines, hasLength(1));
      // Once the notice has slid in.
      await tester.pump(const Duration(milliseconds: 750));
      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(cart.lines.map((l) => l.variantId), [2001, 2003]);
    });

    testWidgets('Express closed: the cart offers Fresh Market', (tester) async {
      final delivery = testDelivery(
        at: uaeTime(23),
        mode: DeliveryMode.express,
      );
      final cart = CartStore()..add(kiwi, kiwi.variants[0]);
      await pumpScreen(
        tester,
        const CartScreen(),
        cart: cart,
        delivery: delivery,
      );
      final button = find.byKey(const ValueKey('cart-switch-market'));
      expect(button, findsOneWidget);
      await tester.tap(button);
      await tester.pump();
      expect(delivery.mode, DeliveryMode.market);
      expect(button, findsNothing);
    });

    testWidgets('items not on Express: the cart offers Fresh Market', (
      tester,
    ) async {
      final delivery = testDelivery(mode: DeliveryMode.express);
      final cart = CartStore()..add(beef, beef.variants[0]);
      await pumpScreen(
        tester,
        const CartScreen(),
        cart: cart,
        delivery: delivery,
      );
      expect(find.byKey(const ValueKey('cart-switch-market')), findsOneWidget);
    });
  });

  group('add control', () {
    testWidgets('adding is announced, focus moves to the stepper, and the '
        'bin offers Undo', (tester) async {
      final handle = tester.ensureSemantics();
      final messages = <Object?>[];
      tester.binding.defaultBinaryMessenger
          .setMockDecodedMessageHandler<Object?>(SystemChannels.accessibility, (
            message,
          ) async {
            messages.add(message);
            return null;
          });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger
            .setMockDecodedMessageHandler<Object?>(
              SystemChannels.accessibility,
              null,
            ),
      );
      final cart = CartStore();
      await pumpScreen(
        tester,
        Scaffold(
          body: Center(child: AddControl(product: kiwi)),
        ),
        cart: cart,
      );

      // Pressed through accessibility services, like Switch Access.
      tester.semantics.tap(
        find.semantics.byLabel('Add Zespri Kiwi Sungold to cart'),
      );
      await tester.pump();
      await tester.pump();
      expect(cart.quantityOf(2001), 1);
      expect(
        messages.whereType<Map<Object?, Object?>>().where(
          (m) =>
              m['type'] == 'announce' &&
              (m['data']! as Map)['message'] ==
                  'Added Zespri Kiwi Sungold. 1 in cart',
        ),
        hasLength(1),
      );
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'stepper plus');

      await tester.tap(find.bySemanticsLabel('Remove from cart'));
      await tester.pump();
      expect(cart.isEmpty, isTrue);
      expect(
        find.text('Removed Zespri Kiwi Sungold from your cart.'),
        findsOneWidget,
      );
      // Once the notice has slid in.
      await tester.pump(const Duration(milliseconds: 750));
      await tester.tap(find.text('Undo'));
      await tester.pump();
      expect(cart.quantityOf(2001), 1);
      handle.dispose();
    });

    testWidgets('a product card meets the 48dp Android target size', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      final cart = CartStore();
      await pumpScreen(
        tester,
        Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => SizedBox(
                width: ProductCard.railWidth,
                height: ProductCard.heightOf(context),
                child: ProductCard(product: kiwi),
              ),
            ),
          ),
        ),
        cart: cart,
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      cart.add(kiwi, kiwi.variants[0]);
      await tester.pump();
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      handle.dispose();
    });
  });

  group('product detail', () {
    testWidgets('says how many are in the cart; a new weight clears the '
        'added notice', (tester) async {
      final cart = CartStore()..add(kiwi, kiwi.variants[0], quantity: 3);
      await pumpScreen(tester, ProductDetailScreen(product: kiwi), cart: cart);
      expect(find.text('3 in your cart'), findsOneWidget);

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();
      expect(find.text('Added to cart · 4 in your cart'), findsOneWidget);
      expect(find.text('3 in your cart'), findsNothing);

      await tester.tap(find.text('1 kg'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Added to cart'), findsNothing);
      expect(find.textContaining('in your cart'), findsNothing);
    });

    testWidgets('round buttons are buttons: the heart says on/off, the cart '
        'says its count', (tester) async {
      final handle = tester.ensureSemantics();
      final cart = CartStore()..add(beef, beef.variants[0], quantity: 2);
      await pumpScreen(tester, ProductDetailScreen(product: kiwi), cart: cart);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Cart, 2 items')),
        isSemantics(isButton: true, hasTapAction: true),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Add to favourites')),
        isSemantics(
          isButton: true,
          hasTapAction: true,
          hasToggledState: true,
          isToggled: false,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('Back')),
        isSemantics(isButton: true, hasTapAction: true),
      );
      handle.dispose();
    });

    testWidgets('a white bar fades in behind the round buttons once the '
        'photo has scrolled away', (tester) async {
      final long = Product(
        id: 9,
        title: kiwi.title,
        handle: 'long',
        descriptionHtml: '<p>${'Sweet and juicy. ' * 60}</p>',
        tags: kiwi.tags,
        variants: kiwi.variants,
        images: kiwi.images,
        options: kiwi.options,
      );
      await pumpScreen(
        tester,
        ProductDetailScreen(product: long),
        delivery: testDelivery(),
      );
      expect(find.byKey(const ValueKey('detail-top-bar')), findsNothing);
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -600),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('detail-top-bar')), findsOneWidget);
    });
  });

  group('accessibility services and keyboard', () {
    testWidgets('every button can be pressed through accessibility '
        'services', (tester) async {
      final handle = tester.ensureSemantics();
      final shell = ShellController();
      final cart = CartStore()..add(kiwi, kiwi.variants[0]);
      await _pumpApp(tester, cart: cart, shell: shell);
      expect(_deadButtons(tester), isEmpty, reason: 'Home');
      for (final tab in [
        AppTab.categories,
        AppTab.deals,
        AppTab.cart,
        AppTab.account,
      ]) {
        shell.select(tab);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        expect(_deadButtons(tester), isEmpty, reason: '$tab');
      }

      // A tab is pressed through its semantics.
      tester.semantics.tap(find.semantics.byLabel('Categories'));
      await tester.pump();
      expect(shell.tab, AppTab.categories);

      await pumpScreen(tester, ProductDetailScreen(product: kiwi));
      expect(_deadButtons(tester), isEmpty, reason: 'detail');
      handle.dispose();
    });

    testWidgets('keyboard focus never rests under the bar or Ask, and shows '
        'a ring', (tester) async {
      await _pumpApp(tester);
      final bar = tester.getRect(find.byType(FloatingNavBar));
      final ask = tester.getRect(find.byType(AskButton));
      final covered = Rect.fromLTRB(0, ask.top, 390, 844);
      var checked = 0;
      for (var i = 0; i < 60; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        // The focus change, the check after its frame, then the short
        // scroll that brings the control clear.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
        final node = FocusManager.instance.primaryFocus;
        final context = node?.context;
        if (node == null || context == null || node is FocusScopeNode) {
          continue;
        }
        // The bar's own tabs and the Ask button are fine where they are.
        final inBar =
            find
                .ancestor(
                  of: find.byElementPredicate((e) => e == context),
                  matching: find.byType(FloatingNavBar),
                )
                .evaluate()
                .isNotEmpty ||
            find
                .ancestor(
                  of: find.byElementPredicate((e) => e == context),
                  matching: find.byType(AskButton),
                )
                .evaluate()
                .isNotEmpty;
        if (inBar) continue;
        checked++;
        final rect = node.rect;
        expect(
          rect.bottom <= covered.top || rect.overlaps(bar) == false,
          isTrue,
          reason: 'focus $i at $rect is under the bar or Ask',
        );
        expect(
          rect.bottom,
          lessThanOrEqualTo(covered.top + 0.5),
          reason: 'focus $i at $rect',
        );
        final ring = tester
            .state<FocusRingLayerState>(find.byType(FocusRingLayer))
            .ringRect;
        expect(ring, isNotNull, reason: 'focus $i has no ring');
      }
      expect(checked, greaterThan(20));
    });
  });

  group('section tags', () {
    test('a tag may take two lines rather than cut its title', () {
      expect(SectionTag.height, 38);
    });

    testWidgets('at 200% on a small phone the titles are whole', (
      tester,
    ) async {
      await loadAppFonts(tester);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpScreen(tester, const HomeScreen(), delivery: testDelivery());
      tester.view.physicalSize = const Size(1080, 2340);
      await tester.pump();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -900));
      await tester.pump();
      for (final element
          in find
              .descendant(
                of: find.byType(SectionTag),
                matching: find.byType(RichText),
              )
              .evaluate()) {
        final paragraph = element.renderObject! as RenderParagraph;
        expect(
          paragraph.didExceedMaxLines,
          isFalse,
          reason: paragraph.text.toPlainText(),
        );
      }
      expect(tester.takeException(), isNull);
    });
  });
}

void _ignore(Object? _) {}
