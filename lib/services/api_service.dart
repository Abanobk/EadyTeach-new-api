import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ApiService {
  // رابط السيرفر المحلي (شغال حتى يتم النشر الرسمي)
  static const String baseUrl = 'https://3000-iajtve8wzip4xotod3a3c-58edb681.sg1.manus.computer';
  static const String trpcUrl = '$baseUrl/api/trpc';

  static Future<String?> _getCookie() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('session_cookie');
  }

  static Future<void> _saveCookie(String cookie) async {
    final prefs = await SharedPreferences.getInstance();
    // Extract only the session cookie value (before the first semicolon)
    final cookieValue = cookie.split(';').first.trim();
    await prefs.setString('session_cookie', cookieValue);
  }

  static Future<void> clearCookie() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('session_cookie');
  }

  static Map<String, String> _headers({String? cookie}) {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };
    if (cookie != null && cookie.isNotEmpty) {
      headers['Cookie'] = cookie;
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
    String url = '$trpcUrl/$procedure';

    // tRPC v11 uses {"json": input} format
    if (input != null) {
      final wrappedInput = {'json': input};
      final encoded = Uri.encodeComponent(jsonEncode({'0': wrappedInput}));
      url += '?batch=1&input=$encoded';
    } else {
      url += '?batch=1';
    }

    final response = await http.get(
      Uri.parse(url),
      headers: _headers(cookie: cookie),
    );

    // Save cookie if returned
    final setCookie = response.headers['set-cookie'];
    if (setCookie != null && setCookie.isNotEmpty) {
      await _saveCookie(setCookie);
    }

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
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

  /// tRPC Mutation (POST)
  static Future<Map<String, dynamic>> mutate(
    String procedure, {
    Map<String, dynamic>? input,
  }) async {
    final cookie = await _getCookie();
    final url = '$trpcUrl/$procedure?batch=1';

    // tRPC v11 uses {"json": input} format
    final body = jsonEncode({'0': {'json': input ?? {}}});

    final response = await http.post(
      Uri.parse(url),
      headers: _headers(cookie: cookie),
      body: body,
    );

    // Save cookie if returned
    final setCookie = response.headers['set-cookie'];
    if (setCookie != null && setCookie.isNotEmpty) {
      await _saveCookie(setCookie);
    }

    if (response.statusCode == 200) {
      final List<dynamic> data = jsonDecode(response.body);
      if (data.isNotEmpty && data[0]['result'] != null) {
        final rawData = data[0]['result']['data'];
        return {'data': _extractData(rawData), 'success': true};
      }
      if (data.isNotEmpty && data[0]['error'] != null) {
        final errorJson = data[0]['error']['json'] ?? data[0]['error'];
        final msg = errorJson['message'] ?? 'Unknown error';
        // Check for UNAUTHORIZED code
        if (errorJson['data']?['code'] == 'UNAUTHORIZED' ||
            msg.contains('UNAUTHORIZED')) {
          throw Exception('UNAUTHORIZED: $msg');
        }
        throw Exception(msg);
      }
    }
    throw Exception('Request failed: ${response.statusCode}');
  }
}
