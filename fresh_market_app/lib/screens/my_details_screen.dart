import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../profile/customer_details.dart';
import '../state/profile_store.dart';
import '../theme/app_theme.dart';
import '../widgets/a11y.dart';
import '../widgets/details_fields.dart';

/// "My details": first and last name, mobile and email, all optional.
/// Saved encrypted on the phone and used only to fill in checkout. Closes
/// with true once saved.
class MyDetailsScreen extends StatefulWidget {
  const MyDetailsScreen({super.key});

  static const String title = 'My details';
  static const String intro =
      'Checkout opens with these already filled in. You can still change '
      'them there.';
  static const String saveLabel = 'Save';

  /// Said after saving.
  static const String savedMessage = 'Your details are saved.';

  @override
  State<MyDetailsScreen> createState() => _MyDetailsScreenState();
}

class _MyDetailsScreenState extends State<MyDetailsScreen> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _first;
  late final TextEditingController _last;
  late final TextEditingController _mobile;
  late final TextEditingController _email;

  final _mobileKey = GlobalKey<FormFieldState<String>>();
  final _emailKey = GlobalKey<FormFieldState<String>>();
  final _mobileNode = FocusNode();
  final _emailNode = FocusNode();

  /// Errors show while typing once Save was tried.
  bool _tried = false;

  @override
  void initState() {
    super.initState();
    final contact = context.read<ProfileStore>().contact;
    _first = TextEditingController(text: contact.firstName);
    _last = TextEditingController(text: contact.lastName);
    _mobile = TextEditingController(text: contact.mobileDisplay);
    _email = TextEditingController(text: contact.email);
  }

  @override
  void dispose() {
    for (final c in [_first, _last, _mobile, _email]) {
      c.dispose();
    }
    _mobileNode.dispose();
    _emailNode.dispose();
    super.dispose();
  }

  void _save() {
    setState(() => _tried = true);
    final form = _form.currentState!;
    if (!form.validate()) {
      final message = focusFirstError(
        [_mobileKey, _emailKey],
        {_mobileKey: _mobileNode, _emailKey: _emailNode},
      );
      if (message != null) announce(context, message);
      return;
    }
    context.read<ProfileStore>().saveContact(
      ContactDetails(
        firstName: CustomerInput.cleanLine(_first.text),
        lastName: CustomerInput.cleanLine(_last.text),
        mobile: CustomerInput.normaliseMobile(_mobile.text) ?? '',
        email: _email.text.trim(),
      ),
    );
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return DetailsPage(
      title: MyDetailsScreen.title,
      saveLabel: MyDetailsScreen.saveLabel,
      saveKey: const ValueKey('details-save'),
      onSave: _save,
      note: const PrivacyNote(),
      children: [
        Text(
          MyDetailsScreen.intro,
          style: AppText.bodySmall.copyWith(color: AppColors.secondary),
        ),
        const SizedBox(height: 20),
        Form(
          key: _form,
          autovalidateMode: _tried
              ? AutovalidateMode.onUserInteraction
              : AutovalidateMode.disabled,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                  hint: '+971 50 123 4567',
                  autofillHints: const [AutofillHints.telephoneNumber],
                  keyboardType: TextInputType.phone,
                  maxLength: 24,
                  validator: CustomerInput.validateMobile,
                ),
                const SizedBox(height: 12),
                DetailsField(
                  fieldKey: _emailKey,
                  focusNode: _emailNode,
                  controller: _email,
                  label: 'Email',
                  hint: 'name@example.com',
                  autofillHints: const [AutofillHints.email],
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  maxLength: CustomerInput.emailMax,
                  validator: CustomerInput.validateEmail,
                  onSubmitted: (_) => _save(),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
