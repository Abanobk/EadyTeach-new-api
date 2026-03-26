import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';

class AdminProductsScreen extends StatefulWidget {
  const AdminProductsScreen({super.key});
  @override
  State<AdminProductsScreen> createState() => _AdminProductsScreenState();
}

class _AdminProductsScreenState extends State<AdminProductsScreen> {
  List<dynamic> _products = [];
  List<dynamic> _categories = [];
  bool _loading = true;
  bool _isGridView = true;
  int? _selectedCategoryFilter;
  String _searchQuery = '';
  String _statusFilter = 'all'; // all, active, inactive
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadProducts();
    _loadCategories();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final res = await ApiService.query('products.getCategories');
      setState(() => _categories = res['data'] ?? []);
    } catch (_) {}
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

  List<dynamic> get _filteredProducts {
    return _products.where((p) {
      if (_searchQuery.isNotEmpty) {
        final name = (p['name'] ?? '').toString().toLowerCase();
        final nameAr = (p['nameAr'] ?? '').toString().toLowerCase();
        final part = (p['partNumber'] ?? '').toString().toLowerCase();
        final q = _searchQuery.toLowerCase();
        if (!name.contains(q) && !nameAr.contains(q) && !part.contains(q)) return false;
      }
      if (_selectedCategoryFilter != null) {
        if (p['categoryId'] != _selectedCategoryFilter) return false;
      }
      if (_statusFilter == 'active' && p['isActive'] != true) return false;
      if (_statusFilter == 'inactive' && p['isActive'] != false) return false;
      return true;
    }).toList();
  }

  String _getCategoryName(int? catId) {
    if (catId == null) return '';
    final cat = _categories.firstWhere((c) => c['id'] == catId, orElse: () => null);
    if (cat == null) return '';
    return cat['nameAr'] ?? cat['name'] ?? '';
  }

  String? _getFirstImageUrl(Map<String, dynamic> p) {
    String? url;
    final mainImg = p['mainImageUrl'] as String?;
    if (mainImg != null && mainImg.isNotEmpty) {
      url = mainImg.contains(', http') ? mainImg.split(', ')[0].trim() : mainImg;
    }
    if (url == null || url.isEmpty) {
      final images = p['images'];
      if (images is List && images.isNotEmpty) url = images[0] as String?;
    }
    if (url != null && url.isNotEmpty) return ApiService.proxyImageUrl(url);
    return null;
  }

  bool _isCurtainPerMeter(Map<String, dynamic> p) =>
      p['pricingMode']?.toString() == 'curtain_per_meter';

  /// يظهر في البطاقة عندما يكون المنتج مفعّلًا كـ «مسار بالمتر التجاري» (ليس منتجًا جديدًا في القائمة).
  Widget _curtainTrackModeChip(Map<String, dynamic> p) {
    if (!_isCurtainPerMeter(p)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.12),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Text(
          'مسار: متر تجاري',
          style: TextStyle(color: AppColors.primary, fontSize: 9, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Future<void> _toggleActive(Map<String, dynamic> product) async {
    final newActive = !(product['isActive'] == true);
    try {
      await ApiService.mutate('products.toggleActive', input: {
        'id': product['id'],
        'isActive': newActive,
      });
      _loadProducts();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(newActive ? 'تم نشر المنتج' : 'تم إخفاء المنتج'),
          backgroundColor: AppColors.success,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('خطأ: $e'),
          backgroundColor: AppColors.error,
        ));
      }
    }
  }

  List<String> _allEditImages(String? main, List<String> extra) {
    final list = <String>[];
    if (main != null && main.isNotEmpty) list.add(main);
    list.addAll(extra);
    return list;
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

  void _showProductDialog(Map<String, dynamic>? product) {
    final isEdit = product != null;
    final nameCtrl = TextEditingController(text: product?['name'] ?? '');
    final nameArCtrl = TextEditingController(text: product?['nameAr'] ?? '');
    final priceCtrl = TextEditingController(text: product?['price']?.toString() ?? '');
    final stockCtrl = TextEditingController(text: product?['stock']?.toString() ?? '0');
    final partNumberCtrl = TextEditingController(text: product?['partNumber']?.toString() ?? '');
    final discountPercentCtrl = TextEditingController(
      text: (product?['discountPercent'] ?? '').toString(),
    );
    final discountAmountCtrl = TextEditingController(
      text: (product?['discountAmount'] ?? '').toString(),
    );
    final discountMinStockCtrl = TextEditingController(
      text: (product?['discountMinStock'] ?? '').toString(),
    );
    final descCtrl = TextEditingController(text: product?['description'] ?? '');
    final curtainMinCtrl = TextEditingController(
      text: '${product?['curtainLengthMinCm'] ?? 50}',
    );
    final curtainMaxCtrl = TextEditingController(
      text: '${product?['curtainLengthMaxCm'] ?? 1200}',
    );
    final curtainWaveCtrl = TextEditingController(
      text: '${product?['curtainWaveSurcharge'] ?? 200}',
    );
    bool curtainTrackMode = product?['pricingMode']?.toString() == 'curtain_per_meter';
    String? mainImageUrl = product?['mainImageUrl'] as String?;
    List<String> extraImages = [];
    if (product != null && product['images'] is List) {
      for (var img in product['images']) {
        if (img is String && img.isNotEmpty && img != mainImageUrl) {
          extraImages.add(img);
        }
      }
    }
    bool isFeatured = product?['isFeatured'] == true;
    bool uploadingImage = false;
    bool uploadingTypeImage = false;
    int? selectedCategoryId = product?['categoryId'] as int?;
    List<Map<String, dynamic>> variants = [];
    List<Map<String, dynamic>> types = [];
    final rawVariants = product?['variants'];
    if (rawVariants is List) {
      variants = rawVariants.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    final rawTypes = product?['types'];
    if (rawTypes is List) {
      types = rawTypes.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppThemeDecorations.cardColor(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 40,
          ),
          child: SingleChildScrollView(
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
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
                TextField(
                  controller: priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: AppColors.text),
                  decoration: _inputDecoration(
                    hint: curtainTrackMode ? 'سعر المتر التجاري (ج.م)' : '0.00',
                  ),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'مسار ستائر — تسعير بالمتر التجاري',
                    style: TextStyle(color: AppColors.text, fontSize: 14),
                  ),
                  subtitle: Text(
                    curtainTrackMode
                        ? 'نفس منطق المسح: الطول بالسم → تقريب لأشهر نصف متر للتسعير'
                        : 'منتج عادي بالسعر الثابت',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  value: curtainTrackMode,
                  activeThumbColor: AppColors.primary,
                  onChanged: (v) => setModalState(() => curtainTrackMode = v),
                ),
                if (curtainTrackMode) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: curtainMinCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: AppColors.text),
                          decoration: _inputDecoration(hint: 'حد أدنى سم'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: curtainMaxCtrl,
                          keyboardType: TextInputType.number,
                          style: const TextStyle(color: AppColors.text),
                          decoration: _inputDecoration(hint: 'حد أقصى سم'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: curtainWaveCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: AppColors.text),
                    decoration: _inputDecoration(hint: 'زيادة Wave (ج.م)'),
                  ),
                ],
                const SizedBox(height: 12),
                const Text('المخزون', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: stockCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppColors.text),
                  decoration: _inputDecoration(hint: 'مثال: 10'),
                ),
                const SizedBox(height: 12),
                const Text('رقم البارت (Part Number)', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: partNumberCtrl,
                  style: const TextStyle(color: AppColors.text),
                  decoration: _inputDecoration(hint: 'مثال: PN-8821-A (اختياري)'),
                ),
                const SizedBox(height: 16),
                const Divider(color: AppColors.border),
                const SizedBox(height: 12),
                const Text('إعدادات الخصم للمنتج', style: TextStyle(color: AppColors.text, fontSize: 13)),
                const SizedBox(height: 8),
                const Text('نسبة الخصم (%)', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: discountPercentCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: AppColors.text),
                  decoration: _inputDecoration(hint: 'مثال: 10'),
                ),
                const SizedBox(height: 12),
                const Text('قيمة خصم ثابتة (ج.م) – تُستخدم إذا كانت النسبة فارغة أو 0', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: discountAmountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(color: AppColors.text),
                  decoration: _inputDecoration(hint: 'مثال: 100'),
                ),
                const SizedBox(height: 12),
                const Text('شرط المخزون لتفعيل الخصم (الحد الأدنى للكمية في المخزون)', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: discountMinStockCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: AppColors.text),
                  decoration: _inputDecoration(hint: 'مثال: 1 (اتركها فارغة لإلغاء الشرط)'),
                ),
                const SizedBox(height: 16),
                const Text('الأنواع (مثلاً: متر، قطعة...)', style: TextStyle(color: AppColors.text, fontSize: 13)),
                const SizedBox(height: 6),
                if (types.isNotEmpty)
                  Column(
                    children: types.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final t = entry.value;
                      final String? imageUrl = t['imageUrl'] as String?;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppThemeDecorations.pageBackground(context),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            if (imageUrl != null && imageUrl.isNotEmpty) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.network(
                                  ApiService.proxyImageUrl(imageUrl),
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, size: 22, color: AppColors.muted),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t['name'] ?? '',
                                    style: const TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (t['price'] != null && t['price'].toString().isNotEmpty)
                                    Text(
                                      '${t['price']} ج.م',
                                      style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w500),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  if (t['partNumber'] != null && t['partNumber'].toString().isNotEmpty)
                                    Text(
                                      'Part: ${t['partNumber']}',
                                      style: const TextStyle(color: AppColors.muted, fontSize: 11),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),
                            if (imageUrl != null && imageUrl.isNotEmpty)
                              IconButton(
                                tooltip: 'تغيير صورة النوع',
                                icon: const Icon(Icons.photo_library_outlined, color: AppColors.muted, size: 18),
                                onPressed: () async {
                                  final picker = ImagePicker();
                                  final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
                                  if (picked == null) return;
                                  setModalState(() => uploadingTypeImage = true);
                                  try {
                                    final bytes = await picked.readAsBytes();
                                    final url = await ApiService.uploadFile(
                                      picked.path,
                                      bytes: bytes,
                                      filename: picked.name,
                                    );
                                    setModalState(() {
                                      uploadingTypeImage = false;
                                      types[idx]['imageUrl'] = url;
                                    });
                                  } catch (e) {
                                    setModalState(() => uploadingTypeImage = false);
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text('فشل تغيير صورة النوع: $e'),
                                          backgroundColor: AppColors.error,
                                        ),
                                      );
                                    }
                                  }
                                },
                              ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 18),
                              onPressed: () {
                                setModalState(() {
                                  types.removeAt(idx);
                                });
                              },
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  )
                else
                  const Text('لا توجد أنواع مضافة بعد', style: TextStyle(color: AppColors.text, fontSize: 12)),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () async {
                      final nameController = TextEditingController();
                      final priceController = TextEditingController();
                      final stockController = TextEditingController();
                      final partController = TextEditingController();
                      final imageController = TextEditingController();
                      final added = await showDialog<bool>(
                        context: ctx,
                        builder: (dCtx) => Directionality(
                          textDirection: TextDirection.rtl,
                          child: AlertDialog(
                            backgroundColor: AppThemeDecorations.cardColor(context),
                            title: const Text('إضافة نوع', style: TextStyle(color: AppColors.text)),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('اسم النوع', style: TextStyle(color: AppColors.text, fontSize: 13)),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: nameController,
                                  style: const TextStyle(color: AppColors.text),
                                  decoration: _inputDecoration(hint: 'مثال: متر، قطعة...'),
                                ),
                                const SizedBox(height: 12),
                                const Text('السعر لهذا النوع (اختياري)', style: TextStyle(color: AppColors.text, fontSize: 13)),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: priceController,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(color: AppColors.text),
                                  decoration: _inputDecoration(hint: 'اتركه فارغًا لاستخدام السعر الأساسي'),
                                ),
                                const SizedBox(height: 12),
                                const Text('المخزون لهذا النوع (اختياري)', style: TextStyle(color: AppColors.text, fontSize: 13)),
                                const SizedBox(height: 6),
                                TextField(
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(color: AppColors.text),
                                  decoration: _inputDecoration(hint: 'اتركه فارغًا لاستخدام مخزون المنتج الأساسي'),
                                controller: stockController,
                                ),
                                const SizedBox(height: 12),
                                const Text('رقم البارت (اختياري)', style: TextStyle(color: AppColors.text, fontSize: 13)),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: partController,
                                  style: const TextStyle(color: AppColors.text),
                                  decoration: _inputDecoration(hint: 'Part Number'),
                                ),
                                const SizedBox(height: 12),
                                const Text('صورة للنوع (اختياري)', style: TextStyle(color: AppColors.text, fontSize: 13)),
                                const SizedBox(height: 6),
                                StatefulBuilder(
                                  builder: (ctx2, setLocal) => Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      ElevatedButton.icon(
                                        onPressed: uploadingTypeImage
                                            ? null
                                            : () async {
                                                final picker = ImagePicker();
                                                final picked = await picker.pickImage(
                                                  source: ImageSource.gallery,
                                                  imageQuality: 80,
                                                );
                                                if (picked == null) return;
                                                setModalState(() => uploadingTypeImage = true);
                                                try {
                                                  final bytes = await picked.readAsBytes();
                                                  final url = await ApiService.uploadFile(
                                                    picked.path,
                                                    bytes: bytes,
                                                    filename: picked.name,
                                                  );
                                                  setModalState(() {
                                                    uploadingTypeImage = false;
                                                  });
                                                  setLocal(() {
                                                    imageController.text = url;
                                                  });
                                                } catch (e) {
                                                  setModalState(() => uploadingTypeImage = false);
                                                  if (context.mounted) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      SnackBar(
                                                        content: Text('فشل رفع صورة النوع: $e'),
                                                        backgroundColor: AppColors.error,
                                                      ),
                                                    );
                                                  }
                                                }
                                              },
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: AppColors.primary,
                                          foregroundColor: Colors.black,
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        ),
                                        icon: uploadingTypeImage
                                            ? const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.black,
                                                ),
                                              )
                                            : const Icon(Icons.photo_library_outlined, size: 18),
                                        label: Text(
                                          uploadingTypeImage ? 'جاري الرفع...' : 'اختيار صورة من الجهاز',
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                        ),
                                      ),
                                      if (imageController.text.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Text(
                                          'تم اختيار صورة لهذا النوع',
                                          style: const TextStyle(color: AppColors.text, fontSize: 12),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('إلغاء')),
                              TextButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('حفظ')),
                            ],
                          ),
                        ),
                      );
                      if (added == true && nameController.text.trim().isNotEmpty) {
                        setModalState(() {
                          types.add({
                            'name': nameController.text.trim(),
                            if (priceController.text.trim().isNotEmpty) 'price': priceController.text.trim(),
                            if (stockController.text.trim().isNotEmpty) 'stock': stockController.text.trim(),
                            if (partController.text.trim().isNotEmpty) 'partNumber': partController.text.trim(),
                            if (imageController.text.trim().isNotEmpty) 'imageUrl': imageController.text.trim(),
                          });
                        });
                      }
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('إضافة نوع', style: TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(height: 8),
                const Text('الألوان', style: TextStyle(color: AppColors.text, fontSize: 13)),
                const SizedBox(height: 6),
                if (variants.isNotEmpty)
                  Column(
                    children: variants.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final v = entry.value;
                      final String? colorName = v['color'] as String?;
                      final String? colorHex = v['colorHex'] as String?;
                      Color? parsedColor;
                      if (colorHex != null && colorHex.isNotEmpty) {
                        try {
                          var h = colorHex.replaceAll('#', '');
                          if (h.length == 6) h = 'FF$h';
                          parsedColor = Color(int.parse(h, radix: 16));
                        } catch (_) {}
                      }
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppThemeDecorations.pageBackground(context),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            if (parsedColor != null)
                              Container(
                                width: 18,
                                height: 18,
                                margin: const EdgeInsets.only(left: 8),
                                decoration: BoxDecoration(
                                  color: parsedColor,
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(color: Colors.white, width: 1),
                                ),
                              ),
                            Expanded(
                              child: Text(
                                '${colorName ?? ''}${v['price'] != null ? ' - ${v['price']} ج.م' : ''}',
                                style: const TextStyle(color: AppColors.text, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 18),
                              onPressed: () {
                                setModalState(() {
                                  variants.removeAt(idx);
                                });
                              },
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  )
                else
                  const Text('لا توجد ألوان مضافة بعد', style: TextStyle(color: AppColors.text, fontSize: 12)),
                const SizedBox(height: 6),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () async {
                      final colorNameController = TextEditingController();
                      final colorHexController = TextEditingController();
                      final priceController = TextEditingController();
                      final added = await showDialog<bool>(
                        context: ctx,
                        builder: (dCtx) => Directionality(
                          textDirection: TextDirection.rtl,
                          child: AlertDialog(
                            backgroundColor: AppThemeDecorations.cardColor(context),
                            title: const Text('إضافة لون', style: TextStyle(color: AppColors.text)),
                            content: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('اسم اللون', style: TextStyle(color: AppColors.text, fontSize: 13)),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: colorNameController,
                                  style: const TextStyle(color: AppColors.text),
                                  decoration: _inputDecoration(hint: 'مثال: أبيض، أسود...'),
                                ),
                                const SizedBox(height: 12),
                                const Text('كود اللون (اختياري)', style: TextStyle(color: AppColors.text, fontSize: 13)),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: colorHexController,
                                  style: const TextStyle(color: AppColors.text),
                                  decoration: _inputDecoration(hint: '#FFFFFF'),
                                ),
                                const SizedBox(height: 12),
                                const Text('السعر لهذا اللون (اختياري)', style: TextStyle(color: AppColors.text, fontSize: 13)),
                                const SizedBox(height: 6),
                                TextField(
                                  controller: priceController,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(color: AppColors.text),
                                  decoration: _inputDecoration(hint: 'اتركه فارغًا لاستخدام السعر الأساسي'),
                                ),
                              ],
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(dCtx, false), child: const Text('إلغاء')),
                              TextButton(onPressed: () => Navigator.pop(dCtx, true), child: const Text('حفظ')),
                            ],
                          ),
                        ),
                      );
                      if (added == true && colorNameController.text.trim().isNotEmpty) {
                        setModalState(() {
                          variants.add({
                            'color': colorNameController.text.trim(),
                            if (colorHexController.text.trim().isNotEmpty) 'colorHex': colorHexController.text.trim(),
                            if (priceController.text.trim().isNotEmpty) 'price': priceController.text.trim(),
                          });
                        });
                      }
                    },
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('إضافة لون', style: TextStyle(fontSize: 13)),
                  ),
                ),
                const SizedBox(height: 12),
                const Text('الكمية في المخزن', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(controller: stockCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: AppColors.text), decoration: _inputDecoration(hint: '0')),
                const SizedBox(height: 12),
                Text('صور المنتج (${_allEditImages(mainImageUrl, extraImages).length})', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 90,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      ..._allEditImages(mainImageUrl, extraImages).asMap().entries.map((entry) {
                        final idx = entry.key;
                        final url = entry.value;
                        final isMain = idx == 0;
                        return Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Stack(
                            children: [
                              GestureDetector(
                                onTap: () {
                                  if (!isMain) {
                                    setModalState(() {
                                      extraImages.remove(url);
                                      if (mainImageUrl != null && mainImageUrl!.isNotEmpty) {
                                        extraImages.insert(0, mainImageUrl!);
                                      }
                                      mainImageUrl = url;
                                    });
                                  }
                                },
                                child: Container(
                                  width: 80, height: 80,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: isMain ? AppColors.primary : AppColors.border, width: isMain ? 2.5 : 1),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(9),
                                    child: Image.network(ApiService.proxyImageUrl(url), fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image, color: AppColors.muted, size: 24)),
                                  ),
                                ),
                              ),
                              if (isMain)
                                Positioned(
                                  bottom: 0, left: 0, right: 0,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(9)),
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 2),
                                    child: const Text('رئيسية', textAlign: TextAlign.center,
                                        style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              Positioned(
                                top: -2, left: -2,
                                child: GestureDetector(
                                  onTap: () => setModalState(() {
                                    if (isMain) {
                                      mainImageUrl = extraImages.isNotEmpty ? extraImages.removeAt(0) : null;
                                    } else {
                                      extraImages.remove(url);
                                    }
                                  }),
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(12)),
                                    child: const Icon(Icons.close, color: Colors.white, size: 14),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: GestureDetector(
                          onTap: uploadingImage ? null : () async {
                            final picker = ImagePicker();
                            final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
                            if (picked == null) return;
                            setModalState(() => uploadingImage = true);
                            try {
                              final pickedBytes = await picked.readAsBytes();
                              final url = await ApiService.uploadFile(picked.path, bytes: pickedBytes, filename: picked.name);
                              setModalState(() {
                                if (mainImageUrl == null || mainImageUrl!.isEmpty) {
                                  mainImageUrl = url;
                                } else {
                                  extraImages.add(url);
                                }
                                uploadingImage = false;
                              });
                            } catch (e) {
                              setModalState(() => uploadingImage = false);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('فشل رفع الصورة: $e'), backgroundColor: AppColors.error));
                              }
                            }
                          },
                          child: Container(
                            width: 80, height: 80,
                            decoration: BoxDecoration(
                              color: AppThemeDecorations.pageBackground(context),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.border, style: BorderStyle.solid, width: 1.5),
                            ),
                            child: uploadingImage
                                ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)))
                                : const Icon(Icons.add_photo_alternate_outlined, color: AppColors.primary, size: 28),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Text('الوصف', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(controller: descCtrl, maxLines: 3, style: const TextStyle(color: AppColors.text), decoration: _inputDecoration(hint: 'وصف المنتج...')),
                const SizedBox(height: 12),
                const Text('الفئة', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppThemeDecorations.pageBackground(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: selectedCategoryId,
                      hint: const Text('اختر الفئة (اختياري)', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                      dropdownColor: AppThemeDecorations.cardColor(context),
                      isExpanded: true,
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('بدون فئة', style: TextStyle(color: AppColors.muted))),
                        ..._categories.map((cat) => DropdownMenuItem<int?>(
                          value: cat['id'] as int?,
                          child: Text(cat['nameAr'] ?? cat['name'] ?? '', style: const TextStyle(color: AppColors.text)),
                        )),
                      ],
                      onChanged: (v) => setModalState(() => selectedCategoryId = v),
                    ),
                  ),
                ),
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
                        final allImgs = _allEditImages(mainImageUrl, extraImages);
                        final body = <String, dynamic>{
                          'name': nameCtrl.text.trim(),
                          'price': priceCtrl.text.trim(),
                          if (nameArCtrl.text.isNotEmpty) 'nameAr': nameArCtrl.text.trim(),
                          if (descCtrl.text.isNotEmpty) 'description': descCtrl.text.trim(),
                          if (mainImageUrl != null && mainImageUrl!.isNotEmpty) 'mainImageUrl': mainImageUrl,
                          'images': allImgs,
                          'stock': int.tryParse(stockCtrl.text) ?? 0,
                          'isFeatured': isFeatured,
                          if (selectedCategoryId != null) 'categoryId': selectedCategoryId,
                          if (variants.isNotEmpty) 'variants': variants,
                          if (types.isNotEmpty) 'types': types,
                          'partNumber': partNumberCtrl.text.trim(),
                        };
                        final discountPct = double.tryParse(discountPercentCtrl.text.trim());
                        final discountAmt = double.tryParse(discountAmountCtrl.text.trim());
                        final minStockForDiscount = int.tryParse(discountMinStockCtrl.text.trim());
                        if (discountPct != null && discountPct > 0) {
                          body['discountPercent'] = discountPct;
                        }
                        if ((discountPct == null || discountPct == 0) && discountAmt != null && discountAmt > 0) {
                          body['discountAmount'] = discountAmt;
                        }
                        if (minStockForDiscount != null && minStockForDiscount > 0) {
                          body['discountMinStock'] = minStockForDiscount;
                        }
                        body['curtainLengthMinCm'] =
                            int.tryParse(curtainMinCtrl.text.trim()) ?? 50;
                        body['curtainLengthMaxCm'] =
                            int.tryParse(curtainMaxCtrl.text.trim()) ?? 1200;
                        body['curtainWaveSurcharge'] = double.tryParse(
                                curtainWaveCtrl.text.trim().replaceAll(',', '.')) ??
                            200;
                        body['pricingMode'] =
                            curtainTrackMode ? 'curtain_per_meter' : '';
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
          backgroundColor: AppThemeDecorations.cardColor(context),
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
    final colors = Theme.of(context).colorScheme;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 700;
    final filtered = _filteredProducts;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppThemeDecorations.pageBackground(context),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => _showProductDialog(null),
          backgroundColor: AppColors.primary,
          icon: const Icon(Icons.add, color: Colors.black),
          label: const Text('إضافة منتج', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        ),
        body: Column(
          children: [
            // ─── Header ───
            Container(
              padding: EdgeInsets.fromLTRB(isWide ? 24 : 16, 12, isWide ? 24 : 16, 12),
              decoration: BoxDecoration(
                color: AppThemeDecorations.cardColor(context),
                border: const Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'إدارة المنتجات',
                              style: TextStyle(color: colors.onSurface, fontSize: 20, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_products.length} منتج',
                              style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                      // View toggle
                      Container(
                        decoration: BoxDecoration(
                          color: AppThemeDecorations.pageBackground(context),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _viewToggleBtn(Icons.grid_view_rounded, true),
                            _viewToggleBtn(Icons.view_list_rounded, false),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: AppColors.muted),
                        onPressed: _loadProducts,
                        tooltip: 'تحديث',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // ─── Search + Filters ───
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      SizedBox(
                        width: isWide ? 300 : double.infinity,
                        height: 40,
                        child: TextField(
                          controller: _searchCtrl,
                          style: TextStyle(color: colors.onSurface, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'بحث بالاسم أو الكود...',
                            hintStyle: TextStyle(color: colors.onSurfaceVariant, fontSize: 13),
                            prefixIcon: Icon(Icons.search, color: colors.onSurfaceVariant, size: 20),
                            filled: true,
                            fillColor: AppThemeDecorations.pageBackground(context),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                          ),
                          onChanged: (v) => setState(() => _searchQuery = v),
                        ),
                      ),
                      // Category filter
                      Container(
                        height: 40,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: AppThemeDecorations.pageBackground(context),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int?>(
                            value: _selectedCategoryFilter,
                            hint: Text('كل الفئات', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13)),
                            dropdownColor: AppThemeDecorations.cardColor(context),
                            icon: Icon(Icons.keyboard_arrow_down, color: colors.onSurfaceVariant, size: 20),
                            items: [
                              DropdownMenuItem<int?>(
                                  value: null,
                                  child: Text('كل الفئات', style: TextStyle(color: colors.onSurface, fontSize: 13))),
                              ..._categories.map((cat) => DropdownMenuItem<int?>(
                                value: cat['id'] as int?,
                                child: Text(
                                  cat['nameAr'] ?? cat['name'] ?? '',
                                  style: TextStyle(color: colors.onSurface, fontSize: 13),
                                ),
                              )),
                            ],
                            onChanged: (v) => setState(() => _selectedCategoryFilter = v),
                          ),
                        ),
                      ),
                      // Status filter chips
                      _filterChip('الكل', 'all'),
                      _filterChip('منشور', 'active', color: AppColors.success),
                      _filterChip('مخفي', 'inactive', color: AppColors.error),
                    ],
                  ),
                ],
              ),
            ),

            // ─── Products Grid/List ───
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  : filtered.isEmpty
                      ? Center(
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            const Icon(Icons.inventory_2_outlined, color: AppColors.muted, size: 48),
                            const SizedBox(height: 12),
                            const Text('لا توجد منتجات', style: TextStyle(color: AppColors.muted)),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () => _showProductDialog(null),
                              icon: const Icon(Icons.add, color: Colors.black),
                              label: const Text('إضافة منتج'),
                            ),
                          ]),
                        )
                      : _isGridView
                          ? _buildGridView(filtered, isWide, screenWidth)
                          : _buildListView(filtered, isWide),
            ),
          ],
        ),
      ),
    );
  }

  Widget _viewToggleBtn(IconData icon, bool isGrid) {
    final isActive = _isGridView == isGrid;
    return GestureDetector(
      onTap: () => setState(() => _isGridView = isGrid),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isActive ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon, color: isActive ? Colors.black : AppColors.muted, size: 20),
      ),
    );
  }

  Widget _filterChip(String label, String value, {Color? color}) {
    final isActive = _statusFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _statusFilter = value),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isActive ? (color ?? AppColors.primary).withOpacity(0.15) : AppThemeDecorations.pageBackground(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isActive ? (color ?? AppColors.primary) : AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (color != null) ...[
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
            ],
            Text(label, style: TextStyle(
              color: isActive ? (color ?? AppColors.primary) : AppColors.muted,
              fontSize: 13,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            )),
          ],
        ),
      ),
    );
  }

  // ─── Grid View ───
  Widget _buildGridView(List<dynamic> products, bool isWide, double screenWidth) {
    int crossAxisCount;
    if (screenWidth > 1200) {
      crossAxisCount = 5;
    } else if (screenWidth > 900) {
      crossAxisCount = 4;
    } else if (screenWidth > 600) {
      crossAxisCount = 3;
    } else {
      crossAxisCount = 2;
    }

    return GridView.builder(
      padding: EdgeInsets.all(isWide ? 20 : 12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 0.72,
        crossAxisSpacing: isWide ? 16 : 10,
        mainAxisSpacing: isWide ? 16 : 10,
      ),
      itemCount: products.length,
      itemBuilder: (ctx, i) => _buildGridCard(products[i]),
    );
  }

  Widget _buildGridCard(Map<String, dynamic> p) {
    final price = double.tryParse(p['price']?.toString() ?? '0') ?? 0;
    final displayImage = _getFirstImageUrl(p);
    final isActive = p['isActive'] == true;
    final catName = _getCategoryName(p['categoryId'] as int?);

    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: AppThemeDecorations.cardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Image
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Stack(
              fit: StackFit.expand,
              children: [
                displayImage != null
                    ? Image.network(
                        displayImage,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _gridPlaceholder(),
                      )
                    : _gridPlaceholder(),
                if (!isActive)
                  Container(
                    color: Colors.black.withOpacity(0.5),
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: AppColors.error, borderRadius: BorderRadius.circular(4)),
                      child: const Text('مخفي', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
          ),
          // Info
          Expanded(
            flex: 2,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p['name'] ?? '',
                    style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w600, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (catName.isNotEmpty)
                    Text(catName, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                  _curtainTrackModeChip(p),
                  if (p['partNumber'] != null && p['partNumber'].toString().isNotEmpty)
                    Text(
                      'بارت: ${p['partNumber']}',
                      style: TextStyle(color: colors.onSurfaceVariant, fontSize: 10),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 4),
                  Text(
                    _isCurtainPerMeter(p)
                        ? '${price.toStringAsFixed(0)} ج.م / متر'
                        : '${price.toStringAsFixed(0)} ج.م',
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const Spacer(),
                  // Action buttons
                  Row(
                    children: [
                      _actionBtn(Icons.edit_outlined, AppColors.primary, () => _showProductDialog(p), 'تعديل'),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () => _toggleActive(p),
                        child: _statusBadge(isActive),
                      ),
                      const Spacer(),
                      _actionBtn(Icons.delete_outline, AppColors.error, () => _deleteProduct(p), 'حذف'),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBtn(IconData icon, Color color, VoidCallback onTap, String label) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 4),
            Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  Widget _statusBadge(bool isActive) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (isActive ? AppColors.success : AppColors.error).withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(
            color: isActive ? AppColors.success : AppColors.error,
            shape: BoxShape.circle,
          )),
          const SizedBox(width: 4),
          Text(
            isActive ? 'منشور' : 'مخفي',
            style: TextStyle(color: isActive ? AppColors.success : AppColors.error, fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _gridPlaceholder() {
    return Container(
      color: AppThemeDecorations.pageBackground(context),
      child: const Center(child: Icon(Icons.image_outlined, color: AppColors.muted, size: 40)),
    );
  }

  // ─── List View ───
  Widget _buildListView(List<dynamic> products, bool isWide) {
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(isWide ? 24 : 12, 12, isWide ? 24 : 12, 80),
      itemCount: products.length,
      itemBuilder: (ctx, i) => _buildListRow(products[i], isWide),
    );
  }

  Widget _buildListRow(Map<String, dynamic> p, bool isWide) {
    final price = double.tryParse(p['price']?.toString() ?? '0') ?? 0;
    final displayImage = _getFirstImageUrl(p);
    final stock = p['stock'] as int? ?? 0;
    final isActive = p['isActive'] == true;
    final catName = _getCategoryName(p['categoryId'] as int?);

    final colors = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(isWide ? 14 : 10),
      decoration: BoxDecoration(
        color: AppThemeDecorations.cardColor(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          // Image
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: isWide ? 64 : 52,
              height: isWide ? 64 : 52,
              child: displayImage != null
                  ? Image.network(displayImage, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _listPlaceholder(isWide))
                  : _listPlaceholder(isWide),
            ),
          ),
          SizedBox(width: isWide ? 16 : 10),
          // Product info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p['name'] ?? '',
                  style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w600, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                if (catName.isNotEmpty)
                  Text(catName, style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
                _curtainTrackModeChip(p),
                if (p['partNumber'] != null && p['partNumber'].toString().isNotEmpty)
                  Text(
                    'بارت: ${p['partNumber']}',
                    style: TextStyle(color: colors.onSurfaceVariant, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          if (isWide) ...[
            SizedBox(
              width: 100,
              child: Text(
                _isCurtainPerMeter(p)
                    ? '${price.toStringAsFixed(0)} ج.م / متر'
                    : '${price.toStringAsFixed(0)} ج.م',
                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 14),
                textAlign: TextAlign.center,
              ),
            ),
            SizedBox(
              width: 60,
              child: Text('$stock', style: const TextStyle(color: AppColors.text, fontSize: 13), textAlign: TextAlign.center),
            ),
          ],
          if (!isWide)
            Text(
              _isCurtainPerMeter(p)
                  ? '${price.toStringAsFixed(0)} ج.م / م'
                  : '${price.toStringAsFixed(0)} ج.م',
              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => _toggleActive(p),
            child: _statusBadge(isActive),
          ),
          const SizedBox(width: 8),
          // Actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit_outlined, size: 18),
                color: AppColors.muted,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
                onPressed: () => _showProductDialog(p),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                color: AppColors.error,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                padding: EdgeInsets.zero,
                onPressed: () => _deleteProduct(p),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _listPlaceholder(bool isWide) {
    final size = isWide ? 64.0 : 52.0;
    return Container(
      width: size,
      height: size,
      color: AppThemeDecorations.pageBackground(context),
      child: const Icon(Icons.image_outlined, color: AppColors.muted, size: 24),
    );
  }
}
