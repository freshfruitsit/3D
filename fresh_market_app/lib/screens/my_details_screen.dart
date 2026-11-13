import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../profile/customer_details.dart';
import '../state/profile_store.dart';
import '../theme/app_theme.dart';
import '../widgets/details_fields.dart';

/// "My details": first and last name, mobile and email, all optional.
/// Saved encrypted on the phone and used only to fill in checkout. Closes
/// with what happened ([MyDetailsResult]), or null when nothing changed.
class MyDetailsScreen extends StatefulWidget {
  const MyDetailsScreen({super.key});

  static const String title = 'My details';
  static const String intro =
      'Checkout opens with these already filled in. You can still change '
      'them there.';
  static const String saveLabel = 'Save';

  /// Said after saving.
  static const String savedMessage = 'Your details are saved.';

  /// Said after clearing every field of saved details.
  static const String clearedMessage = 'Your details are cleared.';

  @override
  State<MyDetailsScreen> createState() => _MyDetailsScreenState();
}

/// What "Save" on [MyDetailsScreen] did.
enum MyDetailsResult {
  saved(MyDetailsScreen.savedMessage),
  cleared(MyDetailsScreen.clearedMessage);

  const MyDetailsResult(this.message);

  /// Said once the screen has closed.
  final String message;
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
    // The form says the first error to screen readers itself; focus goes
    // to that field.
    if (!form.validate()) {
      focusFirstError(
        [_mobileKey, _emailKey],
        {_mobileKey: _mobileNode, _emailKey: _emailNode},
        {_mobileKey: _mobile, _emailKey: _email},
      );
      return;
    }
    final profile = context.read<ProfileStore>();
    final before = profile.contact;
    final contact = ContactDetails(
      firstName: CustomerInput.cleanLine(_first.text),
      lastName: CustomerInput.cleanLine(_last.text),
      mobile: CustomerInput.normaliseMobile(_mobile.text) ?? '',
      email: _email.text.trim(),
    );
    profile.saveContact(contact);
    // Nothing typed and nothing saved before: nothing to confirm.
    Navigator.of(context).pop(
      contact.isEmpty
          ? (before.isEmpty ? null : MyDetailsResult.cleared)
          : MyDetailsResult.saved,
    );
  }

  @override
  Widget build(BuildContext context) {
    return DetailsPage(
      title: MyDetailsScreen.title,
      saveLabel: MyDetailsScreen.saveLabel,
      saveKey: const ValueKey('details-save'),
      onSave: _save,
      children: [
        Text(
          MyDetailsScreen.intro,
          style: AppText.bodySmall.copyWith(color: AppColors.secondary),
        ),
        const SizedBox(height: 20),
        Form(
          key: _form,
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
                  textInputAction: TextInputAction.done,
                  maxLength: CustomerInput.emailMax,
                  validator: CustomerInput.validateEmail,
                  validateWhileTyping: _tried,
                  onSubmitted: (_) => _save(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        const PrivacyNote(),
      ],
    );
  }
}
