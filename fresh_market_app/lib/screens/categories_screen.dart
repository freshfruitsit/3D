import 'package:material_ui/material_ui.dart';

import '../app_nav.dart';
import '../theme/app_theme.dart';
import '../widgets/app_search_field.dart';
import '../widgets/category_tile.dart';

/// The Categories tab: title, search field (opens Search) and the grid of
/// the 12 category tiles. Each tile opens its collection's product list.
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            AppDims.gutter,
            12,
            AppDims.gutter,
            AppDims.floatingSpace(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Semantics(
                header: true,
                child: const Text('Categories', style: AppText.title),
              ),
              const SizedBox(height: 12),
              SearchFieldButton(onTap: () => AppNav.openSearch(context)),
              const SizedBox(height: 16),
              const CategoryGrid(),
            ],
          ),
        ),
      ),
    );
  }
}
