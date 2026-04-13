import 'package:flutter/material.dart';
import '../services/api_service.dart';

class UserModel {
  final int id;
  final String name;
  final String email;
  final String role;
  final String? phone;
  final String? address;
  final String? location;
  final String? avatarUrl;
  List<String> permissions;

  UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.phone,
    this.address,
    this.location,
    this.avatarUrl,
    this.permissions = const [],
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] ?? 0,
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? 'user',
      phone: json['phone'],
      address: json['address'],
      location: json['location'],
      avatarUrl: json['avatarUrl'],
    );
  }

  String get _roleNorm => role.trim().toLowerCase();

  bool get isAdmin => _roleNorm == 'admin';
  bool get isTechnician => _roleNorm == 'technician';
  bool get isClient => _roleNorm == 'user' || _roleNorm == 'client';
  bool get isDealer {
    const dealerRoles = {'dealer', 'reseller', 'merchant'};
    return dealerRoles.contains(_roleNorm);
  }

  bool get canAccessAdmin => _roleNorm == 'admin' || _roleNorm == 'staff' || _roleNorm == 'supervisor';

  String get defaultLandingRoute {
    if (canAccessAdmin) return '/admin';
    if (isTechnician) return '/technician';
    return '/client';
  }

  bool hasPermission(String key) {
    if (isAdmin) return true;
    return permissions.contains(key);
  }

  bool hasAnyPermission(List<String> keys) {
    if (isAdmin) return true;
    return keys.any((k) => permissions.contains(k));
  }
}

class AuthProvider extends ChangeNotifier {
  UserModel? _user;
  bool _isLoading = true;
  String? _error;
  int? _pendingProductId;

  /// حسابات تُعامل دائماً كفني فقط (لا تدخل لوحة المسؤول حتى لو الـ backend أعطاها صلاحية أدمن)
  static const _technicianOnlyEmails = ['easytech50500@gmail.com'];

  /// حسابات تُعامل دائماً كمشرف (يمكنها دخول لوحة المسؤول حتى لو الـ backend لم يرجع role=admin)
  static const _extraAdminEmails = [
    'noshymaryan@gmail.com',
  ];

  UserModel? get user => _user;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _user != null;
  String? get error => _error;
  int? get pendingProductId => _pendingProductId;

  /// أسماء العرض للحسابات (الـ backend قد يرجّع "Admin" بدل الاسم الحقيقي)
  static const _displayNames = {
    'easytech50500@gmail.com': 'حسن عبد الحميد',
  };

  /// اسم المستخدم للعرض في الترحيب وغيره (حسب البريد إن وُجد في القائمة وإلا الاسم من السيرفر)
  String get userDisplayName {
    final u = _user;
    if (u == null) return '';
    final email = u.email.trim().toLowerCase();
    return _displayNames[email] ?? u.name;
  }

  bool get canAccessAdmin {
    final u = _user;
    if (u == null) return false;
    final email = u.email.trim().toLowerCase();
    if (_technicianOnlyEmails.contains(email)) return false;
    if (_extraAdminEmails.contains(email)) return true;
    return u.canAccessAdmin;
  }

  bool hasPermission(String key) => _user?.hasPermission(key) ?? false;

  String get defaultLandingRoute {
    final u = _user;
    if (u == null) return '/login';
    final email = u.email.trim().toLowerCase();
    if (_technicianOnlyEmails.contains(email)) return '/technician';
    if (_extraAdminEmails.contains(email)) return '/admin';
    return u.defaultLandingRoute;
  }

  void setPendingProductId(int? value, {bool notify = false}) {
    _pendingProductId = (value != null && value > 0) ? value : null;
    if (notify) notifyListeners();
  }

  int? consumePendingProductId() {
    final value = _pendingProductId;
    _pendingProductId = null;
    return value;
  }

  Future<void> _loadPermissions() async {
    if (_user == null) return;
    try {
      final res = await ApiService.query('permissions.getUserPermissions', input: {});
      final perms = (res['data']?['permissions'] as List?)?.map((e) => e.toString()).toList() ?? [];
      _user!.permissions = perms;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> checkAuth() async {
    _isLoading = true;
    notifyListeners();
    try {
      print('AUTH_CHECK: calling auth.me...');
      final result = await ApiService.query('auth.me');
      print('AUTH_CHECK: result=$result');
      if (result['data'] != null) {
        _user = UserModel.fromJson(result['data']);
        print('AUTH_CHECK: user loaded: ${_user?.email}');
        await _loadPermissions();
      } else {
        _user = null;
        print('AUTH_CHECK: data is null');
      }
    } catch (e) {
      _user = null;
      print('AUTH_CHECK_ERROR: $e');
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> logout() async {
    try {
      await ApiService.mutate('auth.logout');
    } catch (_) {}
    await ApiService.clearCookie();
    _user = null;
    _pendingProductId = null;
    notifyListeners();
  }

  void setUser(UserModel user) {
    _user = user;
    _isLoading = false;
    notifyListeners();
  }

  /// Set user directly from login response data (avoids need for auth.me call)
  void setUserFromLoginData(Map<String, dynamic> loginData) {
    final userData = loginData['user'] ?? loginData;
    _user = UserModel.fromJson(userData);
    _isLoading = false;
    print('AUTH: user set from login data: ${_user?.email} role=${_user?.role}');
    notifyListeners();
    _loadPermissions();
  }

  /// OAuth login URL. returnTo must point to app path (not API). API stays at root.
  String getLoginUrl() {
    return '${ApiService.baseUrl}/api/oauth/login?returnTo=${Uri.encodeComponent('/app/')}';
  }
}
