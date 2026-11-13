import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app_nav.dart';
import '../delivery/delivery.dart';
import '../profile/customer_details.dart';
import '../state/profile_store.dart';
import '../theme/app_theme.dart';
import '../widgets/a11y.dart';
import '../widgets/details_fields.dart';

/// Adds or edits a delivery address: its label (Home, Office, Other), the
/// area from the location picker (the emirate follows the area), the
/// building or villa, street, flat or floor, delivery instructions and
/// whether it is the default. Closes with the saved address, or null.
class AddressScreen extends StatefulWidget {
  const AddressScreen({super.key, this.address, this.initialArea});

  /// The address to edit; null adds one.
  final SavedAddress? address;

  /// Where a new address starts (the delivery area).
  final DeliveryArea? initialArea;

  static const String addTitle = 'Add address';
  static const String editTitle = 'Edit address';
  static const String saveLabel = 'Save address';
  static const String areaError = 'Choose the area this address is in.';
  static const String defaultLabel = 'Make this my default address';
  static const String deleteLabel = 'Delete this address';

  @override
  State<AddressScreen> createState() => _AddressScreenState();
}

class _AddressScreenState extends State<AddressScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _building;
  late final TextEditingController _street;
  late final TextEditingController _flat;
  late final TextEditingController _notes;
  final _buildingKey = GlobalKey<FormFieldState<String>>();
  final _buildingNode = FocusNode();

  late AddressLabel _label;
  DeliveryArea? _area;
  late bool _makeDefault;
  bool _tried = false;

  @override
  void initState() {
    super.initState();
    final profile = context.read<ProfileStore>();
    final a = widget.address;
    _building = TextEditingController(text: a?.building ?? '');
    _street = TextEditingController(text: a?.street ?? '');
    _flat = TextEditingController(text: a?.flat ?? '');
    _notes = TextEditingController(text: a?.instructions ?? '');
    _area = a?.area ?? widget.initialArea;
    _makeDefault = a == null ? !profile.hasAddresses : profile.isDefault(a);
    _label = a?.label ?? _firstFreeLabel(profile);
  }

  /// Home for the first address, Office for the second, then Other.
  static AddressLabel _firstFreeLabel(ProfileStore profile) {
    final used = {for (final a in profile.addresses) a.label};
    if (!used.contains(AddressLabel.home)) return AddressLabel.home;
    if (!used.contains(AddressLabel.office)) return AddressLabel.office;
    return AddressLabel.other;
  }

  @override
  void dispose() {
    for (final c in [_building, _street, _flat, _notes]) {
      c.dispose();
    }
    _buildingNode.dispose();
    super.dispose();
  }

  Future<void> _changeArea() async {
    final picked = await AppNav.pickAddressArea(context, initial: _area);
    if (picked == null || !mounted) return;
    setState(() => _area = picked);
    announce(context, 'Area: ${picked.label}');
  }

  void _save() {
    setState(() => _tried = true);
    final valid = _form.currentState!.validate();
    final area = _area;
    if (!valid) {
      // The form says the error to screen readers itself.
      focusFirstError([_buildingKey], {_buildingKey: _buildingNode}, {
        _buildingKey: _building,
      });
      return;
    }
    if (area == null) {
      announce(context, AddressScreen.areaError);
      return;
    }
    final profile = context.read<ProfileStore>();
    final before = widget.address;
    final address = SavedAddress(
      id: before?.id ?? profile.newAddressId(),
      label: _label,
      area: area,
      building: CustomerInput.cleanLine(_building.text),
      street: CustomerInput.cleanLine(_street.text),
      flat: CustomerInput.cleanLine(_flat.text),
      instructions: CustomerInput.cleanNote(_notes.text),
    );
    final wasDefault = before != null && profile.isDefault(before);
    profile.saveAddress(address, makeDefault: _makeDefault);
    if (wasDefault && !_makeDefault) {
      // Another address becomes the default.
      for (final other in profile.addresses) {
        if (other.id != address.id) {
          profile.setDefault(other.id);
          break;
        }
      }
    }
    Navigator.of(context).pop(address);
  }

  Future<void> _delete() async {
    final address = widget.address;
    if (address == null) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this address?'),
        content: Text(
          '${address.label.label}: ${address.firstLine}, '
          '${address.area.label}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    context.read<ProfileStore>().removeAddress(address.id);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final area = _area;
    final editing = widget.address != null;
    return DetailsPage(
      title: editing ? AddressScreen.editTitle : AddressScreen.addTitle,
      saveLabel: AddressScreen.saveLabel,
      saveKey: const ValueKey('address-save'),
      onSave: _save,
      note: const PrivacyNote(),
      children: [
        Semantics(
          header: true,
          child: const Text('Label', style: AppText.label),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final label in AddressLabel.values)
              _LabelChoice(
                label: label,
                selected: label == _label,
                onTap: () => setState(() => _label = label),
              ),
          ],
        ),
        const SizedBox(height: 20),
        _AreaRow(area: area, onChange: _changeArea),
        if (_tried && area == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
            child: Row(
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
                Expanded(
                  child: Text(
                    AddressScreen.areaError,
                    style: DetailsField.errorStyle,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DetailsField(
                  fieldKey: _buildingKey,
                  focusNode: _buildingNode,
                  controller: _building,
                  label: 'Building or villa',
                  hint: 'Building name and number, or villa',
                  autofillHints: const [AutofillHints.streetAddressLine1],
                  keyboardType: TextInputType.streetAddress,
                  textCapitalization: TextCapitalization.words,
                  maxLength: CustomerInput.buildingMax,
                  validator: CustomerInput.validateBuilding,
                  validateWhileTyping: _tried,
                ),
                const SizedBox(height: 12),
                DetailsField(
                  controller: _street,
                  label: 'Street',
                  optional: true,
                  autofillHints: const [AutofillHints.streetAddressLine2],
                  keyboardType: TextInputType.streetAddress,
                  textCapitalization: TextCapitalization.words,
                  maxLength: CustomerInput.streetMax,
                ),
                const SizedBox(height: 12),
                DetailsField(
                  controller: _flat,
                  label: 'Flat, floor',
                  optional: true,
                  hint: 'Flat or office number, floor',
                  autofillHints: const [AutofillHints.streetAddressLine3],
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: CustomerInput.flatMax,
                ),
                const SizedBox(height: 12),
                DetailsField(
                  controller: _notes,
                  label: 'Delivery instructions',
                  optional: true,
                  hint: 'For the driver, like "Call when you arrive"',
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.done,
                  maxLength: CustomerInput.instructionsMax,
                  showCounter: true,
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        DetailsSwitchRow(
          key: const ValueKey('address-default'),
          label: AddressScreen.defaultLabel,
          subtitle: 'Used at checkout when you deliver to its area.',
          value: _makeDefault,
          onChanged: (value) => setState(() => _makeDefault = value),
        ),
        if (editing) ...[
          const SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('address-delete'),
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline, size: 20),
              label: const Text(AddressScreen.deleteLabel),
            ),
          ),
        ],
      ],
    );
  }
}

/// One of Home, Office, Other: a pill with its icon; the chosen one has a
/// 2px ink edge (as the size choices on product detail).
class _LabelChoice extends StatelessWidget {
  const _LabelChoice({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final AddressLabel label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: label.label,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: AppColors.surface,
        shape: StadiumBorder(
          side: selected
              ? const BorderSide(color: AppColors.ink, width: 2)
              : const BorderSide(color: AppColors.hairline),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: AppDims.touch,
              minWidth: 88,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(addressLabelIcon(label), size: 18, color: AppColors.ink),
                  const SizedBox(width: 6),
                  Text(
                    label.label,
                    style: AppText.body.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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

/// The area of the address (from the location picker) with "Change".
class _AreaRow extends StatelessWidget {
  const _AreaRow({required this.area, required this.onChange});

  final DeliveryArea? area;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final a = area;
    return Container(
      key: const ValueKey('address-area'),
      decoration: AppDecor.info,
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 4, 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: AppColors.surface,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.location_on_outlined,
              size: 20,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Semantics(
              container: true,
              label: a == null ? 'Area: not chosen' : 'Area: ${a.label}',
              excludeSemantics: true,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Area', style: AppText.caption),
                  Text(
                    a?.label ?? 'Choose the area',
                    style: AppText.body.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
          TextButton(
            onPressed: onChange,
            child: Text(
              a == null ? 'Choose' : 'Change',
              semanticsLabel: a == null ? 'Choose the area' : 'Change the area',
            ),
          ),
        ],
      ),
    );
  }
}
