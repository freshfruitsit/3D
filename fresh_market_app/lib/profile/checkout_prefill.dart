import '../delivery/delivery_config.dart';
import 'customer_details.dart';

/// What the app adds to the Shopify cart permalink so checkout opens with
/// the shopper's details already filled in (they can still change them
/// there). Verified on the store's checkout: `checkout[email]` and
/// `checkout[shipping_address][...]` fill the Contact and Delivery fields.
abstract final class CheckoutPrefill {
  /// The cart attribute that carries an address's delivery instructions
  /// (cart attributes reach the order, like the delivery attributes).
  static const String instructionsAttribute = 'Delivery instructions';

  static const String email = 'checkout[email]';
  static const String firstName = 'checkout[shipping_address][first_name]';
  static const String lastName = 'checkout[shipping_address][last_name]';
  static const String address1 = 'checkout[shipping_address][address1]';
  static const String address2 = 'checkout[shipping_address][address2]';
  static const String city = 'checkout[shipping_address][city]';
  static const String province = 'checkout[shipping_address][province]';
  static const String country = 'checkout[shipping_address][country]';
  static const String phone = 'checkout[shipping_address][phone]';

  /// The store delivers in the UAE only.
  static const String countryCode = 'AE';

  /// [address] when it is in [area] (see [CustomerInput.sameArea]);
  /// otherwise null, so a building in another area is never sent.
  static SavedAddress? addressIn(SavedAddress? address, DeliveryArea? area) {
    if (address == null || area == null) return null;
    return CustomerInput.sameArea(address.area, area) ? address : null;
  }

  /// The checkout fields for [contact], and for [address] when it is in
  /// the current delivery [area], in the order checkout shows them.
  ///
  /// - Contact: email, first and last name, phone (already normalised).
  /// - Address in [area]: address1 (building, street), address2 (flat).
  /// - With anything to send and an [area]: city (the area's name),
  ///   province (the emirate's Shopify code) and country (AE). With an
  ///   address in another area only these are sent, never its building.
  ///
  /// Empty values are left out; with no details at all nothing is sent.
  static Map<String, String> params({
    required ContactDetails contact,
    SavedAddress? address,
    DeliveryArea? area,
  }) {
    final out = <String, String>{};
    void put(String key, String value) {
      final v = CustomerInput.cleanLine(value);
      if (v.isNotEmpty) out[key] = v;
    }

    final match = addressIn(address, area);
    put(email, contact.email);
    put(firstName, contact.firstName);
    put(lastName, contact.lastName);
    if (area != null && (match != null || !contact.isEmpty)) {
      if (match != null) {
        put(address1, match.address1);
        put(address2, match.flat);
      }
      put(city, area.name);
      put(province, CustomerInput.provinceCode(area.emirate));
      put(country, countryCode);
    }
    put(phone, contact.mobile);
    return out;
  }

  /// The cart attributes [address] adds when it is in [area]: its
  /// delivery instructions, if any.
  static Map<String, String> attributes({
    SavedAddress? address,
    DeliveryArea? area,
  }) {
    final match = addressIn(address, area);
    final note = CustomerInput.cleanNote(match?.instructions ?? '');
    return note.isEmpty ? const {} : {instructionsAttribute: note};
  }
}
