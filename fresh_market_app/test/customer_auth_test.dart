import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/config/store_config.dart';
import 'package:fresh_market_app/profile/profile_vault.dart';
import 'package:fresh_market_app/services/customer_auth.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/state/account_session.dart';
import 'package:fresh_market_app/state/cart_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/order_fakes.dart';

/// flutter_appauth's side in tests: records the requests and answers with
/// [next] (or throws [error]).
class _FakeAppAuth implements FlutterAppAuth {
  final List<AuthorizationTokenRequest> authorizeRequests = [];
  final List<TokenRequest> tokenRequests = [];
  TokenResponse? next;
  Object? error;

  @override
  Future<AuthorizationTokenResponse> authorizeAndExchangeCode(
    AuthorizationTokenRequest request,
  ) async {
    authorizeRequests.add(request);
    if (error != null) throw error!;
    final r = next!;
    return AuthorizationTokenResponse(
      r.accessToken,
      r.refreshToken,
      r.accessTokenExpirationDateTime,
      r.idToken,
      'Bearer',
      null,
      null,
      null,
    );
  }

  @override
  Future<TokenResponse> token(TokenRequest request) async {
    tokenRequests.add(request);
    if (error != null) throw error!;
    return next!;
  }

  @override
  Future<AuthorizationResponse> authorize(AuthorizationRequest request) =>
      throw UnimplementedError();

  @override
  Future<EndSessionResponse> endSession(EndSessionRequest request) =>
      throw UnimplementedError();
}

FlutterAppAuthPlatformException _platformError({
  String? error,
  String? type,
  String? code,
}) => FlutterAppAuthPlatformException(
  code: 'token_failed',
  platformErrorDetails: FlutterAppAuthPlatformErrorDetails(
    error: error,
    type: type,
    code: code,
  ),
);

void main() {
  final now = DateTime.utc(2026, 11, 13, 6);

  group('AppAuthClient (flutter_appauth, PKCE in AppAuth)', () {
    test("asks Shopify's Customer Account API for the store's mobile "
        'client: endpoints, redirect, scopes, no secret', () async {
      final appAuth = _FakeAppAuth()
        ..next = TokenResponse(
          'access',
          'refresh',
          now.add(const Duration(hours: 2)),
          fakeIdToken('sara@example.com'),
          'Bearer',
          null,
          null,
        );
      final client = AppAuthClient(
        appAuth: appAuth,
        clientId: 'shp_test_client',
        now: () => now,
      );
      final tokens = await client.authorize();

      final request = appAuth.authorizeRequests.single;
      expect(request.clientId, 'shp_test_client');
      expect(request.clientSecret, isNull, reason: 'a public client');
      expect(request.redirectUrl, 'shop.79173124173.app://callback');
      expect(request.scopes, ['openid', 'email', 'customer-account-api:full']);
      final config = request.serviceConfiguration!;
      expect(
        config.authorizationEndpoint,
        'https://shopify.com/authentication/79173124173/oauth/authorize',
      );
      expect(
        config.tokenEndpoint,
        'https://shopify.com/authentication/79173124173/oauth/token',
      );
      expect(
        config.endSessionEndpoint,
        'https://shopify.com/authentication/79173124173/logout',
      );
      // authorizeAndExchangeCode: AppAuth makes the code verifier and its
      // S256 challenge itself (none is passed in), and sends the verifier
      // with the code.
      expect(request.grantType, GrantType.authorizationCode);
      expect(request.codeVerifier, isNull);

      expect(tokens.accessToken, 'access');
      expect(tokens.refreshToken, 'refresh');
      expect(tokens.expiresAt, now.add(const Duration(hours: 2)));
      expect(tokens.email, 'sara@example.com');
    });

    test(
      'closing the page, an OAuth error, the network and no plugin',
      () async {
        final appAuth = _FakeAppAuth();
        final client = AppAuthClient(appAuth: appAuth, clientId: 'id');
        appAuth.error = FlutterAppAuthUserCancelledException(
          code: 'authorize_and_exchange_code_failed',
          platformErrorDetails: FlutterAppAuthPlatformErrorDetails(),
        );
        expect(client.authorize(), throwsA(isA<SignInCancelled>()));
        appAuth.error = _platformError(error: 'access_denied');
        expect(client.authorize(), throwsA(isA<SignInFailed>()));
        appAuth.error = _platformError(type: '0', code: '3');
        expect(client.authorize(), throwsA(isA<AuthNetworkError>()));
        appAuth.error = MissingPluginException();
        expect(client.authorize(), throwsA(isA<SignInFailed>()));
      },
    );

    test(
      'no client ID: sign-in is not available (and nothing opens)',
      () async {
        final appAuth = _FakeAppAuth();
        final client = AppAuthClient(appAuth: appAuth, clientId: '');
        await expectLater(
          client.authorize(),
          throwsA(isA<SignInUnavailable>()),
        );
        expect(appAuth.authorizeRequests, isEmpty);
        // The app as built for these tests has none.
        expect(CustomerAccountConfig.configured, isFalse);
      },
    );

    test('refresh: the refresh grant; the old refresh token is kept when '
        'none comes back; Shopify refusing or the network', () async {
      final appAuth = _FakeAppAuth()
        ..next = TokenResponse(
          'access-2',
          null,
          now.add(const Duration(hours: 1)),
          null,
          'Bearer',
          null,
          null,
        );
      final client = AppAuthClient(appAuth: appAuth, clientId: 'id');
      final before = testTokens(now: now);
      final fresh = await client.refresh(before);
      final request = appAuth.tokenRequests.single;
      expect(request.refreshToken, 'refresh-1');
      expect(request.grantType, GrantType.refreshToken);
      expect(fresh.accessToken, 'access-2');
      expect(fresh.refreshToken, 'refresh-1');
      expect(fresh.idToken, before.idToken);
      expect(fresh.email, 'sara@example.com');

      appAuth.error = _platformError(
        error: FlutterAppAuthOAuthError.invalidGrant,
      );
      expect(client.refresh(before), throwsA(isA<RefreshRejected>()));
      appAuth.error = _platformError(type: '0', code: '3');
      expect(client.refresh(before), throwsA(isA<AuthNetworkError>()));
      appAuth.error = _platformError(type: '0', code: '4');
      expect(client.refresh(before), throwsA(isA<AuthNetworkError>()));
      expect(
        client.refresh(testTokens(refresh: null)),
        throwsA(isA<RefreshRejected>()),
      );
    });

    test('a refresh that fails for any reason but the network is refused '
        '(the customer signs in again, never "offline" for good)', () async {
      final appAuth = _FakeAppAuth();
      final client = AppAuthClient(appAuth: appAuth, clientId: 'id');
      final before = testTokens(now: now);
      // AppAuth-Android general errors: 5 an unreadable answer (a non-JSON
      // 4xx), 6 no token response, 8 and 9 a bad ID token.
      for (final code in ['5', '6', '8', '9']) {
        appAuth.error = _platformError(type: '0', code: code);
        await expectLater(
          client.refresh(before),
          throwsA(isA<RefreshRejected>()),
          reason: 'general error $code',
        );
      }
      appAuth.error = _platformError(type: '2', code: '2002');
      await expectLater(client.refresh(before), throwsA(isA<RefreshRejected>()));
      appAuth.error = PlatformException(code: 'token_failed');
      await expectLater(client.refresh(before), throwsA(isA<RefreshRejected>()));
      appAuth.error = MissingPluginException();
      await expectLater(client.refresh(before), throwsA(isA<RefreshRejected>()));

      // And so the session ends on the phone.
      final vault = MemoryProfileVault(jsonEncode(before.toJson()));
      final auth = CustomerAuth(
        client: AppAuthClient(appAuth: appAuth, clientId: 'id'),
        vault: vault,
      );
      appAuth.error = _platformError(type: '0', code: '9');
      expect(await auth.accessToken(forceRefresh: true), isNull);
      expect(auth.signedIn, isFalse);
      expect(vault.value, isNull);
    });
  });

  group('AuthTokens', () {
    test('saved and read back; a bad record is not tokens', () {
      final tokens = testTokens(now: now);
      final back = AuthTokens.fromJson(jsonDecode(jsonEncode(tokens.toJson())));
      expect(back!.accessToken, tokens.accessToken);
      expect(back.refreshToken, tokens.refreshToken);
      expect(back.idToken, tokens.idToken);
      expect(back.expiresAt, tokens.expiresAt);
      expect(back.email, 'sara@example.com');
      expect(AuthTokens.fromJson({'access': ''}), isNull);
      expect(AuthTokens.fromJson('x'), isNull);
    });

    test("the ID token's email claim, never anything else", () {
      expect(AuthTokens.emailInIdToken(fakeIdToken('a@b.co')), 'a@b.co');
      expect(AuthTokens.emailInIdToken(fakeIdToken(null)), isNull);
      expect(AuthTokens.emailInIdToken('not.a.jwt'), isNull);
      expect(AuthTokens.emailInIdToken(null), isNull);
    });
  });

  group('CustomerAuth', () {
    test('signing in keeps the tokens in the secure vault only, and they '
        'come back after a restart', () async {
      final vault = MemoryProfileVault();
      final auth = CustomerAuth(client: FakeOAuthClient(), vault: vault);
      await auth.load();
      expect(auth.signedIn, isFalse);
      await auth.signIn();
      expect(auth.signedIn, isTrue);
      final saved = jsonDecode(vault.value!) as Map;
      expect(saved['access'], 'access-1');
      expect(saved['refresh'], 'refresh-1');

      final again = CustomerAuth(client: FakeOAuthClient(), vault: vault);
      await again.load();
      expect(again.signedIn, isTrue);
      expect(await again.accessToken(), 'access-1');
    });

    test("the app's vault is flutter_secure_storage (customer_tokens_v1); "
        'no token ever reaches SharedPreferences', () async {
      final secure = <String, String>{};
      FlutterSecureStorage.setMockInitialValues(secure);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final ends = EndSessionRecorder();
      // The vault the app uses (no vault given).
      final auth = CustomerAuth(
        client: FakeOAuthClient(),
        httpClient: ends.client,
      );
      await auth.load();
      await auth.signIn();
      expect(secure.keys, [SecureTokenVault.key]);
      final saved = jsonDecode(secure[SecureTokenVault.key]!) as Map;
      expect(saved['access'], 'access-1');
      expect(saved['refresh'], 'refresh-1');

      // A cart and an order attempt write to SharedPreferences: never a
      // token.
      final cart = CartStore(prefs: prefs)
        ..add(sampleProducts()[0], sampleProducts()[0].variants[0]);
      cart.orderKey(account: auth.tokens!.email);
      for (final key in prefs.getKeys()) {
        final value = '${prefs.get(key)}';
        expect(value, isNot(contains('access-1')), reason: key);
        expect(value, isNot(contains('refresh-1')), reason: key);
        expect(value, isNot(contains(auth.tokens!.idToken!)), reason: key);
      }

      // Read back by a new run; removed on sign-out.
      final again = CustomerAuth(
        client: FakeOAuthClient(),
        httpClient: ends.client,
      );
      await again.load();
      expect(await again.accessToken(), 'access-1');
      await again.signOut();
      expect(secure, isEmpty);
      expect(ends.calls, hasLength(1));
    });

    test(
      'a damaged or unreadable record is signed out (and removed)',
      () async {
        final damaged = MemoryProfileVault('{"v":1');
        final auth = CustomerAuth(client: FakeOAuthClient(), vault: damaged);
        await auth.load();
        expect(auth.signedIn, isFalse);
        expect(damaged.value, isNull);

        final broken = MemoryProfileVault()..broken = true;
        final other = CustomerAuth(client: FakeOAuthClient(), vault: broken);
        await other.load();
        expect(other.signedIn, isFalse);
        expect(await other.accessToken(), isNull);
      },
    );

    test('refreshes shortly before expiry, once for many callers', () async {
      var clock = now;
      final client = FakeOAuthClient();
      final vault = MemoryProfileVault(
        jsonEncode(
          testTokens(now: now, validFor: const Duration(minutes: 10)).toJson(),
        ),
      );
      final auth = CustomerAuth(client: client, vault: vault, now: () => clock);
      expect(await auth.accessToken(), 'access-1');
      expect(client.refreshCalls, 0);

      clock = now.add(const Duration(minutes: 9));
      final tokens = await Future.wait([
        auth.accessToken(),
        auth.accessToken(),
      ]);
      expect(tokens, ['refreshed-1', 'refreshed-1']);
      expect(client.refreshCalls, 1);
      expect((jsonDecode(vault.value!) as Map)['access'], 'refreshed-1');

      // After a 401: a refresh even though the token looks fine.
      expect(await auth.accessToken(forceRefresh: true), 'refreshed-2');
    });

    test('Shopify refusing the refresh signs out on the phone; the network '
        'failing keeps the customer signed in', () async {
      final client = FakeOAuthClient();
      final vault = MemoryProfileVault(jsonEncode(testTokens().toJson()));
      final auth = CustomerAuth(client: client, vault: vault);

      client.refreshError = const AuthNetworkError();
      await expectLater(
        auth.accessToken(forceRefresh: true),
        throwsA(isA<AuthNetworkError>()),
      );
      expect(auth.signedIn, isTrue);
      expect(vault.value, isNotNull);

      client.refreshError = const RefreshRejected();
      expect(await auth.accessToken(forceRefresh: true), isNull);
      expect(auth.signedIn, isFalse);
      expect(vault.value, isNull);
    });

    test('sign-out tells Shopify (id_token_hint), and a failure there '
        'still signs out on the phone', () async {
      final recorder = EndSessionRecorder();
      final vault = MemoryProfileVault(jsonEncode(testTokens().toJson()));
      final auth = CustomerAuth(
        client: FakeOAuthClient(),
        vault: vault,
        httpClient: recorder.client,
      );
      await auth.signOut();
      expect(auth.signedIn, isFalse);
      expect(vault.value, isNull);
      final call = recorder.calls.single;
      expect(
        call.replace(query: '').toString(),
        'https://shopify.com/authentication/79173124173/logout?',
      );
      expect(call.queryParameters['id_token_hint'], testTokens().idToken);

      final failing = EndSessionRecorder()..fail = true;
      final vault2 = MemoryProfileVault(jsonEncode(testTokens().toJson()));
      final auth2 = CustomerAuth(
        client: FakeOAuthClient(),
        vault: vault2,
        httpClient: failing.client,
      );
      await auth2.signOut();
      expect(auth2.signedIn, isFalse);
      expect(vault2.value, isNull);
    });

    test('not configured: sign-in is refused before anything opens', () async {
      final client = FakeOAuthClient();
      final auth = CustomerAuth(
        client: client,
        vault: MemoryProfileVault(),
        configured: false,
      );
      await expectLater(auth.signIn(), throwsA(isA<SignInUnavailable>()));
      expect(client.authorizeCalls, 0);
    });
  });

  group('AccountSession', () {
    test(
      'sign-in outcomes, the email, and listeners hearing of each change',
      () async {
        final client = FakeOAuthClient();
        final session = signedOutSession(client: client);
        await session.load();
        var heard = 0;
        session.addListener(() => heard++);
        expect(session.signInAvailable, isTrue);
        expect(session.signInNeededToOrder, isTrue);

        client.authorizeError = const SignInCancelled();
        expect(await session.signIn(), SignInOutcome.cancelled);
        client.authorizeError = const AuthNetworkError();
        expect(await session.signIn(), SignInOutcome.offline);
        client.authorizeError = const SignInFailed();
        expect(await session.signIn(), SignInOutcome.failed);
        expect(session.signedIn, isFalse);

        expect(await session.signIn(), SignInOutcome.signedIn);
        expect(session.signedIn, isTrue);
        expect(session.email, 'sara@example.com');
        expect(session.signInNeededToOrder, isFalse);
        expect(heard, greaterThan(0));

        await session.signOut();
        expect(session.signedIn, isFalse);
        expect(session.email, isNull);
      },
    );

    test('without auth (no client ID) sign-in is unavailable', () async {
      final session = AccountSession();
      expect(session.signInAvailable, isFalse);
      expect(await session.signIn(), SignInOutcome.unavailable);
      expect(await session.accessToken(), isNull);
      expect(
        AccountSession(asksAtCheckout: false).signInNeededToOrder,
        isFalse,
      );
    });

    test('a refused refresh ends the session and says so', () async {
      final client = FakeOAuthClient();
      final session = await signedInSession(client: client);
      var heard = 0;
      session.addListener(() => heard++);
      client.refreshError = const RefreshRejected();
      expect(await session.accessToken(forceRefresh: true), isNull);
      expect(session.signedIn, isFalse);
      expect(heard, 1);
    });
  });
}
