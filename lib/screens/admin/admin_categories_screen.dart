import 'package:flutter/material.dart';
import '../../utils/app_theme.dart';
import '../../services/api_service.dart';

class AdminCategoriesScreen extends StatefulWidget {
  const AdminCategoriesScreen({super.key});
  @override
  State<AdminCategoriesScreen> createState() => _AdminCategoriesScreenState();
}

class _AdminCategoriesScreenState extends State<AdminCategoriesScreen> {
  List<dynamic> _categories = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.query('products.getCategories');
      setState(() => _categories = res['data'] ?? []);
    } catch (_) {}
    setState(() => _loading = false);
  }

  InputDecoration _inputDec({String hint = ''}) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.muted),
    filled: true,
    fillColor: AppColors.bg,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );

  void _showCategoryDialog({Map<String, dynamic>? category}) {
    final isEdit = category != null;
    final nameCtrl = TextEditingController(text: category?['name'] ?? '');
    final nameArCtrl = TextEditingController(text: category?['nameAr'] ?? '');
    final descCtrl = TextEditingController(text: category?['description'] ?? '');
    final imageCtrl = TextEditingController(text: category?['imageUrl'] ?? '');

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
                  Text(isEdit ? 'تعديل الفئة' : 'إضافة فئة جديدة',
                      style: const TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close, color: AppColors.muted), onPressed: () => Navigator.pop(ctx)),
                ]),
                const SizedBox(height: 16),
                if (imageCtrl.text.isNotEmpty) ...[
                  Center(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(imageCtrl.text, height: 100, width: 100, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(height: 100, width: 100, color: AppColors.border,
                              child: const Icon(Icons.broken_image, color: AppColors.muted))),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                const Text('اسم الفئة (عربي) *', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(controller: nameArCtrl, style: const TextStyle(color: AppColors.text),
                    textDirection: TextDirection.rtl,
                    decoration: _inputDec(hint: 'مثال: سمارت لوك')),
                const SizedBox(height: 12),
                const Text('اسم الفئة (إنجليزي)', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(controller: nameCtrl, style: const TextStyle(color: AppColors.text),
                    decoration: _inputDec(hint: 'Smart Lock')),
                const SizedBox(height: 12),
                const Text('رابط الصورة / الأيقونة', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: imageCtrl,
                  style: const TextStyle(color: AppColors.text),
                  decoration: _inputDec(hint: 'https://...'),
                  onChanged: (v) => setModalState(() {}),
                ),
                const SizedBox(height: 12),
                const Text('الوصف (اختياري)', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(controller: descCtrl, maxLines: 2, style: const TextStyle(color: AppColors.text),
                    decoration: _inputDec(hint: 'وصف الفئة...')),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      final nameAr = nameArCtrl.text.trim();
                      final nameEn = nameCtrl.text.trim();
                      if (nameAr.isEmpty && nameEn.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('اسم الفئة مطلوب')));
                        return;
                      }
                      Navigator.pop(ctx);
                      try {
                        final body = <String, dynamic>{
                          'name': nameEn.isNotEmpty ? nameEn : nameAr,
                          if (nameAr.isNotEmpty) 'nameAr': nameAr,
                          if (descCtrl.text.trim().isNotEmpty) 'description': descCtrl.text.trim(),
                          if (imageCtrl.text.trim().isNotEmpty) 'imageUrl': imageCtrl.text.trim(),
                        };
                        if (isEdit) {
                          body['id'] = category!['id'];
                          await ApiService.mutate('products.updateCategory', input: body);
                        } else {
                          await ApiService.mutate('products.createCategory', input: body);
                        }
                        _load();
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(isEdit ? 'تم تحديث الفئة' : 'تمت إضافة الفئة'),
                                backgroundColor: AppColors.success));
                      } catch (e) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error));
                      }
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: Text(isEdit ? 'حفظ التعديلات' : 'إضافة الفئة',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        title: const Text('الفئات', style: TextStyle(color: AppColors.text)),
        iconTheme: const IconThemeData(color: AppColors.text),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: AppColors.muted), onPressed: _load),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCategoryDialog(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('فئة جديدة', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _categories.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.category_outlined, color: AppColors.muted, size: 64),
                  const SizedBox(height: 16),
                  const Text('لا توجد فئات بعد', style: TextStyle(color: AppColors.muted, fontSize: 16)),
                  const SizedBox(height: 8),
                  ElevatedButton.icon(
                    onPressed: () => _showCategoryDialog(),
                    icon: const Icon(Icons.add, color: Colors.black),
                    label: const Text('إضافة فئة'),
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.black),
                  ),
                ]))
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.85,
                  ),
                  itemCount: _categories.length,
                  itemBuilder: (_, i) {
                    final cat = _categories[i];
                    final imageUrl = cat['imageUrl'] as String?;
                    final name = cat['nameAr'] ?? cat['name'] ?? '';

                    return GestureDetector(
                      onTap: () => _showCategoryDialog(category: cat),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.card,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: imageUrl != null && imageUrl.isNotEmpty
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: Image.network(imageUrl, fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => const Icon(Icons.category, color: AppColors.primary, size: 36)),
                                    )
                                  : const Icon(Icons.category, color: AppColors.primary, size: 36),
                            ),
                            const SizedBox(height: 10),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(name,
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13)),
                            ),
                            const SizedBox(height: 10),
                            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              GestureDetector(
                                onTap: () => _showCategoryDialog(category: cat),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                                  child: const Icon(Icons.edit_outlined, color: AppColors.primary, size: 16),
                                ),
                              ),
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () async {
                                  final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => Directionality(
                                      textDirection: TextDirection.rtl,
                                      child: AlertDialog(
                                        backgroundColor: AppColors.card,
                                        title: const Text('حذف الفئة', style: TextStyle(color: AppColors.text)),
                                        content: Text('هل تريد حذف فئة "$name"؟', style: const TextStyle(color: AppColors.muted)),
                                        actions: [
                                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
                                          TextButton(onPressed: () => Navigator.pop(ctx, true),
                                              child: const Text('حذف', style: TextStyle(color: Colors.red))),
                                        ],
                                      ),
                                    ),
                                  );
                                  if (confirmed == true) {
                                    try {
                                      await ApiService.mutate('products.deleteCategory', input: {'id': cat['id']});
                                      _load();
                                    } catch (e) {
                                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error));
                                    }
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(color: Colors.red.withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                                  child: const Icon(Icons.delete_outline, color: Colors.red, size: 16),
                                ),
                              ),
                            ]),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
