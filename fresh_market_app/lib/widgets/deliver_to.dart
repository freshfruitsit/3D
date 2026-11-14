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

  /// "Your Home address is in Dubai Marina." ("Your saved address" for
  /// one labelled Other).
  static String elsewhereTitle(SavedAddress address) {
    final whose = address.label == AddressLabel.other
        ? 'saved'
        : address.label.label;
    return 'Your $whose address is in ${address.area.name}.';
  }

  /// Under [elsewhereTitle]: what checkout does without an address here.
  static String elsewhereLine(DeliveryArea? area) => area == null
      ? 'Checkout will ask for your address.'
      : 'Checkout will ask for your building in ${area.name}.';

  /// "Add one in Business Bay", or "Add address" with no area.
  static String addHereLabel(DeliveryArea? area) =>
      area == null ? 'Add address' : 'Add one in ${area.name}';

  /// "Sara Ahmed · +971 50 123 4567" (the number kept on one line).
  static String contactLine(ContactDetails contact) => [
    contact.fullName,
    contact.mobileOneLine,
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
      // A calm prompt with two actions; "Change" comes back once an
      // address is chosen.
      return _Card(
        icon: Icons.place_outlined,
        title: elsewhereTitle(elsewhere),
        lines: [(elsewhereLine(area), false)],
        // The outlined button's border on the text column.
        footerPadding: const EdgeInsetsDirectional.only(start: 46, top: 8),
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
    this.footerPadding = const EdgeInsetsDirectional.only(start: 38, top: 6),
    this.semantics,
  });

  final IconData icon;
  final String title;
  final Widget? tag;

  /// Each line with true for ink, false for grey.
  final List<(String, bool)> lines;
  final Widget? action;
  final Widget? footer;

  /// Puts the footer under the text column (the 36px icon and its 10px
  /// gap): start 38 for a text button (less its own 8px padding), 46 for
  /// an outlined button, whose border is then on the column.
  final EdgeInsetsDirectional footerPadding;

  /// What screen readers hear for the title and lines together.
  final String? semantics;

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.textScalerOf(context).scale(10) / 10 > 1.3;
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
                if (!large) ?action,
              ],
            ),
            // At a large font size the action goes under the text, so the
            // lines keep the card's width (a mobile number stays whole).
            if (large && action != null)
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 38),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: action,
                ),
              ),
            if (footer != null) Padding(padding: footerPadding, child: footer),
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
