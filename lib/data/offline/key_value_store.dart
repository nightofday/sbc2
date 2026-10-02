import 'package:shared_preferences/shared_preferences.dart';

/// Small string storage that survives closing the app. Kept behind an
/// interface so the offline queue can be tested without a device.
abstract class KeyValueStore {
  String? read(String key);

  Future<void> write(String key, String value);

  Future<void> remove(String key);
}

class MemoryKeyValueStore implements KeyValueStore {
  final Map<String, String> _values = {};

  @override
  String? read(String key) => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;

  @override
  Future<void> remove(String key) async => _values.remove(key);
}

class SharedPreferencesStore implements KeyValueStore {
  final SharedPreferences _preferences;

  SharedPreferencesStore(this._preferences);

  static Future<SharedPreferencesStore> open() async {
    return SharedPreferencesStore(await SharedPreferences.getInstance());
  }

  @override
  String? read(String key) => _preferences.getString(key);

  @override
  Future<void> write(String key, String value) async {
    await _preferences.setString(key, value);
  }

  @override
  Future<void> remove(String key) async {
    await _preferences.remove(key);
  }
}
