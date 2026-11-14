import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/store_config.dart';
import '../profile/profile_vault.dart';

/// The tokens of a signed-in customer (Customer Account API).
@immutable
class AuthTokens {
  const AuthTokens({
    required this.accessToken,
    required this.expiresAt,
    this.refreshToken,
    this.idToken,
    this.email,
  });

  /// Sent as is (no "Bearer") to the Customer Account API, and as
  /// "Bearer …" to the order server.
  final String accessToken;

  /// When [accessToken] stops working (from `expires_in`).
  final DateTime expiresAt;

  /// Headless and mobile clients configured on the shop get one.
  final String? refreshToken;

  /// For signing out (`id_token_hint`), and the email.
  final String? idToken;

  /// The customer's email: the ID token's `email` claim, or what the
  /// Customer Account API said.
  final String? email;

  /// [accessToken] stops working within [margin] of [now].
  bool expiresWithin(Duration margin, DateTime now) =>
      !now.add(margin).isBefore(expiresAt);

  AuthTokens copyWith({String? email}) => AuthTokens(
    accessToken: accessToken,
    expiresAt: expiresAt,
    refreshToken: refreshToken,
    idToken: idToken,
    email: email ?? this.email,
  );

  Map<String, dynamic> toJson() => {
    'v': 1,
    'access': accessToken,
    'exp': expiresAt.millisecondsSinceEpoch,
    'refresh': ?refreshToken,
    'id': ?idToken,
    'email': ?email,
  };

  /// Reads [toJson]'s shape; null when it is not a usable record.
  static AuthTokens? fromJson(Object? json) {
    if (json is! Map) return null;
    final access = json['access'];
    final exp = json['exp'];
    if (access is! String || access.isEmpty || exp is! int) return null;
    String? text(String key) {
      final value = json[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    return AuthTokens(
      accessToken: access,
      expiresAt: DateTime.fromMillisecondsSinceEpoch(exp, isUtc: true),
      refreshToken: text('refresh'),
      idToken: text('id'),
      email: text('email'),
    );
  }

  /// The `email` claim of an OpenID Connect ID token (a JWT), read
  /// without checking its signature (AppAuth checked the token when it
  /// arrived; the app only shows the email). Null when there is none.
  static String? emailInIdToken(String? idToken) {
    if (idToken == null) return null;
    final parts = idToken.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      if (payload is! Map) return null;
      final email = payload['email'];
      return email is String && email.contains('@') && email.length <= 254
          ? email
          : null;
    } catch (_) {
      return null;
    }
  }
}

/// Why signing in, or keeping the customer signed in, did not work.
sealed class AuthException implements Exception {
  const AuthException();
}

/// The shopper closed Shopify's sign-in page.
final class SignInCancelled extends AuthException {
  const SignInCancelled();
}

/// The app was built without a Customer Account API client ID.
final class SignInUnavailable extends AuthException {
  const SignInUnavailable();
}

/// Sign-in did not complete (Shopify said no, or the page failed).
final class SignInFailed extends AuthException {
  const SignInFailed([this.reason]);

  final String? reason;
}

/// Shopify refused the refresh token: the customer must sign in again.
final class RefreshRejected extends AuthException {
  const RefreshRejected();
}

/// Shopify could not be reached (offline, a timeout).
final class AuthNetworkError extends AuthException {
  const AuthNetworkError([this.cause]);

  final Object? cause;
}

/// The OAuth 2.0 exchanges with Shopify. The app uses [AppAuthClient];
/// tests use a fake.
abstract interface class OAuthClient {
  /// Shows Shopify's sign-in (email, then a 6-digit code) and returns the
  /// tokens. Throws [SignInCancelled], [SignInFailed] or
  /// [AuthNetworkError].
  Future<AuthTokens> authorize();

  /// New tokens for [tokens]' refresh token. Throws [RefreshRejected] or
  /// [AuthNetworkError].
  Future<AuthTokens> refresh(AuthTokens tokens);
}

/// [OAuthClient] through flutter_appauth: Shopify's sign-in page opens in
/// a Chrome Custom Tab over the app and comes back to
/// [CustomerAccountConfig.redirectUri] by itself. AppAuth makes the PKCE
/// code verifier and its S256 challenge for every sign-in (and the state
/// and nonce), and exchanges the code for tokens as a public client (no
/// secret).
class AppAuthClient implements OAuthClient {
  AppAuthClient({
    this.appAuth = const FlutterAppAuth(),
    this.clientId = CustomerAccountConfig.clientId,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final FlutterAppAuth appAuth;
  final String clientId;
  final DateTime Function() _now;

  static const AuthorizationServiceConfiguration serviceConfiguration =
      AuthorizationServiceConfiguration(
        authorizationEndpoint: CustomerAccountConfig.authorizationEndpoint,
        tokenEndpoint: CustomerAccountConfig.tokenEndpoint,
        endSessionEndpoint: CustomerAccountConfig.endSessionEndpoint,
      );

  /// Used when the server sends no expiry (Shopify sends `expires_in`).
  static const Duration fallbackLifetime = Duration(hours: 1);

  AuthTokens _tokens(TokenResponse response, {AuthTokens? before}) {
    final access = response.accessToken;
    if (access == null || access.isEmpty) {
      throw const SignInFailed('no access token');
    }
    final idToken = response.idToken ?? before?.idToken;
    return AuthTokens(
      accessToken: access,
      expiresAt:
          (response.accessTokenExpirationDateTime ??
                  _now().add(fallbackLifetime))
              .toUtc(),
      // A refresh answer without a new refresh token keeps the old one.
      refreshToken: response.refreshToken ?? before?.refreshToken,
      idToken: idToken,
      email: AuthTokens.emailInIdToken(idToken) ?? before?.email,
    );
  }

  @override
  Future<AuthTokens> authorize() async {
    if (clientId.trim().isEmpty) throw const SignInUnavailable();
    try {
      final response = await appAuth.authorizeAndExchangeCode(
        AuthorizationTokenRequest(
          clientId,
          CustomerAccountConfig.redirectUri,
          serviceConfiguration: serviceConfiguration,
          scopes: CustomerAccountConfig.scopes,
        ),
      );
      return _tokens(response);
    } on FlutterAppAuthUserCancelledException {
      throw const SignInCancelled();
    } on FlutterAppAuthPlatformException catch (e) {
      final details = e.platformErrorDetails;
      if (details.error == null && _isNetwork(details)) {
        throw AuthNetworkError(e);
      }
      throw SignInFailed(details.error ?? e.code);
    } on PlatformException catch (e) {
      throw SignInFailed(e.code);
    } on MissingPluginException {
      throw const SignInFailed('no sign-in on this platform');
    }
  }

  @override
  Future<AuthTokens> refresh(AuthTokens tokens) async {
    final refreshToken = tokens.refreshToken;
    if (refreshToken == null) throw const RefreshRejected();
    try {
      final response = await appAuth.token(
        TokenRequest(
          clientId,
          CustomerAccountConfig.redirectUri,
          refreshToken: refreshToken,
          grantType: GrantType.refreshToken,
          serviceConfiguration: serviceConfiguration,
          scopes: CustomerAccountConfig.scopes,
        ),
      );
      return _tokens(response, before: tokens);
    } on FlutterAppAuthPlatformException catch (e) {
      // An OAuth error from Shopify (invalid_grant, ...) means the
      // refresh token is no good; anything else is the network.
      if (e.platformErrorDetails.error != null) throw const RefreshRejected();
      throw AuthNetworkError(e);
    } on SignInFailed {
      throw const RefreshRejected();
    } on PlatformException catch (e) {
      throw AuthNetworkError(e);
    }
  }

  /// AppAuth-Android's general errors 3 (network) and 4 (server).
  static bool _isNetwork(FlutterAppAuthPlatformErrorDetails details) =>
      details.type == '0' && (details.code == '3' || details.code == '4');
}

/// Where the tokens are kept: the phone's encrypted storage (as the
/// shopper's details are: see [SecureProfileVault]), under their own key.
class SecureTokenVault implements ProfileVault {
  const SecureTokenVault({
    this.storage = const FlutterSecureStorage(aOptions: AndroidOptions()),
  });

  static const String key = 'customer_tokens_v1';

  /// The record of the earlier in-app sign-in (before Customer Account
  /// API tokens), removed on first read.
  static const String legacyKey = 'account_session_v1';

  final FlutterSecureStorage storage;

  @override
  Future<String?> read() async {
    try {
      await storage.delete(key: legacyKey);
    } catch (_) {}
    return storage.read(key: key);
  }

  @override
  Future<void> write(String value) => storage.write(key: key, value: value);

  @override
  Future<void> delete() => storage.delete(key: key);
}

/// Keeps the customer signed in: the tokens in encrypted storage only,
/// refreshed shortly before they expire, and dropped when Shopify refuses
/// a refresh.
class CustomerAuth {
  CustomerAuth({
    required this._client,
    ProfileVault? vault,
    http.Client? httpClient,
    DateTime Function()? now,
    this.configured = true,
    this.refreshMargin = const Duration(minutes: 2),
  }) : _vault = vault ?? const SecureTokenVault(),
       _http = httpClient ?? http.Client(),
       _now = now ?? DateTime.now;

  /// The app's own: flutter_appauth with the client ID it was built
  /// with.
  factory CustomerAuth.app() => CustomerAuth(
    client: AppAuthClient(),
    configured: CustomerAccountConfig.configured,
  );

  final OAuthClient _client;
  final ProfileVault _vault;
  final http.Client _http;
  final DateTime Function() _now;

  /// False when the app was built without a client ID: sign-in is not
  /// offered.
  final bool configured;

  /// Tokens are refreshed when they expire within this.
  final Duration refreshMargin;

  AuthTokens? _tokens;
  Future<void>? _loading;
  Future<AuthTokens?>? _refreshing;

  /// Changes since [load] started (a sign-in or sign-out wins over the
  /// saved record).
  int _changes = 0;

  AuthTokens? get tokens => _tokens;
  bool get signedIn => _tokens != null;

  /// Reads the saved tokens, once. A record that cannot be read counts as
  /// signed out (and is removed); it never crashes.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final changes = _changes;
    String? raw;
    try {
      raw = await _vault.read();
    } catch (_) {
      raw = null;
    }
    if (_changes != changes || raw == null || raw.isEmpty) return;
    AuthTokens? saved;
    try {
      saved = AuthTokens.fromJson(jsonDecode(raw));
    } catch (_) {
      saved = null;
    }
    if (saved == null) {
      await _forget();
      return;
    }
    _tokens = saved;
  }

  /// Signs in through Shopify's page and saves the tokens. Throws an
  /// [AuthException] when it did not work.
  Future<AuthTokens> signIn() async {
    if (!configured) throw const SignInUnavailable();
    final tokens = await _client.authorize();
    _changes++;
    _tokens = tokens;
    await _save(tokens);
    return tokens;
  }

  /// An access token that works for a while yet: the saved one, or a
  /// refreshed one when it expires within [refreshMargin] (or
  /// [forceRefresh], after a 401). Null when the customer is signed out,
  /// including when Shopify refused the refresh (the tokens are then
  /// dropped). Throws [AuthNetworkError] when a refresh could not reach
  /// Shopify (the customer stays signed in).
  Future<String?> accessToken({bool forceRefresh = false}) async {
    await load();
    final tokens = _tokens;
    if (tokens == null) return null;
    if (!forceRefresh && !tokens.expiresWithin(refreshMargin, _now())) {
      return tokens.accessToken;
    }
    final fresh = await (_refreshing ??= _refresh(tokens)
        .whenComplete(() => _refreshing = null));
    return fresh?.accessToken;
  }

  Future<AuthTokens?> _refresh(AuthTokens tokens) async {
    try {
      final fresh = await _client.refresh(tokens);
      if (!identical(_tokens, tokens)) return _tokens;
      _changes++;
      _tokens = fresh;
      await _save(fresh);
      return fresh;
    } on RefreshRejected {
      if (identical(_tokens, tokens)) await _forget();
      return null;
    }
  }

  /// Keeps the email the Customer Account API gave.
  Future<void> rememberEmail(String email) async {
    final tokens = _tokens;
    if (tokens == null || tokens.email == email) return;
    final next = tokens.copyWith(email: email);
    _tokens = next;
    await _save(next);
  }

  /// Signs out at Shopify (the end-session endpoint with `id_token_hint`;
  /// a failure is ignored) and removes the tokens from the phone.
  Future<void> signOut() async {
    final idToken = await forgetLocally();
    if (idToken != null) await endSession(idToken);
  }

  /// Removes the tokens from the phone and returns the ID token, for
  /// [endSession].
  Future<String?> forgetLocally() async {
    await load();
    final idToken = _tokens?.idToken;
    _changes++;
    await _forget();
    return idToken;
  }

  /// Tells Shopify the customer signed out. Mobile clients call the
  /// end-session endpoint as an API (it answers 200); any failure is
  /// ignored, as the phone is signed out already.
  Future<void> endSession(String idToken) async {
    try {
      await _http
          .get(
            Uri.parse(CustomerAccountConfig.endSessionEndpoint)
                .replace(queryParameters: {'id_token_hint': idToken}),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Signed out on the phone all the same.
    }
  }

  Future<void> _forget() async {
    _tokens = null;
    try {
      await _vault.delete();
    } catch (_) {}
  }

  Future<void> _save(AuthTokens tokens) async {
    try {
      await _vault.write(jsonEncode(tokens.toJson()));
    } catch (_) {
      // Kept in memory for this run.
    }
  }
}
