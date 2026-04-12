import '../../services/home_assistant_service.dart';
import '../device_layout_constants.dart';
import '../models/app_device.dart';

/// Maps raw HA [HaEntity] snapshots into [AppDevice] using optional local layout.
class DeviceMappingEngine {
  const DeviceMappingEngine();

  /// Default Hive row for entities seen for the first time.
  static const String defaultFloorName = DeviceLayoutConstants.defaultFloorName;
  static const String defaultRoomName = DeviceLayoutConstants.defaultRoomName;

  /// Domains we surface in the premium app (extend as needed).
  static const Set<String> controllableDomains = {
    'light',
    'switch',
    'fan',
    'climate',
    'cover',
    'lock',
  };

  bool isInteresting(HaEntity e) => controllableDomains.contains(e.domain);

  AppDevice mapEntity(
    HaEntity e, {
    required String floorName,
    required String roomName,
    required int customSortOrder,
  }) {
    var f = floorName.trim();
    var r = roomName.trim();
    if (f.isEmpty) f = defaultFloorName;
    if (r.isEmpty) r = defaultRoomName;
    final placed = !DeviceLayoutConstants.isUnassignedBucket(r);
    return AppDevice(
      entityId: e.entityId,
      domain: e.domain,
      state: e.state,
      attributes: Map<String, dynamic>.from(e.attributes),
      floorName: f,
      roomName: r,
      customSortOrder: customSortOrder,
      isPlaced: placed,
    );
  }

  AppDevice fromHaAndLayoutMap(HaEntity e, Map<String, dynamic>? layout) {
    if (layout == null) {
      return mapEntity(
        e,
        floorName: defaultFloorName,
        roomName: defaultRoomName,
        customSortOrder: 0,
      );
    }
    var floor = (layout['floorName'] ?? '').toString();
    var room = (layout['roomName'] ?? '').toString();
    final sort = int.tryParse(layout['customSortOrder']?.toString() ?? '') ?? 0;
    return mapEntity(e, floorName: floor, roomName: room, customSortOrder: sort);
  }
}
