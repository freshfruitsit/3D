import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';

import '../app_nav.dart';
import '../assistant/assistant_brain.dart';
import '../delivery/delivery.dart';
import '../profile/customer_details.dart';
import '../state/account_session.dart';
import '../state/favourites_store.dart';
import '../state/profile_store.dart';
import '../theme/app_theme.dart';
import '../widgets/deliver_to.dart';
import '../widgets/details_fields.dart';
import 'assistant_screen.dart';
import 'intro_screen.dart';

/// The Account tab: the store account first (signed out, "Sign in to
/// order" with "Sign in with email"; signed in, who is signed in and "My
/// orders"), then the shopper's details for checkout ("Your details" and
/// the delivery addresses, saved encrypted on the phone), the delivery
/// location, the way into the favourites list, a replay of the intro, the
/// store's customer service ("Help & contact"), "Sign out" and "Delete my
/// details".
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key, this.launcher});

  /// Opens the phone, email and contact-page links of "Help & contact";
  /// [AssistantScreen.launchExternally] when null. Tests pass a stub.
  final AssistantLinkLauncher? launcher;

  static const String helpLabel = 'Help & contact';

  /// The second line of the "Help & contact" row: the store's toll-free
  /// number and email, as its website gives them.
  static const String helpSubtitle = '800 1 627538 \u00B7 care@freshmarket.ae';

  @override
  Widget build(BuildContext context) {
    final favourites = context.select<FavouritesStore, int>((s) => s.count);
    final area = context.select<DeliveryStore, DeliveryArea?>((s) => s.area);
    final hasDetails = context.select<ProfileStore, bool>((s) => s.hasDetails);
    final signedIn = context.select<AccountSession, bool>((s) => s.signedIn);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppDims.gutter,
            16,
            AppDims.gutter,
            AppDims.floatingSpace(context),
          ),
          children: [
            Semantics(
              header: true,
              child: const Text('Account', style: AppText.title),
            ),
            const SizedBox(height: 16),
            const _SessionCard(),
            const SizedBox(height: 16),
            const _DetailsCard(),
            const SizedBox(height: 24),
            const _AddressesSection(),
            const SizedBox(height: 24),
            // One white card, rows split by hairlines.
            Container(
              decoration: AppDecor.card,
              clipBehavior: Clip.antiAlias,
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  children: [
                    _AccountRow(
                      key: const ValueKey('account-location'),
                      icon: Icons.location_on_outlined,
                      label: 'Delivery location',
                      onTap: () => AppNav.openLocationPicker(context),
                      // The area, as in the Home chip.
                      subtitle: area == null
                          ? DeliveryCopy.chipLabel(null)
                          : area.label,
                    ),
                    const Divider(height: 1, indent: 52),
                    _AccountRow(
                      // Ink either way: filled when something is saved.
                      icon: favourites > 0
                          ? Icons.favorite
                          : Icons.favorite_border,
                      label: 'Favourites',
                      onTap: () => AppNav.openFavourites(context),
                      trailing: Text(
                        '$favourites',
                        semanticsLabel: favourites == 1
                            ? '1 saved product'
                            : '$favourites saved products',
                        style: AppText.bodySmall.copyWith(
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Divider(height: 1, indent: 52),
                    _AccountRow(
                      icon: Icons.play_circle_outline,
                      label: 'Watch the intro again',
                      onTap: () => _watchIntro(context),
                    ),
                    const Divider(height: 1, indent: 52),
                    _AccountRow(
                      key: const ValueKey('account-help'),
                      icon: Icons.support_agent_outlined,
                      label: helpLabel,
                      subtitle: helpSubtitle,
                      // Read as words, not as a run of digits and a dot.
                      subtitleSemantics:
                          'Call 800 1 627538 or email care@freshmarket.ae',
                      onTap: () => _showHelp(context),
                    ),
                  ],
                ),
              ),
            ),
            if (signedIn || hasDetails) const SizedBox(height: 16),
            if (signedIn)
              _BottomAction(
                key: const ValueKey('sign-out'),
                icon: Icons.logout,
                label: signOutLabel,
                onPressed: () => AppNav.signOut(context),
              ),
            if (hasDetails)
              _BottomAction(
                key: const ValueKey('delete-details'),
                icon: Icons.delete_outline,
                label: deleteLabel,
                onPressed: () => _confirmDelete(context),
              ),
          ],
        ),
      ),
    );
  }

  static const String deleteLabel = 'Delete my details';
  static const String signOutLabel = 'Sign out';

  /// The card rows' columns, which the rows under the cards follow: the
  /// icon 16 in from the card's 1px border, the text 14 after the 22 icon.
  static const double _rowInset = 1 + 16;
  static const double _iconGap = 14;
  static const String deleteTitle = 'Delete your details?';
  static const String deleteMessage =
      'Your name, mobile, email and saved addresses are removed from this '
      'phone. Your cart and favourites stay.';
  static const String deletedMessage = 'Your details are deleted.';

  /// "Delete my details" asks first, then removes everything saved for
  /// checkout.
  static Future<void> _confirmDelete(BuildContext context) async {
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(deleteTitle),
        content: const Text(deleteMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const ValueKey('delete-details-confirm'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true || !context.mounted) return;
    await context.read<ProfileStore>().deleteAll();
    if (context.mounted) AppNav.showNotice(context, deletedMessage);
  }

  /// The store's customer service in a sheet over the bottom bar: the
  /// website's contact text, then Call, Email and the contact page. The
  /// sheet closes and the chosen link opens in the phone, mail or browser
  /// app; if nothing can open it, a notice gives the number or address.
  Future<void> _showHelp(BuildContext context) async {
    final link = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _HelpSheet(),
    );
    if (link == null || !context.mounted) return;
    final launch = launcher ?? AssistantScreen.launchExternally;
    final uri = Uri.tryParse(link);
    var opened = false;
    if (uri != null) {
      try {
        opened = await launch(uri);
      } catch (_) {
        // No app for it, or the platform refused: said below.
      }
    }
    if (opened || !context.mounted) return;
    AppNav.showNotice(context, linkFailureMessage(link));
  }

  /// Plays the intro over the whole screen (no bottom bar) and comes back
  /// here when it finishes.
  static Future<void> _watchIntro(BuildContext context) =>
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (routeContext) =>
              IntroScreen(onDone: () => Navigator.of(routeContext).pop()),
        ),
      );
}

/// One tappable row of the account list: ink icon, label, optional value,
/// chevron.
class _AccountRow extends StatelessWidget {
  const _AccountRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailing,
    this.subtitle,
    this.subtitleSemantics,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Widget? trailing;

  /// A second line under the label in grey ("Business Bay, Dubai").
  final String? subtitle;

  /// What screen readers say for [subtitle], when it differs.
  final String? subtitleSemantics;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Icon(icon, size: 22, color: AppColors.ink),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label,
                      style: AppText.body.copyWith(fontWeight: FontWeight.w600),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        semanticsLabel: subtitleSemantics,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppText.bodySmall.copyWith(
                          color: AppColors.secondary,
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) ...[trailing!, const SizedBox(width: 4)],
              const Icon(
                Icons.chevron_right,
                size: 22,
                color: AppColors.tertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Help & contact": the store's customer service text and one row per
/// contact link (call, email, the website's contact page).
class _HelpSheet extends StatelessWidget {
  const _HelpSheet();

  static IconData _iconFor(String link) => switch (Uri.tryParse(link)?.scheme) {
    'tel' => Icons.phone_outlined,
    'mailto' => Icons.mail_outline,
    _ => Icons.open_in_new,
  };

  @override
  Widget build(BuildContext context) {
    final links = AssistantBrain.contactActions.whereType<OpenLinkAction>();
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
              child: const Text(
                AccountScreen.helpLabel,
                style: AppText.heading,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              AssistantBrain.contactText,
              style: AppText.body.copyWith(color: AppColors.secondary),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: AppDecor.card,
              clipBehavior: Clip.antiAlias,
              child: Material(
                type: MaterialType.transparency,
                child: Column(
                  children: [
                    for (final (index, link) in links.indexed) ...[
                      if (index > 0) const Divider(height: 1, indent: 52),
                      _AccountRow(
                        key: ValueKey('help-${link.uri}'),
                        icon: _iconFor(link.uri),
                        label: link.label,
                        onTap: () => Navigator.of(context).pop(link.uri),
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

/// "Your details": empty, a line on what they are for and "Add details";
/// filled, the name, mobile and email with "Edit".
class _DetailsCard extends StatelessWidget {
  const _DetailsCard();

  static const String emptyTitle = 'Your details';
  static const String emptyLine =
      'Add them once and checkout opens already filled in.';

  @override
  Widget build(BuildContext context) {
    final contact = context.select<ProfileStore, ContactDetails>(
      (s) => s.contact,
    );
    // Signed in, the account card above has the avatar.
    final avatar = !context.select<AccountSession, bool>((s) => s.signedIn);
    void edit() => AppNav.openMyDetails(context);

    if (contact.isEmpty) {
      return Container(
        key: const ValueKey('account-details'),
        decoration: AppDecor.card,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (avatar) ...[const _Avatar(), const SizedBox(width: 12)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: const Text(
                          emptyTitle,
                          style: AppText.cardHeading,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        emptyLine,
                        style: AppText.bodySmall.copyWith(
                          color: AppColors.secondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            OutlinedButton(
              key: const ValueKey('add-details'),
              onPressed: edit,
              child: const Text('Add details'),
            ),
          ],
        ),
      );
    }

    final name = contact.fullName;
    final lines = [
      if (contact.mobile.isNotEmpty) contact.mobileOneLine,
      if (contact.email.isNotEmpty) contact.email,
    ];
    final heading = Semantics(
      header: true,
      child: Text(name.isEmpty ? emptyTitle : name, style: AppText.cardHeading),
    );
    final details = [
      for (final line in lines)
        Text(
          line,
          style: AppText.bodySmall.copyWith(color: AppColors.secondary),
        ),
    ];
    final editButton = TextButton(
      key: const ValueKey('edit-details'),
      onPressed: edit,
      child: const Text('Edit', semanticsLabel: 'Edit my details'),
    );

    // At a large font size the lines take the card's width (the mobile and
    // email stay whole) and Edit goes under them.
    if (MediaQuery.textScalerOf(context).scale(10) / 10 > 1.3) {
      return Container(
        key: const ValueKey('account-details'),
        decoration: AppDecor.card,
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (avatar) ...[
                  _Avatar(initials: _initials(contact)),
                  const SizedBox(width: 12),
                ],
                Expanded(child: heading),
              ],
            ),
            const SizedBox(height: 8),
            ...details,
            const SizedBox(height: 4),
            Transform.translate(
              // The label on the text's edge (less the button's padding).
              offset: Offset(
                Directionality.of(context) == TextDirection.rtl ? 8 : -8,
                0,
              ),
              child: editButton,
            ),
          ],
        ),
      );
    }

    return Container(
      key: const ValueKey('account-details'),
      decoration: AppDecor.card,
      padding: const EdgeInsetsDirectional.fromSTEB(16, 16, 8, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (avatar) ...[
            _Avatar(initials: _initials(contact)),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [heading, const SizedBox(height: 2), ...details],
            ),
          ),
          editButton,
        ],
      ),
    );
  }

  /// "SA" for Sara Ahmed; the first letter of each name given.
  static String _initials(ContactDetails contact) => [
    contact.firstName,
    contact.lastName,
  ].where((n) => n.isNotEmpty).map((n) => n.characters.first).join();
}

/// The round off-white avatar: the initials, or [icon] (a person).
class _Avatar extends StatelessWidget {
  const _Avatar({this.initials = '', this.icon = Icons.person_outline});

  final String initials;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppColors.subtle,
          shape: BoxShape.circle,
        ),
        child: initials.isEmpty
            ? Icon(icon, size: 26, color: AppColors.ink)
            : Text(
                initials.toUpperCase(),
                maxLines: 1,
                textScaler: TextScaler.noScaling,
                style: AppText.cardHeading,
              ),
      ),
    );
  }
}

/// "Delivery addresses": each saved address (label, default, building and
/// flat, area) opens it for editing; "Add address" adds one in the
/// delivery area.
class _AddressesSection extends StatelessWidget {
  const _AddressesSection();

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileStore>();
    final addresses = profile.addresses;
    final defaultId = profile.defaultAddress?.id;
    final area = context.select<DeliveryStore, DeliveryArea?>((s) => s.area);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          container: true,
          header: true,
          child: const Text('Delivery addresses', style: AppText.heading),
        ),
        const SizedBox(height: AppDims.headingGap),
        Container(
          key: const ValueKey('account-addresses'),
          decoration: AppDecor.card,
          clipBehavior: Clip.antiAlias,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              children: [
                for (final (i, a) in addresses.indexed) ...[
                  if (i > 0) const Divider(height: 1, indent: 52),
                  Semantics(
                    container: true,
                    button: true,
                    label:
                        '${a.semantics}${a.id == defaultId ? ', default' : ''}'
                        '. Edit',
                    excludeSemantics: true,
                    child: InkWell(
                      key: ValueKey('account-address-${a.id}'),
                      onTap: () => AppNav.openAddress(context, address: a),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Icon(
                                addressLabelIcon(a.label),
                                size: 22,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: AddressSummary(
                                address: a,
                                isDefault: a.id == defaultId,
                              ),
                            ),
                            const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: Icon(
                                Icons.chevron_right,
                                size: 22,
                                color: AppColors.tertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
                if (profile.canAddAddress) ...[
                  if (addresses.isNotEmpty)
                    const Divider(height: 1, indent: 52),
                  // Its own node: with one row under the heading the two
                  // would otherwise be read (and tapped) as one.
                  Semantics(
                    container: true,
                    child: _AccountRow(
                      key: const ValueKey('add-address'),
                      icon: Icons.add,
                      label: 'Add address',
                      subtitle: addresses.isEmpty
                          ? 'Building and flat, filled in at checkout'
                          : null,
                      onTap: () => AppNav.openAddress(context, area: area),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A full-width ink text button under the cards ("Sign out", "Delete my
/// details"): the whole row is the target; the icon and text on the card
/// rows' columns.
class _BottomAction extends StatelessWidget {
  const _BottomAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: TextButton.styleFrom(
        alignment: AlignmentDirectional.centerStart,
        minimumSize: const Size.fromHeight(AppDims.controlTarget),
        padding: const EdgeInsets.symmetric(
          horizontal: AccountScreen._rowInset,
        ),
      ),
      onPressed: onPressed,
      child: Row(
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: AccountScreen._iconGap),
          Flexible(child: Text(label)),
        ],
      ),
    );
  }
}

/// The store account, first on Account. Signed out: "Sign in to order",
/// what sign-in takes and the ink "Sign in with email". Signed in: the
/// initials, "Signed in" and the email, and "My orders".
class _SessionCard extends StatelessWidget {
  const _SessionCard();

  static const String signedOutTitle = 'Sign in to order';
  static const String signedOutLine =
      "Use your email. We'll send you a 6-digit code, no password needed. "
      'You stay signed in on this phone.';
  static const String signInLabel = 'Sign in with email';
  static const String signedInCaption = 'Signed in';

  /// Shown for the email when the app did not see it.
  static const String unknownEmail = 'Your Fresh Market account';
  static const String ordersLabel = 'My orders';
  static const String ordersSubtitle = 'Track orders and see past ones';

  @override
  Widget build(BuildContext context) {
    final session = context.watch<AccountSession>();
    if (!session.signedIn) return _signedOut(context);

    final contact = context.select<ProfileStore, ContactDetails>(
      (s) => s.contact,
    );
    final email = session.email;
    var initials = _DetailsCard._initials(contact);
    if (initials.isEmpty && email != null) initials = email.characters.first;
    return Container(
      key: const ValueKey('account-session'),
      decoration: AppDecor.card,
      clipBehavior: Clip.antiAlias,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              container: true,
              label: email == null
                  ? signedInCaption
                  : '$signedInCaption as $email',
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    _Avatar(initials: initials),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(signedInCaption, style: AppText.caption),
                          Text(
                            email ?? unknownEmail,
                            style: AppText.cardHeading,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            _AccountRow(
              key: const ValueKey('account-orders'),
              icon: Icons.shopping_bag_outlined,
              label: ordersLabel,
              subtitle: ordersSubtitle,
              onTap: () => AppNav.openOrders(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _signedOut(BuildContext context) {
    return Container(
      key: const ValueKey('account-session'),
      decoration: AppDecor.card,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Avatar(icon: Icons.lock_outline),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: const Text(
                        signedOutTitle,
                        style: AppText.cardHeading,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      signedOutLine,
                      style: AppText.bodySmall.copyWith(
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Ink: signing in is not buying.
          FilledButton(
            key: const ValueKey('account-sign-in'),
            style: AppButtons.dark,
            onPressed: () => AppNav.openSignIn(context),
            child: const Text(signInLabel, textAlign: TextAlign.center),
          ),
        ],
      ),
    );
  }
}
