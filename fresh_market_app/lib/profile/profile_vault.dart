import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the shopper's details are kept: one encrypted record.
abstract class ProfileVault {
  /// The saved record, or null when there is none.
  Future<String?> read();

  Future<void> write(String value);

  /// Removes the record.
  Future<void> delete();
}

/// The phone's own encrypted storage (flutter_secure_storage): on Android
/// a key in the Android Keystore wraps the AES-GCM key that encrypts the
/// record; on the web (https or localhost only) WebCrypto encrypts it.
/// Nothing leaves the phone.
class SecureProfileVault implements ProfileVault {
  const SecureProfileVault({
    this.storage = const FlutterSecureStorage(
      // A record that can no longer be decrypted (a restored backup, a
      // reset Keystore) is wiped rather than throwing on every read.
      aOptions: AndroidOptions(),
    ),
  });

  static const String key = 'customer_details_v1';

  final FlutterSecureStorage storage;

  @override
  Future<String?> read() => storage.read(key: key);

  @override
  Future<void> write(String value) => storage.write(key: key, value: value);

  @override
  Future<void> delete() => storage.delete(key: key);
}

/// Keeps the record in memory only (tests, and a phone whose secure
/// storage cannot be opened).
class MemoryProfileVault implements ProfileVault {
  MemoryProfileVault([this.value]);

  /// The record as written; tests read and corrupt it.
  String? value;

  /// Every write, in order (tests).
  final List<String> writes = [];

  /// Set to make every call fail (tests).
  bool broken = false;

  @override
  Future<String?> read() async {
    if (broken) throw StateError('vault unavailable');
    return value;
  }

  @override
  Future<void> write(String value) async {
    if (broken) throw StateError('vault unavailable');
    this.value = value;
    writes.add(value);
  }

  @override
  Future<void> delete() async {
    if (broken) throw StateError('vault unavailable');
    value = null;
  }
}
