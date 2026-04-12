import 'package:hive_flutter/hive_flutter.dart';

import '../models/scenario_model.dart';

/// Local persistence for [ScenarioModel] rows.
class ScenarioStorage {
  ScenarioStorage._();
  static final ScenarioStorage instance = ScenarioStorage._();

  static const String boxName = 'scenarios_box';

  Box<dynamic>? _box;

  Future<void> init() async {
    if (_box != null && _box!.isOpen) return;
    _box = await Hive.openBox<dynamic>(boxName);
  }

  List<ScenarioModel> loadAll() {
    final box = _box;
    if (box == null || !box.isOpen) return [];
    final out = <ScenarioModel>[];
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(
        raw.map((k, v) => MapEntry(k.toString(), v)),
      );
      final id = (map['id'] ?? key?.toString() ?? '').toString();
      if (id.isEmpty) continue;
      map['id'] = id;
      out.add(ScenarioModel.fromJson(map));
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  Future<void> upsert(ScenarioModel scenario) async {
    final box = _box;
    if (box == null || !box.isOpen) return;
    await box.put(scenario.id, scenario.toJson());
  }

  Future<void> delete(String id) async {
    final box = _box;
    if (box == null || !box.isOpen) return;
    await box.delete(id);
  }
}
