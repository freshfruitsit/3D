import 'package:flutter/foundation.dart';

import '../delivery/delivery_config.dart';

/// The shopper's own contact details, kept on the phone to fill in the
/// Shopify checkout. Every field is optional; an empty string means "not
/// given".
@immutable
class ContactDetails {
  const ContactDetails({
    this.firstName = '',
    this.lastName = '',
    this.mobile = '',
    this.email = '',
  });

  static const ContactDetails empty = ContactDetails();

  /// Any script (Arabic too), trimmed, inner spaces collapsed.
  final String firstName;
  final String lastName;

  /// Normalised by [CustomerInput.normaliseMobile]: `+9715XXXXXXXX` for a
  /// UAE mobile, or another international number as `+` and its digits.
  final String mobile;

  /// Trimmed, as typed.
  final String email;

  bool get isEmpty =>
      firstName.isEmpty && lastName.isEmpty && mobile.isEmpty && email.isEmpty;

  /// "Sara Ahmed", or the one name given; '' when neither.
  String get fullName =>
      [firstName, lastName].where((p) => p.isNotEmpty).join(' ');

  /// The mobile as people write it ("+971 50 123 4567").
  String get mobileDisplay => CustomerInput.formatMobile(mobile);

  ContactDetails copyWith({
    String? firstName,
    String? lastName,
    String? mobile,
    String? email,
  }) => ContactDetails(
    firstName: firstName ?? this.firstName,
    lastName: lastName ?? this.lastName,
    mobile: mobile ?? this.mobile,
    email: email ?? this.email,
  );

  Map<String, dynamic> toJson() => {
    'first': firstName,
    'last': lastName,
    'mobile': mobile,
    'email': email,
  };

  /// Reads [toJson]'s shape. Anything that is not a valid value is left
  /// out, so a damaged record never reaches checkout.
  factory ContactDetails.fromJson(Object? json) {
    if (json is! Map) return empty;
    String text(String key, int max) {
      final value = json[key];
      if (value is! String) return '';
      final clean = CustomerInput.cleanLine(value);
      return clean.length > max ? '' : clean;
    }

    final mobile = json['mobile'];
    final email = text('email', CustomerInput.emailMax);
    return ContactDetails(
      firstName: text('first', CustomerInput.nameMax),
      lastName: text('last', CustomerInput.nameMax),
      mobile: mobile is String
          ? CustomerInput.normaliseMobile(mobile) ?? ''
          : '',
      email: CustomerInput.isValidEmail(email) ? email : '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ContactDetails &&
      other.firstName == firstName &&
      other.lastName == lastName &&
      other.mobile == mobile &&
      other.email == email;

  @override
  int get hashCode => Object.hash(firstName, lastName, mobile, email);
}

/// What the shopper calls a saved address.
enum AddressLabel {
  home('home', 'Home'),
  office('office', 'Office'),
  other('other', 'Other');

  const AddressLabel(this.code, this.label);

  /// Saved on the phone.
  final String code;

  /// "Home".
  final String label;

  static AddressLabel fromCode(Object? code) {
    for (final l in values) {
      if (l.code == code) return l;
    }
    return AddressLabel.other;
  }
}

/// One delivery address: the area comes from the location picker (so the
/// emirate always follows it); the shopper types the rest.
@immutable
class SavedAddress {
  const SavedAddress({
    required this.id,
    required this.label,
    required this.area,
    required this.building,
    this.street = '',
    this.flat = '',
    this.instructions = '',
  });

  /// Stable on this phone; never sent anywhere.
  final String id;
  final AddressLabel label;
  final DeliveryArea area;

  /// "Bay Square, Building 5" or "Villa 12". Required.
  final String building;

  /// Optional.
  final String street;

  /// "Flat 302", "Floor 3". Optional.
  final String flat;

  /// For the driver, at most [CustomerInput.instructionsMax] characters.
  /// Optional.
  final String instructions;

  /// Shopify's first address line: the building, then the street.
  String get address1 => street.isEmpty ? building : '$building, $street';

  /// "Bay Square, Building 5 · Flat 302".
  String get firstLine =>
      [address1, flat].where((p) => p.isNotEmpty).join(' · ');

  /// What screen readers hear for the whole address.
  String get semantics =>
      '${label.label} address: '
      '${[address1, flat, area.label].where((p) => p.isNotEmpty).join(', ')}';

  SavedAddress copyWith({
    AddressLabel? label,
    DeliveryArea? area,
    String? building,
    String? street,
    String? flat,
    String? instructions,
  }) => SavedAddress(
    id: id,
    label: label ?? this.label,
    area: area ?? this.area,
    building: building ?? this.building,
    street: street ?? this.street,
    flat: flat ?? this.flat,
    instructions: instructions ?? this.instructions,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label.code,
    'area': area.toJson(),
    'building': building,
    'street': street,
    'flat': flat,
    'notes': instructions,
  };

  /// Reads [toJson]'s shape; null when the id, the area or the building is
  /// missing or invalid.
  static SavedAddress? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final area = DeliveryArea.fromJson(json['area']);
    String text(String key, int max) {
      final value = json[key];
      if (value is! String) return '';
      final clean = key == 'notes'
          ? CustomerInput.cleanNote(value)
          : CustomerInput.cleanLine(value);
      return clean.length > max ? clean.substring(0, max) : clean;
    }

    final building = text('building', CustomerInput.buildingMax);
    if (id is! String || id.isEmpty || area == null || building.isEmpty) {
      return null;
    }
    return SavedAddress(
      id: id,
      label: AddressLabel.fromCode(json['label']),
      area: area,
      building: building,
      street: text('street', CustomerInput.streetMax),
      flat: text('flat', CustomerInput.flatMax),
      instructions: text('notes', CustomerInput.instructionsMax),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SavedAddress &&
      other.id == id &&
      other.label == label &&
      other.area == area &&
      other.building == building &&
      other.street == street &&
      other.flat == flat &&
      other.instructions == instructions;

  @override
  int get hashCode =>
      Object.hash(id, label, area, building, street, flat, instructions);
}

/// How typed details are cleaned, checked and shown.
abstract final class CustomerInput {
  static const int nameMax = 60;
  static const int emailMax = 254;
  static const int buildingMax = 80;
  static const int streetMax = 80;
  static const int flatMax = 40;
  static const int instructionsMax = 200;

  /// Under a mobile the phone cannot use.
  static const String mobileError =
      'Enter a UAE mobile like 050 123 4567, or a number starting with +.';

  /// Under an email that cannot be right.
  static const String emailError = 'Enter an email like name@example.com.';

  /// Under an empty building on an address.
  static const String buildingError = 'Enter the building or villa.';

  /// One line of typed text: trimmed, runs of spaces (and any line breaks
  /// or control characters) made one space. Any script is kept.
  static String cleanLine(String input) => input
      .replaceAll(RegExp(r'[\u0000-\u001F\u007F]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  /// Delivery instructions: like [cleanLine], so the note travels as one
  /// line in the order.
  static String cleanNote(String input) => cleanLine(input);

  /// Arabic-Indic and Eastern Arabic-Indic digits as 0-9, so a number
  /// typed on an Arabic keyboard is understood.
  static String _asciiDigits(String input) {
    final out = StringBuffer();
    for (final rune in input.runes) {
      if (rune >= 0x0660 && rune <= 0x0669) {
        out.writeCharCode(0x30 + rune - 0x0660);
      } else if (rune >= 0x06F0 && rune <= 0x06F9) {
        out.writeCharCode(0x30 + rune - 0x06F0);
      } else {
        out.writeCharCode(rune);
      }
    }
    return out.toString();
  }

  static final RegExp _uaeMobile = RegExp(r'^5\d{8}$');

  /// A mobile number in any common form, normalised:
  ///
  /// - UAE mobiles: "050 123 4567", "50 1234567", "+971 50 123 4567",
  ///   "00971501234567", "971501234567", "+971 (0)50 …" all become
  ///   `+971501234567`.
  /// - Any other international number written with + (or 00): `+` and
  ///   its 8 to 15 digits (E.164).
  ///
  /// Returns '' for empty input and null when it is not a number the
  /// store can call. A number starting +971 must be a UAE mobile, so a
  /// UAE mobile with a digit missing is caught rather than passed on as
  /// "some other number".
  static String? normaliseMobile(String input) {
    var s = _asciiDigits(input.trim());
    if (s.isEmpty) return '';
    s = s.replaceAll(RegExp(r'[\s\-.()\u00A0\u200E\u200F\u202A-\u202E]'), '');
    if (s.startsWith('00')) s = '+${s.substring(2)}';
    final plus = s.startsWith('+');
    final digits = plus ? s.substring(1) : s;
    if (digits.isEmpty || !RegExp(r'^\d+$').hasMatch(digits)) return null;

    String? uae(String national) =>
        _uaeMobile.hasMatch(national) ? '+971$national' : null;

    if (plus) {
      if (digits.startsWith('971')) {
        var rest = digits.substring(3);
        if (rest.startsWith('0')) rest = rest.substring(1);
        return uae(rest);
      }
      if (digits.startsWith('0') || digits.length < 8 || digits.length > 15) {
        return null;
      }
      return '+$digits';
    }
    if (digits.length == 12 && digits.startsWith('971')) {
      return uae(digits.substring(3));
    }
    if (digits.length == 10 && digits.startsWith('05')) {
      return uae(digits.substring(1));
    }
    if (digits.length == 9) return uae(digits);
    return null;
  }

  /// [mobileError] when [input] is not empty and not a usable number.
  static String? validateMobile(String? input) =>
      normaliseMobile(input ?? '') == null ? mobileError : null;

  /// A UAE mobile as "+971 50 123 4567"; any other number as stored.
  static String formatMobile(String normalised) {
    if (normalised.length == 13 && normalised.startsWith('+9715')) {
      return '+971 ${normalised.substring(4, 6)} '
          '${normalised.substring(6, 9)} ${normalised.substring(9)}';
    }
    return normalised;
  }

  static final RegExp _email = RegExp(
    r'^[^\s@]+@[^\s@.]+(\.[^\s@.]+)*\.[^\s@.]{2,}$',
  );

  /// A sane email: something@domain.tld, no spaces, at most 254
  /// characters. Empty is valid (the field is optional).
  static bool isValidEmail(String input) {
    final s = input.trim();
    if (s.isEmpty) return true;
    return s.length <= emailMax && _email.hasMatch(s);
  }

  /// [emailError] when [input] is not empty and not an email.
  static String? validateEmail(String? input) =>
      isValidEmail(input ?? '') ? null : emailError;

  /// [buildingError] when [input] is blank.
  static String? validateBuilding(String? input) =>
      cleanLine(input ?? '').isEmpty ? buildingError : null;

  /// Shopify's province code for each emirate, as its UAE checkout lists
  /// them (AZ Abu Dhabi, AJ Ajman, DU Dubai, FU Fujairah, RK Ras
  /// al-Khaimah, SH Sharjah, UQ Umm al-Quwain).
  static String provinceCode(Emirate emirate) => switch (emirate) {
    Emirate.dubai => 'DU',
    Emirate.abuDhabi => 'AZ',
    Emirate.sharjah => 'SH',
    Emirate.ajman => 'AJ',
    Emirate.ummAlQuwain => 'UQ',
    Emirate.rasAlKhaimah => 'RK',
    Emirate.fujairah => 'FU',
  };

  /// True when [a] and [b] are the same place for an address: the same
  /// emirate and area name (case and spacing aside), wherever the pin
  /// inside it was dropped.
  static bool sameArea(DeliveryArea a, DeliveryArea b) =>
      a.emirate == b.emirate &&
      cleanLine(a.name).toLowerCase() == cleanLine(b.name).toLowerCase();
}
