import 'dart:async';

import 'package:flutter/foundation.dart';
import '../services/api_service.dart';
import '../services/home_assistant_service.dart';

class SmartHomeProvider extends ChangeNotifier {
  SmartHomeProvider();

  bool _loading = false;
  String? _error;
  HomeAssistantCredentials? _creds;
  List<HaEntity> _entities = const [];

  String? get error => _error;
  bool get isLoading => _loading;
  bool get isEnabled => _creds?.enabled == true;
  List<HaEntity> get entities => _entities;

  StreamSubscription<HaEntity>? _realtimeSub;

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
        _entities = const [];
        _loading = false;
        notifyListeners();
        return;
      }

      await refreshStates();
      await _connectRealtime();
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> refreshStates() async {
    try {
      final list = await HomeAssistantService.instance.listStates();
      _entities = _filterInteresting(list);
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  List<HaEntity> _filterInteresting(List<HaEntity> input) {
    // Keep UI focused (Tuya-like): controllable domains by default.
    const allowed = {'light', 'switch', 'fan', 'climate', 'cover'};
    final filtered = input.where((e) => allowed.contains(e.domain)).toList();
    filtered.sort((a, b) => a.friendlyName.compareTo(b.friendlyName));
    return filtered;
  }

  Future<void> toggleEntity(HaEntity entity) async {
    try {
      await HomeAssistantService.instance.toggle(entity);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> setBrightness(HaEntity entity, int brightness0to255) async {
    try {
      await HomeAssistantService.instance
          .setLightBrightness(entity.entityId, brightness0to255);
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> _connectRealtime() async {
    await _realtimeSub?.cancel();
    _realtimeSub = null;

    try {
      await HomeAssistantService.instance.connectRealtime();
      _realtimeSub =
          HomeAssistantService.instance.onEntityChanged.listen((changed) {
        final idx = _entities.indexWhere((e) => e.entityId == changed.entityId);
        if (idx >= 0) {
          final copy = List<HaEntity>.from(_entities);
          copy[idx] = changed;
          _entities = copy;
          notifyListeners();
        }
      });
    } catch (_) {
      // best-effort realtime
    }
  }

  List<String> buildRoomChips() {
    // If you later add a custom attribute (easytecheg_room), we'll auto-pick it.
    final rooms = <String>{};
    for (final e in _entities) {
      final r = (e.attributes['easytecheg_room'] ?? '').toString().trim();
      if (r.isNotEmpty) rooms.add(r);
    }
    final list = rooms.toList()..sort();
    return ['All', ...list];
  }

  List<HaEntity> entitiesForRoom(String room) {
    if (room == 'All') return _entities;
    return _entities
        .where((e) =>
            (e.attributes['easytecheg_room'] ?? '').toString().trim() == room)
        .toList(growable: false);
  }

  @override
  void dispose() {
    unawaited(_realtimeSub?.cancel());
    unawaited(HomeAssistantService.instance.disconnectRealtime());
    super.dispose();
  }
}

