import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app_nav.dart';
import '../delivery/delivery.dart';
import '../profile/customer_details.dart';
import '../state/profile_store.dart';
import '../theme/app_theme.dart';
import 'details_fields.dart';

/// The "Deliver to" card on the cart, under the delivery card: the saved
/// address checkout will be filled in with and the contact line, with
/// "Change". When no saved address is in the delivery area it offers the
/// one elsewhere or a new one here; with nothing saved it is a quiet row
/// that leads to "My details".
class CartDeliverToCard extends StatelessWidget {
  const CartDeliverToCard({super.key});

  static const String quietLabel =
      'Add your details to fill in checkout faster';

  /// "Your Home address is in Dubai Marina."
  static String elsewhereTitle(SavedAddress address) =>
      'Your ${address.label.label} address is in ${address.area.name}.';

  /// "Add one in Business Bay", or "Add address" with no area.
  static String addHereLabel(DeliveryArea? area) =>
      area == null ? 'Add address' : 'Add one in ${area.name}';

  /// "Sara Ahmed · +971 50 123 4567".
  static String contactLine(ContactDetails contact) => [
    contact.fullName,
    contact.mobileDisplay,
  ].where((p) => p.isNotEmpty).join(' · ');

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileStore>();
    final area = context.select<DeliveryStore, DeliveryArea?>((s) => s.area);
    if (!profile.hasDetails) return const _QuietRow();

    final contact = contactLine(profile.contact);
    final address = profile.addressFor(area);
    final elsewhere = profile.addressElsewhere(area);
    void change() => changeCartAddress(context);

    if (address != null) {
      return _Card(
        icon: addressLabelIcon(address.label),
        title: 'Deliver to',
        tag: AddressLabelTag(label: address.label, color: AppColors.surface),
        semantics:
            'Deliver to ${address.semantics}'
            '${contact.isEmpty ? '' : '. $contact'}',
        lines: [
          (address.firstLine, true),
          (address.area.label, false),
          if (contact.isNotEmpty) (contact, false),
        ],
        action: TextButton(
          key: const ValueKey('deliver-to-change'),
          onPressed: change,
          child: const Text('Change', semanticsLabel: 'Change address'),
        ),
      );
    }

    if (elsewhere != null) {
      return _Card(
        icon: Icons.place_outlined,
        title: elsewhereTitle(elsewhere),
        lines: [if (contact.isNotEmpty) (contact, false)],
        action: profile.addresses.length > 1
            ? TextButton(
                key: const ValueKey('deliver-to-change'),
                onPressed: change,
                child: const Text('Change', semanticsLabel: 'Change address'),
              )
            : null,
        footer: Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton(
              key: const ValueKey('deliver-there'),
              style: AppButtons.outline.copyWith(
                minimumSize: const WidgetStatePropertyAll(
                  Size(64, AppDims.touch),
                ),
              ),
              onPressed: () => AppNav.deliverTo(context, elsewhere),
              child: const Text('Deliver there'),
            ),
            TextButton(
              key: const ValueKey('add-here'),
              onPressed: () => addCartAddress(context),
              child: Text(addHereLabel(area)),
            ),
          ],
        ),
      );
    }

    // Contact details only.
    return _Card(
      icon: Icons.person_outline,
      title: 'Deliver to',
      lines: [(contact, true)],
      action: TextButton(
        key: const ValueKey('deliver-to-edit'),
        onPressed: () => AppNav.openMyDetails(context),
        child: const Text('Edit', semanticsLabel: 'Edit my details'),
      ),
      footer: Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton.icon(
          key: const ValueKey('add-here'),
          onPressed: () => addCartAddress(context),
          icon: const Icon(Icons.add, size: 18),
          label: Text(
            area == null
                ? 'Add your address'
                : 'Add your address in ${area.name}',
          ),
        ),
      ),
    );
  }
}

/// Adds an address in the delivery area from the cart and delivers there.
Future<void> addCartAddress(BuildContext context) async {
  final area = context.read<DeliveryStore>().area;
  final saved = await AppNav.openAddress(context, area: area);
  if (saved != null && context.mounted) AppNav.deliverTo(context, saved);
}

/// "Change" on the cart's "Deliver to" card: the saved addresses as radio
/// rows and "Add new address". Choosing one in another area moves the
/// delivery location there.
Future<void> changeCartAddress(BuildContext context) async {
  final profile = context.read<ProfileStore>();
  final area = context.read<DeliveryStore>().area;
  final current = profile.addressFor(area);
  final choice = await showModalBottomSheet<String>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => AddressSheet(
      addresses: profile.addresses,
      selectedId: current?.id,
      defaultId: profile.defaultAddress?.id,
      canAdd: profile.canAddAddress,
    ),
  );
  if (choice == null || !context.mounted) return;
  if (choice == AddressSheet.addNew) {
    await addCartAddress(context);
    return;
  }
  final address = profile.addressById(choice);
  if (address != null) AppNav.deliverTo(context, address);
}

/// The address sheet of the cart: one radio row per saved address and
/// "Add new address". Closes with the chosen address id, or [addNew].
class AddressSheet extends StatelessWidget {
  const AddressSheet({
    super.key,
    required this.addresses,
    required this.selectedId,
    required this.defaultId,
    required this.canAdd,
  });

  /// What the sheet closes with for "Add new address".
  static const String addNew = '+new';

  static const String title = 'Deliver to';
  static const String note =
      'An address in another area changes your delivery location.';

  final List<SavedAddress> addresses;
  final String? selectedId;
  final String? defaultId;
  final bool canAdd;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppDims.gutter,
          0,
          AppDims.gutter,
          AppDims.gutter,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Semantics(
              header: true,
              child: const Text(title, style: AppText.heading),
            ),
            const SizedBox(height: 4),
            Text(
              note,
              style: AppText.bodySmall.copyWith(color: AppColors.secondary),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: AppDecor.card,
              clipBehavior: Clip.antiAlias,
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  children: [
                    for (final (i, a) in addresses.indexed) ...[
                      if (i > 0) const Divider(height: 1, indent: 52),
                      _RadioRow(
                        key: ValueKey('address-option-${a.id}'),
                        address: a,
                        selected: a.id == selectedId,
                        isDefault: a.id == defaultId,
                        onTap: () => Navigator.of(context).pop(a.id),
                      ),
                    ],
                    if (canAdd) ...[
                      if (addresses.isNotEmpty)
                        const Divider(height: 1, indent: 52),
                      InkWell(
                        key: const ValueKey('address-option-new'),
                        onTap: () => Navigator.of(context).pop(addNew),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 56),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.add, size: 22, color: AppColors.ink),
                                SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    'Add new address',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One address in the sheet: an ink radio mark, its label (and
/// "Default"), the building and flat, and the area.
class _RadioRow extends StatelessWidget {
  const _RadioRow({
    super.key,
    required this.address,
    required this.selected,
    required this.isDefault,
    required this.onTap,
  });

  final SavedAddress address;
  final bool selected;
  final bool isDefault;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      checked: selected,
      inMutuallyExclusiveGroup: true,
      label: '${address.semantics}${isDefault ? ', default' : ''}',
      onTap: onTap,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: Icon(
                    selected
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    size: 22,
                    color: selected ? AppColors.ink : AppColors.tertiary,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: AddressSummary(address: address, isDefault: isDefault),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An address as listed: its label tag (and "Default"), the building and
/// flat, then the area.
class AddressSummary extends StatelessWidget {
  const AddressSummary({
    super.key,
    required this.address,
    required this.isDefault,
  });

  final SavedAddress address;
  final bool isDefault;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            AddressLabelTag(label: address.label),
            if (isDefault) const SmallTag(text: 'Default'),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          address.firstLine,
          style: AppText.body.copyWith(fontWeight: FontWeight.w600),
        ),
        Text(
          address.area.label,
          style: AppText.bodySmall.copyWith(color: AppColors.secondary),
        ),
      ],
    );
  }
}

/// The off-white info card of the "Deliver to" states (as the delivery
/// card above it): a round white icon, the title, lines (ink first, then
/// grey), an action at the end and an optional footer.
class _Card extends StatelessWidget {
  const _Card({
    required this.icon,
    required this.title,
    required this.lines,
    this.tag,
    this.action,
    this.footer,
    this.semantics,
  });

  final IconData icon;
  final String title;
  final Widget? tag;

  /// Each line with true for ink, false for grey.
  final List<(String, bool)> lines;
  final Widget? action;
  final Widget? footer;

  /// What screen readers hear for the title and lines together.
  final String? semantics;

  @override
  Widget build(BuildContext context) {
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 2,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(title, style: AppText.cardHeading.copyWith(fontSize: 15)),
            ?tag,
          ],
        ),
        for (final (line, ink) in lines)
          Text(
            line,
            style: AppText.bodySmall.copyWith(
              color: ink ? AppColors.ink : AppColors.secondary,
            ),
          ),
      ],
    );
    // Its own node, apart from the delivery card above it.
    return Semantics(
      container: true,
      child: Container(
        key: const ValueKey('cart-deliver-to'),
        decoration: AppDecor.info,
        padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 4, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 36,
                  height: 36,
                  margin: const EdgeInsets.only(top: 2),
                  decoration: const BoxDecoration(
                    color: AppColors.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 20, color: AppColors.ink),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: semantics == null
                        ? Semantics(container: true, child: text)
                        : Semantics(
                            container: true,
                            label: semantics,
                            excludeSemantics: true,
                            child: text,
                          ),
                  ),
                ),
                ?action,
              ],
            ),
            if (footer != null)
              Padding(
                // Under the text column (the 36px icon and its 10px gap, less
                // the button's own 8px padding), as on the delivery card.
                padding: const EdgeInsetsDirectional.only(start: 38, top: 6),
                child: footer,
              ),
          ],
        ),
      ),
    );
  }
}

/// With nothing saved: a quiet row (no green) that leads to "My details".
class _QuietRow extends StatelessWidget {
  const _QuietRow();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      child: Material(
        key: const ValueKey('cart-deliver-to'),
        color: AppColors.subtle,
        borderRadius: AppDims.wellBorderRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => AppNav.openMyDetails(context),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppDims.controlTarget),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.person_outline, size: 20, color: AppColors.ink),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      CartDeliverToCard.quietLabel,
                      style: AppText.bodySmall,
                    ),
                  ),
                  SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: AppColors.tertiary,
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

/// The first checkout with nothing saved: "Fill in checkout faster" with
/// name, mobile, email and the building and flat in [area], "Save for
/// next time" (on), the green "Continue to checkout" and "Skip, fill in at
/// checkout". Null when the sheet was closed (the shopper stays on the
/// cart).
Future<CheckoutSheetResult?> showCheckoutDetailsSheet(
  BuildContext context, {
  required DeliveryArea area,
  CheckoutDetails? initial,
}) => showModalBottomSheet<CheckoutSheetResult>(
  context: context,
  useRootNavigator: true,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (_) => CheckoutDetailsSheet(area: area, initial: initial),
);

class CheckoutDetailsSheet extends StatefulWidget {
  const CheckoutDetailsSheet({super.key, required this.area, this.initial});

  final DeliveryArea area;

  /// Details typed earlier for one checkout.
  final CheckoutDetails? initial;

  static const String title = 'Fill in checkout faster';
  static const String continueLabel = 'Continue to checkout';
  static const String skipLabel = 'Skip, fill in at checkout';
  static const String saveLabel = 'Save for next time';
  static const String flatWithoutBuilding =
      'Add the building or villa too, or leave the flat empty.';

  static String intro(DeliveryArea area) =>
      'Add your details once and checkout opens already filled in. '
      'Delivering to ${area.label}.';

  @override
  State<CheckoutDetailsSheet> createState() => _CheckoutDetailsSheetState();
}

class _CheckoutDetailsSheetState extends State<CheckoutDetailsSheet> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _first;
  late final TextEditingController _last;
  late final TextEditingController _mobile;
  late final TextEditingController _email;
  late final TextEditingController _building;
  late final TextEditingController _flat;
  final _mobileKey = GlobalKey<FormFieldState<String>>();
  final _emailKey = GlobalKey<FormFieldState<String>>();
  final _buildingKey = GlobalKey<FormFieldState<String>>();
  final _mobileNode = FocusNode();
  final _emailNode = FocusNode();
  final _buildingNode = FocusNode();
  bool _save = true;
  bool _tried = false;

  @override
  void initState() {
    super.initState();
    final contact = widget.initial?.contact ?? ContactDetails.empty;
    final address = widget.initial?.address;
    final here =
        address != null && CustomerInput.sameArea(address.area, widget.area);
    _first = TextEditingController(text: contact.firstName);
    _last = TextEditingController(text: contact.lastName);
    _mobile = TextEditingController(text: contact.mobileDisplay);
    _email = TextEditingController(text: contact.email);
    _building = TextEditingController(text: here ? address.building : '');
    _flat = TextEditingController(text: here ? address.flat : '');
    if (widget.initial != null) _save = false;
  }

  @override
  void dispose() {
    for (final c in [_first, _last, _mobile, _email, _building, _flat]) {
      c.dispose();
    }
    for (final n in [_mobileNode, _emailNode, _buildingNode]) {
      n.dispose();
    }
    super.dispose();
  }

  String? _validateBuilding(String? value) =>
      CustomerInput.cleanLine(value ?? '').isEmpty &&
          CustomerInput.cleanLine(_flat.text).isNotEmpty
      ? CheckoutDetailsSheet.flatWithoutBuilding
      : null;

  void _continue() {
    setState(() => _tried = true);
    // The form says the first error to screen readers itself.
    if (!_form.currentState!.validate()) {
      focusFirstError(
        [_mobileKey, _emailKey, _buildingKey],
        {
          _mobileKey: _mobileNode,
          _emailKey: _emailNode,
          _buildingKey: _buildingNode,
        },
        {_mobileKey: _mobile, _emailKey: _email, _buildingKey: _building},
      );
      return;
    }
    Navigator.of(context).pop(
      CheckoutSheetResult(
        contact: ContactDetails(
          firstName: CustomerInput.cleanLine(_first.text),
          lastName: CustomerInput.cleanLine(_last.text),
          mobile: CustomerInput.normaliseMobile(_mobile.text) ?? '',
          email: _email.text.trim(),
        ),
        building: CustomerInput.cleanLine(_building.text),
        flat: CustomerInput.cleanLine(_flat.text),
        save: _save,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: media.size.height * 0.88),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.fromLTRB(
                  AppDims.gutter,
                  0,
                  AppDims.gutter,
                  12,
                ),
                child: Form(
                  key: _form,
                  child: AutofillGroup(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Semantics(
                          header: true,
                          child: const Text(
                            CheckoutDetailsSheet.title,
                            style: AppText.heading,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          CheckoutDetailsSheet.intro(widget.area),
                          style: AppText.bodySmall.copyWith(
                            color: AppColors.secondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FieldPair(
                          first: DetailsField(
                            controller: _first,
                            label: 'First name',
                            autofillHints: const [AutofillHints.givenName],
                            keyboardType: TextInputType.name,
                            textCapitalization: TextCapitalization.words,
                            maxLength: CustomerInput.nameMax,
                          ),
                          second: DetailsField(
                            controller: _last,
                            label: 'Last name',
                            autofillHints: const [AutofillHints.familyName],
                            keyboardType: TextInputType.name,
                            textCapitalization: TextCapitalization.words,
                            maxLength: CustomerInput.nameMax,
                          ),
                        ),
                        const SizedBox(height: 12),
                        DetailsField(
                          fieldKey: _mobileKey,
                          focusNode: _mobileNode,
                          controller: _mobile,
                          label: 'Mobile',
                          hint: mobileHint,
                          autofillHints: const [AutofillHints.telephoneNumber],
                          keyboardType: TextInputType.phone,
                          maxLength: 24,
                          validator: CustomerInput.validateMobile,
                          validateWhileTyping: _tried,
                        ),
                        const SizedBox(height: 12),
                        DetailsField(
                          fieldKey: _emailKey,
                          focusNode: _emailNode,
                          controller: _email,
                          label: 'Email',
                          hint: emailHint,
                          autofillHints: const [AutofillHints.email],
                          keyboardType: TextInputType.emailAddress,
                          maxLength: CustomerInput.emailMax,
                          validator: CustomerInput.validateEmail,
                          validateWhileTyping: _tried,
                        ),
                        const SizedBox(height: 16),
                        Semantics(
                          header: true,
                          child: Text(
                            'Your address in ${widget.area.name}',
                            style: AppText.cardHeading.copyWith(fontSize: 15),
                          ),
                        ),
                        const SizedBox(height: 10),
                        FieldPair(
                          first: DetailsField(
                            fieldKey: _buildingKey,
                            focusNode: _buildingNode,
                            controller: _building,
                            label: 'Building or villa',
                            autofillHints: const [
                              AutofillHints.streetAddressLine1,
                            ],
                            keyboardType: TextInputType.streetAddress,
                            textCapitalization: TextCapitalization.words,
                            maxLength: CustomerInput.buildingMax,
                            validator: _validateBuilding,
                            validateWhileTyping: _tried,
                          ),
                          second: DetailsField(
                            controller: _flat,
                            label: 'Flat, floor',
                            autofillHints: const [
                              AutofillHints.streetAddressLine3,
                            ],
                            textInputAction: TextInputAction.done,
                            maxLength: CustomerInput.flatMax,
                            onSubmitted: (_) => _continue(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        DetailsSwitchRow(
                          key: const ValueKey('sheet-save'),
                          label: CheckoutDetailsSheet.saveLabel,
                          subtitle: 'Encrypted, only on this phone.',
                          value: _save,
                          onChanged: (value) => setState(() => _save = value),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            DecoratedBox(
              decoration: AppDecor.stickyBar,
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppDims.gutter,
                    12,
                    AppDims.gutter,
                    4,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton(
                        key: const ValueKey('sheet-continue'),
                        onPressed: _continue,
                        child: const Text(
                          CheckoutDetailsSheet.continueLabel,
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                        key: const ValueKey('sheet-skip'),
                        onPressed: () =>
                            Navigator.of(context)
                                .pop(const CheckoutSheetResult.skip()),
                        child: const Text(
                          CheckoutDetailsSheet.skipLabel,
                          textAlign: TextAlign.center,
                        ),
                      ),
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
