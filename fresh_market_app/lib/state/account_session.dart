import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/store_config.dart';
import '../services/customer_auth.dart';

/// How a sign-in ended.
enum SignInOutcome {
  signedIn,

  /// The shopper closed Shopify's page.
  cancelled,

  /// The app was built without a Customer Account API client ID.
  unavailable,

  /// Offline: Shopify could not be reached.
  offline,

  /// Shopify said no, or the page failed.
  failed,
}

/// Whether the shopper is signed in to their store account (Shopify's
/// customer accounts: an email and a 6-digit code), and with which email.
///
/// The tokens live in [CustomerAuth] (encrypted on the phone); this is
/// what the screens show and what checkout asks for. A saved record that
/// cannot be read counts as signed out; nothing here ever crashes.
class AccountSession extends ChangeNotifier {
  /// With no [auth], sign-in is not available and the shopper is signed
  /// out. [asksAtCheckout] false never asks to sign in before checkout
  /// (the session `AppScope` makes when it is given none).
  AccountSession({this._auth, this.asksAtCheckout = true});

  final CustomerAuth? _auth;
  final bool asksAtCheckout;

  Future<void>? _loading;
  bool _loaded = false;
  bool _signingIn = false;

  /// Sign-in can be offered: the app was built with a client ID.
  bool get signInAvailable => _auth?.configured ?? false;

  bool get signedIn => _auth?.signedIn ?? false;

  /// The account's email, when known.
  String? get email => _auth?.tokens?.email;

  /// True while Shopify's sign-in page is open.
  bool get signingIn => _signingIn;

  /// Checkout first asks the shopper to sign in
  /// ([StoreConfig.requireSignInToOrder]).
  bool get signInNeededToOrder =>
      StoreConfig.requireSignInToOrder && asksAtCheckout && !signedIn;

  /// True once the saved tokens were read (at once with no auth).
  bool get loaded => _auth == null || _loaded;

  /// Reads the saved tokens, once (later calls return the same read).
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final auth = _auth;
    if (auth == null) return;
    await auth.load();
    _loaded = true;
    notifyListeners();
  }

  /// Opens Shopify's sign-in over the app and waits for it to come back.
  Future<SignInOutcome> signIn() async {
    final auth = _auth;
    if (auth == null || !auth.configured) return SignInOutcome.unavailable;
    if (_signingIn) return SignInOutcome.cancelled;
    _signingIn = true;
    notifyListeners();
    try {
      await auth.signIn();
      return SignInOutcome.signedIn;
    } on SignInCancelled {
      return SignInOutcome.cancelled;
    } on SignInUnavailable {
      return SignInOutcome.unavailable;
    } on AuthNetworkError {
      return SignInOutcome.offline;
    } on AuthException {
      return SignInOutcome.failed;
    } finally {
      _signingIn = false;
      notifyListeners();
    }
  }

  /// A working access token, refreshed when it is about to expire (or
  /// with [forceRefresh], after the server said 401). Null when signed
  /// out, including when Shopify refused the refresh: the session then
  /// ends here and listeners hear of it. Throws [AuthNetworkError] when a
  /// refresh could not reach Shopify.
  Future<String?> accessToken({bool forceRefresh = false}) async {
    final auth = _auth;
    if (auth == null) return null;
    final before = auth.signedIn;
    final token = await auth.accessToken(forceRefresh: forceRefresh);
    if (before != auth.signedIn) notifyListeners();
    return token;
  }

  /// Keeps the email the Customer Account API gave (when the ID token had
  /// none).
  Future<void> rememberEmail(String? email) async {
    final auth = _auth;
    if (auth == null || email == null || email == this.email) return;
    await auth.rememberEmail(email);
    notifyListeners();
  }

  /// Signs out at Shopify and on the phone. The shopper's details for
  /// checkout ("My details", addresses) stay.
  Future<void> signOut() async {
    final auth = _auth;
    if (auth == null) return;
    final idToken = await auth.forgetLocally();
    // The screens change at once; Shopify is told after.
    notifyListeners();
    if (idToken != null) await auth.endSession(idToken);
  }
}
