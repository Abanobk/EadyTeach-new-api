import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../services/home_assistant_service.dart';
import '../smart_home/models/scenario_model.dart';
import '../smart_home/storage/scenario_storage.dart';

/// Loads/saves scenarios from Hive and runs them against [HomeAssistantService] (no hardcoded URLs).
class ScenarioProvider extends ChangeNotifier {
  ScenarioProvider({
    ScenarioStorage? storage,
    HomeAssistantService? ha,
  })  : _storage = storage ?? ScenarioStorage.instance,
        _ha = ha ?? HomeAssistantService.instance;

  final ScenarioStorage _storage;
  final HomeAssistantService _ha;

  List<ScenarioModel> _scenarios = const [];
  bool _loading = false;
  String? _error;
  bool _inited = false;
  final Set<String> _runningScenarioIds = <String>{};

  List<ScenarioModel> get scenarios => _scenarios;
  bool get isLoading => _loading;
  String? get error => _error;

  bool isScenarioRunning(String id) => _runningScenarioIds.contains(id);

  void _setRunning(String id, bool running) {
    if (running) {
      _runningScenarioIds.add(id);
    } else {
      _runningScenarioIds.remove(id);
    }
  }

  Future<void> ensureInitialized() async {
    if (_inited) return;
    _loading = true;
    notifyListeners();
    try {
      await _storage.init();
      _scenarios = _storage.loadAll();
      _inited = true;
    } catch (e) {
      _error = e.toString();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> reload() async {
    await _storage.init();
    _scenarios = _storage.loadAll();
    notifyListeners();
  }

  Future<void> saveScenario(ScenarioModel scenario) async {
    _error = null;
    await _storage.init();
    await _storage.upsert(scenario);
    _scenarios = _storage.loadAll();
    notifyListeners();
  }

  Future<void> deleteScenario(String id) async {
    _error = null;
    await _storage.init();
    await _storage.delete(id);
    _scenarios = _storage.loadAll();
    notifyListeners();
  }

  /// Runs all actions in parallel via [Future.wait] for minimal latency.
  Future<void> runScenario(ScenarioModel scenario) async {
    _error = null;

    if (!_ha.isEnabled) {
      _error = 'Home Assistant is not enabled.';
      notifyListeners();
      return;
    }
    if (scenario.actions.isEmpty) {
      _error = 'Scenario has no actions.';
      notifyListeners();
      return;
    }

    HapticFeedback.mediumImpact();
    _setRunning(scenario.id, true);
    notifyListeners();

    try {
      await Future.wait(
        scenario.actions.map((a) {
          return _ha.callService(
            a.domain,
            a.service,
            a.buildServicePayload(),
          );
        }),
      );
      HapticFeedback.lightImpact();
    } catch (e) {
      HapticFeedback.vibrate();
      _error = e.toString();
    } finally {
      _setRunning(scenario.id, false);
      notifyListeners();
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
