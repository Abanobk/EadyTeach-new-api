import 'dart:async';
import 'dart:convert';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_service.dart';
import '../screens/admin/admin_secretary_screen.dart';

/// مفتاح حفظ عدد الشارة (يُستخدم أيضاً من معالج الخلفية)
const String _kBadgePrefsKey = 'app_icon_badge_count';

/// زيادة عدد الشارة على أيقونة التطبيق عند وصول إشعار في الخلفية (بدون اتصال بالخادم)
Future<void> _incrementBadgeInBackground() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final n = (prefs.getInt(_kBadgePrefsKey) ?? 0) + 1;
    await prefs.setInt(_kBadgePrefsKey, n);
    if (kIsWeb) return;
    await AppBadgePlus.updateBadge(n);
  } catch (e) {
    debugPrint('[Badge] Background increment failed: $e');
  }
}

/// توجيه عند فتح الإشعار — يحتاج مفتاح الـ Navigator (يُعيَّن من main بعد بناء الشجرة)
GlobalKey<NavigatorState>? _navigatorKey;
RemoteMessage? _pendingOpenMessage;
String? _pendingTapPayload;

/// Background message handler - must be top-level function (outside any class)
/// يعمل عندما يكون التطبيق في الخلفية أو مغلق تماماً (Android)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    WidgetsFlutterBinding.ensureInitialized();
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    debugPrint('[FCM Background] Received: ${message.notification?.title ?? message.data['title']}');

    // Handle silent admin commands.
    final type = (message.data['type'] ?? message.data['refType'] ?? message.data['notification_type'])?.toString().toLowerCase().trim();
    if (type == 'location_request') {
      try {
        final reqId = int.tryParse((message.data['requestId'] ?? message.data['refId'] ?? '').toString());
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) return;
        LocationPermission perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
        final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        await ApiService.mutate('technicianLocation.update', input: {
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'accuracy': pos.accuracy,
          'source': 'request',
          if (reqId != null) 'requestId': reqId,
          if (message.data['taskId'] != null) 'taskId': int.tryParse(message.data['taskId'].toString()),
        });
      } catch (e) {
        debugPrint('[LocationRequest] background failed: $e');
      }
      return;
    }

    if (type == 'status_check') {
      try {
        final reqId = int.tryParse((message.data['requestId'] ?? message.data['refId'] ?? '').toString());
        final enabled = await Geolocator.isLocationServiceEnabled();
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        final permStr = () {
          switch (perm) {
            case LocationPermission.always:
              return 'always';
            case LocationPermission.whileInUse:
              return 'while_in_use';
            case LocationPermission.denied:
              return 'denied';
            case LocationPermission.deniedForever:
              return 'denied_forever';
            case LocationPermission.unableToDetermine:
              return 'unknown';
          }
        }();
        await ApiService.mutate('technicianStatus.update', input: {
          'locationPermission': permStr,
          'locationServiceEnabled': enabled,
          'devicePlatform': 'android',
          if (reqId != null) 'requestId': reqId,
        });
      } catch (e) {
        debugPrint('[StatusCheck] background failed: $e');
      }
      return;
    }

    // نعرض إشعار محلي بالصوت والاهتزاز حتى لو كانت رسالة data فقط
    final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings = DarwinInitializationSettings();
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await flutterLocalNotificationsPlugin.initialize(initSettings);

    const AndroidNotificationChannel bgChannel = AndroidNotificationChannel(
      'easy_tech_v2',
      'Easy Tech - إشعارات مهمة',
      description: 'إشعارات تطبيق Easy Tech للمهام والطلبات',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
    );

    await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(bgChannel);

    final notification = message.notification;
    final title = notification?.title ??
        message.data['title']?.toString() ??
        message.data['subject']?.toString() ??
        'Easy Tech';
    var body = notification?.body?.toString() ??
        message.data['body']?.toString() ??
        message.data['message']?.toString() ??
        message.data['content']?.toString() ??
        message.data['text']?.toString() ??
        '';
    if (body.isEmpty && title.isNotEmpty) {
      body = 'اضغط للتفاصيل';
    }
    if (body.isEmpty) return;

    final notifId = (DateTime.now().microsecondsSinceEpoch % 2147483647).abs();

    await flutterLocalNotificationsPlugin.show(
      notifId,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'easy_tech_v2',
          'Easy Tech - إشعارات مهمة',
          channelDescription: 'إشعارات تطبيق Easy Tech للمهام والطلبات',
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          enableLights: true,
          fullScreenIntent: true,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(message.data),
    );
    await _incrementBadgeInBackground();
  } catch (e) {
    debugPrint('[FCM Background] Error: $e');
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// Lazy FCM access — null on web when Firebase is not configured.
  FirebaseMessaging? get _fcm {
    try {
      if (Firebase.apps.isEmpty) return null;
      return FirebaseMessaging.instance;
    } catch (_) {
      return null;
    }
  }

  // NEW channel ID v2 - forces Android to recreate channel with correct sound/vibration settings
  // Old channel 'easy_tech_high_importance' may have been created without sound in a previous install
  static const String _channelId = 'easy_tech_v2';
  static const String _channelName = 'Easy Tech - إشعارات مهمة';
  static const String _channelDesc = 'إشعارات تطبيق Easy Tech للمهام والطلبات';

  // Badge count tracker
  static int _badgeCount = 0;
  static bool _didBindTokenRefresh = false;

  static Future<void> _loadBadgeFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _badgeCount = prefs.getInt(_kBadgePrefsKey) ?? 0;
    } catch (_) {}
  }

  /// Initialize notifications - call once at app start
  Future<void> initialize() async {
    await _loadBadgeFromPrefs();
    if (_fcm == null) {
      debugPrint('[NotificationService] FCM not available (e.g. web without Firebase options).');
      return;
    }
    final fcm = _fcm!;
    await fcm.setAutoInitEnabled(true);

    // 1. Request permission
    final settings = await fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
      criticalAlert: false,
      announcement: false,
      carPlay: false,
    );
    debugPrint('[FCM] Permission status: ${settings.authorizationStatus}');

    // 2. Setup local notifications (for foreground display)
    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const InitializationSettings initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );
    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundNotificationTap,
    );

    // Android 13+ (API 33): لازم طلب صلاحية الإشعارات صراحةً وإلا قد لا تظهر في الخلفية/المغلق
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      final granted = await androidPlugin.requestNotificationsPermission();
      debugPrint('[FCM] Android POST_NOTIFICATIONS granted: $granted');
    }

    // 3. Create Android notification channel (HIGH importance = sound + heads-up)
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDesc,
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      enableLights: true,
      ledColor: Color(0xFFF5A623),
      showBadge: true,
    );
    await _localNotifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // 4. Handle foreground messages - show local notification with badge
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // 5. Handle notification tap when app is in background/terminated
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    // 6. Handle initial message (app opened from terminated state via notification)
    // نؤجل التوجيه حتى يُعيَّن navigatorKey ويُبنى الشجرة
    final initialMessage = await fcm.getInitialMessage();
    if (initialMessage != null) {
      debugPrint('[FCM] App opened from terminated state via notification');
      _pendingOpenMessage = initialMessage;
    }

    // 7. Set foreground notification presentation options (iOS)
    await fcm.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: true,
      sound: true,
    );

    await getAndSaveFcmToken();
    debugPrint('[NotificationService] Initialized successfully');
  }

  /// Get FCM token and save to server - with retry logic
  Future<String?> getAndSaveFcmToken() async {
    try {
      if (_fcm == null) return null;
      // Wait a bit to ensure auth cookie is saved
      await Future.delayed(const Duration(milliseconds: 500));

      final token = await _fcm!.getToken();
      if (token != null) {
        debugPrint('[FCM Token] Got token, saving to server...');
        // Retry up to 3 times in case of network issues
        for (int i = 0; i < 3; i++) {
          try {
            await ApiService().saveFcmToken(token);
            debugPrint('[FCM Token] Saved successfully on attempt ${i + 1}');
            break;
          } catch (e) {
            debugPrint('[FCM Token] Save attempt ${i + 1} failed: $e');
            if (i < 2) await Future.delayed(Duration(seconds: (i + 1) * 2));
          }
        }
      }

      // Listen for token refresh مرة واحدة فقط حتى لا تتكرر الحفظات مع كل تهيئة.
      if (!_didBindTokenRefresh) {
        _didBindTokenRefresh = true;
        _fcm!.onTokenRefresh.listen((newToken) {
          debugPrint('[FCM Token] Token refreshed, saving new token...');
          ApiService().saveFcmToken(newToken);
        });
      }

      return token;
    } catch (e) {
      debugPrint('[FCM] Failed to get token: $e');
      return null;
    }
  }

  /// Update badge count from server (call when app becomes active)
  Future<void> updateBadgeFromServer() async {
    try {
      final result = await ApiService.query('notifications.getUnreadCount');
      final raw = result['data'];
      int count = 0;
      if (raw is int) {
        count = raw;
      } else if (raw is double) {
        count = raw.toInt();
      } else if (raw is Map) {
        count = (raw['count'] is int) ? raw['count'] : int.tryParse('${raw['count']}') ?? 0;
      }
      await setBadgeCount(count);
    } catch (e) {
      debugPrint('[Badge] Failed to get unread count: $e');
    }
  }

  /// تعيين عدد الشارة على أيقونة التطبيق (Android/iOS عبر app_badge_plus) + مزامنة محلية
  static Future<void> setBadgeCount(int count) async {
    try {
      _badgeCount = count < 0 ? 0 : count;
      debugPrint('[Badge] Badge count set to $_badgeCount');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kBadgePrefsKey, _badgeCount);
      if (kIsWeb) return;
      await AppBadgePlus.updateBadge(_badgeCount);
    } catch (e) {
      debugPrint('[Badge] Failed to set badge: $e');
    }
  }

  /// Increment badge count
  static Future<void> incrementBadge() async {
    await setBadgeCount(_badgeCount + 1);
  }

  /// Clear badge count
  static Future<void> clearBadge() async {
    await setBadgeCount(0);
  }

  /// Show local notification for foreground messages
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    debugPrint('[FCM Foreground] ${message.notification?.title}');

    final type = (message.data['type'] ?? message.data['refType'] ?? message.data['notification_type'])?.toString().toLowerCase().trim();
    if (type == 'location_request') {
      // Technician device: send location immediately, no need to show UI notification.
      try {
        final reqId = int.tryParse((message.data['requestId'] ?? message.data['refId'] ?? '').toString());
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) return;
        LocationPermission perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
        final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
        await ApiService.mutate('technicianLocation.update', input: {
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'accuracy': pos.accuracy,
          'source': 'request',
          if (reqId != null) 'requestId': reqId,
          if (message.data['taskId'] != null) 'taskId': int.tryParse(message.data['taskId'].toString()),
        });
      } catch (e) {
        debugPrint('[LocationRequest] foreground failed: $e');
      }
      return;
    }

    if (type == 'status_check') {
      try {
        final reqId = int.tryParse((message.data['requestId'] ?? message.data['refId'] ?? '').toString());
        final enabled = await Geolocator.isLocationServiceEnabled();
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        final permStr = () {
          switch (perm) {
            case LocationPermission.always:
              return 'always';
            case LocationPermission.whileInUse:
              return 'while_in_use';
            case LocationPermission.denied:
              return 'denied';
            case LocationPermission.deniedForever:
              return 'denied_forever';
            case LocationPermission.unableToDetermine:
              return 'unknown';
          }
        }();
        await ApiService.mutate('technicianStatus.update', input: {
          'locationPermission': permStr,
          'locationServiceEnabled': enabled,
          if (reqId != null) 'requestId': reqId,
        });
      } catch (e) {
        debugPrint('[StatusCheck] foreground failed: $e');
      }
      return;
    }

    final notification = message.notification;
    final title = notification?.title ??
        message.data['title']?.toString() ??
        message.data['subject']?.toString() ??
        'Easy Tech';
    final body = notification?.body?.toString() ??
        message.data['body']?.toString() ??
        message.data['message']?.toString() ??
        message.data['content']?.toString() ??
        message.data['text']?.toString() ??
        '';
    if (body.isEmpty) return;

    // Increment badge count
    await incrementBadge();

    // معرّف فريد — استخدام hashCode فقط كان يُكرر ID لرسائل متشابهة فيُستبدل الإشعار بصمت على أندرويد
    final notifId = (DateTime.now().microsecondsSinceEpoch % 2147483647).abs();

    await _localNotifications.show(
      notifId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDesc,
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
          enableLights: true,
          ledColor: const Color(0xFFF5A623),
          icon: '@mipmap/ic_launcher',
          fullScreenIntent: true,
          number: _badgeCount,
          styleInformation: BigTextStyleInformation(
            body,
            htmlFormatBigText: false,
            contentTitle: title,
          ),
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          badgeNumber: _badgeCount,
        ),
      ),
      payload: jsonEncode(message.data),
    );
  }

  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  /// يُستدعى بعد أول إطار لمعالجة إشعار فتح التطبيق (من حالة مغلقة)
  void processPendingNotification() {
    if (_pendingOpenMessage != null) {
      final msg = _pendingOpenMessage!;
      _pendingOpenMessage = null;
      final data = msg.data;
      // تأخير التوجيه حتى تنتهي شاشة البداية وتصل للشاشة الرئيسية
      Future.delayed(const Duration(milliseconds: 2500), () {
        _navigateToNotificationData(data);
      });
    }
    processTapPayload();
  }

  /// معالجة ضغط إشعار (مثلاً عند فتح التطبيق من الخلفية بالضغط على إشعار محلي)
  void processTapPayload() {
    final payload = _pendingTapPayload;
    _pendingTapPayload = null;
    if (payload == null || payload.isEmpty) return;
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>?;
      _navigateToNotificationData(data);
    } catch (_) {}
  }

  void _handleMessageOpenedApp(RemoteMessage message) {
    debugPrint('[FCM Opened] ${message.notification?.title}');
    unawaited(updateBadgeFromServer());
    _navigateToNotificationData(message.data);
  }

  void _onNotificationTap(NotificationResponse response) {
    debugPrint('[Notification Tap] payload: ${response.payload}');
    unawaited(updateBadgeFromServer());
    if (response.payload != null && response.payload!.isNotEmpty) {
      try {
        final data = jsonDecode(response.payload!) as Map<String, dynamic>?;
        _navigateToNotificationData(data);
      } catch (_) {}
    }
  }

  static int? _parseId(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is double) return v.toInt();
    return int.tryParse(v.toString());
  }

  /// التوجيه للصفحة المناسبة حسب بيانات الإشعار
  void _navigateToNotificationData(Map<String, dynamic>? data) {
    if (data == null || data.isEmpty) return;

    final type = (data['type'] as String? ?? data['screen'] as String? ?? data['refType'] as String? ?? data['notification_type'] as String?)?.toLowerCase().trim();
    final refId = _parseId(data['refId']) ?? _parseId(data['id']) ?? _parseId(data['taskId']) ?? _parseId(data['task_id']);

    void doNavigate() {
      final nav = _navigatorKey?.currentState;
      if (nav == null) return;

      switch (type) {
        case 'task':
          if (refId != null) nav.pushNamed('/task-detail', arguments: refId);
          break;
        case 'quotation':
        case 'quote':
          if (refId != null) nav.pushNamed('/quotation-detail', arguments: refId);
          break;
        case 'quotationpurchase':
          if (refId != null) nav.pushNamed('/quotation-detail', arguments: refId);
          break;
        case 'order':
          nav.pushNamed('/admin');
          break;
        case 'accounting':
          nav.pushNamed('/admin', arguments: 'accounting');
          break;
        case 'message':
        case 'inbox':
          nav.pushNamed('/admin', arguments: 'inbox');
          break;
        case 'crm':
          nav.pushNamed('/admin', arguments: 'crm');
          break;
        case 'appointment':
        case 'secretary':
          nav.push(MaterialPageRoute<void>(
            builder: (ctx) => const AdminSecretaryScreen(),
          ));
          break;
        default:
          if (refId != null) {
            nav.pushNamed('/task-detail', arguments: refId);
          }
          break;
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_navigatorKey?.currentState != null) {
        doNavigate();
        return;
      }
      Future.delayed(const Duration(milliseconds: 400), () {
        if (_navigatorKey?.currentState != null) doNavigate();
      });
    });
  }
}

/// Background notification tap handler - must be top-level
@pragma('vm:entry-point')
void _onBackgroundNotificationTap(NotificationResponse response) {
  debugPrint('[Background Notification Tap] payload: ${response.payload}');
  _pendingTapPayload = response.payload;
  WidgetsBinding.instance.addPostFrameCallback((_) {
    NotificationService().processTapPayload();
  });
}
