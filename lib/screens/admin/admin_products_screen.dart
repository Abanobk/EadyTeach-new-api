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
        final q = _searchQuery.toLowerCase();
        if (!name.contains(q) && !nameAr.contains(q)) return false;
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
    final descCtrl = TextEditingController(text: product?['description'] ?? '');
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
    int? selectedCategoryId = product?['categoryId'] as int?;

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
                            const Text('إدارة المنتجات', style: TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 2),
                            Text('${_products.length} منتج', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
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
                          style: const TextStyle(color: AppColors.text, fontSize: 13),
                          decoration: InputDecoration(
                            hintText: 'بحث بالاسم أو الكود...',
                            hintStyle: const TextStyle(color: AppColors.muted, fontSize: 13),
                            prefixIcon: const Icon(Icons.search, color: AppColors.muted, size: 20),
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
                            hint: const Text('كل الفئات', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                            dropdownColor: AppThemeDecorations.cardColor(context),
                            icon: const Icon(Icons.keyboard_arrow_down, color: AppColors.muted, size: 20),
                            items: [
                              const DropdownMenuItem<int?>(value: null, child: Text('كل الفئات', style: TextStyle(color: AppColors.text, fontSize: 13))),
                              ..._categories.map((cat) => DropdownMenuItem<int?>(
                                value: cat['id'] as int?,
                                child: Text(cat['nameAr'] ?? cat['name'] ?? '', style: const TextStyle(color: AppColors.text, fontSize: 13)),
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
          Expanded(
            flex: 3,
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
                    style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (catName.isNotEmpty)
                    Text(catName, style: const TextStyle(color: AppColors.muted, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(
                    '${price.toStringAsFixed(0)} ج.م',
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
                  style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                if (catName.isNotEmpty)
                  Text(catName, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ),
          if (isWide) ...[
            SizedBox(
              width: 100,
              child: Text(
                '${price.toStringAsFixed(0)} ج.م',
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
              '${price.toStringAsFixed(0)} ج.م',
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
