import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/app.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/state/cart_store.dart';
import 'package:fresh_market_app/theme/app_theme.dart';
import 'package:fresh_market_app/widgets/add_control.dart';
import 'package:fresh_market_app/widgets/app_search_field.dart';
import 'package:fresh_market_app/widgets/category_tile.dart';
import 'package:fresh_market_app/widgets/circle_icon_button.dart';
import 'package:fresh_market_app/widgets/floating_nav_bar.dart';
import 'package:fresh_market_app/widgets/price_widgets.dart';
import 'package:fresh_market_app/widgets/product_card.dart';
import 'package:fresh_market_app/widgets/section_header.dart';
import 'package:fresh_market_app/widgets/state_views.dart';
import 'package:material_ui/material_ui.dart';
import 'support/test_app.dart';

Future<void> loadFonts() async {
  final inter = FontLoader('Inter');
  for (final w in ['Regular','Medium','SemiBold','Bold','ExtraBold']) {
    inter.addFont(File('assets/fonts/Inter-$w.otf').readAsBytes().then((b) => ByteData.view(b.buffer)));
  }
  await inter.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(File('/opt/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytes().then((b) => ByteData.view(b.buffer)));
  await icons.load();
}

void main() {
  testWidgets('render', (tester) async {
    await tester.runAsync(loadFonts);
    final cart = CartStore();
    final ps = sampleProducts();
    cart.add(ps[2], ps[2].variants[0], quantity: 1);
    cart.add(ps[4], ps[4].variants[0], quantity: 3);
    await pumpScreen(tester, Scaffold(body: Stack(children: [
      Builder(builder: (context) => ListView(padding: EdgeInsets.only(top: 50, bottom: AppDims.bottomBarSpace(context)), children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: SearchFieldButton(onTap: () {})),
        const SizedBox(height: 16),
        const SectionHeader(title: 'Shop By Category'),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: CategoryGrid()),
        const SizedBox(height: 16),
        SectionHeader(title: "Today's Top Deals", onViewAll: () {}),
        SizedBox(height: ProductCard.heightOf(context), child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16), scrollDirection: Axis.horizontal,
          itemCount: ps.length, separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, i) => SizedBox(width: ProductCard.railWidth, child: ProductCard(product: ps[i])))),
        const SizedBox(height: 16),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Row(children: [
          CircleIconButton.back(context), const SizedBox(width: 8),
          CircleIconButton(icon: Icons.shopping_bag_outlined, onPressed: () {}, tooltip: 'Cart', badgeCount: 4),
          const SizedBox(width: 8),
          QuantityStepper(quantity: 2, onDecrement: () {}, onIncrement: () {}),
          const SizedBox(width: 8),
          const Expanded(child: PriceRow(priceCents: 6250, oldPriceCents: 11500, large: true, trailing: SalePill(percent: 46))),
        ])),
        SizedBox(height: 260, child: EmptyView(title: 'Your cart is empty', message: 'Add fresh produce to get started.', actionLabel: 'Start shopping', onAction: () {})),
        ErrorView(message: 'We could not reach the store.', onRetry: () {}, compact: true),
      ])),
      Positioned(left: 0, right: 0, bottom: 12, child: FloatingNavBar(current: AppTab.home, onSelected: (_) {}, cartCount: 4)),
    ])), cart: cart);
    await tester.pump(const Duration(seconds: 1));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('/tmp/claude-0/-home-user-3D/6bd0b7d4-dc11-536b-b147-8b167cf2f96e/scratchpad/foundation/a.png'));
    await tester.drag(find.byType(ListView).first, const Offset(0, -420));
    await tester.pump(const Duration(seconds: 1));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('/tmp/claude-0/-home-user-3D/6bd0b7d4-dc11-536b-b147-8b167cf2f96e/scratchpad/foundation/b.png'));
    expect(tester.takeException(), isNull);
  });
}
