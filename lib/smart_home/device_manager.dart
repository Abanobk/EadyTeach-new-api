import 'dart:async';

import '../services/home_assistant_service.dart';
import 'device_layout_constants.dart';
import 'mapping/device_mapping_engine.dart';
import 'models/app_device.dart';
import 'storage/device_layout_storage.dart';

/// Orchestrates HA data + local layout. **Never** holds baseUrl/token — uses [HomeAssistantService] only.
class DeviceManager {
  DeviceManager({
    HomeAssistantService? ha,
    DeviceLayoutStorage? storage,
    DeviceMappingEngine? engine,
  })  : _ha = ha ?? HomeAssistantService.instance,
        _storage = storage ?? DeviceLayoutStorage.instance,
        _engine = engine ?? const DeviceMappingEngine();

  final HomeAssistantService _ha;
  final DeviceLayoutStorage _storage;
  final DeviceMappingEngine _engine;

  /// Called after device list changes (sync, assign, realtime).
  void Function()? onChanged;

  List<AppDevice> _devices = const [];
  String? _error;
  bool _loading = false;
  StreamSubscription<HaEntity>? _wsSub;

  List<AppDevice> get devices => _devices;
  String? get error => _error;
  bool get isLoading => _loading;

  List<AppDevice> get unassignedDevices =>
      _devices.where((d) => d.isInUnassignedBucket).toList(growable: false);

  List<AppDevice> get placedDevices {
    final list = _devices.where((d) => d.isPlaced).toList();
    list.sort((a, b) {
      final cf = a.floorName.compareTo(b.floorName);
      if (cf != 0) return cf;
      final cr = a.roomName.compareTo(b.roomName);
      if (cr != 0) return cr;
      final cs = a.customSortOrder.compareTo(b.customSortOrder);
      if (cs != 0) return cs;
      return a.friendlyName.compareTo(b.friendlyName);
    });
    return list;
  }

  List<String> floorNames() {
    final s = <String>{};
    for (final d in _devices) {
      if (d.isPlaced) s.add(d.floorName);
    }
    final list = s.toList()..sort();
    return list;
  }

  List<String> roomNamesForFloor(String floor) {
    final s = <String>{};
    for (final d in _devices) {
      if (d.isPlaced && d.floorName == floor) s.add(d.roomName);
    }
    final list = s.toList()..sort();
    return list;
  }

  List<AppDevice> devicesInFloorAndRoom(String floor, String room) {
    return placedDevices
        .where((d) => d.floorName == floor && d.roomName == room)
        .toList(growable: false);
  }

  Future<void> initStorage() => _storage.init();

  void _emit() => onChanged?.call();

  Future<void> syncFromHa() async {
    if (!_ha.isEnabled) {
      _devices = const [];
      _emit();
      return;
    }
    _loading = true;
    _error = null;
    _emit();
    try {
      await _storage.init();
      final raw = await _ha.listStates();
      final merged = <AppDevice>[];
      for (final e in raw) {
        if (!_engine.isInteresting(e)) continue;
        if (_storage.read(e.entityId) == null) {
          await _storage.write(
            e.entityId,
            floorName: DeviceLayoutConstants.defaultFloorName,
            roomName: DeviceLayoutConstants.defaultRoomName,
            customSortOrder: 0,
          );
        }
        final layout = _storage.read(e.entityId);
        merged.add(_engine.fromHaAndLayoutMap(e, layout));
      }
      merged.sort((a, b) => a.friendlyName.compareTo(b.friendlyName));
      _devices = merged;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      _emit();
    }
  }

  Future<void> assignToRoom({
    required String entityId,
    required String floorName,
    required String roomName,
    int? customSortOrder,
  }) async {
    await _storage.init();
    final f = floorName.trim();
    final r = roomName.trim();
    int sort = customSortOrder ?? 0;
    if (customSortOrder == null) {
      var maxSort = 0;
      for (final d in _devices) {
        if (d.floorName == f && d.roomName == r && d.customSortOrder > maxSort) {
          maxSort = d.customSortOrder;
        }
      }
      sort = maxSort + 1;
    }
    await _storage.write(
      entityId,
      floorName: f,
      roomName: r,
      customSortOrder: sort,
    );
    final idx = _devices.indexWhere((d) => d.entityId == entityId);
    if (idx >= 0) {
      final d = _devices[idx];
      final next = _engine.mapEntity(
        d.asHaEntity,
        floorName: f,
        roomName: r,
        customSortOrder: sort,
      );
      final copy = List<AppDevice>.from(_devices);
      copy[idx] = next;
      _devices = copy;
    } else {
      await syncFromHa();
      return;
    }
    _emit();
  }

  Future<void> unassign(String entityId) async {
    await _storage.init();
    await _storage.write(
      entityId,
      floorName: DeviceLayoutConstants.defaultFloorName,
      roomName: DeviceLayoutConstants.defaultRoomName,
      customSortOrder: 0,
    );
    final idx = _devices.indexWhere((d) => d.entityId == entityId);
    if (idx >= 0) {
      final d = _devices[idx];
      final next = _engine.mapEntity(
        d.asHaEntity,
        floorName: DeviceLayoutConstants.defaultFloorName,
        roomName: DeviceLayoutConstants.defaultRoomName,
        customSortOrder: 0,
      );
      final copy = List<AppDevice>.from(_devices);
      copy[idx] = next;
      _devices = copy;
    }
    _emit();
  }

  Future<void> connectRealtime() async {
    await _wsSub?.cancel();
    _wsSub = null;
    if (!_ha.isEnabled) return;
    try {
      await _ha.connectRealtime();
      _wsSub = _ha.onEntityChanged.listen(_onHaEntity);
    } catch (_) {}
  }

  void _onHaEntity(HaEntity e) {
    unawaited(_applyEntityEvent(e));
  }

  Future<void> _applyEntityEvent(HaEntity e) async {
    if (!_engine.isInteresting(e)) return;
    await _storage.init();
    if (_storage.read(e.entityId) == null) {
      await _storage.write(
        e.entityId,
        floorName: DeviceLayoutConstants.defaultFloorName,
        roomName: DeviceLayoutConstants.defaultRoomName,
        customSortOrder: 0,
      );
    }
    final layout = _storage.read(e.entityId);
    final mapped = _engine.fromHaAndLayoutMap(e, layout);
    final idx = _devices.indexWhere((d) => d.entityId == e.entityId);
    if (idx >= 0) {
      final copy = List<AppDevice>.from(_devices);
      copy[idx] = mapped;
      _devices = copy;
    } else {
      _devices = [..._devices, mapped];
    }
    _emit();
  }

  Future<void> toggle(AppDevice device) async {
    try {
      await _ha.toggle(device.asHaEntity);
    } catch (e) {
      _error = e.toString();
      _emit();
    }
  }

  Future<void> setBrightness(AppDevice device, int brightness0to255) async {
    try {
      await _ha.setLightBrightness(device.entityId, brightness0to255);
    } catch (e) {
      _error = e.toString();
      _emit();
    }
  }

  Future<void> dispose() async {
    await _wsSub?.cancel();
    _wsSub = null;
    await _ha.disconnectRealtime();
  }
}
