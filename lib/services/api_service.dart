import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // رابط السيرفر الرسمي الثابت — لا تغيير في Base URL أو Headers
  static const String baseUrl = 'https://api.easytecheg.net';
  static const String trpcUrl = '$baseUrl/api/trpc';

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
    if (url.contains('firebasestorage.googleapis.com')) {
      return '$baseUrl/api/image-proxy?url=${Uri.encodeComponent(url)}';
    }
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
    String url = '$trpcUrl/$procedure';

    // tRPC v11 uses {"json": input} format
    if (input != null) {
      final wrappedInput = {'json': input};
      final encoded = Uri.encodeComponent(jsonEncode({'0': wrappedInput}));
      url += '?batch=1&input=$encoded';
    } else {
      url += '?batch=1';
    }
    if (token != null) url += '&_token=$token';

    print('QUERY: $procedure');
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

    // Save cookie if returned in header
    final setCookie = response.headers['set-cookie'];
    if (setCookie != null && setCookie.isNotEmpty) {
      await _saveCookieFromHeader(setCookie);
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

  /// Save FCM token to server
  Future<void> saveFcmToken(String token) async {
    try {
      await mutate('users.saveFcmToken', input: {'fcmToken': token});
    } catch (e) {
      // Ignore errors - token save is non-critical
    }
  }

  /// Upload a file via standalone upload.php endpoint.
  /// Uses bytes for web compatibility, falls back to file path on mobile.
  static Future<String> uploadFile(String filePath, {List<int>? bytes, String? filename}) async {
    final url = '$baseUrl/upload.php';
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
    var url = '$trpcUrl/$procedure?batch=1';
    if (token != null) url += '&_token=$token';

    // tRPC v11 uses {"json": input} format
    final body = jsonEncode({'0': {'json': input ?? {}}});

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

    // Save cookie if returned in Set-Cookie header
    final setCookie = response.headers['set-cookie'];
    if (setCookie != null && setCookie.isNotEmpty) {
      await _saveCookieFromHeader(setCookie);
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
