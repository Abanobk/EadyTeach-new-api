import '../../services/home_assistant_service.dart';
import '../device_layout_constants.dart';

/// Flutter-owned view of a Home Assistant entity + local layout metadata.
/// URLs/tokens never appear here — connection is via [HomeAssistantService].
class AppDevice {
  final String entityId;
  final String domain;
  final String state;
  final Map<String, dynamic> attributes;

  /// Local DB (Hive): which floor this device belongs to (may be empty if unassigned).
  final String floorName;

  /// Local DB: room name (may be empty if unassigned).
  final String roomName;

  /// Local DB: sort order within the room (lower = first).
  final int customSortOrder;

  /// True when [roomName] is not the default unassigned bucket.
  final bool isPlaced;

  const AppDevice({
    required this.entityId,
    required this.domain,
    required this.state,
    required this.attributes,
    required this.floorName,
    required this.roomName,
    required this.customSortOrder,
    required this.isPlaced,
  });

  String get friendlyName =>
      (attributes['friendly_name'] ?? entityId).toString();

  bool get isOn => state == 'on';

  int? get brightness => asHaEntity.brightness;

  double? get temperature => asHaEntity.temperature;

  HaEntity get asHaEntity => HaEntity(
        entityId: entityId,
        domain: domain,
        state: state,
        attributes: attributes,
      );

  bool get isInUnassignedBucket =>
      DeviceLayoutConstants.isUnassignedBucket(roomName);

  AppDevice copyWith({
    String? state,
    Map<String, dynamic>? attributes,
    String? floorName,
    String? roomName,
    int? customSortOrder,
    bool? isPlaced,
  }) {
    final nf = floorName ?? this.floorName;
    final nr = roomName ?? this.roomName;
    var f = nf.trim();
    var r = nr.trim();
    if (f.isEmpty) f = DeviceLayoutConstants.defaultFloorName;
    if (r.isEmpty) r = DeviceLayoutConstants.defaultRoomName;
    final placed = isPlaced ?? !DeviceLayoutConstants.isUnassignedBucket(r);
    return AppDevice(
      entityId: entityId,
      domain: domain,
      state: state ?? this.state,
      attributes: attributes ?? this.attributes,
      floorName: f,
      roomName: r,
      customSortOrder: customSortOrder ?? this.customSortOrder,
      isPlaced: placed,
    );
  }
}
