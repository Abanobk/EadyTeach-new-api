import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  Future<void> _forgotPassword() async {
    final emailCtrl = TextEditingController(text: _emailController.text.trim());
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppThemeDecorations.cardColor(context),
          title: const Text('إعادة تعيين كلمة المرور', style: TextStyle(color: AppColors.text)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('أدخل البريد الإلكتروني للحساب الذي تريد إعادة تعيين كلمته:', style: TextStyle(color: AppColors.muted, fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  hintText: 'example@email.com',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('إرسال', style: TextStyle(color: _kPrimaryBlue))),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      final email = emailCtrl.text.trim();
      if (!email.contains('@')) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('أدخل بريد إلكتروني صحيح'), backgroundColor: Colors.red));
        }
        return;
      }
      try {
        final result = await ApiService.mutate('auth.forgotPassword', input: {'email': email});
        if (!mounted) return;
        final data = result['data'];
        final tempPassword = data is Map ? data['temporaryPassword']?.toString() : null;
        if (tempPassword != null && tempPassword.isNotEmpty) {
          await showDialog<void>(
            context: context,
            builder: (ctx) => Directionality(
              textDirection: TextDirection.rtl,
              child: AlertDialog(
                backgroundColor: AppThemeDecorations.cardColor(context),
                title: const Text('كلمة المرور الجديدة', style: TextStyle(color: AppColors.text)),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'تعذّر إرسال البريد من السيرفر. استخدم كلمة المرور التالية للدخول ثم غيّرها من الإعدادات.',
                      style: TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    SelectableText(
                      tempPassword,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: tempPassword));
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('تم النسخ')));
                      }
                    },
                    child: const Text('نسخ'),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('حسناً', style: TextStyle(color: _kPrimaryBlue)),
                  ),
                ],
              ),
            ),
          );
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('إذا كان البريد مسجلاً ستصلك كلمة مرور جديدة (تحقق من الرسائل غير المرغوب فيها).'),
          backgroundColor: Colors.green,
        ));
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('خطأ أثناء إعادة التعيين: $e'),
            backgroundColor: Colors.red,
          ));
        }
      }
    }
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
          final pendingProductId = auth.consumePendingProductId();
          Navigator.pushReplacementNamed(
            context,
            auth.defaultLandingRoute,
            arguments: auth.defaultLandingRoute == '/client' && pendingProductId != null
                ? {'productId': pendingProductId}
                : null,
          );
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
          final pendingProductId = auth.consumePendingProductId();
          Navigator.pushReplacementNamed(
            context,
            auth.defaultLandingRoute,
            arguments: auth.defaultLandingRoute == '/client' && pendingProductId != null
                ? {'productId': pendingProductId}
                : null,
          );
        } else {
          setState(() => _error = 'تم تسجيل الدخول لكن تعذّر تحميل البيانات.');
        }
      }
    } catch (e) {
      if (!mounted) return;
      var msg = e.toString();
      if (msg.startsWith('Exception: ')) {
        msg = msg.substring('Exception: '.length);
      }
      if (msg.startsWith('UNAUTHORIZED: ')) {
        msg = msg.substring('UNAUTHORIZED: '.length);
      }
      setState(() => _error = msg.length > 220 ? '${msg.substring(0, 220)}…' : msg);
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Container(
        decoration: AppThemeDecorations.gradientBackground(context),
        child: SafeArea(
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 920;
                      final loginCard = ClipRRect(
                        borderRadius: BorderRadius.circular(32),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                          child: Container(
                            width: wide ? null : 460,
                            padding: const EdgeInsets.all(28),
                            decoration: AppThemeDecorations.loginStyleCard(context, 32),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Center(child: ThemeToggleLogo(size: 82)),
                                  const SizedBox(height: 22),
                                  Center(
                                    child: Text(
                                      'تسجيل الدخول',
                                      style: Theme.of(context).textTheme.headlineSmall,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Center(
                                    child: Text(
                                      'واجهة أحدث للدخول السريع إلى منظومة Easy Tech',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            color: c.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  if (_error != null) ...[
                                    _buildErrorBanner(context, _error!),
                                    const SizedBox(height: 16),
                                  ],
                                  TextFormField(
                                    controller: _emailController,
                                    keyboardType: TextInputType.emailAddress,
                                    textDirection: TextDirection.ltr,
                                    style: TextStyle(color: c.onSurface, fontSize: 16, fontWeight: FontWeight.w600),
                                    validator: (v) {
                                      if (v == null || v.isEmpty) return 'أدخل البريد الإلكتروني';
                                      if (!v.contains('@')) return 'بريد إلكتروني غير صحيح';
                                      return null;
                                    },
                                    decoration: appThemeInputDecoration(
                                      context,
                                      hintText: 'example@email.com',
                                      labelText: 'البريد الإلكتروني',
                                      prefixIcon: Icon(Icons.alternate_email_rounded, color: c.secondary),
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  TextFormField(
                                    controller: _passwordController,
                                    obscureText: _obscurePassword,
                                    textDirection: TextDirection.ltr,
                                    onFieldSubmitted: (_) => _login(),
                                    style: TextStyle(color: c.onSurface, fontSize: 16, fontWeight: FontWeight.w600),
                                    validator: (v) {
                                      if (v == null || v.isEmpty) return 'أدخل كلمة المرور';
                                      return null;
                                    },
                                    decoration: appThemeInputDecoration(
                                      context,
                                      hintText: '••••••••',
                                      labelText: 'كلمة المرور',
                                      prefixIcon: Icon(Icons.lock_outline_rounded, color: c.secondary),
                                      suffixIcon: GestureDetector(
                                        onTap: () => setState(() => _obscurePassword = !_obscurePassword),
                                        child: Icon(
                                          _obscurePassword ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                                          size: 22,
                                          color: c.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  _buildRememberMe(),
                                  const SizedBox(height: 18),
                                  SizedBox(
                                    width: double.infinity,
                                    height: 58,
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: _loading ? null : _login,
                                        borderRadius: BorderRadius.circular(18),
                                        child: Ink(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(18),
                                            gradient: AppThemeDecorations.primaryButtonGradient,
                                            boxShadow: [
                                              BoxShadow(
                                                color: c.primary.withOpacity(0.22),
                                                blurRadius: 22,
                                                spreadRadius: -8,
                                                offset: const Offset(0, 16),
                                              ),
                                            ],
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
                                                    'دخول إلى المنصة',
                                                    style: TextStyle(
                                                      color: _kTextWhite,
                                                      fontSize: 17,
                                                      fontWeight: FontWeight.w800,
                                                    ),
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 14),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton(
                                      onPressed: _forgotPassword,
                                      child: Text(
                                        'نسيت كلمة المرور؟',
                                        style: TextStyle(color: c.secondary, fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Row(
                                    children: [
                                      Expanded(child: Divider(color: c.outline.withOpacity(0.8))),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12),
                                        child: Text(
                                          'أو المتابعة عبر',
                                          style: TextStyle(color: c.onSurfaceVariant, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      Expanded(child: Divider(color: c.outline.withOpacity(0.8))),
                                    ],
                                  ),
                                  const SizedBox(height: 18),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      _socialButton(Icons.g_mobiledata, onPressed: _googleLoading ? null : _googleSignIn, loading: _googleLoading, iconColor: Colors.red),
                                      const SizedBox(width: 16),
                                      _socialButton(Icons.facebook, onPressed: null, loading: false, iconColor: const Color(0xFF1877F2)),
                                      const SizedBox(width: 16),
                                      _socialButton(Icons.apple, onPressed: null, loading: false, iconColor: isDark ? Colors.white : Colors.black),
                                    ],
                                  ),
                                  const SizedBox(height: 24),
                                  Center(
                                    child: Wrap(
                                      crossAxisAlignment: WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          'ليس لديك حساب؟ ',
                                          style: TextStyle(color: c.onSurfaceVariant),
                                        ),
                                        GestureDetector(
                                          onTap: () => _flipToSignup(context),
                                          child: Text(
                                            'إنشاء حساب جديد',
                                            style: TextStyle(
                                              color: c.primary,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );

                      if (!wide) {
                        return SingleChildScrollView(child: Center(child: loginCard));
                      }

                      return Row(
                        children: [
                          Expanded(
                            flex: 6,
                            child: Container(
                              padding: const EdgeInsets.all(32),
                              decoration: AppThemeDecorations.heroPanel(context),
                              child: Stack(
                                children: [
                                  Positioned(
                                    top: -55,
                                    left: -30,
                                    child: Container(
                                      width: 180,
                                      height: 180,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white.withOpacity(0.08),
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    bottom: -70,
                                    right: -20,
                                    child: Container(
                                      width: 220,
                                      height: 220,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: Colors.white.withOpacity(0.07),
                                      ),
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const ThemeToggleLogo(size: 88),
                                      const Spacer(),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.14),
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: const Text(
                                          'حلول ذكية لإدارة المتجر والخدمات',
                                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                                        ),
                                      ),
                                      const SizedBox(height: 18),
                                      const Text(
                                        'واجهة دخول تليق بعلامة Easy Tech',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 34,
                                          fontWeight: FontWeight.w900,
                                          height: 1.2,
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      const Text(
                                        'تم رفع جودة الهوية البصرية لتصبح أكثر أناقة واحترافية مع تركيز على الوضوح وسرعة الوصول إلى الوظائف الأساسية.',
                                        style: TextStyle(
                                          color: Color(0xFFE2E8F0),
                                          fontSize: 15,
                                          fontWeight: FontWeight.w500,
                                          height: 1.7,
                                        ),
                                      ),
                                      const SizedBox(height: 26),
                                      Wrap(
                                        spacing: 10,
                                        runSpacing: 10,
                                        children: const [
                                          _LoginFeature(icon: Icons.verified_user_rounded, label: 'دخول آمن'),
                                          _LoginFeature(icon: Icons.palette_rounded, label: 'مظهر حديث'),
                                          _LoginFeature(icon: Icons.bolt_rounded, label: 'تنقل أسرع'),
                                        ],
                                      ),
                                      const Spacer(),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(flex: 5, child: Center(child: SingleChildScrollView(child: loginCard))),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _socialButton(IconData icon, {VoidCallback? onPressed, bool loading = false, Color? iconColor}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = Theme.of(context).colorScheme;
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: isDark ? c.surfaceContainerHighest : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.outline.withOpacity(0.7)),
        boxShadow: isDark
            ? []
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 14,
                  spreadRadius: -4,
                  offset: const Offset(0, 10),
                ),
              ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(18),
          child: loading
              ? Center(
                  child: SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(strokeWidth: 2, color: c.secondary),
                  ),
                )
              : Center(
                  child: Icon(icon, size: 30, color: iconColor ?? c.onSurfaceVariant),
                ),
        ),
      ),
    );
  }

  Widget _buildRememberMe() {
    final c = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.surfaceContainerHighest.withOpacity(0.45),
        borderRadius: BorderRadius.circular(14),
      ),
      child: InkWell(
        onTap: () async {
          final newVal = !_rememberMe;
          setState(() => _rememberMe = newVal);
          await _saveRememberMe(newVal);
        },
        borderRadius: BorderRadius.circular(12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'تذكّر الحساب على هذا الجهاز',
              style: TextStyle(color: c.onSurfaceVariant, fontSize: 13, fontWeight: FontWeight.w700),
            ),
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: _rememberMe,
                onChanged: (v) async {
                  setState(() => _rememberMe = v ?? true);
                  await _saveRememberMe(_rememberMe);
                },
                activeColor: c.secondary,
                side: BorderSide(color: c.outline),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
            ),
          ],
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.error.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.error.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: c.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: c.error, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginFeature extends StatelessWidget {
  final IconData icon;
  final String label;

  const _LoginFeature({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
