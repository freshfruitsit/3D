import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/delivery/delivery.dart';
import 'package:fresh_market_app/profile/customer_details.dart';
import 'package:fresh_market_app/profile/profile_vault.dart';
import 'package:fresh_market_app/app_nav.dart';
import 'package:fresh_market_app/services/order_api.dart';
import 'package:fresh_market_app/state/profile_store.dart';

/// Fictional demo data only.
const sara = ContactDetails(
  firstName: 'Sara',
  lastName: 'Ahmed',
  mobile: '+971501234567',
  email: 'sara@example.com',
);

DeliveryArea area(String name) => DeliveryConfig.areaNamed(name)!;

SavedAddress home({String id = 'h1', String flat = 'Flat 302'}) => SavedAddress(
  id: id,
  label: AddressLabel.home,
  area: area('Business Bay'),
  building: 'Bay Square, Building 5',
  flat: flat,
  instructions: 'Call when you arrive',
);

SavedAddress office() => SavedAddress(
  id: 'o1',
  label: AddressLabel.office,
  area: area('Dubai Marina'),
  building: 'Marina Plaza',
  street: 'Al Marsa Street',
  flat: 'Office 1204',
);

void main() {
  group('mobile numbers', () {
    test('every common UAE form becomes +9715XXXXXXXX', () {
      for (final input in [
        '050 123 4567',
        '0501234567',
        '50 1234567',
        '501234567',
        '+971 50 123 4567',
        '+971501234567',
        '00971501234567',
        '00971 50 123 4567',
        '971501234567',
        '+971 (0)50 123 4567',
        '+971-50-123-4567',
        '050.123.4567',
        '  050 123 4567  ',
        // Arabic-Indic digits from an Arabic keyboard.
        '٠٥٠١٢٣٤٥٦٧',
      ]) {
        expect(
          CustomerInput.normaliseMobile(input),
          '+971501234567',
          reason: input,
        );
      }
      expect(CustomerInput.normaliseMobile('055 765 4321'), '+971557654321');
    });

    test('other international numbers written with + or 00 (E.164)', () {
      expect(
        CustomerInput.normaliseMobile('+44 20 7946 0958'),
        '+442079460958',
      );
      expect(
        CustomerInput.normaliseMobile('0044 7700 900123'),
        '+447700900123',
      );
      expect(CustomerInput.normaliseMobile('+91 98765 43210'), '+919876543210');
      expect(
        CustomerInput.normaliseMobile('+1 (202) 555-0143'),
        '+12025550143',
      );
      // 8 and 15 digits are the limits.
      expect(CustomerInput.normaliseMobile('+12345678'), '+12345678');
      expect(
        CustomerInput.normaliseMobile('+123456789012345'),
        '+123456789012345',
      );
    });

    test('empty is fine (optional); anything else is an error', () {
      expect(CustomerInput.normaliseMobile(''), '');
      expect(CustomerInput.normaliseMobile('   '), '');
      expect(CustomerInput.validateMobile(''), isNull);
      for (final bad in [
        '12345',
        '050 123 456', // a digit short
        '050 123 45678', // a digit long
        '+971 50 123 456', // +971 must be a UAE mobile
        '+971 4 123 4567', // a landline under +971
        '04 123 4567', // a landline
        '+1234567', // 7 digits
        '+1234567890123456', // 16 digits
        '+0501234567',
        'abc',
        '050 123 4567 ext 2',
        '++971501234567',
        '+',
      ]) {
        expect(CustomerInput.normaliseMobile(bad), isNull, reason: bad);
        expect(
          CustomerInput.validateMobile(bad),
          CustomerInput.mobileError,
          reason: bad,
        );
      }
    });

    test('shown the way people write them', () {
      expect(CustomerInput.formatMobile('+971501234567'), '+971 50 123 4567');
      expect(CustomerInput.formatMobile('+442079460958'), '+442079460958');
      expect(CustomerInput.formatMobile(''), '');
      expect(sara.mobileDisplay, '+971 50 123 4567');
    });
  });

  group('email, names and text', () {
    test('sane emails pass, others are said', () {
      for (final ok in [
        'sara@example.com',
        'sara.ahmed+shop@example.co.ae',
        'S@EXAMPLE.AE',
        '',
        '  sara@example.com  ',
      ]) {
        expect(CustomerInput.isValidEmail(ok), isTrue, reason: ok);
      }
      for (final bad in [
        'sara',
        'sara@',
        '@example.com',
        'sara@example',
        'sara@example.c',
        'sara ahmed@example.com',
        'sara@@example.com',
        'sara@example..com',
        '${'a' * 250}@example.com',
      ]) {
        expect(CustomerInput.isValidEmail(bad), isFalse, reason: bad);
        expect(CustomerInput.validateEmail(bad), CustomerInput.emailError);
      }
    });

    test('names in any script are trimmed and kept', () {
      expect(CustomerInput.cleanLine('  سارة   أحمد  '), 'سارة أحمد');
      expect(CustomerInput.cleanLine('Sara\n Ahmed\t'), 'Sara Ahmed');
      expect(CustomerInput.cleanLine('   '), '');
    });

    test('a building is required on an address', () {
      expect(CustomerInput.validateBuilding(''), CustomerInput.buildingError);
      expect(CustomerInput.validateBuilding('  '), CustomerInput.buildingError);
      expect(CustomerInput.validateBuilding('Villa 12'), isNull);
    });
  });

  group('ProfileStore', () {
    test('saves encrypted-vault records and reads them back', () async {
      final vault = MemoryProfileVault();
      final store = ProfileStore(vault: vault);
      await store.load();
      store.saveContact(sara);
      store.saveAddress(home());
      store.saveAddress(office());
      await store.idle;
      expect(vault.value, isNotNull);

      final again = ProfileStore(vault: vault);
      await again.load();
      expect(again.contact, sara);
      expect(again.addresses.map((a) => a.id), ['h1', 'o1']);
      expect(again.defaultAddress!.id, 'h1', reason: 'the first is default');
      expect(again.addresses.first, home());
    });

    test('the default comes first; making another the default', () async {
      final store = ProfileStore();
      store.saveAddress(home());
      store.saveAddress(office(), makeDefault: true);
      expect(store.defaultAddress!.id, 'o1');
      expect(store.addresses.map((a) => a.id), ['o1', 'h1']);
      store.removeAddress('o1');
      expect(store.defaultAddress!.id, 'h1');
    });

    test('the address used is the one in the delivery area', () {
      final store = ProfileStore()
        ..saveAddress(home())
        ..saveAddress(office());
      expect(store.addressFor(area('Business Bay'))!.id, 'h1');
      expect(store.addressFor(area('Dubai Marina'))!.id, 'o1');
      expect(store.addressFor(area('Mirdif')), isNull);
      expect(store.addressElsewhere(area('Mirdif'))!.id, 'h1');
      expect(store.addressElsewhere(area('Business Bay')), isNull);
      // A chosen address wins in its own area only.
      final second = home(id: 'h2', flat: 'Flat 101');
      store
        ..saveAddress(second)
        ..choose('h2');
      expect(store.addressFor(area('Business Bay'))!.id, 'h2');
      expect(store.addressFor(area('Dubai Marina'))!.id, 'o1');
    });

    test('a damaged record is dropped, never crashes', () async {
      for (final raw in [
        'not json',
        '[1,2,3]',
        '{"contact": 5, "addresses": "x"}',
        '{"contact": {"first": 7, "mobile": "12", "email": "bad"}, '
            '"addresses": [{"id": "a"}, null, 3]}',
      ]) {
        final vault = MemoryProfileVault(raw);
        final store = ProfileStore(vault: vault);
        await store.load();
        await store.idle;
        expect(store.contact.firstName, '', reason: raw);
        expect(store.contact.mobile, '', reason: raw);
        expect(store.contact.email, '', reason: raw);
        expect(store.addresses, isEmpty, reason: raw);
      }
      // Unparseable JSON is removed from the phone.
      final vault = MemoryProfileVault('not json');
      await ProfileStore(vault: vault).load();
      await Future<void>.delayed(Duration.zero);
      expect(vault.value, isNull);
    });

    test('an unreadable vault starts empty and keeps working', () async {
      final vault = MemoryProfileVault()..broken = true;
      final store = ProfileStore(vault: vault);
      await store.load();
      expect(store.hasDetails, isFalse);
      store.saveContact(sara);
      await store.idle;
      expect(store.contact, sara, reason: 'kept in memory for this run');
    });

    test('valid parts of a record survive a bad part', () async {
      final record = jsonEncode({
        'contact': {
          'first': 'Sara',
          'last': 'Ahmed',
          'mobile': '050 123 4567',
          'email': 'nope',
        },
        'addresses': [
          home().toJson(),
          {
            'id': 'bad',
            'area': {'name': 'X'},
            'building': 'B',
          },
        ],
        'default': 'missing',
      });
      final store = ProfileStore(vault: MemoryProfileVault(record));
      await store.load();
      expect(store.contact.mobile, '+971501234567');
      expect(store.contact.email, '');
      expect(store.addresses.map((a) => a.id), ['h1']);
      expect(store.defaultAddress!.id, 'h1');
    });

    test('Delete my details removes everything from the phone', () async {
      final vault = MemoryProfileVault();
      final store = ProfileStore(vault: vault)
        ..saveContact(sara)
        ..saveAddress(home());
      await store.load();
      await store.idle;
      expect(vault.value, isNotNull);
      await store.deleteAll();
      expect(store.hasDetails, isFalse);
      expect(vault.value, isNull);
    });

    test('the store account fills only the empty contact fields', () async {
      final vault = MemoryProfileVault();
      final store = ProfileStore(vault: vault)
        ..saveContact(const ContactDetails(firstName: 'Sara'));
      store.fillMissingContact(
        firstName: 'Sarah',
        lastName: 'Ahmed',
        mobile: '+971501234567',
        email: 'sara@example.com',
      );
      expect(store.contact, sara, reason: 'the typed first name is kept');
      await store.idle;
      final later = ProfileStore(vault: vault);
      await later.load();
      expect(later.contact, sara);
      // Nothing new: nothing written.
      final writes = vault.writes.length;
      later.fillMissingContact(firstName: 'Other');
      await later.idle;
      expect(vault.writes, hasLength(writes));
    });
  });

  group('ProfileStore: a slow first read', () {
    final saved = jsonEncode({
      'v': 1,
      'contact': sara.toJson(),
      'addresses': [home().toJson(), office().toJson()],
      'default': 'h1',
    });

    test('nothing is offered or written before the record is read', () async {
      final vault = _GatedVault(saved);
      final store = ProfileStore(vault: vault);
      final loading = store.load();
      expect(store.loaded, isFalse);
      vault.open();
      await loading;
      expect(store.loaded, isTrue);
      expect(store.contact, sara);
      expect(vault.writes, isEmpty);
    });

    test('saving My details or an address during the read merges', () async {
      final vault = _GatedVault(saved);
      final store = ProfileStore(vault: vault);
      final loading = store.load();
      store.saveContact(const ContactDetails(email: 'sara.new@example.com'));
      final villa = SavedAddress(
        id: 'n1',
        label: AddressLabel.other,
        area: area('Mirdif'),
        building: 'Villa 12',
      );
      store.saveAddress(villa);
      vault.open();
      await loading;
      await store.idle;
      // The field typed meanwhile wins; the others are kept.
      expect(store.contact.email, 'sara.new@example.com');
      expect(store.contact.firstName, 'Sara');
      expect(store.contact.mobile, '+971501234567');
      // The saved addresses first, their default kept; the new one added.
      expect(store.addresses.map((a) => a.id), ['h1', 'o1', 'n1']);
      expect(store.defaultAddress!.id, 'h1');
      final again = ProfileStore(vault: MemoryProfileVault(vault.value));
      await again.load();
      expect(again.addresses.map((a) => a.id), ['h1', 'o1', 'n1']);
      expect(again.contact.lastName, 'Ahmed');
    });

    test('Delete my details during the read removes the record', () async {
      final vault = _GatedVault(saved);
      final store = ProfileStore(vault: vault)
        ..saveContact(const ContactDetails(firstName: 'Sara'));
      final deleting = store.deleteAll();
      vault.open();
      await deleting;
      expect(store.hasDetails, isFalse);
      expect(vault.value, isNull);
    });
  });

  group('checkout pin', () {
    test('the order\'s delivery pin is the pin of the address sent', () {
      final delivery = DeliveryStore(
        now: () => DateTime.utc(2026, 11, 13, 6),
        refreshEvery: null,
      );
      // A pin in Business Bay, 1 km from where Home was saved.
      delivery.setArea(
        const DeliveryArea(
          name: 'Business Bay',
          emirate: Emirate.dubai,
          lat: 25.194,
          lng: 55.265,
        ),
      );
      final profile = ProfileStore()..saveAddress(home());
      // What checkout does first: the delivery pin moves to the address.
      AppNav.alignDeliveryWithAddress(delivery: delivery, profile: profile);
      expect(delivery.area, home().area);
      final request = DeliveryRequest(
        mode: delivery.mode,
        area: delivery.area!,
        pin: profile.checkoutDetails(delivery.area).address!.area.pin,
      ).toJson();
      final pin = home().area;
      expect(
        request['pin'],
        '${pin.lat.toStringAsFixed(5)},${pin.lng.toStringAsFixed(5)}',
      );
      expect((request['area'] as Map)['emirate'], 'dubai');
    });
  });
}

/// A vault whose read waits until [open] (a slow phone at start-up).
class _GatedVault extends MemoryProfileVault {
  _GatedVault(super.value);

  final Completer<void> _gate = Completer<void>();

  void open() => _gate.complete();

  @override
  Future<String?> read() async {
    await _gate.future;
    return super.read();
  }
}
