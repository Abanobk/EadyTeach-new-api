import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  /// API is at the root: https://api.easytecheg.net (no trailing slash — avoids double slashes in URLs).
  static const String _apiOrigin = 'https://api.easytecheg.net';
  /// الـ container document root = المشروع كله، فالـ API تحت /backend/ — نستخدم backend/trpc.php أولاً.
  static const String _apiTrpcPath = 'backend/trpc.php';
  static const String _apiTrpcPathAlt = 'trpc.php';
  static const String _apiTrpcPathAlt2 = 'trpc';
  static const String _apiTrpcPathAlt3 = 'api/trpc';
  static String? _resolvedTrpcPath;

  static String get baseUrl => _apiOrigin;
  static String get trpcUrl {
    final origin = _apiOrigin.endsWith('/') ? _apiOrigin.substring(0, _apiOrigin.length - 1) : _apiOrigin;
    final path = _resolvedTrpcPath ?? _apiTrpcPath;
    return '$origin/$path';
  }

  static String _trpcPathForRequest() => _resolvedTrpcPath ?? _apiTrpcPath;

  /// Always return an absolute API URL (never relative), with a single slash between origin and path (no double slashes).
  static String _absoluteUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final origin = _apiOrigin.endsWith('/') ? _apiOrigin.substring(0, _apiOrigin.length - 1) : _apiOrigin;
    final p = path.startsWith('/') ? path.substring(1) : path;
    return '$origin/$p';
  }

  /// رسالة موحدة عند فشل الاتصال (شبكة، CORS، انقطاع)
  static String _networkErrorMessage(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('failed to fetch') ||
        msg.contains('socketexception') ||
        msg.contains('connection') ||
        msg.contains('network') ||
        msg.contains('timeout') ||
        msg.contains('connection refused')) {
      return 'فشل الاتصال بالسيرفر. تحقق من الإنترنت وحاول مرة أخرى.';
    }
    return 'خطأ في الاتصال: ${e.toString().length > 80 ? e.toString().substring(0, 80) : e}';
  }

  static String proxyImageUrl(String? url) {
    if (url == null || url.isEmpty) return '';

    // لو الرابط نفسه هو الـ image-proxy نتاكد إنه مطلق (absolute) من نفس الـ origin
    if (url.contains('image-proxy')) {
      // إن كان نسبي (يبدأ بـ /api/...) نحوله لمطلق على api.easytecheg.net
      if (url.startsWith('/')) {
        return _absoluteUrl(url);
      }
      return url;
    }

    // لو الصورة على Firebase Storage أو نطاق خارجي مشابه
    final uri = Uri.tryParse(url);
    final host = uri?.host.toLowerCase() ?? '';

    if (kIsWeb) {
      // على الويب: نمرّر Firebase و /uploads عبر proxy (router.php) لتفادي CORS
      if (host.contains('firebasestorage.googleapis.com') ||
          url.startsWith('/uploads') ||
          host == Uri.tryParse(_apiOrigin)?.host) {
        final absolute = url.startsWith('http') ? url : _absoluteUrl(url);
        final encoded = Uri.encodeComponent(absolute);
        // نستخدم router.php مباشرة لضمان عمله بدون إعدادات خاصة في Apache
        return '$_apiOrigin/backend/router.php?image-proxy=1&url=$encoded';
      }
      // أي دومينات خارجية أخرى نستخدمها مباشرة
      return url;
    }

    // على الموبايل: نستخدم Firebase / الروابط الخارجية مباشرة
    if (host.contains('firebasestorage.googleapis.com')) {
      return url;
    }

    // غير كده نرجّع الرابط كما هو.
    return url;
  }

  static bool _persistSession = true;
  static String? _memoryOnlyCookie;

  /// يحدد هل تُحفظ الجلسة على الجهاز (حفظ الحساب) أم للجلسة الحالية فقط
  static void setPersistSession(bool persist) {
    _persistSession = persist;
  }

  static Future<String?> _getCookie() async {
    if (_memoryOnlyCookie != null && _memoryOnlyCookie!.isNotEmpty) return _memoryOnlyCookie;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('session_cookie');
  }

  static Future<void> _saveCookie(String cookieValue) async {
    if (cookieValue.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    if (_persistSession) {
      await prefs.setString('session_cookie', cookieValue);
      _memoryOnlyCookie = null;
    } else {
      _memoryOnlyCookie = cookieValue;
      await prefs.remove('session_cookie');
    }
  }

  /// Save session cookie from either Set-Cookie header or sessionToken in response body
  static Future<void> _saveCookieFromHeader(String setCookieHeader) async {
    final cookieValue = setCookieHeader.split(';').first.trim();
    await _saveCookie(cookieValue);
  }

  /// Save session token directly from response body (more reliable than Set-Cookie header)
  static Future<void> saveSessionToken(String sessionToken) async {
    await _saveCookie('app_session_id=$sessionToken');
  }

  static Future<void> clearCookie() async {
    _memoryOnlyCookie = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('session_cookie');
  }

  /// للاستخدام في طلبات خارجية (مثل تحميل PDF) تحتاج إرسال الجلسة
  static Future<String?> getCookieForRequest() async => await _getCookie();

  static String? _extractToken(String? cookie) {
    if (cookie == null || cookie.isEmpty) return null;
    final match = RegExp(r'app_session_id=(.+)').firstMatch(cookie);
    return match?.group(1) ?? cookie;
  }

  static Map<String, String> _headers({String? cookie}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (cookie != null && cookie.isNotEmpty) {
      headers['Cookie'] = cookie;
      final token = _extractToken(cookie);
      if (token != null) {
        headers['Authorization'] = 'Bearer $token';
      }
    }
    return headers;
  }

  /// Extract data from tRPC v11 response format
  /// Response format: [{"result":{"data":{"json": <actual_data>}}}]
  static dynamic _extractData(dynamic responseData) {
    if (responseData is Map) {
      // tRPC v11 wraps data in {"json": ...}
      if (responseData.containsKey('json')) {
        return responseData['json'];
      }
      return responseData;
    }
    return responseData;
  }

  /// tRPC Query (GET)
  static Future<Map<String, dynamic>> query(
    String procedure, {
    Map<String, dynamic>? input,
  }) async {
    final cookie = await _getCookie();
    final token = _extractToken(cookie);

    String pathSeg = _trpcPathForRequest();
    String url = _absoluteUrl('$pathSeg/$procedure');
    if (input != null) {
      final wrappedInput = {'json': input};
      final encoded = Uri.encodeComponent(jsonEncode({'0': wrappedInput}));
      url += '?batch=1&input=$encoded';
    } else {
      url += '?batch=1';
    }
    if (token != null) url += '&_token=$token';

    print('QUERY: $procedure -> $url');
    http.Response response;
    try {
      response = await http.get(
        Uri.parse(url),
        headers: _headers(cookie: cookie),
      ).timeout(const Duration(seconds: 20));
    } catch (e) {
      print('QUERY: network error $e');
      throw Exception(_networkErrorMessage(e));
    }

    print('QUERY: status=${response.statusCode}');

    final setCookie = response.headers['set-cookie'];
    if (setCookie != null && setCookie.isNotEmpty) {
      await _saveCookieFromHeader(setCookie);
    }

    if (response.statusCode == 404) {
      final nextPath = pathSeg == _apiTrpcPath
          ? _apiTrpcPathAlt
          : (pathSeg == _apiTrpcPathAlt
              ? _apiTrpcPathAlt2
              : (pathSeg == _apiTrpcPathAlt2 ? _apiTrpcPathAlt3 : null));
      if (nextPath != null && _resolvedTrpcPath == null) {
        _resolvedTrpcPath = nextPath;
        print('QUERY: 404 with $pathSeg, retrying with $nextPath');
        return query(procedure, input: input);
      }
      throw Exception('الرابط غير موجود (404). جرّب إعداد السيرفر حسب docs/FIX-404-خطوة-بخطوة.md — الرابط: $url');
    }
    if (response.statusCode == 200) {
      _resolvedTrpcPath = pathSeg;
    }
    if (response.statusCode == 200) {
      List<dynamic> data;
      try {
        data = jsonDecode(response.body) as List<dynamic>? ?? [];
      } catch (_) {
        print('QUERY: invalid JSON body length=${response.body.length}');
        throw Exception('استجابة غير صالحة من السيرفر. حاول مرة أخرى.');
      }
      if (data.isNotEmpty && data[0]['result'] != null) {
        final rawData = data[0]['result']['data'];
        return {'data': _extractData(rawData), 'success': true};
      }
      if (data.isNotEmpty && data[0]['error'] != null) {
        final errorJson = data[0]['error']['json'] ?? data[0]['error'];
        throw Exception(errorJson['message'] ?? 'Unknown error');
      }
    }
    throw Exception('Request failed: ${response.statusCode}');
  }

  /// Save FCM token to server (يجب إرسال [platform] الصحيح — كان يُحفظ كـ web فيُرسل للأندرويد payload خاطئ)
  Future<void> saveFcmToken(String token) async {
    try {
      final String platform;
      if (kIsWeb) {
        platform = 'web';
      } else {
        switch (defaultTargetPlatform) {
          case TargetPlatform.android:
            platform = 'android';
            break;
          case TargetPlatform.iOS:
            platform = 'ios';
            break;
          default:
            platform = 'unknown';
        }
      }
      await mutate('users.saveFcmToken', input: {'fcmToken': token, 'platform': platform});
    } catch (e) {
      // بدون توكن على السيرفر لن يصل أي push في الخلفية — سجّل للتشخيص
      print('[FCM] saveFcmToken failed: $e');
    }
  }

  /// Upload a file via standalone upload.php endpoint.
  /// Uses bytes for web compatibility, falls back to file path on mobile.
  static Future<String> uploadFile(String filePath, {List<int>? bytes, String? filename}) async {
    // On the server, upload endpoint lives under backend/upload.php
    // (container document root is the project root).
    final url = _absoluteUrl('backend/upload.php');
    final request = http.MultipartRequest('POST', Uri.parse(url));
    if (bytes != null) {
      request.files.add(http.MultipartFile.fromBytes(
        'file', bytes,
        filename: filename ?? 'upload_${DateTime.now().millisecondsSinceEpoch}.jpg',
      ));
    } else {
      request.files.add(await http.MultipartFile.fromPath('file', filePath));
    }
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode == 200) {
      final json = jsonDecode(response.body);
      return json['url'] as String;
    }
    throw Exception('Upload failed: ${response.statusCode} - ${response.body}');
  }

  /// tRPC Mutation (POST)
  static Future<Map<String, dynamic>> mutate(
    String procedure, {
    Map<String, dynamic>? input,
  }) async {
    final cookie = await _getCookie();
    final token = _extractToken(cookie);
    final pathSeg = _trpcPathForRequest();
    var url = _absoluteUrl('$pathSeg/$procedure?batch=1');
    if (token != null) url += '&_token=$token';

    final body = jsonEncode({'0': {'json': input ?? {}}});

    print('MUTATE: $procedure -> $url');
    http.Response response;
    try {
      response = await http.post(
        Uri.parse(url),
        headers: _headers(cookie: cookie),
        body: body,
      ).timeout(const Duration(seconds: 20));
    } catch (e) {
      print('MUTATE: network error $e');
      throw Exception(_networkErrorMessage(e));
    }

    final setCookie = response.headers['set-cookie'];
    if (setCookie != null && setCookie.isNotEmpty) {
      await _saveCookieFromHeader(setCookie);
    }

    if (response.statusCode == 404) {
      final nextPath = pathSeg == _apiTrpcPath
          ? _apiTrpcPathAlt
          : (pathSeg == _apiTrpcPathAlt
              ? _apiTrpcPathAlt2
              : (pathSeg == _apiTrpcPathAlt2 ? _apiTrpcPathAlt3 : null));
      if (nextPath != null && _resolvedTrpcPath == null) {
        _resolvedTrpcPath = nextPath;
        print('MUTATE: 404 with $pathSeg, retrying with $nextPath');
        return mutate(procedure, input: input);
      }
      throw Exception('الرابط غير موجود (404). جرّب إعداد السيرفر حسب docs/FIX-404-خطوة-بخطوة.md — الرابط: $url');
    }
    if (response.statusCode == 200 || response.statusCode == 207) {
      _resolvedTrpcPath = pathSeg;
    }
    // tRPC returns errors as 200 with error field, OR as 400/401/403/4xx
    final acceptedCodes = [200, 207, 400, 401, 403];
    if (acceptedCodes.contains(response.statusCode)) {
      try {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>? ?? [];
        if (data.isNotEmpty && data[0]['result'] != null) {
          final rawData = data[0]['result']['data'];
          final extractedData = _extractData(rawData);

          // If the response contains a sessionToken, save it directly
          // This is more reliable than Set-Cookie header in Flutter http package
          if (extractedData is Map && extractedData.containsKey('sessionToken')) {
            final token = extractedData['sessionToken'];
            if (token != null && token.toString().isNotEmpty) {
              await saveSessionToken(token.toString());
            }
          }

          return {'data': extractedData, 'success': true};
        }
        if (data.isNotEmpty && data[0]['error'] != null) {
          final errorJson = data[0]['error']['json'] ?? data[0]['error'];
          final msg = errorJson['message'] ?? 'Unknown error';
          final code = errorJson['data']?['code'] ?? '';
          // Check for UNAUTHORIZED code
          if (code == 'UNAUTHORIZED' || msg.contains('UNAUTHORIZED')) {
            throw Exception('UNAUTHORIZED: $msg');
          }
          // Check for FORBIDDEN code
          if (code == 'FORBIDDEN' || msg.contains('Staff access required')) {
            throw Exception('ليس لديك صلاحية لتنفيذ هذه العملية');
          }
          throw Exception(msg);
        }
      } catch (e) {
        if (e is Exception) rethrow;
      }
    }
    throw Exception('Request failed: ${response.statusCode}');
  }
}
