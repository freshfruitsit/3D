import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// A 20/800 section heading with an optional green "View all" link.
/// Includes the page gutter by default.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.onViewAll,
    this.padding = const EdgeInsets.fromLTRB(AppDims.gutter, 0, 8, 0),
  });

  final String title;
  final VoidCallback? onViewAll;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppDims.touch),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                header: true,
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.heading,
                ),
              ),
            ),
            if (onViewAll != null)
              TextButton(
                onPressed: onViewAll,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('View all', semanticsLabel: 'View all $title'),
                    const SizedBox(width: 2),
                    const Icon(Icons.chevron_right, size: 20),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
