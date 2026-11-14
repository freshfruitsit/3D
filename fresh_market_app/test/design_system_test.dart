import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/delivery/delivery.dart';
import 'package:fresh_market_app/models/money.dart';
import 'package:fresh_market_app/screens/product_list_screen.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/state/cart_store.dart';
import 'package:fresh_market_app/state/favourites_store.dart';
import 'package:fresh_market_app/theme/app_theme.dart';
import 'package:fresh_market_app/widgets/add_control.dart';
import 'package:fresh_market_app/widgets/ask_button.dart';
import 'package:fresh_market_app/widgets/category_tile.dart';
import 'package:fresh_market_app/widgets/delivery_widgets.dart';
import 'package:fresh_market_app/widgets/floating_nav_bar.dart';
import 'package:fresh_market_app/widgets/price_widgets.dart';
import 'package:fresh_market_app/widgets/product_card.dart';
import 'package:fresh_market_app/widgets/section_header.dart';
import 'package:material_ui/material_ui.dart';

import 'support/test_app.dart';

/// WCAG contrast ratio of two opaque colours.
double _contrast(Color a, Color b) {
  double channel(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
  double luminance(Color c) =>
      0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  final la = luminance(a);
  final lb = luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

Finder _inKey(String key, Finder matching) =>
    find.descendant(of: find.byKey(ValueKey(key)), matching: matching);

Future<DeliveryStore> _pumpLine(
  WidgetTester tester, {
  String? area = 'Business Bay',
  DateTime? at,
  DeliveryMode mode = DeliveryMode.market,
}) async {
  final store = testDelivery(area: area, at: at, mode: mode);
  await pumpScreen(
    tester,
    const Scaffold(
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(children: [DeliveryModeSwitch(), DeliveryLine()]),
      ),
    ),
    delivery: store,
  );
  return store;
}

String _lineText(WidgetTester tester) => tester
    .widget<Text>(
      find
          .descendant(
            of: find.byKey(const ValueKey('delivery-line')),
            matching: find.byType(Text),
          )
          .first,
    )
    .textSpan!
    .toPlainText()
    // Times keep together with non-breaking spaces on screen.
    .replaceAll('\u00A0', ' ');

/// A Text showing [text], read with non-breaking spaces as spaces.
Finder _textN(String text) => find.byWidgetPredicate(
  (w) =>
      w is Text &&
      (w.data ?? w.textSpan?.toPlainText())?.replaceAll('\u00A0', ' ') == text,
  description: 'text "$text"',
);

void main() {
  group('colour tokens', () {
    test('text pairs keep 4.5:1', () {
      const pairs = [
        (AppColors.ink, AppColors.canvas),
        (AppColors.ink, AppColors.subtle),
        (AppColors.secondary, AppColors.canvas),
        (AppColors.secondary, AppColors.subtle),
        (AppColors.onDark, AppColors.green),
        (AppColors.green, AppColors.canvas),
        (AppColors.green, AppColors.subtle),
        (AppColors.green, AppColors.greenSoft),
        (AppColors.onDark, AppColors.saving),
        (AppColors.saving, AppColors.canvas),
        (AppColors.navInactive, AppColors.ink),
        (AppColors.onDark, AppColors.ink),
      ];
      for (final (fg, bg) in pairs) {
        expect(
          _contrast(fg, bg),
          greaterThanOrEqualTo(4.5),
          reason: '$fg on $bg',
        );
      }
    });

    test('the palette has no lime, olive or flag colours', () {
      const banned = [
        Color(0xFFB8D432), // lime
        Color(0xFF4F6B00), // olive
        Color(0xFFEFF5DA), // lime page tint
      ];
      final tokens = [
        AppColors.canvas,
        AppColors.surface,
        AppColors.subtle,
        AppColors.hairline,
        AppColors.ink,
        AppColors.secondary,
        AppColors.tertiary,
        AppColors.green,
        AppColors.greenSoft,
        AppColors.saving,
        AppColors.navInactive,
        AppColors.disabledFill,
        AppColors.disabledText,
      ];
      for (final c in banned) {
        expect(tokens, isNot(contains(c)));
      }
    });
  });

  group('type', () {
    test('every AppText style falls back to the Dirham font', () {
      const styles = [
        AppText.title,
        AppText.heading,
        AppText.cardHeading,
        AppText.body,
        AppText.bodySmall,
        AppText.productName,
        AppText.cardTitle,
        AppText.caption,
        AppText.label,
        AppText.price,
        AppText.priceLarge,
        AppText.oldPrice,
        AppText.button,
        AppText.buttonSmall,
        AppText.link,
        AppText.tileLabel,
        AppText.navLabel,
        AppText.tag,
      ];
      for (final style in styles) {
        expect(style.fontFamily, 'Inter');
        expect(style.fontFamilyFallback, ['Dirham']);
      }
      expect(AppText.title.fontSize, 24);
      expect(AppText.title.fontWeight, FontWeight.w800);
      expect(AppText.heading.fontSize, 18);
      expect(AppText.productName.fontSize, 14);
      expect(AppText.productName.fontWeight, FontWeight.w500);
      expect(AppText.body.fontSize, 15);
      expect(AppText.caption.fontSize, 12);
      expect(AppText.price.fontSize, 16);
      expect(AppText.price.fontWeight, FontWeight.w800);
    });

    test('the theme text styles fall back to the Dirham font too', () {
      final theme = buildAppTheme();
      for (final style in [
        theme.textTheme.bodyMedium!,
        theme.textTheme.bodyLarge!,
        theme.textTheme.titleLarge!,
        theme.textTheme.labelLarge!,
        theme.primaryTextTheme.bodyMedium!,
      ]) {
        expect(style.fontFamilyFallback, contains('Dirham'));
      }
      expect(theme.scaffoldBackgroundColor, AppColors.canvas);
    });

    testWidgets('a plain Text inherits the fallback', (tester) async {
      await pumpScreen(tester, Scaffold(body: Text(formatMoney(1250))));
      final style = DefaultTextStyle.of(tester.element(find.text('⃃ 12.50')))
          .style;
      expect(style.fontFamilyFallback, contains('Dirham'));
    });
  });

  group('prices', () {
    testWidgets('a sale price is saving orange, read out as AED', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const Scaffold(
          body: PriceRow(
            priceCents: 6250,
            oldPriceCents: 11500,
            trailing: SalePill(percent: 46),
          ),
        ),
      );
      final price = tester.widget<Text>(find.text('⃃ 62.50'));
      expect(price.style!.color, AppColors.saving);
      expect(price.semanticsLabel, 'AED 62.50');
      final old = tester.widget<Text>(find.text('115.00'));
      expect(old.semanticsLabel, 'was AED 115.00');
      expect(old.style!.decoration, TextDecoration.lineThrough);
      final pill = tester.widget<Text>(find.text('−46%'));
      expect(pill.style!.color, AppColors.onDark);
      expect(pill.semanticsLabel, '46 percent off');
    });

    testWidgets('a regular price is ink', (tester) async {
      await pumpScreen(
        tester,
        const Scaffold(body: PriceRow(priceCents: 1995)),
      );
      final price = tester.widget<Text>(find.text('⃃ 19.95'));
      expect(price.style!.color, AppColors.ink);
      expect(find.text('19.95'), findsNothing);
    });

    testWidgets('MoneyText says AED', (tester) async {
      await pumpScreen(
        tester,
        const Scaffold(body: MoneyText(10240, prefix: 'Subtotal ')),
      );
      final text = tester.widget<Text>(find.text('Subtotal ⃃ 102.40'));
      expect(text.semanticsLabel, 'Subtotal AED 102.40');
    });
  });

  group('bottom bar and Ask', () {
    testWidgets('ink bar, white active tab with a green dot, green badge', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: FloatingNavBar(
              current: AppTab.deals,
              cartCount: 3,
              onSelected: (_) {},
            ),
          ),
        ),
      );
      final bar = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(FloatingNavBar),
              matching: find.byType(Container),
            )
            .first,
      );
      final shape = bar.decoration! as ShapeDecoration;
      expect(shape.color, AppColors.ink);
      expect(
        tester.widget<Text>(find.text('Deals')).style!.color,
        AppColors.onDark,
      );
      expect(
        tester.widget<Text>(find.text('Home')).style!.color,
        AppColors.navInactive,
      );
      expect(find.byKey(const ValueKey('nav-active-dot')), findsOneWidget);
      final badge = tester.widget<Text>(find.text('3'));
      expect(badge.style!.color, AppColors.onDark);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Ask is a white pill with a green sparkle', (tester) async {
      await pumpScreen(
        tester,
        const Scaffold(body: Center(child: AskButton())),
      );
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(AskButton),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.color, AppColors.surface);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.auto_awesome)).color,
        AppColors.green,
      );
      expect(tester.widget<Text>(find.text('Ask')).style!.color, AppColors.ink);
    });
  });

  group('section header', () {
    testWidgets('See all is an ink link', (tester) async {
      var tapped = 0;
      await pumpScreen(
        tester,
        Scaffold(
          body: SectionHeader(
            title: 'Best Deals',
            icon: Icons.sell,
            onViewAll: () => tapped++,
          ),
        ),
      );
      expect(find.text('See all'), findsOneWidget);
      expect(find.text('View all'), findsNothing);
      await tester.tap(find.text('See all'));
      expect(tapped, 1);
      expect(SectionTag.fill, AppColors.ink);
      expect(SectionTag.accent, AppColors.green);
    });
  });

  group('header delivery widgets', () {
    testWidgets('10:00 Fresh Market: the compact line offers Express', (
      tester,
    ) async {
      final store = await _pumpLine(tester, at: uaeTime(10));
      expect(_lineText(tester), 'Today by 4 PM · order within 8h 0m');
      expect(_inKey('mode-express', find.text('30–40 min')), findsOneWidget);
      final range = tester.widget<Text>(
        _inKey('mode-express', find.text('30–40 min')),
      );
      expect(range.style!.color, AppColors.green);

      await tester.tap(
        _inKey('delivery-line', _textN(DeliveryLine.expressLabel('30–40 min'))),
      );
      await tester.pump();
      expect(store.mode, DeliveryMode.express);
      expect(_lineText(tester), '30–40 min · open until 10 PM');
      expect(
        _inKey('delivery-line', find.text(DeliveryLine.shopExpress)),
        findsOneWidget,
      );
      await tester.tap(
        _inKey('delivery-line', find.text(DeliveryLine.shopExpress)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      final list = tester.widget<ProductListScreen>(
        find.byType(ProductListScreen),
      );
      expect(list.handle, ExpressCollection.handle);
    });

    testWidgets('after the cut-off and with Express closed', (tester) async {
      await _pumpLine(tester, at: uaeTime(18, 30));
      expect(
        _lineText(tester),
        'Tomorrow by 11 AM · same-day orders closed at 6 PM',
      );

      final store = await _pumpLine(
        tester,
        at: uaeTime(23),
        mode: DeliveryMode.express,
      );
      expect(_lineText(tester), 'Express is closed right now. Opens 8 AM');
      final opens = tester.widget<Text>(
        _inKey('mode-express', find.text('Opens 8 AM')),
      );
      expect(opens.style!.color, AppColors.secondary);
      await tester.tap(
        _inKey('delivery-line', find.text(DeliveryLine.backToMarket)),
      );
      await tester.pump();
      expect(store.mode, DeliveryMode.market);
    });

    testWidgets('outside the Express zone: no Express button, grey bolt', (
      tester,
    ) async {
      await _pumpLine(tester, area: 'Jebel Ali', at: uaeTime(10));
      expect(_lineText(tester), startsWith('Today by'));
      expect(find.textContaining('Express 3'), findsNothing);
      final notHere = tester.widget<Text>(
        _inKey('mode-express', find.text('Not in your area')),
      );
      expect(notHere.style!.color, AppColors.secondary);
    });

    testWidgets('no area: the website sentence and Set location', (
      tester,
    ) async {
      await _pumpLine(tester, area: null);
      expect(
        _lineText(tester),
        'Tell us where you are to see delivery times and Express '
        'availability.',
      );
      expect(
        _inKey('delivery-line', find.text(DeliveryLine.setLocation)),
        findsOneWidget,
      );
    });

    testWidgets('the location chip sits at the right end, area in ink', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        const Scaffold(
          body: SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [Text('Logo'), Spacer(), LocationChip()]),
            ),
          ),
        ),
        delivery: testDelivery(),
      );
      final chip = tester.getRect(find.byKey(const ValueKey('location-chip')));
      expect(chip.right, moreOrLessEquals(390 - 16));
      expect(chip.width, lessThanOrEqualTo(390 * 0.55));
      expect(chip.height, greaterThanOrEqualTo(44));
      final area = tester.widget<Text>(find.text('Business Bay'));
      expect(area.style!.color, AppColors.ink);
      expect(area.style!.fontWeight, FontWeight.w700);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.location_on)).color,
        AppColors.green,
      );
    });

    testWidgets('no overflow at 360dp and text scale 1.3', (tester) async {
      final products = sampleProducts();
      await pumpScreen(
        tester,
        Scaffold(
          body: Builder(
            builder: (context) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Row(children: [Text('Logo'), Spacer(), LocationChip()]),
                const DeliveryModeSwitch(),
                const DeliveryLine(),
                SizedBox(
                  height: ProductCard.heightOf(context),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final p in products)
                        SizedBox(
                          width: ProductCard.railWidth,
                          child: ProductCard(product: p),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        delivery: testDelivery(),
      );
      // A 360dp phone with large text.
      tester.view.physicalSize = const Size(1080, 2340);
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await tester.pump();
      expect(tester.takeException(), isNull);
      for (final time in [uaeTime(18, 30), uaeTime(23)]) {
        for (final mode in DeliveryMode.values) {
          final store = testDelivery(at: time, mode: mode);
          await pumpScreen(
            tester,
            const Scaffold(
              body: Padding(
                padding: EdgeInsets.all(16),
                child: Column(children: [DeliveryModeSwitch(), DeliveryLine()]),
              ),
            ),
            delivery: store,
          );
          tester.view.physicalSize = const Size(1080, 2340);
          await tester.pump();
          expect(tester.takeException(), isNull, reason: '$time $mode');
        }
      }
    });
  });

  group('tile grids', () {
    testWidgets('rows keep a second label line only when a name needs it', (
      tester,
    ) async {
      late BuildContext context;
      await pumpScreen(
        tester,
        Builder(
          builder: (c) {
            context = c;
            return const SizedBox();
          },
        ),
      );
      expect(SquareTile.linesNeeded(context, 80, ['Fig', 'Kiwi']), 1);
      expect(
        SquareTile.linesNeeded(context, 80, ['Fig', 'Exotic fruit boxes']),
        2,
      );
      // One line: the row is a line shorter than with two.
      expect(
        SquareTile.heightFor(context, 80, 2) -
            SquareTile.heightFor(context, 80, 1),
        moreOrLessEquals(12 * 1.25),
      );
      // After the grid, only the slack is left under a one-line last row.
      expect(
        TileGrid.trailingSpace(context, 4 * 80 + 3 * 12, ['Fig', 'Kiwi']),
        SquareTile.slack,
      );
    });
  });

  group('product card', () {
    testWidgets('the add control sits on the photo well, bottom right', (
      tester,
    ) async {
      final kiwi = sampleProducts().first;
      final cart = CartStore();
      await pumpScreen(
        tester,
        Scaffold(
          body: Center(
            child: SizedBox(
              width: ProductCard.railWidth,
              child: Builder(
                builder: (context) => SizedBox(
                  height: ProductCard.heightOf(context),
                  child: ProductCard(product: kiwi),
                ),
              ),
            ),
          ),
        ),
        cart: cart,
      );
      final well = tester.getRect(
        find
            .descendant(
              of: find.byType(ProductCard),
              matching: find.byWidgetPredicate(
                (w) => w is DecoratedBox && w.decoration == AppDecor.well,
              ),
            )
            .first,
      );
      Rect circle() => tester.getRect(
        find
            .descendant(
              of: find.bySemanticsLabel('Add ${kiwi.title} to cart'),
              matching: find.byWidgetPredicate(
                (w) => w is SizedBox && w.width == AddControl.circleSize,
              ),
            )
            .first,
      );
      expect(
        circle().right,
        moreOrLessEquals(well.right - ProductCard.wellInset),
      );
      expect(
        circle().bottom,
        moreOrLessEquals(well.bottom - ProductCard.wellInset),
      );
      // Nothing of the card sits below the text: no empty control row.
      final card = tester.getRect(find.byType(ProductCard));
      final price = tester.getRect(find.byType(PriceRow));
      expect(card.bottom - price.bottom, lessThan(40));

      // In the cart it is a green stepper, still on the well.
      await tester.tap(find.bySemanticsLabel('Add ${kiwi.title} to cart'));
      await tester.pump();
      final stepper = tester.getRect(find.byType(QuantityStepper));
      expect(stepper.right, lessThanOrEqualTo(well.right));
      expect(stepper.bottom, lessThanOrEqualTo(well.bottom));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the heart saves to favourites', (tester) async {
      final favourites = FavouritesStore();
      final kiwi = sampleProducts().first;
      await pumpScreen(
        tester,
        Scaffold(
          body: Center(
            child: SizedBox(
              width: ProductCard.railWidth,
              child: Builder(
                builder: (context) => SizedBox(
                  height: ProductCard.heightOf(context),
                  child: ProductCard(product: kiwi),
                ),
              ),
            ),
          ),
        ),
        favourites: favourites,
      );
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('favourite-${kiwi.id}')));
      await tester.pump();
      expect(favourites.contains(kiwi.id), isTrue);
      expect(find.byIcon(Icons.favorite), findsOneWidget);
      expect(
        tester.widget<Icon>(find.byIcon(Icons.favorite)).color,
        AppColors.ink,
      );
      // The add button is a green circle with a white plus.
      expect(
        tester.widget<Icon>(find.byIcon(Icons.add)).color,
        AppColors.onDark,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
