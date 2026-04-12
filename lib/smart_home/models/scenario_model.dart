/// A user-defined Home Assistant automation triggered from the app.
class ScenarioModel {
  final String id;
  final String name;
  final List<ScenarioAction> actions;

  /// Material icon code point chosen in the editor; null = infer from scenario name.
  final int? iconCodePoint;

  const ScenarioModel({
    required this.id,
    required this.name,
    required this.actions,
    this.iconCodePoint,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'actions': actions.map((a) => a.toJson()).toList(),
        if (iconCodePoint != null) 'iconCodePoint': iconCodePoint,
      };

  factory ScenarioModel.fromJson(Map<String, dynamic> json) {
    final rawActions = json['actions'];
    final actions = <ScenarioAction>[];
    if (rawActions is List) {
      for (final a in rawActions) {
        if (a is Map) {
          actions.add(
            ScenarioAction.fromJson(Map<String, dynamic>.from(
              a.map((k, v) => MapEntry(k.toString(), v)),
            )),
          );
        }
      }
    }
    final iconRaw = json['iconCodePoint'];
    final iconCp =
        iconRaw == null ? null : int.tryParse(iconRaw.toString());

    return ScenarioModel(
      id: (json['id'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      actions: actions,
      iconCodePoint: iconCp,
    );
  }

  ScenarioModel copyWith({
    String? id,
    String? name,
    List<ScenarioAction>? actions,
    int? iconCodePoint,
  }) {
    return ScenarioModel(
      id: id ?? this.id,
      name: name ?? this.name,
      actions: actions ?? this.actions,
      iconCodePoint: iconCodePoint ?? this.iconCodePoint,
    );
  }
}

/// One HA service call: [entityId], [domain], [service] name, and optional [data]
/// merged into the REST payload (always includes `entity_id`).
class ScenarioAction {
  final String entityId;
  final String domain;
  final String service;
  final Map<String, dynamic> data;

  const ScenarioAction({
    required this.entityId,
    required this.domain,
    required this.service,
    this.data = const {},
  });

  Map<String, dynamic> toJson() => {
        'entity_id': entityId,
        'domain': domain,
        'service': service,
        'data': data,
      };

  factory ScenarioAction.fromJson(Map<String, dynamic> json) {
    final entityId = (json['entity_id'] ?? '').toString();
    var domain = (json['domain'] ?? '').toString().trim();
    if (domain.isEmpty && entityId.contains('.')) {
      domain = entityId.split('.').first;
    }
    final dataRaw = json['data'];
    return ScenarioAction(
      entityId: entityId,
      domain: domain,
      service: (json['service'] ?? 'turn_on').toString(),
      data: dataRaw is Map
          ? Map<String, dynamic>.from(
              dataRaw.map((k, v) => MapEntry(k.toString(), v)),
            )
          : <String, dynamic>{},
    );
  }

  /// Payload for `POST /api/services/{domain}/{service}`.
  Map<String, dynamic> buildServicePayload() {
    final payload = Map<String, dynamic>.from(data);
    payload['entity_id'] = entityId;
    return payload;
  }
}
