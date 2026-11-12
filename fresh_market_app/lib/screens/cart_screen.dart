import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// STUB: replaced by the screen's owner. Keep the class name and
/// constructor(s): the shell and AppNav depend on them.
class CartScreen extends StatelessWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(child: Text('Cart', style: AppText.heading)),
      ),
    );
  }
}
