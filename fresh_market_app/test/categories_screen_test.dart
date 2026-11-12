import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/data/catalog.dart';
import 'package:fresh_market_app/screens/categories_screen.dart';
import 'package:fresh_market_app/screens/product_list_screen.dart';
import 'package:fresh_market_app/screens/search_screen.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/widgets/app_search_field.dart';
import 'package:fresh_market_app/widgets/category_tile.dart';

import 'support/test_app.dart';

void main() {
  testWidgets('shows the title, search field and all 12 tiles',
      (tester) async {
    await pumpScreen(tester, const CategoriesScreen());

    expect(find.text('Categories'), findsOneWidget);
    expect(find.byType(SearchFieldButton), findsOneWidget);
    expect(find.byType(CategoryTile), findsNWidgets(12));
    for (final c in Catalog.categories) {
      expect(find.text(c.label.toUpperCase()), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tile opens its collection list', (tester) async {
    final api = FakeShopifyApi.sample();
    await pumpScreen(tester, const CategoriesScreen(), api: api);

    await tester.tap(find.text('FRUITS'));
    await tester.pumpAndSettle();

    final list = tester.widget<ProductListScreen>(
      find.byType(ProductListScreen),
    );
    expect(list.handle, 'fruits');
    expect(list.title, 'Fruits');
    expect(api.calls, contains('collectionProducts(fruits, page 1)'));
    expect(find.byTooltip('Back'), findsOneWidget);
  });

  testWidgets('the search field opens Search', (tester) async {
    await pumpScreen(tester, const CategoriesScreen());

    await tester.tap(find.byType(SearchFieldButton));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(SearchScreen), findsOneWidget);
  });
}
