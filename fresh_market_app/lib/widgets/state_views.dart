import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// Centred ink spinner for a first load.
class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.padding = const EdgeInsets.all(32)});

  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: padding,
        child: const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: AppColors.ink,
          ),
        ),
      ),
    );
  }
}

/// An off-white placeholder block for loading skeletons.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.radius = 6,
  });

  /// Null fills the available width.
  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.skeleton,
        borderRadius: BorderRadius.all(Radius.circular(radius)),
      ),
    );
  }
}

/// A product-card-shaped placeholder: white card with an off-white image
/// well and three text bars. Size it like a card ([ProductCard.railWidth]
/// wide and [ProductCard.heightOf] high in rails, a grid cell in grids).
class ProductCardSkeleton extends StatelessWidget {
  const ProductCardSkeleton({super.key, this.wellHeight = 128});

  /// Matches the card's image well.
  final double wellHeight;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: AppDecor.card,
      padding: const EdgeInsets.all(8),
      child: ClipRect(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: wellHeight, decoration: AppDecor.well),
            const SizedBox(height: 12),
            const SkeletonBox(width: 112, height: 12),
            const SizedBox(height: 8),
            const SkeletonBox(width: 72, height: 10),
            const SizedBox(height: 12),
            const SkeletonBox(width: 64, height: 14),
          ],
        ),
      ),
    );
  }
}

/// A load failure with a "Try again" button. Pass
/// `ApiException.userMessage` as [message].
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    required this.message,
    required this.onRetry,
    this.compact = false,
  });

  final String message;
  final VoidCallback onRetry;

  /// A single row for use inside a rail or at the end of a list.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppDims.gutter,
          vertical: 8,
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
          decoration: AppDecor.info,
          child: Row(
            children: [
              const Icon(
                Icons.wifi_off_rounded,
                size: 20,
                color: AppColors.secondary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: AppText.bodySmall.copyWith(
                    color: AppColors.secondary,
                  ),
                ),
              ),
              TextButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    return _Message(
      icon: Icons.wifi_off_rounded,
      title: 'Could not load',
      message: message,
      actionLabel: 'Try again',
      onAction: onRetry,
    );
  }
}

/// A friendly empty state, with an ink outlined button (back to shopping)
/// when [actionLabel] and [onAction] are given.
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.shopping_basket_outlined,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return _Message(
      icon: icon,
      title: title,
      message: message,
      actionLabel: actionLabel,
      onAction: onAction,
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColors.subtle,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 32, color: AppColors.ink),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppText.heading,
            ),
            if (message != null) ...[
              const SizedBox(height: 6),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: AppText.body.copyWith(color: AppColors.secondary),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
