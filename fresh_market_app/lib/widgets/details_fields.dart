import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../profile/customer_details.dart';
import '../theme/app_theme.dart';

/// The text field of the details forms (My details, an address, the
/// checkout sheet): the theme's off-white field with its label always
/// shown above the typed text, the hint inside, and errors in ink (never
/// red) with an icon, so they read without colour.
class DetailsField extends StatelessWidget {
  const DetailsField({
    super.key,
    required this.controller,
    required this.label,
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
  });

  final TextEditingController controller;

  /// Shown above the typed text and read out as the field's name.
  final String label;
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

  /// Error messages: ink, never red, with an icon.
  static final TextStyle errorStyle = AppText.caption.copyWith(
    color: AppColors.ink,
    fontWeight: FontWeight.w600,
  );

  static const OutlineInputBorder _errorBorder = OutlineInputBorder(
    borderRadius: AppDims.controlBorderRadius,
    borderSide: BorderSide(color: AppColors.ink, width: 1.5),
  );

  @override
  Widget build(BuildContext context) {
    final limit = maxLength;
    return TextFormField(
      key: fieldKey,
      controller: controller,
      focusNode: focusNode,
      validator: validator,
      autofillHints: autofillHints,
      keyboardType: maxLines > 1 ? TextInputType.multiline : keyboardType,
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
            child: Icon(Icons.error_outline, size: 15, color: AppColors.ink),
          ),
          const SizedBox(width: 4),
          Expanded(child: Text(message, style: errorStyle)),
        ],
      ),
      style: AppText.body,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        floatingLabelBehavior: FloatingLabelBehavior.always,
        labelStyle: AppText.body.copyWith(color: AppColors.secondary),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith(
          (states) => AppText.label.copyWith(
            color: states.contains(WidgetState.focused) ||
                    states.contains(WidgetState.error)
                ? AppColors.ink
                : AppColors.secondary,
          ),
        ),
        errorBorder: _errorBorder,
        focusedErrorBorder: _errorBorder,
        counterStyle: AppText.caption,
        contentPadding: const EdgeInsets.fromLTRB(14, 22, 14, 12),
      ),
    );
  }
}

/// The small off-white tag with an address's label ("Home") and its icon.
class AddressLabelTag extends StatelessWidget {
  const AddressLabelTag({super.key, required this.label});

  final AddressLabel label;

  @override
  Widget build(BuildContext context) => SmallTag(
    text: label.label,
    icon: addressLabelIcon(label),
  );
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
  const SmallTag({super.key, required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: const ShapeDecoration(
        color: AppColors.subtle,
        shape: StadiumBorder(),
      ),
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The note under the Save buttons: where the details are kept.
class PrivacyNote extends StatelessWidget {
  const PrivacyNote({super.key});

  static const String text =
      'Saved only on this phone, encrypted. Used only to fill in your '
      'checkout.';

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 1),
          child: Icon(Icons.lock_outline, size: 14, color: AppColors.secondary),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(text, style: AppText.caption),
        ),
      ],
    );
  }
}

/// A full-screen form page: back button and 24/800 title, the scrolling
/// [children], and a white bar pinned at the bottom with the green
/// [saveLabel] button (52pt) and [note] under it.
class DetailsPage extends StatelessWidget {
  const DetailsPage({
    super.key,
    required this.title,
    required this.children,
    required this.saveLabel,
    required this.onSave,
    this.note,
    this.saveKey,
  });

  final String title;
  final List<Widget> children;
  final String saveLabel;
  final VoidCallback onSave;
  final Widget? note;
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
                  _BackButton(),
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
                    10,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton(
                        key: saveKey,
                        onPressed: onSave,
                        child: Text(saveLabel, textAlign: TextAlign.center),
                      ),
                      if (note != null) ...[
                        const SizedBox(height: 8),
                        note!,
                      ],
                    ],
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

/// The round back button of the form pages (pops the page).
class _BackButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Back',
      excludeSemantics: true,
      onTap: () => Navigator.of(context).maybePop(),
      child: Tooltip(
        message: 'Back',
        child: DecoratedBox(
          decoration: const ShapeDecoration(
            shape: CircleBorder(),
            shadows: AppShadows.raised,
          ),
          child: Material(
            color: AppColors.surface,
            shape: const CircleBorder(
              side: BorderSide(color: AppColors.hairline),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.of(context).maybePop(),
              child: const SizedBox(
                width: AppDims.touch,
                height: AppDims.touch,
                child: Icon(Icons.arrow_back, size: 22, color: AppColors.ink),
              ),
            ),
          ),
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
/// and returns its message (to announce), or null when all are right.
String? focusFirstError(
  List<GlobalKey<FormFieldState<String>>> keys,
  Map<GlobalKey<FormFieldState<String>>, FocusNode> nodes,
) {
  for (final key in keys) {
    final state = key.currentState;
    if (state != null && state.hasError) {
      nodes[key]?.requestFocus();
      return state.errorText;
    }
  }
  return null;
}
