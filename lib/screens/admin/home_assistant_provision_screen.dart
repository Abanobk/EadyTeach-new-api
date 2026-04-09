import 'package:flutter/material.dart';
import 'dart:async';

import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';

class HomeAssistantProvisionScreen extends StatefulWidget {
  const HomeAssistantProvisionScreen({super.key});

  @override
  State<HomeAssistantProvisionScreen> createState() =>
      _HomeAssistantProvisionScreenState();
}

class _HomeAssistantProvisionScreenState
    extends State<HomeAssistantProvisionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  final _tokenCtrl = TextEditingController();
  bool _saving = false;
  bool _loadingExisting = false;
  String? _existingSummary;
  bool _prefilledOnce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_prefilledOnce) return;
    _prefilledOnce = true;
    final arg = ModalRoute.of(context)?.settings.arguments;
    if (arg is String && arg.contains('@')) {
      _emailCtrl.text = arg.trim();
      // fire-and-forget (load existing provisioning for this email)
      Future.microtask(_loadExisting);
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _urlCtrl.dispose();
    _tokenCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final res = await ApiService.mutate(
        'admin.homeAssistant.provision',
        input: {
          'email': _emailCtrl.text.trim(),
          'haUrl': _urlCtrl.text.trim(),
          'haToken': _tokenCtrl.text.trim(),
        },
      );
      final data = res['data'];
      final userId = data is Map ? data['userId'] : null;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم الحفظ بنجاح (User ID: $userId)'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _loadExisting() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('أدخل بريد صحيح أولاً'),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    setState(() {
      _loadingExisting = true;
      _existingSummary = null;
    });
    try {
      final res = await ApiService.mutate(
        'admin.homeAssistant.getProvision',
        input: {'email': email},
      );
      final data = res['data'];
      final enabled = data is Map ? (data['enabled'] == true) : false;
      final haUrl = data is Map ? (data['haUrl'] ?? '').toString() : '';
      final tokenMasked = data is Map ? (data['tokenMasked'] ?? '').toString() : '';

      if (mounted) {
        setState(() {
          _urlCtrl.text = haUrl;
          _existingSummary = enabled
              ? 'موجود: Enabled • URL: $haUrl • Token: $tokenMasked'
              : 'غير مفعّل لهذا الحساب (لا يوجد URL/Token محفوظين).';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _existingSummary = 'خطأ تحميل البيانات: $e');
      }
    } finally {
      if (mounted) setState(() => _loadingExisting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Provision Home Assistant'),
      ),
      body: Container(
        decoration: AppThemeDecorations.gradientBackground(context),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Container(
              width: 560,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: scheme.surface.withOpacity(0.9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: scheme.outline.withOpacity(0.2)),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'ربط حساب العميل بـ Home Assistant',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'أدخل البريد + رابط HA + Long-lived token. العميل لن يرى شاشة تسجيل دخول.',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'User Email',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) {
                        final s = (v ?? '').trim();
                        if (s.isEmpty) return 'مطلوب';
                        if (!s.contains('@')) return 'بريد غير صحيح';
                        return null;
                      },
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _loadingExisting ? null : _loadExisting,
                      icon: _loadingExisting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.download_rounded),
                      label: Text(_loadingExisting ? 'جارٍ التحميل...' : 'تحميل بيانات العميل الحالية'),
                    ),
                    if (_existingSummary != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _existingSummary!,
                        style: TextStyle(
                          color: _existingSummary!.startsWith('خطأ')
                              ? scheme.error
                              : scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _urlCtrl,
                      decoration: const InputDecoration(
                        labelText: 'HA URL (e.g. https://ha.example.com:8123)',
                        border: OutlineInputBorder(),
                      ),
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'مطلوب' : null,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _tokenCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Long-lived Access Token',
                        border: OutlineInputBorder(),
                      ),
                      minLines: 2,
                      maxLines: 4,
                      validator: (v) =>
                          (v ?? '').trim().isEmpty ? 'مطلوب' : null,
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_rounded),
                      label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ'),
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
}

