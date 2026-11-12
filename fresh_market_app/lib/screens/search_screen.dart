import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// STUB: replaced by the screen's owner. Keep the class name and
/// constructor(s): the shell and AppNav depend on them.
class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key, this.initialQuery});

  /// Text to search for straight away (brand tiles, popular chips).
  final String? initialQuery;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(child: Text('Search', style: AppText.heading)),
      ),
    );
  }
}
