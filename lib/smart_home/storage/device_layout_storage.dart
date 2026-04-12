import 'package:hive_flutter/hive_flutter.dart';

/// Persists per-entity layout (floor/room/sort). Keyed by `entity_id` from HA.
class DeviceLayoutStorage {
  DeviceLayoutStorage._();
  static final DeviceLayoutStorage instance = DeviceLayoutStorage._();

  static const _boxName = 'ha_device_layout_v1';

  Box<dynamic>? _box;

  Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    _box = await Hive.openBox<dynamic>(_boxName);
  }

  Map<String, dynamic>? read(String entityId) {
    final b = _box;
    if (b == null || !b.isOpen) return null;
    final raw = b.get(entityId);
    if (raw is! Map) return null;
    return Map<String, dynamic>.from(
      raw.map((k, v) => MapEntry(k.toString(), v)),
    );
  }

  Future<void> write(
    String entityId, {
    required String floorName,
    required String roomName,
    required int customSortOrder,
  }) async {
    final b = _box;
    if (b == null || !b.isOpen) return;
    await b.put(entityId, {
      'floorName': floorName,
      'roomName': roomName,
      'customSortOrder': customSortOrder,
    });
  }

  Future<void> remove(String entityId) async {
    final b = _box;
    if (b == null || !b.isOpen) return;
    await b.delete(entityId);
  }
}
