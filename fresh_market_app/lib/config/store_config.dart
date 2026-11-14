/// Store-wide switches that match how the Shopify store is set up.
abstract final class StoreConfig {
  /// Orders need a signed-in customer account (email and a 6-digit code,
  /// no password). The store itself enforces it with "Require customers
  /// to sign in to their account before checkout" (Shopify admin:
  /// Settings > Checkout); the app asks first, so checkout opens signed
  /// in. False turns the app's own sign-in step off again.
  static const bool requireSignInToOrder = true;
}
