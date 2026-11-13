import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../profile/customer_details.dart';
import '../theme/app_theme.dart';
import 'circle_icon_button.dart';

/// The hints of the mobile and email fields: "e.g." so an empty field
/// never looks filled in.
const String mobileHint = 'e.g. +971 50 123 4567';
const String emailHint = 'e.g. name@example.com';

/// The text field of the details forms (My details, an address, the
/// checkout sheet): its label above it (13/600 ink, "optional" in grey),
/// then the theme's off-white field with the hint inside, and errors in
/// ink (never red) with an icon, so they read without colour. Screen
/// readers hear the label as the field's name.
class DetailsField extends StatelessWidget {
  const DetailsField({
    super.key,
    required this.controller,
    required this.label,
    this.optional = false,
    this.hint,
    this.focusNode,
    this.validator,
    this.autofillHints,
    this.keyboardType = TextInputType.text,
    this.textInputAction = TextInputAction.next,
    this.textCapitalization = TextCapitalization.none,
    this.maxLength,
    this.showCounter = false,
    this.maxLines = 1,
    this.onSubmitted,
    this.onChanged,
    this.fieldKey,
    this.validateWhileTyping = false,
  });

  final TextEditingController controller;

  /// Shown above the field and read out as its name.
  final String label;

  /// Adds "(optional)" after the label.
  final bool optional;
  final String? hint;
  final FocusNode? focusNode;
  final FormFieldValidator<String>? validator;
  final Iterable<String>? autofillHints;
  final TextInputType keyboardType;
  final TextInputAction textInputAction;
  final TextCapitalization textCapitalization;

  /// Typing stops at this many characters.
  final int? maxLength;

  /// Shows "12/200" under the field.
  final bool showCounter;
  final int maxLines;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;

  /// The [FormFieldState]'s key, to read or focus it from the form.
  final GlobalKey<FormFieldState<String>>? fieldKey;

  /// Checks the field as it is typed (once Save was tried), so an error
  /// clears as soon as it is fixed. Field by field: the form's own check
  /// would say its first error again on every key.
  final bool validateWhileTyping;

  /// Error messages: ink, never red, with an icon.
  static final TextStyle errorStyle = AppText.caption.copyWith(
    color: AppColors.ink,
    fontWeight: FontWeight.w600,
  );

  /// An error: an ink 1.5 edge (with the icon and message under it).
  static const OutlineInputBorder _errorBorder = OutlineInputBorder(
    borderRadius: AppDims.controlBorderRadius,
    borderSide: BorderSide(color: AppColors.ink, width: 1.5),
  );

  /// Focus, with or without an error: ink 2.5, always the heaviest edge,
  /// so the field typing goes to is seen among fields with errors.
  static const OutlineInputBorder _focusBorder = OutlineInputBorder(
    borderRadius: AppDims.controlBorderRadius,
    borderSide: BorderSide(color: AppColors.ink, width: 2.5),
  );

  @override
  Widget build(BuildContext context) {
    final limit = maxLength;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: Text.rich(
            TextSpan(
              text: label,
              children: [
                if (optional)
                  TextSpan(
                    text: ' (optional)',
                    style: AppText.label.copyWith(
                      color: AppColors.secondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
            style: AppText.label,
          ),
        ),
        const SizedBox(height: 8),
        Semantics(
          label: optional ? '$label, optional' : label,
          // Rebuilt as it is typed in: see hintMaxLines.
          child: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => TextFormField(
              key: fieldKey,
              controller: controller,
              focusNode: focusNode,
              validator: validator,
              autovalidateMode: validateWhileTyping
                  ? AutovalidateMode.onUserInteraction
                  : AutovalidateMode.disabled,
              autofillHints: autofillHints,
              keyboardType: maxLines > 1
                  ? TextInputType.multiline
                  : keyboardType,
              textInputAction: textInputAction,
              textCapitalization: textCapitalization,
              maxLines: maxLines,
              minLines: 1,
              maxLength: showCounter ? limit : null,
              maxLengthEnforcement: MaxLengthEnforcement.enforced,
              inputFormatters: [
                if (limit != null && !showCounter)
                  LengthLimitingTextInputFormatter(limit),
              ],
              onFieldSubmitted: onSubmitted,
              onChanged: onChanged,
              // An icon with the message, so an error does not rely on colour.
              errorBuilder: (context, message) => Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.error_outline,
                      size: 15,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(child: Text(message, style: errorStyle)),
                ],
              ),
              style: AppText.body,
              decoration: InputDecoration(
                hintText: hint,
                // A hint is the only place that shows the format: never cut
                // at a large font size. Only while it shows, so a filled
                // field is one line high again.
                hintMaxLines: controller.text.isEmpty ? 2 : 1,
                errorBorder: _errorBorder,
                focusedBorder: _focusBorder,
                focusedErrorBorder: _focusBorder,
                counterStyle: AppText.caption,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The small off-white tag with an address's label ("Home"); the row it
/// sits in shows the label's icon.
class AddressLabelTag extends StatelessWidget {
  const AddressLabelTag({
    super.key,
    required this.label,
    this.color = AppColors.subtle,
  });

  final AddressLabel label;

  /// The pill: off-white on white, white on an off-white card.
  final Color color;

  @override
  Widget build(BuildContext context) =>
      SmallTag(text: label.label, color: color);
}

/// The icon of an address label.
IconData addressLabelIcon(AddressLabel label) => switch (label) {
  AddressLabel.home => Icons.home_outlined,
  AddressLabel.office => Icons.work_outline,
  AddressLabel.other => Icons.place_outlined,
};

/// A small off-white pill with ink text ("Home", "Default", "Coming
/// soon").
class SmallTag extends StatelessWidget {
  const SmallTag({
    super.key,
    required this.text,
    this.icon,
    this.color = AppColors.subtle,
  });

  final String text;
  final IconData? icon;

  /// The pill's fill: [AppColors.subtle], or white on an off-white card.
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: ShapeDecoration(color: color, shape: const StadiumBorder()),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: AppColors.ink),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              style: AppText.caption.copyWith(
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A row with a label, an optional line under it and an ink switch (not
/// green: a toggle is not a buying action). The whole row toggles.
class DetailsSwitchRow extends StatelessWidget {
  const DetailsSwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final change = onChanged;
    return MergeSemantics(
      child: InkWell(
        onTap: change == null ? null : () => change(!value),
        borderRadius: AppDims.controlBorderRadius,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: AppDims.controlTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: AppText.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (subtitle != null)
                        Text(subtitle!, style: AppText.caption),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Switch(
                  value: value,
                  onChanged: change,
                  activeThumbColor: AppColors.onDark,
                  activeTrackColor: AppColors.ink,
                  // Off: a grey thumb and outline that keep 3:1 (WCAG
                  // 1.4.11), not the hairline.
                  inactiveThumbColor: AppColors.secondary,
                  inactiveTrackColor: AppColors.surface,
                  trackOutlineColor: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.selected)
                        ? AppColors.ink
                        : AppColors.secondary,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The note after a details form's fields: where the details are kept.
class PrivacyNote extends StatelessWidget {
  const PrivacyNote({super.key});

  static const String text =
      'Saved only on this phone, encrypted. Used only to fill in your '
      'checkout.';

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.lock_outline, size: 14, color: AppColors.secondary),
        ),
        const SizedBox(width: 6),
        Flexible(child: Text(text, style: AppText.caption)),
      ],
    );
  }
}

/// A full-screen form page: back button and 24/800 title, the scrolling
/// [children], and a white bar pinned at the bottom with only the green
/// [saveLabel] button (52pt), so at a large font size the bar stays small
/// and never covers an error (the [PrivacyNote] scrolls with the form).
class DetailsPage extends StatelessWidget {
  const DetailsPage({
    super.key,
    required this.title,
    required this.children,
    required this.saveLabel,
    required this.onSave,
    this.saveKey,
  });

  final String title;
  final List<Widget> children;
  final String saveLabel;
  final VoidCallback onSave;
  final Key? saveKey;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppDims.gutter,
                8,
                AppDims.gutter,
                8,
              ),
              child: Row(
                children: [
                  CircleIconButton.back(context),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Semantics(
                      header: true,
                      child: Text(title, style: AppText.title),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  AppDims.gutter,
                  8,
                  AppDims.gutter,
                  24,
                ),
                children: children,
              ),
            ),
            DecoratedBox(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.hairline)),
                boxShadow: AppShadows.sticky,
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppDims.gutter,
                    12,
                    AppDims.gutter,
                    12,
                  ),
                  child: FilledButton(
                    key: saveKey,
                    onPressed: onSave,
                    child: Text(saveLabel, textAlign: TextAlign.center),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Two fields side by side, or one under the other at a large font size
/// (above 1.3x), so neither label is cut.
class FieldPair extends StatelessWidget {
  const FieldPair({super.key, required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.textScalerOf(context).scale(10) / 10 > 1.3;
    if (large) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [first, const SizedBox(height: 12), second],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: first),
        const SizedBox(width: 12),
        Expanded(child: second),
      ],
    );
  }
}

/// Moves focus to the first field of [keys] whose form says it is wrong
/// (the cursor at the end of its text) and returns its message (to
/// announce), or null when all are right.
String? focusFirstError(
  List<GlobalKey<FormFieldState<String>>> keys,
  Map<GlobalKey<FormFieldState<String>>, FocusNode> nodes, [
  Map<GlobalKey<FormFieldState<String>>, TextEditingController> controllers =
      const {},
]) {
  for (final key in keys) {
    final state = key.currentState;
    if (state != null && state.hasError) {
      nodes[key]?.requestFocus();
      final controller = controllers[key];
      if (controller != null) {
        // Not the whole text selected, as a web field does on focus.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          controller.selection = TextSelection.collapsed(
            offset: controller.text.length,
          );
        });
      }
      return state.errorText;
    }
  }
  return null;
}
