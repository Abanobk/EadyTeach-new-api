import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';

class ClientProfileScreen extends StatefulWidget {
  const ClientProfileScreen({super.key});

  @override
  State<ClientProfileScreen> createState() => _ClientProfileScreenState();
}

class _ClientProfileScreenState extends State<ClientProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  bool _saving = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final res = await ApiService.query('users.getProfile');
      final data = res['data'];
      if (data != null) {
        _nameCtrl.text = data['name'] ?? '';
        _phoneCtrl.text = data['phone'] ?? '';
        _addressCtrl.text = data['address'] ?? '';
        setState(() => _loaded = true);
      }
    } catch (e) {
      setState(() => _loaded = true);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ApiService.mutate('users.updateProfile', input: {
        'name': _nameCtrl.text,
        'phone': _phoneCtrl.text,
        'address': _addressCtrl.text,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ البيانات بنجاح'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return Scaffold(
      backgroundColor: AppThemeDecorations.pageBackground(context),
      appBar: AppBar(
        title: const Text('بياناتي'),
        backgroundColor: AppThemeDecorations.cardColor(context),
        automaticallyImplyLeading: false,
      ),
      body: !_loaded
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    // Avatar
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: AppColors.primary.withOpacity(0.2),
                      backgroundImage: user?.avatarUrl != null
                          ? NetworkImage(user!.avatarUrl!)
                          : null,
                      child: user?.avatarUrl == null
                          ? Text(
                              ((user?.name?.isNotEmpty == true) ? user!.name[0] : 'U').toUpperCase(),
                              style: const TextStyle(
                                  color: AppColors.primary,
                                  fontSize: 28,
                                  fontWeight: FontWeight.bold),
                            )
                          : null,
                    ),
                    const SizedBox(height: 12),
                    Text(user?.name ?? '',
                        style: const TextStyle(
                            color: AppColors.text,
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    Text(user?.email ?? '',
                        style: const TextStyle(
                            color: AppColors.muted, fontSize: 13)),
                    const SizedBox(height: 28),

                    // Fields
                    _buildField(
                      controller: _nameCtrl,
                      label: 'الاسم الكامل',
                      icon: Icons.person_outline,
                    ),
                    const SizedBox(height: 14),
                    _buildField(
                      controller: _phoneCtrl,
                      label: 'رقم الهاتف',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                    ),
                    const SizedBox(height: 14),
                    _buildField(
                      controller: _addressCtrl,
                      label: 'العنوان',
                      icon: Icons.location_on_outlined,
                      maxLines: 3,
                    ),
                    const SizedBox(height: 24),

                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.save_outlined, color: Colors.black),
                        label: _saving
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.black))
                            : const Text('حفظ البيانات'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await auth.logout();
                          if (mounted) {
                            Navigator.pushReplacementNamed(context, '/login');
                          }
                        },
                        icon: const Icon(Icons.logout, color: AppColors.error),
                        label: const Text('تسجيل الخروج',
                            style: TextStyle(color: AppColors.error)),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: AppColors.error),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(color: AppColors.text),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: AppColors.muted, size: 20),
      ),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }
}
