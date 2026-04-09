import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class HaEntity {
  final String entityId;
  final String domain;
  final String state;
  final Map<String, dynamic> attributes;

  HaEntity({
    required this.entityId,
    required this.domain,
    required this.state,
    required this.attributes,
  });

  String get friendlyName =>
      (attributes['friendly_name'] ?? entityId).toString();

  bool get isOn => state == 'on';

  int? get brightness {
    final v = attributes['brightness'];
    if (v == null) return null;
    return int.tryParse(v.toString());
  }

  double? get temperature {
    final v = attributes['temperature'];
    if (v == null) return null;
    return double.tryParse(v.toString());
  }
}

class HomeAssistantCredentials {
  final bool enabled;
  final String haUrl;
  final String haToken;

  HomeAssistantCredentials({
    required this.enabled,
    required this.haUrl,
    required this.haToken,
  });
}

class HomeAssistantService {
  HomeAssistantService._();
  static final HomeAssistantService instance = HomeAssistantService._();

  Dio? _dio;
  WebSocketChannel? _channel;
  StreamSubscription? _wsSub;
  final _stateChangedController =
      StreamController<HaEntity>.broadcast(sync: true);

  HomeAssistantCredentials? _creds;
  bool get isEnabled => _creds?.enabled == true;

  Stream<HaEntity> get onEntityChanged => _stateChangedController.stream;

  void configure(HomeAssistantCredentials creds) {
    _creds = creds;
    if (!creds.enabled) {
      _dio = null;
      return;
    }
    _dio = Dio(
      BaseOptions(
        baseUrl: creds.haUrl,
        connectTimeout: const Duration(seconds: 12),
        receiveTimeout: const Duration(seconds: 15),
        headers: {
          'Authorization': 'Bearer ${creds.haToken}',
          'Content-Type': 'application/json',
        },
      ),
    );
  }

  Future<List<HaEntity>> listStates() async {
    final dio = _dio;
    if (dio == null || !isEnabled) return [];
    final res = await dio.get('/api/states');
    final data = res.data;
    if (data is! List) return [];
    return data
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .map((m) {
          final entityId = (m['entity_id'] ?? '').toString();
          final domain = entityId.contains('.') ? entityId.split('.').first : '';
          return HaEntity(
            entityId: entityId,
            domain: domain,
            state: (m['state'] ?? '').toString(),
            attributes: (m['attributes'] is Map)
                ? Map<String, dynamic>.from(m['attributes'])
                : <String, dynamic>{},
          );
        })
        .where((e) => e.entityId.isNotEmpty)
        .toList(growable: false);
  }

  Future<void> toggle(HaEntity entity) async {
    if (!isEnabled) return;
    final domain = entity.domain;
    final service = entity.isOn ? 'turn_off' : 'turn_on';
    await callService(domain, service, {'entity_id': entity.entityId});
  }

  Future<void> setLightBrightness(String entityId, int brightness0to255) async {
    if (!isEnabled) return;
    await callService('light', 'turn_on', {
      'entity_id': entityId,
      'brightness': brightness0to255.clamp(0, 255),
    });
  }

  Future<void> callService(
    String domain,
    String service,
    Map<String, dynamic> payload,
  ) async {
    final dio = _dio;
    if (dio == null || !isEnabled) return;
    await dio.post('/api/services/$domain/$service', data: payload);
  }

  Future<void> connectRealtime() async {
    if (!isEnabled) return;
    await disconnectRealtime();

    final creds = _creds!;
    final wsUrl = _toWsUrl(creds.haUrl);
    final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
    _channel = channel;

    var authed = false;
    int nextId = 1;

    _wsSub = channel.stream.listen(
      (event) {
        final raw = event?.toString() ?? '';
        if (raw.isEmpty) return;
        final msg = jsonDecode(raw);
        if (msg is! Map) return;
        final type = (msg['type'] ?? '').toString();

        if (type == 'auth_required') {
          channel.sink.add(jsonEncode({
            'type': 'auth',
            'access_token': creds.haToken,
          }));
          return;
        }

        if (type == 'auth_ok') {
          authed = true;
          final subId = nextId++;
          channel.sink.add(jsonEncode({
            'id': subId,
            'type': 'subscribe_events',
            'event_type': 'state_changed',
          }));
          return;
        }

        if (!authed) return;

        // Event payload format:
        // { "type":"event", "event": { "data": { "entity_id":..., "new_state": {...} } } }
        if (type == 'event') {
          final eventObj = msg['event'];
          if (eventObj is! Map) return;
          final data = eventObj['data'];
          if (data is! Map) return;
          final entityId = (data['entity_id'] ?? '').toString();
          final newState = data['new_state'];
          if (entityId.isEmpty || newState is! Map) return;
          final state = (newState['state'] ?? '').toString();
          final attrs = newState['attributes'] is Map
              ? Map<String, dynamic>.from(newState['attributes'])
              : <String, dynamic>{};
          final domain =
              entityId.contains('.') ? entityId.split('.').first : '';
          _stateChangedController.add(HaEntity(
            entityId: entityId,
            domain: domain,
            state: state,
            attributes: attrs,
          ));
        }
      },
      onError: (_) {},
      onDone: () {},
      cancelOnError: false,
    );
  }

  Future<void> disconnectRealtime() async {
    try {
      await _wsSub?.cancel();
    } catch (_) {}
    _wsSub = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
  }

  static String _toWsUrl(String httpUrl) {
    final uri = Uri.parse(httpUrl);
    final scheme = uri.scheme == 'https' ? 'wss' : 'ws';
    final wsUri = uri.replace(scheme: scheme, path: '/api/websocket');
    return wsUri.toString();
  }
}

