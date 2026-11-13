import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../delivery/delivery_config.dart';
import '../profile/customer_details.dart';
import '../profile/profile_vault.dart';

/// What checkout is filled in with: the contact details and, when one is
/// in the delivery area, an address.
@immutable
class CheckoutDetails {
  const CheckoutDetails({this.contact = ContactDetails.empty, this.address});

  static const CheckoutDetails none = CheckoutDetails();

  final ContactDetails contact;
  final SavedAddress? address;

  bool get isEmpty => contact.isEmpty && address == null;
}

/// What the "Fill in checkout faster" sheet hands back.
@immutable
class CheckoutSheetResult {
  const CheckoutSheetResult.skip()
    : skipped = true,
      contact = ContactDetails.empty,
      building = '',
      flat = '',
      save = false;

  const CheckoutSheetResult({
    required this.contact,
    this.building = '',
    this.flat = '',
    this.save = true,
  }) : skipped = false;

  /// "Skip, fill in at checkout": nothing is sent and the sheet is not
  /// shown again.
  final bool skipped;
  final ContactDetails contact;

  /// For the current delivery area; '' when not given.
  final String building;
  final String flat;

  /// "Save for next time": false uses the details for this checkout only.
  final bool save;
}

/// The shopper's details for checkout (contact and saved addresses), kept
/// encrypted on the phone through a [ProfileVault]. Every change is saved
/// at once; a record that cannot be read is dropped, never crashes.
class ProfileStore extends ChangeNotifier {
  /// With no [vault] the details live in memory only. [askAtCheckout]
  /// false never shows the first-checkout sheet (the in-memory store
  /// `AppScope` makes when it is given none).
  ProfileStore({this._vault, this.askAtCheckout = true});

  /// How many addresses can be saved.
  static const int maxAddresses = 10;

  final ProfileVault? _vault;
  final bool askAtCheckout;

  ContactDetails _contact = ContactDetails.empty;
  final List<SavedAddress> _addresses = [];
  String? _defaultId;
  String? _chosenId;
  bool _sheetSkipped = false;

  /// Typed in the checkout sheet with "Save for next time" off: used for
  /// checkout, kept in memory only (the sheet opens with it again).
  CheckoutDetails? _oneTime;

  bool _changedBeforeLoad = false;
  bool _loaded = false;
  Future<void> _writing = Future.value();
  int _idSeq = 0;

  ContactDetails get contact => _contact;

  /// Default first, then in the order they were added.
  List<SavedAddress> get addresses {
    final d = defaultAddress;
    return List.unmodifiable([?d, ..._addresses.where((a) => a.id != d?.id)]);
  }

  /// The default address (the first one saved, unless another was made
  /// the default); null when none is saved.
  SavedAddress? get defaultAddress =>
      addressById(_defaultId) ?? (_addresses.isEmpty ? null : _addresses.first);

  bool isDefault(SavedAddress address) => defaultAddress?.id == address.id;

  bool get hasContact => !_contact.isEmpty;
  bool get hasAddresses => _addresses.isNotEmpty;

  /// Anything saved at all ("Delete my details" is offered).
  bool get hasDetails => hasContact || hasAddresses;

  bool get canAddAddress => _addresses.length < maxAddresses;

  /// True once the shopper chose "Skip, fill in at checkout".
  bool get checkoutSheetSkipped => _sheetSkipped;

  /// The first checkout offers the "Fill in checkout faster" sheet: until
  /// something is saved or the shopper skips it.
  bool get offersCheckoutSheet =>
      askAtCheckout && !hasDetails && !_sheetSkipped;

  /// The details typed for one checkout only (see [CheckoutSheetResult]).
  CheckoutDetails? get oneTime => _oneTime;

  SavedAddress? addressById(String? id) {
    if (id == null) return null;
    for (final a in _addresses) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// The saved address checkout uses in [area]: the one chosen on the
  /// cart, else the default, else the first saved there. Null when none
  /// is in [area] (a building in another area is never used).
  SavedAddress? addressFor(DeliveryArea? area) {
    if (area == null) return null;
    bool here(SavedAddress? a) =>
        a != null && CustomerInput.sameArea(a.area, area);
    final chosen = addressById(_chosenId);
    if (here(chosen)) return chosen;
    final d = defaultAddress;
    if (here(d)) return d;
    for (final a in _addresses) {
      if (here(a)) return a;
    }
    return null;
  }

  /// When no saved address is in [area], the one to offer instead ("Your
  /// Home address is in Dubai Marina"): the chosen one, else the default.
  /// Null when one is in [area] or none is saved.
  SavedAddress? addressElsewhere(DeliveryArea? area) {
    if (_addresses.isEmpty || addressFor(area) != null) return null;
    return addressById(_chosenId) ?? defaultAddress;
  }

  /// What checkout is filled in with in [area]: the saved details, or
  /// the ones typed for one checkout.
  CheckoutDetails checkoutDetails(DeliveryArea? area) {
    if (hasDetails) {
      return CheckoutDetails(contact: _contact, address: addressFor(area));
    }
    final once = _oneTime;
    if (once == null) return CheckoutDetails.none;
    final address = once.address;
    return CheckoutDetails(
      contact: once.contact,
      address:
          address != null &&
              area != null &&
              CustomerInput.sameArea(address.area, area)
          ? address
          : null,
    );
  }

  /// A new id for an address.
  String newAddressId() =>
      'a${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${(_idSeq++).toRadixString(36)}';

  void saveContact(ContactDetails contact) {
    if (contact == _contact) return;
    _contact = contact;
    _changed();
  }

  /// Adds [address], or replaces the saved one with its id. The first
  /// address is the default; [makeDefault] makes this one the default.
  /// Nothing is added past [maxAddresses].
  void saveAddress(SavedAddress address, {bool makeDefault = false}) {
    final at = _addresses.indexWhere((a) => a.id == address.id);
    if (at >= 0) {
      _addresses[at] = address;
    } else {
      if (!canAddAddress) return;
      _addresses.add(address);
    }
    if (makeDefault || _addresses.length == 1) _defaultId = address.id;
    _changed();
  }

  void removeAddress(String id) {
    final before = _addresses.length;
    _addresses.removeWhere((a) => a.id == id);
    if (_addresses.length == before) return;
    if (_defaultId == id) _defaultId = null;
    if (_chosenId == id) _chosenId = null;
    _changed();
  }

  void setDefault(String id) {
    if (addressById(id) == null || _defaultId == id) return;
    _defaultId = id;
    _changed();
  }

  /// The address the cart delivers to (until another is chosen).
  void choose(String id) {
    if (addressById(id) == null || _chosenId == id) return;
    _chosenId = id;
    _changed();
  }

  /// Applies the "Fill in checkout faster" sheet's answer for [area].
  void applyCheckoutSheet(CheckoutSheetResult result, DeliveryArea area) {
    if (result.skipped) {
      _sheetSkipped = true;
      _oneTime = null;
      _changed();
      return;
    }
    final building = CustomerInput.cleanLine(result.building);
    final address = building.isEmpty
        ? null
        : SavedAddress(
            id: newAddressId(),
            label: AddressLabel.home,
            area: area,
            building: building,
            flat: CustomerInput.cleanLine(result.flat),
          );
    if (!result.save) {
      _oneTime = CheckoutDetails(contact: result.contact, address: address);
      notifyListeners();
      return;
    }
    _oneTime = null;
    _contact = result.contact;
    if (address != null && canAddAddress) {
      _addresses.add(address);
      _defaultId = address.id;
      _chosenId = address.id;
    }
    _changed();
  }

  /// "Delete my details": removes everything this store keeps, here and
  /// on the phone. The first checkout asks again.
  Future<void> deleteAll() async {
    _contact = ContactDetails.empty;
    _addresses.clear();
    _defaultId = null;
    _chosenId = null;
    _sheetSkipped = false;
    _oneTime = null;
    _changed();
    await _writing;
  }

  /// Completes when every change so far has reached the vault (tests).
  Future<void> get idle => _writing;

  /// True once [load] has run.
  bool get loaded => _loaded;

  /// Reads the saved record. A record that cannot be read or parsed is
  /// dropped (and a damaged one removed); a change made while loading
  /// wins over the record.
  Future<void> load() async {
    final vault = _vault;
    if (vault == null) {
      _loaded = true;
      return;
    }
    String? raw;
    try {
      raw = await vault.read();
    } catch (_) {
      // The phone's secure storage could not be opened or decrypted:
      // start empty; the next change writes a fresh record.
      raw = null;
    }
    _loaded = true;
    if (_changedBeforeLoad || raw == null || raw.isEmpty) return;
    try {
      _restore(jsonDecode(raw));
    } catch (_) {
      _contact = ContactDetails.empty;
      _addresses.clear();
      _defaultId = null;
      _chosenId = null;
      _sheetSkipped = false;
      _writing = _writing.then((_) async {
        try {
          await vault.delete();
        } catch (_) {}
      });
    }
    notifyListeners();
  }

  void _restore(Object? saved) {
    if (saved is! Map) throw const FormatException('not a record');
    final contact = ContactDetails.fromJson(saved['contact']);
    final list = saved['addresses'];
    final addresses = <SavedAddress>[];
    if (list is List) {
      for (final item in list) {
        final a = SavedAddress.fromJson(item);
        if (a != null &&
            addresses.length < maxAddresses &&
            !addresses.any((b) => b.id == a.id)) {
          addresses.add(a);
        }
      }
    }
    _contact = contact;
    _addresses
      ..clear()
      ..addAll(addresses);
    final d = saved['default'];
    _defaultId = d is String && addressById(d) != null ? d : null;
    final c = saved['chosen'];
    _chosenId = c is String && addressById(c) != null ? c : null;
    _sheetSkipped = saved['skipped'] == true;
  }

  bool get _blank => !hasDetails && !_sheetSkipped;

  Map<String, dynamic> _toJson() => {
    'v': 1,
    'contact': _contact.toJson(),
    'addresses': [for (final a in _addresses) a.toJson()],
    'default': ?_defaultId,
    'chosen': ?_chosenId,
    'skipped': _sheetSkipped,
  };

  void _changed() {
    if (!_loaded) _changedBeforeLoad = true;
    notifyListeners();
    final vault = _vault;
    if (vault == null) return;
    final record = _blank ? null : jsonEncode(_toJson());
    _writing = _writing.then((_) async {
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
