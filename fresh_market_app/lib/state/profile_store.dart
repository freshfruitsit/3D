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

  /// A change was made before the saved record was read: [load] merges
  /// the record into it rather than replacing it.
  bool _changedBeforeLoad = false;

  /// "Delete my details" before the saved record was read: [load] drops
  /// the record.
  bool _discardSaved = false;

  /// The read of the saved record ([load]), once started.
  Future<void>? _loading;
  bool _readDone = false;
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
  /// something is saved or the shopper skips it. Never before the saved
  /// record was read (a returning shopper is not asked again).
  bool get offersCheckoutSheet =>
      askAtCheckout && loaded && !hasDetails && !_sheetSkipped;

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
  /// "Continue to checkout" with nothing typed counts as a skip, so the
  /// sheet is not shown on every checkout.
  void applyCheckoutSheet(CheckoutSheetResult result, DeliveryArea area) {
    if (result.skipped ||
        (result.contact.isEmpty &&
            CustomerInput.cleanLine(result.building).isEmpty)) {
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
    if (!loaded) _discardSaved = true;
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

  /// True once the saved record was read (at once with no vault).
  bool get loaded => _vault == null || _readDone;

  /// Reads the saved record, once (later calls return the same read). A
  /// record that cannot be read or parsed is dropped (and a damaged one
  /// removed). A change made while it was being read is kept: the record
  /// is merged into it (see [_merge]), never written over unread.
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    final vault = _vault;
    if (vault == null) return;
    String? raw;
    try {
      raw = await vault.read();
    } catch (_) {
      // The phone's secure storage could not be opened or decrypted:
      // start empty; the next change writes a fresh record.
      raw = null;
    }
    _readDone = true;
    if (_discardSaved || raw == null || raw.isEmpty) {
      // Nothing to restore; any change made meanwhile is saved as is.
      notifyListeners();
      return;
    }
    _Saved saved;
    try {
      saved = _parse(jsonDecode(raw));
    } catch (_) {
      // Damaged: removed from the phone, unless a change made meanwhile
      // is about to replace it.
      if (!_changedBeforeLoad) {
        _writing = _writing.then((_) async {
          try {
            await vault.delete();
          } catch (_) {}
        });
      }
      notifyListeners();
      return;
    }
    if (_changedBeforeLoad) {
      _merge(saved);
      _changed();
    } else {
      _apply(saved);
      notifyListeners();
    }
  }

  /// Reads a saved record; throws when it is not a record at all.
  _Saved _parse(Object? saved) {
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
    bool known(Object? id) => id is String && addresses.any((a) => a.id == id);
    final d = saved['default'];
    final c = saved['chosen'];
    return (
      contact: contact,
      addresses: addresses,
      defaultId: known(d) ? d as String : null,
      chosenId: known(c) ? c as String : null,
      skipped: saved['skipped'] == true,
    );
  }

  void _apply(_Saved saved) {
    _contact = saved.contact;
    _addresses
      ..clear()
      ..addAll(saved.addresses);
    _defaultId = saved.defaultId;
    _chosenId = saved.chosenId;
    _sheetSkipped = saved.skipped;
  }

  /// The saved record joined with what changed before it was read: each
  /// contact field typed meanwhile wins (the screens started empty, so
  /// nothing could be cleared), the saved addresses come first and keep
  /// their default, and a skip from either side counts.
  void _merge(_Saved saved) {
    String pick(String now, String before) => now.isNotEmpty ? now : before;
    final c = saved.contact;
    _contact = ContactDetails(
      firstName: pick(_contact.firstName, c.firstName),
      lastName: pick(_contact.lastName, c.lastName),
      mobile: pick(_contact.mobile, c.mobile),
      email: pick(_contact.email, c.email),
    );
    final added = _addresses
        .where((a) => !saved.addresses.any((b) => b.id == a.id))
        .toList();
    _addresses
      ..clear()
      ..addAll(saved.addresses)
      ..addAll(added.take(maxAddresses - saved.addresses.length));
    _defaultId =
        saved.defaultId ??
        (saved.addresses.isEmpty ? _defaultId : saved.addresses.first.id);
    if (addressById(_defaultId) == null) _defaultId = null;
    if (addressById(_chosenId) == null) _chosenId = saved.chosenId;
    _sheetSkipped = _sheetSkipped || saved.skipped;
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

  /// Says the change and saves it. A change before the saved record was
  /// read starts the read (it is merged, see [load]); writes wait for it.
  void _changed() {
    if (!loaded) _changedBeforeLoad = true;
    notifyListeners();
    final vault = _vault;
    if (vault == null) return;
    final reading = load();
    _writing = _writing.then((_) async {
      await reading;
      // What is saved is the state when the write runs, so a merge made
      // by the read is never written over.
      final record = _blank ? null : jsonEncode(_toJson());
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

/// A saved record as read from the phone.
typedef _Saved = ({
  ContactDetails contact,
  List<SavedAddress> addresses,
  String? defaultId,
  String? chosenId,
  bool skipped,
});
