import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

/// The search input (Search screen, location picker): off-white fill, no
/// border, radius 12, 48px high. Shows a clear (x) button while it has
/// text; clearing also calls [onChanged] with an empty string.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    this.focusNode,
    this.autofocus = false,
    this.hintText = 'Search fruits, vegetables, meat…',
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(AppSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onText);
      widget.controller.addListener(_onText);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  void _onText() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.isNotEmpty;
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      textInputAction: TextInputAction.search,
      autocorrect: false,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
      style: AppText.body,
      cursorColor: AppColors.ink,
      decoration: InputDecoration(
        hintText: widget.hintText,
        hintStyle: AppText.body.copyWith(color: AppColors.secondary),
        filled: true,
        fillColor: AppColors.subtle,
        isDense: true,
        constraints: const BoxConstraints(minHeight: AppDims.fieldHeight),
        contentPadding: const EdgeInsets.symmetric(vertical: 14),
        border: _border,
        enabledBorder: _border,
        focusedBorder: _focusedBorder,
        prefixIcon: const Icon(Icons.search, color: AppColors.ink, size: 22),
        prefixIconConstraints: const BoxConstraints(minWidth: 46, minHeight: 44),
        suffixIcon: hasText
            ? IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.close, size: 20),
                color: AppColors.secondary,
                onPressed: () {
                  widget.controller.clear();
                  widget.onChanged?.call('');
                },
              )
            : null,
      ),
    );
  }
}

const OutlineInputBorder _border = OutlineInputBorder(
  borderRadius: AppDims.controlBorderRadius,
  borderSide: BorderSide.none,
);

const OutlineInputBorder _focusedBorder = OutlineInputBorder(
  borderRadius: AppDims.controlBorderRadius,
  borderSide: BorderSide(color: AppColors.ink, width: 1.5),
);

/// Looks like the search input but is a button: Home and Categories use it
/// to open the Search screen.
class SearchFieldButton extends StatelessWidget {
  const SearchFieldButton({
    super.key,
    required this.onTap,
    this.hintText = 'Search fruits, vegetables, meat…',
  });

  final VoidCallback onTap;
  final String hintText;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Search',
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: AppColors.subtle,
        shape: const RoundedRectangleBorder(
          borderRadius: AppDims.controlBorderRadius,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppDims.fieldHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  const Icon(Icons.search, color: AppColors.ink, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      hintText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.body.copyWith(color: AppColors.secondary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
