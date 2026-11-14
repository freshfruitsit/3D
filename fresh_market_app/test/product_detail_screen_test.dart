import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/app.dart';
import 'package:fresh_market_app/models/product.dart';
import 'package:fresh_market_app/screens/product_detail_screen.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/state/cart_store.dart';
import 'package:fresh_market_app/state/favourites_store.dart';
import 'package:fresh_market_app/theme/app_theme.dart';
import 'package:fresh_market_app/widgets/add_control.dart';
import 'package:fresh_market_app/widgets/delivery_widgets.dart';
import 'package:fresh_market_app/widgets/price_widgets.dart';
import 'package:material_ui/material_ui.dart';

import 'support/test_app.dart';

void main() {
  final products = sampleProducts();
  final kiwi = products[0]; // 500 GM 19.95, 1 KG 39.75
  final beef = products[1]; // sale, single variant
  final blueberry = products[3]; // sold out
  final bouquet = products[4]; // no tags
  final strawberry = products[5]; // 250 GM sold out, 1 KG on sale

  FilledButton addButton(WidgetTester tester) =>
      tester.widget<FilledButton>(find.byType(FilledButton));

  testWidgets('shows vendor, title, size line, price, facts and description', (
    tester,
  ) async {
    await pumpScreen(tester, ProductDetailScreen(product: kiwi));

    expect(find.text('Zespri'), findsOneWidget);
    expect(find.text('Zespri Kiwi Sungold'), findsOneWidget);
    expect(find.text('500 g · New Zealand'), findsOneWidget);
    expect(find.text('Weight'), findsOneWidget);
    expect(find.text('1Hr Express'), findsOneWidget);
    expect(find.text('By air'), findsOneWidget);
    expect(find.text('Local UAE'), findsNothing);
    expect(find.textContaining('Golden, juicy and sweet.'), findsOneWidget);
    expect(find.textContaining('<p>'), findsNothing);
    expect(find.text('Add to cart · \u20C3\u00A019.95'), findsOneWidget);
    expect(find.byType(SalePill), findsNothing);
    expect(find.text('View cart'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('choosing a variant updates the size line and the price', (
    tester,
  ) async {
    await pumpScreen(tester, ProductDetailScreen(product: kiwi));

    await tester.tap(find.text('1 kg'));
    await tester.pump();

    expect(find.text('1 kg · New Zealand'), findsOneWidget);
    expect(find.text('Add to cart · \u20C3\u00A039.75'), findsOneWidget);
  });

  testWidgets(
    'quantity stepper multiplies the button price and adds that many',
    (tester) async {
      final cart = CartStore();
      await pumpScreen(tester, ProductDetailScreen(product: kiwi), cart: cart);

      // At 1 the minus is disabled and is not a bin.
      final stepper = tester.widget<QuantityStepper>(
        find.byType(QuantityStepper),
      );
      expect(stepper.onDecrement, isNull);
      expect(find.byIcon(Icons.delete_outline), findsNothing);

      await tester.tap(find.bySemanticsLabel('Increase quantity'));
      await tester.pump();
      await tester.tap(find.bySemanticsLabel('Increase quantity'));
      await tester.pump();
      expect(find.text('Add to cart · \u20C3\u00A059.85'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Decrease quantity'));
      await tester.pump();
      expect(find.text('Add to cart · \u20C3\u00A039.90'), findsOneWidget);

      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      expect(cart.quantityOf(2001), 2);
      expect(find.text('2 added to cart · 2 in your cart'), findsOneWidget);
      expect(find.text('View cart'), findsOneWidget);
      // Quantity goes back to 1 and the cart button shows the badge.
      expect(find.text('Add to cart · \u20C3\u00A019.95'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    },
  );

  testWidgets('"View cart" switches to the cart tab', (tester) async {
    final shell = ShellController();
    await pumpScreen(
      tester,
      ProductDetailScreen(product: bouquet),
      shell: shell,
    );

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(find.text('Added to cart · 1 in your cart'), findsOneWidget);

    await tester.tap(find.text('View cart'));
    await tester.pump();
    expect(shell.tab, AppTab.cart);
  });

  testWidgets('cart button shows what is in the cart and opens the cart tab', (
    tester,
  ) async {
    final shell = ShellController();
    final cart = CartStore()..add(beef, beef.variants.first, quantity: 3);
    await pumpScreen(
      tester,
      ProductDetailScreen(product: kiwi),
      cart: cart,
      shell: shell,
    );

    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.byTooltip('Cart'));
    await tester.pump();
    expect(shell.tab, AppTab.cart);
  });

  testWidgets('a sale shows the old price and the sale pill', (tester) async {
    await pumpScreen(tester, ProductDetailScreen(product: beef));

    expect(find.text('\u20C3\u00A062.50'), findsOneWidget);
    expect(find.text('115.00'), findsOneWidget);
    expect(find.text('\u221246%'), findsOneWidget);
    // One variant called "Default Title": no variant buttons.
    expect(find.text('Weight'), findsNothing);
    expect(find.text('Default Title'), findsNothing);
  });

  testWidgets('a sold-out product cannot be added', (tester) async {
    final cart = CartStore();
    await pumpScreen(
      tester,
      ProductDetailScreen(product: blueberry),
      cart: cart,
    );

    expect(addButton(tester).onPressed, isNull);
    expect(find.widgetWithText(FilledButton, 'Sold out'), findsOneWidget);
    await tester.tap(find.byType(FilledButton));
    await tester.pump();
    expect(cart.isEmpty, isTrue);
  });

  testWidgets('a sold-out variant is labelled and cannot be chosen', (
    tester,
  ) async {
    final cart = CartStore();
    await pumpScreen(
      tester,
      ProductDetailScreen(product: strawberry),
      cart: cart,
    );

    // The in-stock weight is chosen to start with.
    expect(find.text('1 kg · South Africa'), findsOneWidget);
    expect(find.text('Sold out'), findsOneWidget);

    await tester.tap(find.text('250 g'));
    await tester.pump();
    expect(find.text('1 kg · South Africa'), findsOneWidget);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(cart.quantityOf(2009), 1);
    expect(cart.quantityOf(2008), 0);
  });

  testWidgets('the heart toggles the favourite', (tester) async {
    final favourites = FavouritesStore();
    await pumpScreen(
      tester,
      ProductDetailScreen(product: kiwi),
      favourites: favourites,
    );

    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
    await tester.tap(find.byTooltip('Add to favourites'));
    await tester.pump();
    expect(favourites.contains(kiwi.id), isTrue);
    expect(find.byIcon(Icons.favorite), findsOneWidget);

    await tester.tap(find.byTooltip('Remove from favourites'));
    await tester.pump();
    expect(favourites.contains(kiwi.id), isFalse);
  });

  testWidgets('cannot add past the cart limit', (tester) async {
    final cart = CartStore()
      ..add(bouquet, bouquet.variants.first, quantity: CartStore.maxQuantity);
    await pumpScreen(tester, ProductDetailScreen(product: bouquet), cart: cart);

    expect(addButton(tester).onPressed, isNull);
    expect(find.text('Limit reached'), findsOneWidget);
  });

  testWidgets('back, favourite and cart stay in reach when scrolled', (
    tester,
  ) async {
    await pumpScreen(tester, ProductDetailScreen(product: kiwi));
    final before = tester.getRect(find.byTooltip('Back'));
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -400),
    );
    await tester.pump();
    // The page moved under them; the round buttons did not.
    expect(tester.getRect(find.byTooltip('Back')), before);
    expect(find.byTooltip('Back').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Cart').hitTestable(), findsOneWidget);
    expect(find.byTooltip('Add to favourites').hitTestable(), findsOneWidget);
  });

  test('delivery lines keep times, units and the area name together', () {
    expect(
      ProductDeliveryInfo.keepTogether(
        'Today within 6 hours to Business Bay · by 9:45 PM',
        'Business Bay',
      ),
      'Today within 6\u00A0hours to Business\u00A0Bay · by\u00A09:45\u00A0PM',
    );
    expect(
      ProductDeliveryInfo.keepTogether(
        'Express: Get it in 30–40 min to Business Bay',
        'Business Bay',
      ),
      'Express: Get it in\u00A030–40\u00A0min to Business\u00A0Bay',
    );
    expect(
      ProductDeliveryInfo.keepTogether('Express opens 8 AM', null),
      'Express opens 8\u00A0AM',
    );
  });

  testWidgets('a product with several photos and long text does not overflow', (
    tester,
  ) async {
    final product = Product(
      id: 1,
      title: 'A very long product title that wraps over more than one line',
      handle: 'long',
      vendor: 'Vendor',
      descriptionHtml: '<p>${'Lorem ipsum dolor sit amet. ' * 80}</p>',
      tags: const ['1hr-delivery', 'UAE', 'AIR'],
      variants: const [
        Variant(
          id: 11,
          title: '250 GM',
          priceCents: 123456,
          compareAtCents: 234567,
        ),
        Variant(id: 12, title: '500 GM', priceCents: 1000),
        Variant(id: 13, title: '1 KG', priceCents: 2000, available: false),
        Variant(id: 14, title: '2 KG', priceCents: 4000),
      ],
      images: const [
        'https://cdn.shopify.com/a.jpg',
        'https://cdn.shopify.com/b.jpg',
      ],
      options: const [
        ProductOption(
          name: 'Size',
          values: ['250 GM', '500 GM', '1 KG', '2 KG'],
        ),
      ],
    );
    await pumpScreen(tester, ProductDetailScreen(product: product));
    await tester.pump();

    expect(find.text('Size'), findsOneWidget);
    expect(find.byType(PageView), findsOneWidget);
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -600),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  group('design', () {
    /// The Material that draws the variant chip around [label].
    Material chip(WidgetTester tester, String label) => tester.widget<Material>(
      find
          .ancestor(of: find.text(label), matching: find.byType(Material))
          .first,
    );

    testWidgets('the photo sits on a full-width off-white area', (
      tester,
    ) async {
      await pumpScreen(tester, ProductDetailScreen(product: kiwi));
      final area = find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == AppColors.subtle,
      );
      expect(area, findsOneWidget);
      expect(tester.getSize(area).width, 390);
      expect(tester.getTopLeft(area), Offset.zero);
    });

    testWidgets('variant chips are white; the chosen one has a 2px ink edge', (
      tester,
    ) async {
      await pumpScreen(tester, ProductDetailScreen(product: kiwi));

      final chosen = chip(tester, '500 g');
      final chosenEdge = (chosen.shape! as RoundedRectangleBorder).side;
      expect(chosen.color, AppColors.surface);
      expect(chosenEdge.color, AppColors.ink);
      expect(chosenEdge.width, 2);

      final other = chip(tester, '1 kg');
      final otherEdge = (other.shape! as RoundedRectangleBorder).side;
      expect(other.color, AppColors.surface);
      expect(otherEdge.color, AppColors.hairline);
      expect(otherEdge.width, 1);
      expect(find.bySemanticsLabel('1 kg, AED 39.75'), findsOneWidget);
    });

    testWidgets('the add button is green and reads the price as AED', (
      tester,
    ) async {
      await pumpScreen(tester, ProductDetailScreen(product: kiwi));
      final button = addButton(tester);
      expect(button.style, isNull); // the theme's green buying button
      expect(find.bySemanticsLabel('Add to cart, AED 19.95'), findsOneWidget);
    });

    testWidgets('the added notice is green on green-soft', (tester) async {
      await pumpScreen(tester, ProductDetailScreen(product: bouquet));
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      final check = tester.widget<Icon>(find.byIcon(Icons.check_circle));
      expect(check.color, AppColors.green);
      final notice = tester.widget<Container>(
        find
            .ancestor(
              of: find.text('Added to cart · 1 in your cart'),
              matching: find.byType(Container),
            )
            .first,
      );
      expect((notice.decoration! as BoxDecoration).color, AppColors.greenSoft);
    });

    testWidgets('no overflow at 360dp and text scale 1.3', (tester) async {
      for (final product in [kiwi, beef, blueberry, strawberry]) {
        await pumpScreen(
          tester,
          ProductDetailScreen(product: product),
          delivery: testDelivery(),
        );
        tester.view.physicalSize = const Size(1080, 2340);
        tester.platformDispatcher.textScaleFactorTestValue = 1.3;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pump();
        expect(tester.takeException(), isNull, reason: product.title);
        await tester.drag(
          find.byType(SingleChildScrollView),
          const Offset(0, -800),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: product.title);
      }
    });
  });
}
