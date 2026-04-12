import 'dart:async';

import 'package:flutter/foundation.dart';

import '../services/api_service.dart';
import '../services/home_assistant_service.dart';
import '../smart_home/device_manager.dart';
import '../smart_home/models/app_device.dart';

class SmartHomeProvider extends ChangeNotifier {
  SmartHomeProvider() {
    _deviceManager.onChanged = notifyListeners;
  }

  final DeviceManager _deviceManager = DeviceManager();

  bool _loading = false;
  String? _error;
  HomeAssistantCredentials? _creds;

  String? get error => _error ?? _deviceManager.error;
  bool get isLoading => _loading || _deviceManager.isLoading;
  bool get isEnabled => _creds?.enabled == true;

  DeviceManager get deviceManager => _deviceManager;

  List<AppDevice> get devices => _deviceManager.devices;
  List<AppDevice> get placedDevices => _deviceManager.placedDevices;
  List<AppDevice> get unassignedDevices => _deviceManager.unassignedDevices;

  /// Floors that have at least one placed device (sorted).
  List<String> floorNames() => _deviceManager.floorNames();

  List<String> roomNamesForFloor(String floor) =>
      _deviceManager.roomNamesForFloor(floor);

  List<AppDevice> devicesForFloorAndRoom(String floor, String room) {
    var list = placedDevices;
    if (floor != 'All') {
      list = list.where((d) => d.floorName == floor).toList();
    }
    if (room != 'All') {
      list = list.where((d) => d.roomName == room).toList();
    }
    return list;
  }

  Future<void> initSilent() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      final res = await ApiService.query('homeAssistant.getCredentials');
      final data = res['data'];
      final enabled = data is Map ? (data['enabled'] == true) : false;
      final url = data is Map ? (data['haUrl'] ?? '').toString() : '';
      final token = data is Map ? (data['haToken'] ?? '').toString() : '';

      _creds = HomeAssistantCredentials(
        enabled: enabled,
        haUrl: url,
        haToken: token,
      );

      HomeAssistantService.instance.configure(_creds!);

      if (!enabled) {
        await _deviceManager.initStorage();
        await _deviceManager.syncFromHa();
        _loading = false;
        notifyListeners();
        return;
      }

      await _deviceManager.initStorage();
      await _deviceManager.syncFromHa();
      await _deviceManager.connectRealtime();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refreshStates() => _deviceManager.syncFromHa();

  Future<void> toggleDevice(AppDevice device) async {
    await _deviceManager.toggle(device);
  }

  Future<void> setBrightness(AppDevice device, int brightness0to255) async {
    await _deviceManager.setBrightness(device, brightness0to255);
  }

  Future<void> assignToRoom({
    required String entityId,
    required String floorName,
    required String roomName,
    int? customSortOrder,
  }) async {
    await _deviceManager.assignToRoom(
      entityId: entityId,
      floorName: floorName,
      roomName: roomName,
      customSortOrder: customSortOrder,
    );
  }

  Future<void> unassignDevice(String entityId) async {
    await _deviceManager.unassign(entityId);
  }

  @override
  void dispose() {
    unawaited(_deviceManager.dispose());
    super.dispose();
  }
}
