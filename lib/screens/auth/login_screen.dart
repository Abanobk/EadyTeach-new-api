import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auth_provider.dart';
import '../../utils/app_theme.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/google_auth_service.dart';
import '../../services/notification_service.dart';
import 'signup_screen.dart';

// ─── Design: gradient background, white card, gradient button ─────────────
const Color _kPrimaryBlue = Color(0xFF2B6CB0);
const Color _kAccentOrange = Color(0xFFF68B1F);
const Color _kTextDark = Color(0xFF1A1D21);
const Color _kTextWhite = Color(0xFFFFFFFF);

void _flipToSignup(BuildContext context) {
  Navigator.of(context).push(
    PageRouteBuilder(
      transitionDuration: const Duration(milliseconds: 600),
      pageBuilder: (context, animation, secondaryAnimation) => const SignupScreen(),
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final rotateAnimation = Tween<double>(begin: 1.0, end: 0.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeInOut),
        );
        return AnimatedBuilder(
          animation: rotateAnimation,
          child: child,
          builder: (context, child) {
            final angle = rotateAnimation.value * 3.1416;
            return Transform(
              transform: Matrix4.rotationY(angle),
              alignment: Alignment.center,
              child: child,
            );
          },
        );
      },
    ),
  );
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _googleLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = true;
  String? _error;

  static const _keyRememberMe = 'remember_me';

  @override
  void initState() {
    super.initState();
    _loadRememberMe();
  }

  Future<void> _loadRememberMe() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() => _rememberMe = prefs.getBool(_keyRememberMe) ?? true);
  }

  Future<void> _saveRememberMe(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyRememberMe, value);
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    ApiService.setPersistSession(_rememberMe);

    try {
      Map<String, dynamic>? result;
      try {
        result = await ApiService.mutate(
          'auth.adminLogin',
          input: {
            'email': _emailController.text.trim(),
            'password': _passwordController.text,
          },
        );
      } catch (_) {
        result = await ApiService.mutate(
          'auth.userLogin',
          input: {
            'email': _emailController.text.trim(),
            'password': _passwordController.text,
          },
        );
      }

      if (!mounted) return;

      if (result != null && result['success'] == true) {
        final auth = context.read<AuthProvider>();
        final data = result['data'];
        if (data != null && data is Map<String, dynamic> && data['user'] != null) {
          auth.setUserFromLoginData(data);
        } else {
          await auth.checkAuth();
        }
        if (!mounted) return;
        if (auth.isLoggedIn) {
          try {
            await NotificationService().getAndSaveFcmToken();
            unawaited(NotificationService().updateBadgeFromServer());
          } catch (e) {
            print('FCM_ERROR: $e');
          }
          Navigator.pushReplacementNamed(context, '/role-select');
        } else {
          setState(() => _error = 'تم تسجيل الدخول لكن تعذّر تحميل البيانات.');
        }
      }
    } catch (e) {
      if (!mounted) return;
      print('LOGIN_ERROR: $e');
      final errMsg = e.toString();
      if (errMsg.contains('UNAUTHORIZED') || errMsg.contains('غير صحيح') || errMsg.contains('غير نشط')) {
        setState(() => _error = 'البريد الإلكتروني أو كلمة المرور غير صحيحة');
      } else {
        setState(() => _error = 'خطأ: ${errMsg.length > 120 ? errMsg.substring(0, 120) : errMsg}');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _googleSignIn() async {
    setState(() {
      _googleLoading = true;
      _error = null;
    });
    ApiService.setPersistSession(_rememberMe);

    try {
      final result = await GoogleAuthService.signIn();
      if (result == null) {
        setState(() => _googleLoading = false);
        return;
      }

      if (!mounted) return;

      if (result['success'] == true) {
        final auth = context.read<AuthProvider>();
        final data = result['data'];
        if (data != null && data is Map<String, dynamic> && data['user'] != null) {
          auth.setUserFromLoginData(data);
        } else {
          await auth.checkAuth();
        }
        if (!mounted) return;
        if (auth.isLoggedIn) {
          try {
            await NotificationService().getAndSaveFcmToken();
            unawaited(NotificationService().updateBadgeFromServer());
          } catch (e) {
            print('FCM_ERROR: $e');
          }
          Navigator.pushReplacementNamed(context, '/role-select');
        } else {
          setState(() => _error = 'تم تسجيل الدخول لكن تعذّر تحميل البيانات.');
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'فشل تسجيل الدخول بـ Google. حاول مرة أخرى.');
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: AppThemeDecorations.gradientBackground(context),
        child: Center(
          child: SingleChildScrollView(
            child: Form(
              key: _formKey,
              child: Container(
                width: 420,
                padding: const EdgeInsets.all(24),
                margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: AppThemeDecorations.loginStyleCard(context, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ThemeToggleLogo(size: 80),
                    const SizedBox(height: 20),
                    Builder(
                      builder: (context) {
                        final isDark = Theme.of(context).brightness == Brightness.dark;
                        return ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [
                              Color(0xFF6CB4FF),
                              Color(0xFFF68B1F),
                              Color(0xFF6CB4FF),
                            ],
                          ).createShader(bounds),
                          child: Text(
                            'Easy Tech Solutions',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                              color: Colors.white,
                              shadows: isDark
                                  ? [
                                      Shadow(
                                        color: const Color(0xFF6CB4FF).withOpacity(0.9),
                                        blurRadius: 25,
                                      ),
                                      Shadow(
                                        color: const Color(0xFFF68B1F).withOpacity(0.6),
                                        blurRadius: 18,
                                      ),
                                    ]
                                  : [
                                      Shadow(
                                        color: Colors.black.withOpacity(0.15),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Smart Home Ecosystem',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.white70,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 30),
                    if (_error != null) ...[
                      _buildErrorBanner(context, _error!),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textDirection: TextDirection.ltr,
                      style: TextStyle(color: c.onSurface, fontSize: 16),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'أدخل البريد الإلكتروني';
                        if (!v.contains('@')) return 'بريد إلكتروني غير صحيح';
                        return null;
                      },
                      decoration: appThemeInputDecoration(
                        context,
                        hintText: 'Enter your email',
                        prefixIcon: Icon(Icons.email_outlined, color: c.onSurfaceVariant),
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textDirection: TextDirection.ltr,
                      onFieldSubmitted: (_) => _login(),
                      style: TextStyle(color: c.onSurface, fontSize: 16),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'أدخل كلمة المرور';
                        return null;
                      },
                      decoration: appThemeInputDecoration(
                        context,
                        hintText: 'Enter your password',
                        prefixIcon: Icon(Icons.lock_outline, color: c.onSurfaceVariant),
                        suffixIcon: GestureDetector(
                          onTap: () => setState(() => _obscurePassword = !_obscurePassword),
                          child: Icon(
                            _obscurePassword ? Icons.visibility_off : Icons.visibility,
                            size: 22,
                            color: c.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 25),
                    SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _loading ? null : _login,
                          borderRadius: BorderRadius.circular(16),
                          child: Ink(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              gradient: AppThemeDecorations.primaryButtonGradient,
                            ),
                            child: Center(
                              child: _loading
                                  ? const SizedBox(
                                      height: 24,
                                      width: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: _kTextWhite,
                                      ),
                                    )
                                  : const Text(
                                      'LOGIN',
                                      style: TextStyle(
                                        color: _kTextWhite,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('تواصل مع الدعم لإعادة تعيين كلمة المرور'),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.grey,
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('Forgot Password?'),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _socialButton(Icons.g_mobiledata, onPressed: _googleLoading ? null : _googleSignIn, loading: _googleLoading, iconColor: Colors.red),
                        const SizedBox(width: 20),
                        _socialButton(Icons.facebook, onPressed: null, loading: false, iconColor: const Color(0xFF1877F2)),
                        const SizedBox(width: 20),
                        _socialButton(Icons.apple, onPressed: null, loading: false, iconColor: Colors.black),
                      ],
                    ),
                    const SizedBox(height: 25),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Text("Don't have an account? "),
                        GestureDetector(
                          onTap: () => _flipToSignup(context),
                          child: const Text(
                            'Sign Up',
                            style: TextStyle(
                              color: Colors.orange,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _socialButton(IconData icon, {VoidCallback? onPressed, bool loading = false, Color? iconColor}) {
    return Container(
      width: 55,
      height: 55,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: loading
              ? const Center(
                  child: SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : Center(
                  child: Icon(icon, size: 28, color: iconColor ?? const Color(0xFF5C6370)),
                ),
        ),
      ),
    );
  }

  Widget _buildRememberMe() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InkWell(
        onTap: () async {
          final newVal = !_rememberMe;
          setState(() => _rememberMe = newVal);
          await _saveRememberMe(newVal);
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: Checkbox(
                  value: _rememberMe,
                  onChanged: (v) async {
                    setState(() => _rememberMe = v ?? true);
                    await _saveRememberMe(_rememberMe);
                  },
                  activeColor: _kPrimaryBlue,
                  fillColor: MaterialStateProperty.resolveWith((states) {
                    if (states.contains(MaterialState.selected)) return _kPrimaryBlue;
                    return Colors.transparent;
                  }),
                  side: BorderSide(color: _kTextDark.withOpacity(0.4)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'حفظ الحساب للتذكّر',
                style: TextStyle(color: _kTextDark.withOpacity(0.8), fontSize: 13, fontWeight: FontWeight.w300),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSocialIconButton({
    required VoidCallback? onPressed,
    required bool loading,
    required Widget child,
  }) {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kPrimaryBlue.withOpacity(0.2)),
        boxShadow: [BoxShadow(color: _kPrimaryBlue.withOpacity(0.08), blurRadius: 12)],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: loading
              ? const Center(child: SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: _kPrimaryBlue)))
              : Center(child: child),
        ),
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, String message) {
    final c = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.error.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.error.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, color: c.error, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(color: c.error, fontSize: 13))),
        ],
      ),
    );
  }
}
