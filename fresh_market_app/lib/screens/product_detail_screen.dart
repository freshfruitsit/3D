import 'package:material_ui/material_ui.dart';

import '../models/product.dart';
import '../theme/app_theme.dart';

/// STUB: replaced by the screen's owner. Keep the class name and
/// constructor(s): the shell and AppNav depend on them.
class ProductDetailScreen extends StatelessWidget {
  const ProductDetailScreen({super.key, required this.product});

  /// Always a full product (with variants).
  final Product product;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(child: Text(product.title, style: AppText.heading)),
      ),
    );
  }
}
