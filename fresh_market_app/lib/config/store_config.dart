/// Store-wide switches that match how the Shopify store is set up.
abstract final class StoreConfig {
  /// Orders need a signed-in customer account (Shopify's customer
  /// accounts: an email and a 6-digit code, no password). The order server
  /// only takes orders with a customer's access token; the app asks first,
  /// so checkout opens signed in. False turns the app's own sign-in step
  /// off again.
  static const bool requireSignInToOrder = true;

  /// The owner's order server (Vercel), e.g. `https://orders.example.com`:
  /// `--dart-define=ORDER_API_BASE=...`. Empty: checkout says "Ordering
  /// isn't available yet".
  static const String orderApiBase = String.fromEnvironment('ORDER_API_BASE');

  /// Delivery is free from this subtotal (AED 200, the store's live
  /// setting). The order server works the fee out; the app only uses this
  /// for the "Add AED x more for free delivery" hint, so keep it in step
  /// with the server's `FREE_DELIVERY_FROM_AED`.
  static const int freeDeliveryFromFils = 20000;
}

/// Shopify's Customer Account API for the store (shop id 79173124173), as
/// a public mobile client: OAuth 2.0 with PKCE (S256) in a Chrome Custom
/// Tab. Verified against the store's OpenID discovery and
/// https://shopify.dev/docs/api/customer/2026-10.
abstract final class CustomerAccountConfig {
  static const String shopId = '79173124173';

  /// Created by the owner in Shopify (Headless channel > Customer Account
  /// API > Public, Mobile): `--dart-define=CUSTOMER_ACCOUNT_CLIENT_ID=...`.
  /// Empty: sign-in shows as not available yet (and nothing crashes).
  static const String clientId = String.fromEnvironment(
    'CUSTOMER_ACCOUNT_CLIENT_ID',
  );

  /// True when the app was built with a client ID.
  static bool get configured => clientId.trim().isNotEmpty;

  static const String authorizationEndpoint =
      'https://shopify.com/authentication/$shopId/oauth/authorize';
  static const String tokenEndpoint =
      'https://shopify.com/authentication/$shopId/oauth/token';
  static const String endSessionEndpoint =
      'https://shopify.com/authentication/$shopId/logout';

  /// Mobile apps must use the `shop.<shop id>.` scheme (Shopify). The
  /// scheme is also the `appAuthRedirectScheme` in
  /// android/app/build.gradle.kts.
  static const String redirectScheme = 'shop.$shopId.app';
  static const String redirectUri = '$redirectScheme://callback';

  static const List<String> scopes = [
    'openid',
    'email',
    'customer-account-api:full',
  ];

  /// The Customer Account API version the app's queries were checked
  /// against.
  static const String apiVersion = '2026-10';

  /// The GraphQL endpoint. It takes the raw access token in the
  /// Authorization header (no "Bearer").
  static const String graphqlEndpoint =
      'https://shopify.com/$shopId/account/customer/api/$apiVersion/graphql';
}
