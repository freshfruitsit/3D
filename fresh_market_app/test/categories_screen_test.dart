import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/data/catalog.dart';
import 'package:fresh_market_app/screens/categories_screen.dart';
import 'package:fresh_market_app/screens/product_list_screen.dart';
import 'package:fresh_market_app/screens/search_screen.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/widgets/app_search_field.dart';
import 'package:fresh_market_app/theme/app_theme.dart';
import 'package:fresh_market_app/widgets/category_tile.dart';
import 'package:fresh_market_app/widgets/section_header.dart';
import 'package:material_ui/material_ui.dart';

import 'support/test_app.dart';

void main() {
  testWidgets('shows the title, search field and all 12 tiles',
      (tester) async {
    await pumpScreen(tester, const CategoriesScreen());

    expect(find.text('Categories'), findsOneWidget);
    expect(find.byType(SearchFieldButton), findsOneWidget);
    expect(find.byType(CategoryTile), findsNWidgets(12));
    for (final c in Catalog.categories) {
      // Sentence case under the tile, as written in the catalogue.
      expect(find.text(c.label), findsOneWidget);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tile opens its collection list', (tester) async {
    final api = FakeShopifyApi.sample();
    await pumpScreen(tester, const CategoriesScreen(), api: api);

    await tester.tap(find.text('Fruits'));
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

  testWidgets('white canvas, the ink heading tag and a subtle search field',
      (tester) async {
    await pumpScreen(tester, const CategoriesScreen());
    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(scaffold.backgroundColor, AppColors.canvas);
    expect(
      find.descendant(
        of: find.byType(SectionTag),
        matching: find.text('Categories'),
      ),
      findsOneWidget,
    );
    expect(SectionTag.fill, AppColors.ink);
    final search = tester.widget<Material>(find
        .descendant(
          of: find.byType(SearchFieldButton),
          matching: find.byType(Material),
        )
        .first);
    expect(search.color, AppColors.subtle);
    // The grid starts below the search field, inside the gutter.
    final first = tester.getRect(find.byKey(const ValueKey('category-0')));
    expect(first.left, 16);
    expect(
      first.top,
      greaterThan(tester.getRect(find.byType(SearchFieldButton)).bottom),
    );
  });

  testWidgets('no overflow at 360dp with text scale 1.3', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpScreen(tester, const CategoriesScreen());
    tester.view.physicalSize = const Size(1080, 2340);
    await tester.pump();
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -600));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
