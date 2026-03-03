import 'package:flutter/material.dart';
import '../../services/api_service.dart';
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
      fillColor: AppColors.bg,
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
    String selectedRole = user?['role'] ?? 'user';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
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
                const Text('الدور', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String>(
                  value: selectedRole,
                  dropdownColor: AppColors.card,
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

  void _deleteUser(Map<String, dynamic> user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppColors.card,
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
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('إدارة المستخدمين'),
        backgroundColor: AppColors.card,
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
                fillColor: AppColors.card,
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
                        final roleLabel = {'user': 'عميل', 'technician': 'فني', 'admin': 'مسؤول', 'supervisor': 'مشرف'}[role] ?? role;
                        final roleColor = {'user': const Color(0xFFD4920A), 'technician': const Color(0xFF2E7D32), 'admin': const Color(0xFF7B4F1A), 'supervisor': const Color(0xFF1565C0)}[role] ?? AppColors.muted;
                        final name = u['name'] ?? '';
                        final initial = name.isNotEmpty ? name[0] : '?';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                          child: Directionality(
                            textDirection: TextDirection.rtl,
                            child: Row(children: [
                              CircleAvatar(
                                backgroundColor: AppColors.primary.withOpacity(0.15),
                                child: Text(initial, style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Text(name, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 14)),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(color: roleColor.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                                    child: Text(roleLabel, style: TextStyle(color: roleColor, fontSize: 10, fontWeight: FontWeight.w600)),
                                  ),
                                ]),
                                if (u['phone'] != null && u['phone'] != '') ...[
                                  const SizedBox(height: 3),
                                  Text(u['phone'], style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                                ],
                                if (u['email'] != null && u['email'] != '') ...[
                                  const SizedBox(height: 2),
                                  Text(u['email'], style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                                ],
                              ])),
                              Row(children: [
                                GestureDetector(onTap: () => _showUserDialog(u), child: const Icon(Icons.edit_outlined, color: AppColors.muted, size: 20)),
                                const SizedBox(width: 12),
                                GestureDetector(onTap: () => _deleteUser(u), child: const Icon(Icons.delete_outline, color: AppColors.error, size: 20)),
                              ]),
                            ]),
                          ),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
