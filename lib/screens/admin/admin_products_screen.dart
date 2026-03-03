import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../utils/app_theme.dart';

class AdminProductsScreen extends StatefulWidget {
  const AdminProductsScreen({super.key});
  @override
  State<AdminProductsScreen> createState() => _AdminProductsScreenState();
}

class _AdminProductsScreenState extends State<AdminProductsScreen> {
  List<dynamic> _products = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.query('products.listAdmin');
      setState(() {
        _products = res['data'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
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

  void _showProductDialog(Map<String, dynamic>? product) {
    final isEdit = product != null;
    final nameCtrl = TextEditingController(text: product?['name'] ?? '');
    final nameArCtrl = TextEditingController(text: product?['nameAr'] ?? '');
    final priceCtrl = TextEditingController(text: product?['price']?.toString() ?? '');
    final stockCtrl = TextEditingController(text: product?['stock']?.toString() ?? '0');
    final descCtrl = TextEditingController(text: product?['description'] ?? '');
    final imageCtrl = TextEditingController(text: product?['mainImageUrl'] ?? '');
    bool isFeatured = product?['isFeatured'] == true;

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
                  Text(isEdit ? 'تعديل المنتج' : 'إضافة منتج جديد',
                      style: const TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.close, color: AppColors.muted), onPressed: () => Navigator.pop(ctx)),
                ]),
                const SizedBox(height: 16),
                const Text('اسم المنتج (إنجليزي) *', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(controller: nameCtrl, style: const TextStyle(color: AppColors.text), decoration: _inputDecoration(hint: 'Product Name')),
                const SizedBox(height: 12),
                const Text('اسم المنتج (عربي)', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(controller: nameArCtrl, style: const TextStyle(color: AppColors.text), decoration: _inputDecoration(hint: 'اسم المنتج بالعربي')),
                const SizedBox(height: 12),
                const Text('السعر (ج.م) *', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(controller: priceCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: AppColors.text), decoration: _inputDecoration(hint: '0.00')),
                const SizedBox(height: 12),
                const Text('الكمية في المخزن', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(controller: stockCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: AppColors.text), decoration: _inputDecoration(hint: '0')),
                const SizedBox(height: 12),
                const Text('رابط الصورة الرئيسية', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(controller: imageCtrl, style: const TextStyle(color: AppColors.text), decoration: _inputDecoration(hint: 'https://...')),
                const SizedBox(height: 12),
                const Text('الوصف', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(controller: descCtrl, maxLines: 3, style: const TextStyle(color: AppColors.text), decoration: _inputDecoration(hint: 'وصف المنتج...')),
                const SizedBox(height: 12),
                Row(children: [
                  Switch(value: isFeatured, onChanged: (v) => setModalState(() => isFeatured = v), activeColor: AppColors.primary),
                  const SizedBox(width: 8),
                  const Text('منتج مميز', style: TextStyle(color: AppColors.text)),
                ]),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      if (nameCtrl.text.trim().isEmpty || priceCtrl.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('الاسم والسعر مطلوبان')));
                        return;
                      }
                      Navigator.pop(ctx);
                      try {
                        final body = <String, dynamic>{
                          'name': nameCtrl.text.trim(),
                          'price': priceCtrl.text.trim(),
                          if (nameArCtrl.text.isNotEmpty) 'nameAr': nameArCtrl.text.trim(),
                          if (descCtrl.text.isNotEmpty) 'description': descCtrl.text.trim(),
                          if (imageCtrl.text.isNotEmpty) 'mainImageUrl': imageCtrl.text.trim(),
                          'stock': int.tryParse(stockCtrl.text) ?? 0,
                          'isFeatured': isFeatured,
                        };
                        if (isEdit) {
                          body['id'] = product!['id'];
                          await ApiService.mutate('products.update', input: body);
                        } else {
                          await ApiService.mutate('products.create', input: body);
                        }
                        _loadProducts();
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isEdit ? 'تم تحديث المنتج' : 'تمت إضافة المنتج'), backgroundColor: AppColors.success));
                      } catch (e) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error));
                      }
                    },
                    style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                    child: Text(isEdit ? 'حفظ التعديلات' : 'إضافة المنتج'),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  void _deleteProduct(Map<String, dynamic> product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text('حذف المنتج', style: TextStyle(color: AppColors.text)),
          content: Text('هل تريد حذف "${product['name']}"؟', style: const TextStyle(color: AppColors.muted)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف', style: TextStyle(color: AppColors.error))),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      try {
        await ApiService.mutate('products.delete', input: {'id': product['id']});
        _loadProducts();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم حذف المنتج'), backgroundColor: AppColors.success));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('إدارة المنتجات'),
        backgroundColor: AppColors.card,
        automaticallyImplyLeading: false,
        actions: [IconButton(icon: const Icon(Icons.refresh, color: AppColors.muted), onPressed: _loadProducts)],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showProductDialog(null),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.black),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _products.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.inventory_2_outlined, color: AppColors.muted, size: 48),
                  const SizedBox(height: 12),
                  const Text('لا توجد منتجات', style: TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(onPressed: () => _showProductDialog(null), icon: const Icon(Icons.add, color: Colors.black), label: const Text('إضافة منتج')),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                  itemCount: _products.length,
                  itemBuilder: (ctx, i) {
                    final p = _products[i];
                    final price = double.tryParse(p['price']?.toString() ?? '0') ?? 0;
                    final image = p['mainImageUrl'] as String?;
                    final stock = p['stock'] as int? ?? 0;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                      child: Directionality(
                        textDirection: TextDirection.rtl,
                        child: Row(children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: image != null
                                ? Image.network(image, width: 56, height: 56, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder())
                                : _placeholder(),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(p['nameAr'] ?? p['name'] ?? '', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 14)),
                            const SizedBox(height: 4),
                            Text('${price.toStringAsFixed(2)} ج.م', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                          ])),
                          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: stock > 0 ? AppColors.success.withOpacity(0.15) : AppColors.error.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(stock > 0 ? 'متاح ($stock)' : 'نفد',
                                  style: TextStyle(color: stock > 0 ? AppColors.success : AppColors.error, fontSize: 10, fontWeight: FontWeight.w600)),
                            ),
                            const SizedBox(height: 8),
                            Row(children: [
                              GestureDetector(onTap: () => _showProductDialog(p), child: const Icon(Icons.edit_outlined, color: AppColors.muted, size: 20)),
                              const SizedBox(width: 10),
                              GestureDetector(onTap: () => _deleteProduct(p), child: const Icon(Icons.delete_outline, color: AppColors.error, size: 20)),
                            ]),
                          ]),
                        ]),
                      ),
                    );
                  },
                ),
    );
  }

  Widget _placeholder() {
    return Container(width: 56, height: 56, color: AppColors.border, child: const Icon(Icons.image_outlined, color: AppColors.muted, size: 24));
  }
}
