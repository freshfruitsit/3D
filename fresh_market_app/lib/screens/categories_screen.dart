import 'package:material_ui/material_ui.dart';

import '../app_nav.dart';
import '../theme/app_theme.dart';
import '../widgets/app_search_field.dart';
import '../widgets/category_tile.dart';
import '../widgets/section_header.dart';

/// The Categories tab on the white canvas: the ink "Categories" heading
/// tag, the off-white search field (opens Search) and the 4-column grid of
/// the 12 category tiles. Each tile opens its collection's product list.
class CategoriesScreen extends StatelessWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.only(
            top: 16,
            bottom: AppDims.floatingSpace(context),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // The heading tag runs in from the screen edge, like Home's.
              const Align(
                alignment: Alignment.centerLeft,
                child: SectionTag(
                  title: 'Categories',
                  icon: Icons.grid_view_rounded,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppDims.gutter,
                  16,
                  AppDims.gutter,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SearchFieldButton(onTap: () => AppNav.openSearch(context)),
                    const SizedBox(height: 20),
                    const CategoryGrid(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
