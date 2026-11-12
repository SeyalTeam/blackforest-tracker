import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AppGridSettings {
  static const String _storageKey = 'app_grid_column_count';
  static final ValueNotifier<int> columnCount = ValueNotifier<int>(2);
  static const _storage = FlutterSecureStorage();
  static bool _initialized = false;

  /// Initializes the grid column preference from storage. Default is 2 columns.
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final saved = await _storage.read(key: _storageKey);
      if (saved == '3') {
        columnCount.value = 3;
      } else {
        columnCount.value = 2; // Default is 2 grid
      }
    } catch (_) {
      columnCount.value = 2;
    }
  }

  /// Sets grid column count (either 2 or 3) and persists the choice.
  static Future<void> setColumnCount(int count) async {
    final val = (count == 3) ? 3 : 2;
    if (columnCount.value != val) {
      columnCount.value = val;
    }
    try {
      await _storage.write(key: _storageKey, value: val.toString());
    } catch (_) {}
  }

  /// Toggles between 2 and 3 columns.
  static Future<void> toggle() async {
    final next = (columnCount.value == 2) ? 3 : 2;
    await setColumnCount(next);
  }
}
