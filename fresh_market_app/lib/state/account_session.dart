import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/store_config.dart';
import '../profile/profile_vault.dart';
import '../services/customer_account.dart';

/// Whether the shopper is signed in to their store account (Shopify's
/// customer accounts: an email and a 6-digit code), and with which email
/// when the app saw it typed.
///
/// The sign-in itself lives in the WebViews' cookies; this is what the
/// app shows and what checkout asks for. It is kept on the phone through
/// a vault, encrypted ([SecureAccountVault]): the email is personal. A
/// record that cannot be read counts as signed out and is removed; it
/// never crashes.
class AccountSession extends ChangeNotifier {
  /// With no [vault] the session lives in memory only. [asksAtCheckout]
  /// false never asks to sign in before checkout (the in-memory session
  /// `AppScope` makes when it is given none).
  AccountSession({this._vault, this.asksAtCheckout = true});

  final ProfileVault? _vault;
  final bool asksAtCheckout;

  bool _signedIn = false;
  String? _email;

  Future<void>? _loading;
  bool _readDone = false;

  /// A sign-in or sign-out came before the saved record was read: it
  /// wins over the record.
  bool _changedBeforeLoad = false;
  Future<void> _writing = Future.value();

  bool get signedIn => _signedIn;

  /// The account's email, when the app saw it; null otherwise.
  String? get email => _email;

  /// Checkout first asks the shopper to sign in
  /// ([StoreConfig.requireSignInToOrder]).
  bool get signInNeededToOrder =>
      StoreConfig.requireSignInToOrder && asksAtCheckout && !_signedIn;

  /// True once the saved record was read (at once with no vault).
  bool get loaded => _vault == null || _readDone;

  /// Completes when every change so far has reached the vault (tests).
  Future<void> get idle => _writing;

  /// Signed in, as [email] when given (a valid email only); otherwise an
  /// email already known is kept.
  void signIn({String? email}) {
    final clean = CustomerAccount.emailIn(email) ?? _email;
    if (_signedIn && clean == _email) return;
    _signedIn = true;
    _email = clean;
    _changed();
  }

  /// Signed out: the record is removed from the phone. The WebViews'
  /// cookies are cleared by the caller (see `AppNav.signOut`).
  Future<void> signOut() async {
    if (_signedIn || _email != null) {
      _signedIn = false;
      _email = null;
      _changed();
    }
    await _writing;
  }

  /// Reads the saved record, once (later calls return the same read).
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final vault = _vault;
    if (vault == null) return;
    String? raw;
    try {
      raw = await vault.read();
    } catch (_) {
      // The phone's secure storage could not be opened or decrypted:
      // signed out; the next sign-in writes a fresh record.
      raw = null;
    }
    _readDone = true;
    if (_changedBeforeLoad || raw == null || raw.isEmpty) return;
    try {
      final saved = jsonDecode(raw);
      if (saved is! Map || saved['signedIn'] != true) {
        throw const FormatException('not a session');
      }
      _signedIn = true;
      _email = CustomerAccount.emailIn(saved['email']);
    } catch (_) {
      // Damaged: signed out, and the record is removed.
      _signedIn = false;
      _email = null;
      _writing = _writing.then((_) => _delete(vault));
    }
    notifyListeners();
  }

  static Future<void> _delete(ProfileVault vault) async {
    try {
      await vault.delete();
    } catch (_) {}
  }

  void _changed() {
    if (!loaded) _changedBeforeLoad = true;
    notifyListeners();
    final vault = _vault;
    if (vault == null) return;
    final reading = load();
    _writing = _writing.then((_) async {
      await reading;
      // The state when the write runs, so writes never go back in time.
      final record = _signedIn
          ? jsonEncode({'v': 1, 'signedIn': true, 'email': ?_email})
          : null;
      try {
        if (record == null) {
          await vault.delete();
        } else {
          await vault.write(record);
        }
      } catch (_) {
        // Kept in memory for this run.
      }
    });
  }
}

/// The session record in the phone's encrypted storage (as the shopper's
/// details are: see [SecureProfileVault]), under its own key.
class SecureAccountVault implements ProfileVault {
  const SecureAccountVault({
    this.storage = const FlutterSecureStorage(aOptions: AndroidOptions()),
  });

  static const String key = 'account_session_v1';

  final FlutterSecureStorage storage;

  @override
  Future<String?> read() => storage.read(key: key);

  @override
  Future<void> write(String value) => storage.write(key: key, value: value);

  @override
  Future<void> delete() => storage.delete(key: key);
}
