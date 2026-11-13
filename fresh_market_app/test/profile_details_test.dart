import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:fresh_market_app/delivery/delivery.dart';
import 'package:fresh_market_app/profile/checkout_prefill.dart';
import 'package:fresh_market_app/profile/customer_details.dart';
import 'package:fresh_market_app/profile/profile_vault.dart';
import 'package:fresh_market_app/services/fake_shopify_api.dart';
import 'package:fresh_market_app/state/cart_store.dart';
import 'package:fresh_market_app/state/profile_store.dart';

/// Fictional demo data only.
const sara = ContactDetails(
  firstName: 'Sara',
  lastName: 'Ahmed',
  mobile: '+971501234567',
  email: 'sara@example.com',
);

DeliveryArea area(String name) => DeliveryConfig.areaNamed(name)!;

SavedAddress home({String id = 'h1', String flat = 'Flat 302'}) =>
    SavedAddress(
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
      expect(CustomerInput.normaliseMobile('+44 20 7946 0958'), '+442079460958');
      expect(CustomerInput.normaliseMobile('0044 7700 900123'), '+447700900123');
      expect(CustomerInput.normaliseMobile('+91 98765 43210'), '+919876543210');
      expect(CustomerInput.normaliseMobile('+1 (202) 555-0143'), '+12025550143');
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

  group('emirates to Shopify province codes', () {
    test('every emirate maps to the code the checkout lists', () {
      final codes = {
        for (final e in Emirate.values) e.code: CustomerInput.provinceCode(e),
      };
      expect(codes, {
        'dubai': 'DU',
        'auh': 'AZ',
        'shj': 'SH',
        'ajm': 'AJ',
        'uaq': 'UQ',
        'rak': 'RK',
        'fuj': 'FU',
      });
    });
  });

  group('checkout prefill', () {
    final bay = area('Business Bay');

    test('contact and the address in the delivery area, in checkout order',
        () {
      final params = CheckoutPrefill.params(
        contact: sara,
        address: home(),
        area: bay,
      );
      expect(params, {
        'checkout[email]': 'sara@example.com',
        'checkout[shipping_address][first_name]': 'Sara',
        'checkout[shipping_address][last_name]': 'Ahmed',
        'checkout[shipping_address][address1]': 'Bay Square, Building 5',
        'checkout[shipping_address][address2]': 'Flat 302',
        'checkout[shipping_address][city]': 'Business Bay',
        'checkout[shipping_address][province]': 'DU',
        'checkout[shipping_address][country]': 'AE',
        'checkout[shipping_address][phone]': '+971501234567',
      });
      expect(params.keys.toList(), [
        CheckoutPrefill.email,
        CheckoutPrefill.firstName,
        CheckoutPrefill.lastName,
        CheckoutPrefill.address1,
        CheckoutPrefill.address2,
        CheckoutPrefill.city,
        CheckoutPrefill.province,
        CheckoutPrefill.country,
        CheckoutPrefill.phone,
      ]);
    });

    test('address1 is the building, then the street', () {
      final params = CheckoutPrefill.params(
        contact: ContactDetails.empty,
        address: office(),
        area: area('Dubai Marina'),
      );
      expect(
        params[CheckoutPrefill.address1],
        'Marina Plaza, Al Marsa Street',
      );
      expect(params[CheckoutPrefill.address2], 'Office 1204');
      expect(params[CheckoutPrefill.city], 'Dubai Marina');
      expect(params[CheckoutPrefill.country], 'AE');
    });

    test('an address in another area: never its building; city and '
        'province are the current area', () {
      final params = CheckoutPrefill.params(
        contact: sara,
        address: office(), // Dubai Marina
        area: bay,
      );
      expect(params.containsKey(CheckoutPrefill.address1), isFalse);
      expect(params.containsKey(CheckoutPrefill.address2), isFalse);
      expect(params[CheckoutPrefill.city], 'Business Bay');
      expect(params[CheckoutPrefill.province], 'DU');
      expect(params[CheckoutPrefill.country], 'AE');
      expect(params[CheckoutPrefill.email], 'sara@example.com');
      expect(
        CheckoutPrefill.attributes(address: office(), area: bay),
        isEmpty,
      );
    });

    test('the same area by name and emirate, wherever the pin is', () {
      const pin = DeliveryArea(
        name: 'business bay',
        emirate: Emirate.dubai,
        lat: 25.19,
        lng: 55.27,
      );
      expect(
        CheckoutPrefill.params(
          contact: ContactDetails.empty,
          address: home(),
          area: pin,
        )[CheckoutPrefill.address1],
        'Bay Square, Building 5',
      );
      const sharjahBay = DeliveryArea(
        name: 'Business Bay',
        emirate: Emirate.sharjah,
        lat: 25.3,
        lng: 55.4,
      );
      expect(
        CheckoutPrefill.params(
          contact: ContactDetails.empty,
          address: home(),
          area: sharjahBay,
        ),
        isEmpty,
      );
    });

    test('empty values are left out; nothing saved sends nothing', () {
      expect(
        CheckoutPrefill.params(contact: ContactDetails.empty, area: bay),
        isEmpty,
      );
      final params = CheckoutPrefill.params(
        contact: const ContactDetails(firstName: 'Sara'),
        address: home(flat: ''),
        area: bay,
      );
      expect(params.keys, isNot(contains(CheckoutPrefill.email)));
      expect(params.keys, isNot(contains(CheckoutPrefill.lastName)));
      expect(params.keys, isNot(contains(CheckoutPrefill.phone)));
      expect(params.keys, isNot(contains(CheckoutPrefill.address2)));
      expect(params[CheckoutPrefill.firstName], 'Sara');
      // Contact only, no address: the area's city and emirate still help.
      final contactOnly = CheckoutPrefill.params(contact: sara, area: bay);
      expect(contactOnly[CheckoutPrefill.city], 'Business Bay');
      expect(contactOnly[CheckoutPrefill.province], 'DU');
      expect(contactOnly.keys, isNot(contains(CheckoutPrefill.address1)));
      // No area: contact only.
      final noArea = CheckoutPrefill.params(contact: sara, address: home());
      expect(noArea.keys, [
        CheckoutPrefill.email,
        CheckoutPrefill.firstName,
        CheckoutPrefill.lastName,
        CheckoutPrefill.phone,
      ]);
    });

    test('every emirate goes as its province code', () {
      for (final e in Emirate.values) {
        final a = DeliveryArea(name: 'Somewhere', emirate: e, lat: 25, lng: 55);
        expect(
          CheckoutPrefill.params(contact: sara, area: a)[
              CheckoutPrefill.province],
          CustomerInput.provinceCode(e),
        );
      }
    });

    test('delivery instructions go as a cart attribute', () {
      expect(CheckoutPrefill.attributes(address: home(), area: bay), {
        'Delivery instructions': 'Call when you arrive',
      });
      expect(
        CheckoutPrefill.attributes(
          address: home().copyWith(instructions: '  '),
          area: bay,
        ),
        isEmpty,
      );
    });
  });

  group('checkout URL', () {
    final products = sampleProducts();
    final kiwi = products[0];
    final beef = products[1];
    final bay = area('Business Bay');

    test('the demo cart: attributes kept, then the details, encoded', () {
      final cart = CartStore()
        ..add(kiwi, kiwi.variants[0], quantity: 2)
        ..add(beef, beef.variants[0]);
      final delivery = DeliveryRules.cartAttributes(
        bay,
        DeliveryMode.market,
        DateTime.utc(2026, 11, 13, 6),
      );
      final url = cart.checkoutUrlWith(
        {
          ...delivery,
          ...CheckoutPrefill.attributes(address: home(), area: bay),
        },
        prefill: CheckoutPrefill.params(
          contact: sara,
          address: home(),
          area: bay,
        ),
      )!;
      expect(
        url.toString(),
        'https://testtfm.myshopify.com/cart/2001:2,2003:1'
        '?attributes%5BDelivery%20mode%5D=Fresh%20Market'
        '&attributes%5BDelivery%20area%5D=Business%20Bay%2C%20Dubai'
        '&attributes%5BDelivery%20promise%5D=Today%20within%206%20hours'
        '&attributes%5BDelivery%20pin%5D=25.18500%2C55.26500'
        '&attributes%5BDelivery%20instructions%5D=Call%20when%20you%20arrive'
        '&checkout%5Bemail%5D=sara%40example.com'
        '&checkout%5Bshipping_address%5D%5Bfirst_name%5D=Sara'
        '&checkout%5Bshipping_address%5D%5Blast_name%5D=Ahmed'
        '&checkout%5Bshipping_address%5D%5Baddress1%5D='
        'Bay%20Square%2C%20Building%205'
        '&checkout%5Bshipping_address%5D%5Baddress2%5D=Flat%20302'
        '&checkout%5Bshipping_address%5D%5Bcity%5D=Business%20Bay'
        '&checkout%5Bshipping_address%5D%5Bprovince%5D=DU'
        '&checkout%5Bshipping_address%5D%5Bcountry%5D=AE'
        '&checkout%5Bshipping_address%5D%5Bphone%5D=%2B971501234567',
      );
      // Shopify reads every value back exactly.
      final query = url.queryParameters;
      expect(query['checkout[shipping_address][phone]'], '+971501234567');
      expect(query['attributes[Delivery area]'], 'Business Bay, Dubai');
    });

    test('Arabic, &, +, # and spaces survive the round trip', () {
      const tricky = ContactDetails(
        firstName: 'سارة',
        lastName: 'Ahmed & Sons',
        email: 'sara+shop@example.com',
      );
      final address = SavedAddress(
        id: 'x',
        label: AddressLabel.other,
        area: bay,
        building: 'برج #5 & Co',
        flat: 'Flat 3+4',
        instructions: 'Ring #2 & knock + wait',
      );
      final url = CartStore.buildCheckoutUrl(
        {2001: 1},
        attributes: CheckoutPrefill.attributes(address: address, area: bay),
        prefill: CheckoutPrefill.params(
          contact: tricky,
          address: address,
          area: bay,
        ),
      )!;
      final text = url.toString();
      // Nothing that would end or split a value is left raw.
      final query = text.substring(text.indexOf('?') + 1);
      for (final pair in query.split('&')) {
        final value = pair.substring(pair.indexOf('=') + 1);
        expect(value, isNot(matches(RegExp(r'[&+# \[\]]'))), reason: pair);
      }
      expect(text, contains('first_name%5D=%D8%B3%D8%A7%D8%B1%D8%A9'));
      expect(text, contains('last_name%5D=Ahmed%20%26%20Sons'));
      expect(text, contains('email%5D=sara%2Bshop%40example.com'));
      final q = url.queryParameters;
      expect(q['checkout[shipping_address][first_name]'], 'سارة');
      expect(q['checkout[shipping_address][last_name]'], 'Ahmed & Sons');
      expect(q['checkout[email]'], 'sara+shop@example.com');
      expect(q['checkout[shipping_address][address1]'], 'برج #5 & Co');
      expect(q['checkout[shipping_address][address2]'], 'Flat 3+4');
      expect(q['attributes[Delivery instructions]'], 'Ring #2 & knock + wait');
      expect(url.fragment, isEmpty);
    });

    test('sold-out lines stay out and empty prefill changes nothing', () {
      final cart = CartStore()..add(kiwi, kiwi.variants[0]);
      expect(
        cart.checkoutUrlWith(const {'A': 'b'}, prefill: const {}).toString(),
        cart.checkoutUrlWith(const {'A': 'b'}).toString(),
      );
      expect(
        CartStore.buildCheckoutUrl(
          {2001: 1},
          prefill: const {'checkout[email]': '  '},
        ).toString(),
        'https://testtfm.myshopify.com/cart/2001:1',
      );
      expect(CartStore.buildCheckoutUrl({2001: 0}, prefill: {'a': 'b'}), isNull);
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
          {'id': 'bad', 'area': {'name': 'X'}, 'building': 'B'},
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
      expect(store.offersCheckoutSheet, isTrue);
    });

    test('the checkout sheet: save, one checkout only, skip', () async {
      final bay = area('Business Bay');
      const answer = CheckoutSheetResult(
        contact: sara,
        building: 'Bay Square, Building 5',
        flat: 'Flat 302',
      );

      final saving = ProfileStore(vault: MemoryProfileVault());
      expect(saving.offersCheckoutSheet, isTrue);
      saving.applyCheckoutSheet(answer, bay);
      expect(saving.contact, sara);
      expect(saving.addresses.single.building, 'Bay Square, Building 5');
      expect(saving.addresses.single.label, AddressLabel.home);
      expect(saving.offersCheckoutSheet, isFalse);

      final vault = MemoryProfileVault();
      final once = ProfileStore(vault: vault);
      once.applyCheckoutSheet(
        const CheckoutSheetResult(
          contact: sara,
          building: 'Bay Square, Building 5',
          save: false,
        ),
        bay,
      );
      await once.idle;
      expect(once.hasDetails, isFalse);
      expect(vault.writes, isEmpty, reason: 'nothing kept on the phone');
      final details = once.checkoutDetails(bay);
      expect(details.contact, sara);
      expect(details.address!.building, 'Bay Square, Building 5');
      expect(once.checkoutDetails(area('Mirdif')).address, isNull);

      final skipVault = MemoryProfileVault();
      final skipping = ProfileStore(vault: skipVault);
      skipping.applyCheckoutSheet(const CheckoutSheetResult.skip(), bay);
      expect(skipping.offersCheckoutSheet, isFalse);
      await skipping.idle;
      final later = ProfileStore(vault: skipVault);
      await later.load();
      expect(later.offersCheckoutSheet, isFalse, reason: 'skip remembered');
      expect(later.checkoutSheetSkipped, isTrue);
    });

    test('the store AppScope makes by default never asks', () {
      expect(ProfileStore(askAtCheckout: false).offersCheckoutSheet, isFalse);
    });
  });
}
