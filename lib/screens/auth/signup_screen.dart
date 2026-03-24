import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/app_theme.dart';
import '../../theme/app_theme.dart';
import '../../services/api_service.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _loading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _signup() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await ApiService.mutate(
        'auth.register',
        input: {
          'name': _nameController.text.trim(),
          'email': _emailController.text.trim(),
          'phone': _phoneController.text.trim(),
          'password': _passwordController.text,
        },
      );

      if (!mounted) return;

      if (result['success'] == true) {
        final auth = context.read<AuthProvider>();
        await auth.checkAuth();
        if (!mounted) return;
        if (auth.isLoggedIn) {
          Navigator.pushReplacementNamed(context, '/role-select');
        } else {
          setState(() => _error = 'تم إنشاء الحساب لكن تعذّر تحميل البيانات.');
        }
      }
    } catch (e) {
      if (!mounted) return;
      var errMsg = e.toString();
      if (errMsg.startsWith('Exception: ')) {
        errMsg = errMsg.substring('Exception: '.length).trim();
      }
      if (errMsg.contains('CONFLICT') || errMsg.contains('مسجل مسبقاً')) {
        setState(() => _error = 'هذا البريد الإلكتروني مسجل مسبقاً');
      } else if (errMsg.contains('فشل الاتصال') ||
          errMsg.contains('SocketException') ||
          errMsg.toLowerCase().contains('network') ||
          errMsg.contains('timeout')) {
        setState(() => _error = 'حدث خطأ. تأكد من الاتصال بالإنترنت.');
      } else if (errMsg.isNotEmpty) {
        setState(() => _error = errMsg);
      } else {
        setState(() => _error = 'حدث خطأ. حاول مرة أخرى.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: AppThemeDecorations.gradientBackground(context),
        child: SafeArea(
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: AppThemeDecorations.loginStyleCard(context, 24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ThemeToggleLogo(size: 70),
                      const SizedBox(height: 16),
                      Text(
                        'إنشاء حساب جديد',
                        style: TextStyle(
                          color: c.onSurface,
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'أنشئ حسابك للوصول إلى خدمات EASY TECH',
                        style: TextStyle(color: c.onSurfaceVariant, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      if (_error != null) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: c.error.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: c.error.withOpacity(0.3)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error_outline, color: c.error, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: TextStyle(color: c.error, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                  // Name field
                  _buildLabel(context, 'الاسم الكامل'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _nameController,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(color: c.onSurface),
                    decoration: _inputDecoration(
                      context,
                      hint: 'أدخل اسمك الكامل',
                      icon: Icons.person_outline,
                    ),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'أدخل اسمك';
                      if (v.trim().length < 2) return 'الاسم قصير جداً';
                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  // Email field
                  _buildLabel(context, 'البريد الإلكتروني'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(color: c.onSurface),
                    decoration: _inputDecoration(
                      context,
                      hint: 'example@email.com',
                      icon: Icons.email_outlined,
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'أدخل البريد الإلكتروني';
                      if (!v.contains('@') || !v.contains('.')) return 'بريد إلكتروني غير صحيح';
                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  // Phone field
                  _buildLabel(context, 'رقم الهاتف (اختياري)'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(color: c.onSurface),
                    decoration: _inputDecoration(
                      context,
                      hint: '01xxxxxxxxx',
                      icon: Icons.phone_outlined,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Password field
                  _buildLabel(context, 'كلمة المرور'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(color: c.onSurface),
                    decoration: _inputDecoration(
                      context,
                      hint: '••••••••',
                      icon: Icons.lock_outline,
                      suffixIcon: GestureDetector(
                        onTap: () => setState(() => _obscurePassword = !_obscurePassword),
                        child: Icon(
                          _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          color: c.onSurfaceVariant,
                        ),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'أدخل كلمة المرور';
                      if (v.length < 6) return 'كلمة المرور يجب أن تكون 6 أحرف على الأقل';
                      return null;
                    },
                  ),

                  const SizedBox(height: 16),

                  // Confirm Password field
                  _buildLabel(context, 'تأكيد كلمة المرور'),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: _obscureConfirm,
                    textDirection: TextDirection.ltr,
                    style: TextStyle(color: c.onSurface),
                    decoration: _inputDecoration(
                      context,
                      hint: '••••••••',
                      icon: Icons.lock_outline,
                      suffixIcon: GestureDetector(
                        onTap: () => setState(() => _obscureConfirm = !_obscureConfirm),
                        child: Icon(
                          _obscureConfirm ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                          color: c.onSurfaceVariant,
                        ),
                      ),
                    ),
                    validator: (v) {
                      if (v == null || v.isEmpty) return 'أكّد كلمة المرور';
                      if (v != _passwordController.text) return 'كلمتا المرور غير متطابقتين';
                      return null;
                    },
                  ),

                  const SizedBox(height: 28),

                  // Signup button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _loading ? null : _signup,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _loading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.person_add_outlined, color: Colors.black),
                                SizedBox(width: 8),
                                Text(
                                  'إنشاء الحساب',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  // Back to login
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'لديك حساب بالفعل؟ ',
                        style: TextStyle(color: c.onSurfaceVariant, fontSize: 14),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Text(
                          'تسجيل الدخول',
                          style: TextStyle(
                            color: c.primary,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 30),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(BuildContext context, String text) {
    final c = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: Text(
        text,
        style: TextStyle(
          color: c.onSurface,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
    BuildContext context, {
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    final c = Theme.of(context).colorScheme;
    return appThemeInputDecoration(
      context,
      hintText: hint,
      prefixIcon: Icon(icon, color: c.onSurfaceVariant),
      suffixIcon: suffixIcon,
    );
  }
}
