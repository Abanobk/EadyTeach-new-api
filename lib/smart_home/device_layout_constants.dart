/// Shared defaults and rules for floor/room layout (Hive + UI).
abstract final class DeviceLayoutConstants {
  static const String defaultFloorName = 'General';
  static const String defaultRoomName = 'Unassigned';

  /// Devices in this bucket show under "Unassigned Devices" on the dashboard.
  static bool isUnassignedBucket(String roomName) {
    final r = roomName.trim().toLowerCase();
    return r.isEmpty || r == defaultRoomName.toLowerCase();
  }
}
