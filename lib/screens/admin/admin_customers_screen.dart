import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';

class AdminCustomersScreen extends StatefulWidget {
  const AdminCustomersScreen({super.key});
  @override
  State<AdminCustomersScreen> createState() => _AdminCustomersScreenState();
}

class _AdminCustomersScreenState extends State<AdminCustomersScreen> {
  List<dynamic> _users = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.query('clients.allUsers');
      setState(() {
        _users = res['data'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  List<dynamic> get _filtered {
    if (_search.isEmpty) return _users;
    return _users.where((u) {
      final name = (u['name'] ?? '').toLowerCase();
      final phone = (u['phone'] ?? '').toLowerCase();
      final email = (u['email'] ?? '').toLowerCase();
      final q = _search.toLowerCase();
      return name.contains(q) || phone.contains(q) || email.contains(q);
    }).toList();
  }

  InputDecoration _inputDecoration({String hint = ''}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.muted),
      filled: true,
      fillColor: AppThemeDecorations.pageBackground(context),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  void _showUserDialog(Map<String, dynamic>? user) {
    final isEdit = user != null;
    final nameCtrl = TextEditingController(text: user?['name'] ?? '');
    final emailCtrl = TextEditingController(text: user?['email'] ?? '');
    final phoneCtrl = TextEditingController(text: user?['phone'] ?? '');
    final addressCtrl = TextEditingController(text: user?['address'] ?? '');
    final locationCtrl = TextEditingController(text: user?['location'] ?? '');
    String selectedRole = user?['role'] ?? 'user';
    bool loadingLocation = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppThemeDecorations.cardColor(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: SingleChildScrollView(
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(isEdit ? 'تعديل المستخدم' : 'إضافة مستخدم جديد',
                      style: const TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close, color: AppColors.muted), onPressed: () => Navigator.pop(ctx)),
                ]),
                const SizedBox(height: 16),
                const Text('الاسم *', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(controller: nameCtrl, style: const TextStyle(color: AppColors.text), decoration: _inputDecoration(hint: 'الاسم الكامل')),
                const SizedBox(height: 12),
                const Text('رقم الهاتف', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(controller: phoneCtrl, keyboardType: TextInputType.phone, style: const TextStyle(color: AppColors.text), decoration: _inputDecoration(hint: '01xxxxxxxxx')),
                const SizedBox(height: 12),
                const Text('البريد الإلكتروني', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(controller: emailCtrl, keyboardType: TextInputType.emailAddress, style: const TextStyle(color: AppColors.text), decoration: _inputDecoration(hint: 'example@email.com')),
                const SizedBox(height: 12),
                const Text('العنوان', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(controller: addressCtrl, style: const TextStyle(color: AppColors.text), decoration: _inputDecoration(hint: 'العنوان')),
                const SizedBox(height: 12),
                const Text('الموقع الجغرافي', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: locationCtrl,
                  style: const TextStyle(color: AppColors.text),
                  decoration: _inputDecoration(hint: 'الصق رابط Google Maps أو إحداثيات'),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: loadingLocation ? null : () async {
                        setModalState(() => loadingLocation = true);
                        try {
                          bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
                          if (!serviceEnabled) {
                            setModalState(() => loadingLocation = false);
                            return;
                          }
                          LocationPermission perm = await Geolocator.checkPermission();
                          if (perm == LocationPermission.denied) {
                            perm = await Geolocator.requestPermission();
                          }
                          if (perm == LocationPermission.deniedForever || perm == LocationPermission.denied) {
                            setModalState(() => loadingLocation = false);
                            return;
                          }
                          final pos = await Geolocator.getCurrentPosition(
                              desiredAccuracy: LocationAccuracy.high);
                          locationCtrl.text =
                              'https://www.google.com/maps?q=${pos.latitude},${pos.longitude}';
                        } catch (_) {}
                        setModalState(() => loadingLocation = false);
                      },
                      icon: loadingLocation
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                          : const Icon(Icons.my_location, size: 14, color: AppColors.primary),
                      label: const Text('موقعي الحالي',
                          style: TextStyle(color: AppColors.primary, fontSize: 12)),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text('الصق رابط خرائط جوجل أو اضغط "موقعي الحالي"',
                    style: TextStyle(color: AppColors.muted, fontSize: 11)),
                const SizedBox(height: 12),
                // ── الدور ────────────────────────────────────────────────
                const Text('الدور', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  dropdownColor: AppThemeDecorations.cardColor(context),
                  style: const TextStyle(color: AppColors.text),
                  decoration: _inputDecoration(),
                  items: const [
                    DropdownMenuItem(value: 'user', child: Text('عميل')),
                    DropdownMenuItem(value: 'technician', child: Text('فني')),
                    DropdownMenuItem(value: 'supervisor', child: Text('مشرف')),
                    DropdownMenuItem(value: 'admin', child: Text('مسؤول')),
                  ],
                  onChanged: (v) => setModalState(() => selectedRole = v!),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (nameCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الاسم مطلوب')));
                        return;
                      }
                      Navigator.pop(ctx);
                      try {
                        if (isEdit) {
                          await ApiService.mutate('clients.updateUserById', input: {
                            'userId': user!['id'],
                            'name': nameCtrl.text.trim(),
                            if (phoneCtrl.text.isNotEmpty) 'phone': phoneCtrl.text.trim(),
                            if (emailCtrl.text.isNotEmpty) 'email': emailCtrl.text.trim(),
                            if (addressCtrl.text.isNotEmpty) 'address': addressCtrl.text.trim(),
                            if (locationCtrl.text.isNotEmpty) 'location': locationCtrl.text.trim(),
                          });
                          if (selectedRole != user['role']) {
                            await ApiService.mutate('clients.updateRole', input: {'userId': user['id'], 'role': selectedRole});
                          }
                        } else {
                          await ApiService.mutate('clients.create', input: {
                            'name': nameCtrl.text.trim(),
                            if (phoneCtrl.text.isNotEmpty) 'phone': phoneCtrl.text.trim(),
                            if (emailCtrl.text.isNotEmpty) 'email': emailCtrl.text.trim(),
                            if (addressCtrl.text.isNotEmpty) 'address': addressCtrl.text.trim(),
                            if (locationCtrl.text.isNotEmpty) 'location': locationCtrl.text.trim(),
                            'role': selectedRole,
                          });
                        }
                        _loadUsers();
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isEdit ? 'تم تحديث المستخدم' : 'تمت إضافة المستخدم'), backgroundColor: AppColors.success));
                      } catch (e) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error));
                      }
                    },
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: Text(isEdit ? 'حفظ التعديلات' : 'إضافة المستخدم'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  /// حسابات المالك — لا يمكن حذفها، ونعرض "مالك" بدل زر الحذف
  static const _ownerEmails = ['abanob.kamal.pr@gmail.com'];

  bool _isOwner(Map<String, dynamic> u) {
    final email = (u['email'] as String? ?? '').trim().toLowerCase();
    return _ownerEmails.contains(email);
  }

  void _deleteUser(Map<String, dynamic> user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppThemeDecorations.cardColor(context),
          title: const Text('حذف المستخدم', style: TextStyle(color: AppColors.text)),
          content: Text('هل تريد حذف "${user['name']}"؟', style: const TextStyle(color: AppColors.muted)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف', style: TextStyle(color: AppColors.error))),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      try {
        await ApiService.mutate('clients.delete', input: {'userId': user['id']});
        _loadUsers();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف المستخدم'), backgroundColor: AppColors.success));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered;
    return Scaffold(
      backgroundColor: AppThemeDecorations.pageBackground(context),
      appBar: AppBar(
        title: const Text('إدارة المستخدمين'),
        backgroundColor: AppThemeDecorations.cardColor(context),
        automaticallyImplyLeading: false,
        actions: [IconButton(icon: const Icon(Icons.refresh, color: AppColors.muted), onPressed: _loadUsers)],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showUserDialog(null),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.black),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: TextField(
              style: const TextStyle(color: AppColors.text),
              decoration: InputDecoration(
                hintText: 'بحث بالاسم أو الهاتف...',
                hintStyle: const TextStyle(color: AppColors.muted),
                prefixIcon: const Icon(Icons.search, color: AppColors.muted),
                filled: true,
                fillColor: AppThemeDecorations.cardColor(context),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : filtered.isEmpty
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.people_outline, color: AppColors.muted, size: 48),
                      const SizedBox(height: 12),
                      const Text('لا يوجد مستخدمون', style: TextStyle(color: AppColors.muted)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(onPressed: () => _showUserDialog(null), icon: const Icon(Icons.add, color: Colors.black), label: const Text('إضافة مستخدم')),
                    ]))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 80),
                      itemCount: filtered.length,
                      itemBuilder: (ctx, i) {
                        final u = filtered[i];
                        final role = u['role'] as String? ?? 'user';
                        final roleLabel = {'user': 'عميل', 'technician': 'فني', 'supervisor': 'مشرف', 'admin': 'مسؤول'}[role] ?? role;
                        final roleColor = {'user': Colors.blue, 'technician': Colors.green, 'supervisor': Colors.orange, 'admin': AppColors.primary}[role] ?? AppColors.muted;
                        return Directionality(
                          textDirection: TextDirection.rtl,
                          child: Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                              leading: CircleAvatar(
                                backgroundColor: roleColor.withOpacity(0.15),
                                child: Text(
                                  (u['name'] as String? ?? '?').isNotEmpty ? (u['name'] as String)[0].toUpperCase() : '?',
                                  style: TextStyle(color: roleColor, fontWeight: FontWeight.bold),
                                ),
                              ),
                              title: Row(children: [
                                Expanded(child: Text(u['name'] ?? '—', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600))),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: roleColor.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: roleColor.withOpacity(0.3)),
                                  ),
                                  child: Text(roleLabel, style: TextStyle(color: roleColor, fontSize: 11)),
                                ),
                              ]),
                              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                if (u['phone'] != null && u['phone'] != '') ...[
                                  const SizedBox(height: 4),
                                  Text(u['phone'], style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                                ],
                                if (u['location'] != null && u['location'] != '') ...[
                                  const SizedBox(height: 2),
                                  GestureDetector(
                                    onTap: () {
                                      final loc = u['location'] as String;
                                      if (loc.startsWith('http')) {
                                        launchUrl(Uri.parse(loc), mode: LaunchMode.externalApplication);
                                      } else if (loc.contains(',')) {
                                        launchUrl(Uri.parse('https://www.google.com/maps?q=$loc'), mode: LaunchMode.externalApplication);
                                      }
                                    },
                                    child: Row(children: [
                                      const Icon(Icons.location_on, color: AppColors.primary, size: 12),
                                      const SizedBox(width: 4),
                                      Flexible(
                                        child: Text(
                                          u['location'].toString().startsWith('http') ? 'فتح الموقع على الخريطة' : u['location'],
                                          style: const TextStyle(color: AppColors.primary, fontSize: 11, decoration: TextDecoration.underline),
                                        ),
                                      ),
                                    ]),
                                  ),
                                ],
                              ]),
                              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined, color: AppColors.muted, size: 20),
                                  onPressed: () => _showUserDialog(Map<String, dynamic>.from(u)),
                                ),
                                if (_isOwner(u))
                                  Padding(
                                    padding: const EdgeInsets.only(left: 8),
                                    child: Text('مالك', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600)),
                                  )
                                else
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
                                    onPressed: () => _deleteUser(Map<String, dynamic>.from(u)),
                                  ),
                              ]),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
