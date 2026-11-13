import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/screens/product_detail_screen.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:material_ui/material_ui.dart';

import 'support/test_app.dart';

/// The product page's Express row in Fresh Market mode shows the website's
/// [data-tfm-promise="express"] text, labelled only while Express is open.
void main() {
  final kiwi = sampleProducts()[0]; // 1hr-delivery

  // Times and the area name are joined by non-breaking spaces on screen.
  Finder inBox(String text) => find.descendant(
    of: find.byKey(const ValueKey('product-delivery')),
    matching: find.byWidgetPredicate(
      (w) =>
          w is Text &&
          (w.data ?? w.textSpan?.toPlainText())?.replaceAll('\u00A0', ' ') ==
              text,
      description: 'text "$text"',
    ),
  );

  testWidgets('open: labelled "Express: ..."', (tester) async {
    await pumpScreen(
      tester,
      ProductDetailScreen(product: kiwi),
      delivery: testDelivery(at: uaeTime(10)),
    );
    expect(
      inBox('Express: Get it in 30–40 min to Business Bay'),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('closed: "Express opens 8 AM", not "Express: Express ..."', (
    tester,
  ) async {
    await pumpScreen(
      tester,
      ProductDetailScreen(product: kiwi),
      delivery: testDelivery(at: uaeTime(23)),
    );
    expect(inBox('Express opens 8 AM'), findsOneWidget);
    expect(find.textContaining('Express: Express'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('outside the zone: the website text as is', (tester) async {
    await pumpScreen(
      tester,
      ProductDetailScreen(product: kiwi),
      delivery: testDelivery(area: 'Jebel Ali', at: uaeTime(10)),
    );
    expect(inBox("Express isn't available in Jebel Ali yet"), findsOneWidget);
    expect(find.textContaining('Express: Express'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
