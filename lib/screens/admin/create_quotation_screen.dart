import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';

class CreateQuotationScreen extends StatefulWidget {
  const CreateQuotationScreen({super.key});

  @override
  State<CreateQuotationScreen> createState() => _CreateQuotationScreenState();
}

class _CreateQuotationScreenState extends State<CreateQuotationScreen> {
  int _step = 1;
  List<dynamic> _categories = [];
  List<dynamic> _products = [];
  String? _selectedCategoryId;
  String _searchQuery = '';
  bool _loadingProducts = false;

  // Cart items: {productId, productName, productImage, selectedColor, selectedVariant, unitPrice, qty}
  final List<Map<String, dynamic>> _cartItems = [];

  // Client info
  String _clientType = 'external'; // 'registered' | 'external'
  String _clientSearch = '';
  List<dynamic> _clients = [];
  int? _selectedClientId;
  String? _selectedClientName;
  final _clientNameCtrl = TextEditingController();
  final _clientEmailCtrl = TextEditingController();
  final _clientPhoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  bool _addInstallation = false;
  double _installationPercent = 20.0;
  bool _addDiscount = false;
  bool _discountIsPercent = true;
  double _discountPercent = 10.0;
  double _discountFixed = 0;
  final _discountFixedCtrl = TextEditingController();
  bool _submitting = false;

  // Variant selection modal
  Map<String, dynamic>? _variantModalProduct;
  String? _selectedColor;
  String? _selectedVariant;

  @override
  void initState() {
    super.initState();
    _loadCategories();
    _loadClients();
  }

  @override
  void dispose() {
    _clientNameCtrl.dispose();
    _clientEmailCtrl.dispose();
    _clientPhoneCtrl.dispose();
    _notesCtrl.dispose();
    _discountFixedCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    try {
      final res = await ApiService.query('categories.list');
      setState(() => _categories = res['data'] ?? []);
    } catch (_) {}
  }

  Future<void> _loadProducts({String? categoryId, String? search}) async {
    setState(() => _loadingProducts = true);
    try {
      final input = <String, dynamic>{'adminView': true};
      if (categoryId != null) input['categoryId'] = int.tryParse(categoryId) ?? categoryId;
      if (search != null && search.isNotEmpty) input['search'] = search;
      final res = await ApiService.query('products.listAdmin', input: input);
      setState(() {
        _products = res['data'] ?? [];
        _loadingProducts = false;
      });
    } catch (e) {
      setState(() => _loadingProducts = false);
    }
  }

  Future<void> _loadClients() async {
    try {
      final res = await ApiService.query('clients.list');
      setState(() => _clients = res['data'] ?? []);
    } catch (_) {}
  }

  List<dynamic> get _filteredProducts {
    if (_searchQuery.isEmpty) return _products;
    final q = _searchQuery.toLowerCase();
    return _products.where((p) {
      final name = (p['name'] ?? '').toString().toLowerCase();
      final sn = (p['serialNumber'] ?? '').toString().toLowerCase();
      final sku = (p['sku'] ?? '').toString().toLowerCase();
      return name.contains(q) || sn.contains(q) || sku.contains(q);
    }).toList();
  }

  void _onCategoryTap(dynamic cat) {
    final id = cat['id'].toString();
    setState(() {
      _selectedCategoryId = _selectedCategoryId == id ? null : id;
      _searchQuery = '';
    });
    _loadProducts(categoryId: _selectedCategoryId);
  }

  void _onSearchChanged(String val) {
    setState(() => _searchQuery = val);
    if (val.isNotEmpty) {
      _loadProducts(search: val);
    } else if (_selectedCategoryId != null) {
      _loadProducts(categoryId: _selectedCategoryId);
    } else {
      setState(() => _products = []);
    }
  }

  void _addToCart(Map<String, dynamic> product) {
    // variants = ألوان ({color, colorHex, price}), types = أنواع ({name, price})
    final variants = (product['variants'] as List?) ?? [];
    final types = (product['types'] as List?) ?? [];
    if (variants.isNotEmpty || types.isNotEmpty) {
      setState(() {
        _variantModalProduct = product;
        _selectedColor = null;
        _selectedVariant = null;
      });
    } else {
      _addToCartDirect(product, null, null);
    }
  }

  void _addToCartDirect(Map<String, dynamic> product, String? color, String? variant) {
    final basePrice = double.tryParse(product['price']?.toString() ?? '0') ?? 0;
    // Find price from selected color/variant
    double unitPrice = basePrice;
    if (color != null) {
      // variants لها حقل color وليس name
      final variants = (product['variants'] as List?) ?? [];
      final colorData = variants.firstWhere(
        (c) => c['color'] == color,
        orElse: () => null,
      );
      if (colorData != null && colorData['price'] != null) {
        final cp = double.tryParse(colorData['price'].toString()) ?? 0;
        if (cp > 0) unitPrice = cp;
      }
    }
    if (variant != null) {
      // types لها حقل name
      final types = (product['types'] as List?) ?? [];
      final variantData = types.firstWhere(
        (v) => v['name'] == variant,
        orElse: () => null,
      );
      if (variantData != null && variantData['price'] != null) {
        final vp = double.tryParse(variantData['price'].toString()) ?? 0;
        if (vp > 0) unitPrice = vp;
      }
    }

    setState(() {
      // Check if same product+color+variant already in cart
      final existing = _cartItems.indexWhere((item) =>
          item['productId'] == product['id'] &&
          item['selectedColor'] == color &&
          item['selectedVariant'] == variant);
      if (existing >= 0) {
        _cartItems[existing]['qty'] = (_cartItems[existing]['qty'] as int) + 1;
      } else {
        _cartItems.add({
          'productId': product['id'],
          'productName': product['nameAr'] ?? product['name'],
          'productDescription': product['descriptionAr'] ?? product['description'] ?? '',
          'productImage': product['mainImageUrl'] ??
              (product['images'] != null && (product['images'] as List).isNotEmpty
                  ? (product['images'] as List)[0]
                  : null),
          'selectedColor': color,
          'selectedVariant': variant,
          'unitPrice': unitPrice,
          'qty': 1,
        });
      }
      _variantModalProduct = null;
    });
  }

  void _removeFromCart(int index) {
    setState(() => _cartItems.removeAt(index));
  }

  double get _subtotal => _cartItems.fold(0, (sum, item) => sum + (item['unitPrice'] as double) * (item['qty'] as int));
  double get _installationAmount => _addInstallation ? _subtotal * _installationPercent / 100 : 0;
  double get _discountAmount {
    if (!_addDiscount) return 0;
    if (_discountIsPercent) return _subtotal * _discountPercent / 100;
    return _discountFixed;
  }
  double get _total => _subtotal + _installationAmount - _discountAmount;

  Future<void> _submit() async {
    if (_cartItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أضف منتجاً واحداً على الأقل'), backgroundColor: AppColors.error),
      );
      return;
    }
    if (_clientType == 'external' && _clientEmailCtrl.text.trim().isEmpty && _clientNameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('أدخل اسم العميل أو بريده الإلكتروني'), backgroundColor: AppColors.error),
      );
      return;
    }
    if (_clientType == 'registered' && _selectedClientId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر العميل من القائمة'), backgroundColor: AppColors.error),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final input = <String, dynamic>{
        'items': _cartItems.asMap().entries.map((e) {
          final idx = e.key;
          final item = e.value;
          // Build description with color/variant info
          final descParts = <String>[];
          if (item['productDescription'] != null && item['productDescription'].toString().isNotEmpty) {
            descParts.add(item['productDescription'].toString());
          }
          if (item['selectedColor'] != null && item['selectedColor'].toString().isNotEmpty) {
            descParts.add('اللون: ${item['selectedColor']}');
          }
          if (item['selectedVariant'] != null && item['selectedVariant'].toString().isNotEmpty) {
            descParts.add('النوع: ${item['selectedVariant']}');
          }
          return {
            'productId': item['productId'] is int ? item['productId'] as int : int.tryParse(item['productId'].toString()),
            'productName': item['productName'] as String,
            'productNameAr': item['productName'] as String,
            'description': descParts.isEmpty ? null : descParts.join(' | '),
            'imageUrl': item['productImage'],
            'quantity': item['qty'] as int,
            'unitPrice': (item['unitPrice'] as double),
            'sortOrder': idx,
          };
        }).toList(),
        'installationPercent': _addInstallation ? _installationPercent : 0.0,
        'discountPercent': _addDiscount && _discountIsPercent ? _discountPercent : 0.0,
        'discountAmount': _addDiscount && !_discountIsPercent ? _discountFixed : 0.0,
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      };

      if (_clientType == 'registered' && _selectedClientId != null) {
        input['clientUserId'] = _selectedClientId;
        input['clientName'] = _selectedClientName;
      } else {
        input['clientName'] = _clientNameCtrl.text.trim().isEmpty ? null : _clientNameCtrl.text.trim();
        input['clientEmail'] = _clientEmailCtrl.text.trim().isEmpty ? null : _clientEmailCtrl.text.trim();
        input['clientPhone'] = _clientPhoneCtrl.text.trim().isEmpty ? null : _clientPhoneCtrl.text.trim();
      }

      await ApiService.mutate('quotations.create', input: input);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ تم إنشاء عرض السعر بنجاح'), backgroundColor: AppColors.success),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: AppThemeDecorations.pageBackground(context),
            appBar: AppBar(
              title: Text(_step == 1 ? 'اختيار المنتجات' : 'بيانات العميل'),
              backgroundColor: AppThemeDecorations.cardColor(context),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: AppColors.text),
                onPressed: () {
                  if (_step == 2) {
                    setState(() => _step = 1);
                  } else {
                    Navigator.pop(context);
                  }
                },
              ),
              actions: [
                if (_step == 1 && _cartItems.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => setState(() => _step = 2),
                    icon: const Icon(Icons.arrow_forward_ios, size: 14, color: AppColors.primary),
                    label: Text('التالي (${_cartItems.length})', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            body: _step == 1 ? _buildStep1() : _buildStep2(),
          ),
          // Variant Modal
          if (_variantModalProduct != null)
            Material(color: Colors.transparent, child: _buildVariantModal()),
        ],
      ),
    );
  }

  Widget _buildStep1() {
    return Column(
      children: [
        // Search bar
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'بحث بالاسم أو الرقم المسلسل أو SKU...',
              prefixIcon: const Icon(Icons.search, color: AppColors.muted),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: AppColors.muted),
                      onPressed: () {
                        setState(() => _searchQuery = '');
                        if (_selectedCategoryId != null) {
                          _loadProducts(categoryId: _selectedCategoryId);
                        } else {
                          setState(() => _products = []);
                        }
                      },
                    )
                  : null,
            ),
          ),
        ),
        // Category chips
        if (_searchQuery.isEmpty) ...[
          SizedBox(
            height: 42,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _categories.length,
              itemBuilder: (context, i) {
                final cat = _categories[i];
                final selected = _selectedCategoryId == cat['id'].toString();
                return Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: FilterChip(
                    label: Text(cat['name'] ?? ''),
                    selected: selected,
                    onSelected: (_) => _onCategoryTap(cat),
                    backgroundColor: AppThemeDecorations.cardColor(context),
                    selectedColor: AppColors.primary.withOpacity(0.2),
                    checkmarkColor: AppColors.primary,
                    labelStyle: TextStyle(
                      color: selected ? AppColors.primary : AppColors.muted,
                      fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                      fontSize: 12,
                    ),
                    side: BorderSide(color: selected ? AppColors.primary : AppColors.border),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 8),
        ],
        // Products
        Expanded(
          child: _loadingProducts
              ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
              : _products.isEmpty && _selectedCategoryId == null && _searchQuery.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.category_outlined, size: 56, color: AppColors.muted.withOpacity(0.4)),
                          const SizedBox(height: 12),
                          const Text('اختر فئة أو ابحث عن منتج', style: TextStyle(color: AppColors.muted)),
                        ],
                      ),
                    )
                  : _filteredProducts.isEmpty
                      ? const Center(child: Text('لا توجد منتجات', style: TextStyle(color: AppColors.muted)))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          itemCount: _filteredProducts.length,
                          itemBuilder: (context, i) {
                            final p = _filteredProducts[i];
                            final inCart = _cartItems.where((c) => c['productId'] == p['id']).fold(0, (sum, c) => sum + (c['qty'] as int));
                            final price = double.tryParse(p['price']?.toString() ?? '0') ?? 0;
                            // variants = ألوان, types = أنواع
                            final variantsList = (p['variants'] as List?) ?? [];
                            final typesList = (p['types'] as List?) ?? [];
                            final hasVariants = variantsList.isNotEmpty || typesList.isNotEmpty;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: AppThemeDecorations.cardColor(context),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: inCart > 0 ? AppColors.primary.withOpacity(0.5) : AppColors.border,
                                  ),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: () {
                                      final rawImgUrl = p['mainImageUrl'] as String? ??
                                          (p['images'] != null && (p['images'] as List).isNotEmpty
                                              ? (p['images'] as List)[0].toString()
                                              : null);
                                      final imgUrl = rawImgUrl != null ? ApiService.proxyImageUrl(rawImgUrl) : null;
                                      return imgUrl != null
                                          ? Image.network(
                                              imgUrl,
                                              width: 52, height: 52, fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => Container(
                                                width: 52, height: 52,
                                                color: AppColors.border,
                                                child: const Icon(Icons.image_not_supported, color: AppColors.muted, size: 20),
                                              ),
                                            )
                                          : Container(
                                              width: 52, height: 52,
                                              color: AppColors.border,
                                              child: const Icon(Icons.inventory_2_outlined, color: AppColors.muted, size: 20),
                                            );
                                    }(),
                                  ),
                                  title: Text(
                                    p['nameAr'] ?? p['name'] ?? '',
                                    style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            '${price.toStringAsFixed(0)} ج.م',
                                            style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13),
                                          ),
                                          if (variantsList.isNotEmpty) ...[const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(4)), child: Text('${variantsList.length} لون', style: const TextStyle(color: AppColors.primary, fontSize: 10, fontWeight: FontWeight.bold)))],
                                          if (typesList.isNotEmpty) ...[const SizedBox(width: 4), Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(4)), child: Text('${typesList.length} نوع', style: const TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)))],
                                        ],
                                      ),
                                      if (p['serialNumber'] != null && p['serialNumber'].toString().isNotEmpty)
                                        Text('S/N: ${p['serialNumber']}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                                    ],
                                  ),
                                  trailing: inCart > 0
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                                          ),
                                          child: Text('$inCart في السلة', style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold)),
                                        )
                                      : ElevatedButton(
                                          onPressed: () => _addToCart(p),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: AppColors.primary,
                                            foregroundColor: Colors.black,
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            minimumSize: Size.zero,
                                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                          ),
                                          child: Text(hasVariants ? 'اختر المواصفات' : 'إضافة', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                        ),
                                  onTap: () => _addToCart(p),
                                ),
                              ),
                            );
                          },
                        ),
        ),
        // Cart summary bar
        if (_cartItems.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppThemeDecorations.cardColor(context),
              border: Border(top: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${_cartItems.length} منتج | ${_cartItems.fold(0, (s, i) => s + (i['qty'] as int))} قطعة',
                        style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    Text('${_total.toStringAsFixed(0)} ج.م', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: () => setState(() => _step = 2),
                  icon: const Icon(Icons.arrow_forward_ios, size: 14),
                  label: const Text('التالي'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.black),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildStep2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cart review
          const Text('📋 ملخص المنتجات', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: AppThemeDecorations.cardColor(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
            child: Column(
              children: [
                ..._cartItems.asMap().entries.map((entry) {
                  final i = entry.key;
                  final item = entry.value;
                  return Padding(
                    padding: const EdgeInsets.all(10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item['productName'] ?? '', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13)),
                              if (item['selectedColor'] != null)
                                Text('لون: ${item['selectedColor']}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                              if (item['selectedVariant'] != null)
                                Text('نوع: ${item['selectedVariant']}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                              Text('${(item['unitPrice'] as double).toStringAsFixed(0)} × ${item['qty']} = ${((item['unitPrice'] as double) * (item['qty'] as int)).toStringAsFixed(0)} ج.م',
                                  style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline, color: AppColors.error, size: 20),
                              onPressed: () {
                                setState(() {
                                  if (item['qty'] > 1) {
                                    _cartItems[i]['qty'] = item['qty'] - 1;
                                  } else {
                                    _cartItems.removeAt(i);
                                  }
                                });
                              },
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Text('${item['qty']}', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline, color: AppColors.success, size: 20),
                              onPressed: () => setState(() => _cartItems[i]['qty'] = item['qty'] + 1),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
                Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      // Installation toggle
                      Row(
                        children: [
                          Checkbox(
                            value: _addInstallation,
                            onChanged: (v) => setState(() => _addInstallation = v ?? false),
                            activeColor: AppColors.primary,
                          ),
                          const Text('إضافة تركيبات', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      if (_addInstallation) ...[
                        Row(
                          children: [
                            const Text('نسبة التركيبات:', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Slider(
                                value: _installationPercent,
                                min: 0, max: 50,
                                divisions: 50,
                                activeColor: AppColors.primary,
                                onChanged: (v) => setState(() => _installationPercent = v),
                              ),
                            ),
                            Text('${_installationPercent.toStringAsFixed(0)}%', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('قيمة التركيبات:', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                            Text('${_installationAmount.toStringAsFixed(0)} ج.م', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                      const SizedBox(height: 4),
                      // Discount toggle
                      Row(
                        children: [
                          Checkbox(
                            value: _addDiscount,
                            onChanged: (v) => setState(() => _addDiscount = v ?? false),
                            activeColor: AppColors.error,
                          ),
                          const Text('إضافة خصم', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      if (_addDiscount) ...[
                        Row(
                          children: [
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _discountIsPercent = true),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _discountIsPercent ? AppColors.error.withOpacity(0.15) : AppThemeDecorations.pageBackground(context),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: _discountIsPercent ? AppColors.error : AppColors.border),
                                  ),
                                  child: Center(child: Text('نسبة %', style: TextStyle(color: _discountIsPercent ? AppColors.error : AppColors.muted, fontWeight: FontWeight.bold, fontSize: 12))),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _discountIsPercent = false),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: !_discountIsPercent ? AppColors.error.withOpacity(0.15) : AppThemeDecorations.pageBackground(context),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: !_discountIsPercent ? AppColors.error : AppColors.border),
                                  ),
                                  child: Center(child: Text('مبلغ ثابت', style: TextStyle(color: !_discountIsPercent ? AppColors.error : AppColors.muted, fontWeight: FontWeight.bold, fontSize: 12))),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_discountIsPercent) ...[
                          Row(
                            children: [
                              const Text('نسبة الخصم:', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Slider(
                                  value: _discountPercent,
                                  min: 0, max: 50,
                                  divisions: 50,
                                  activeColor: AppColors.error,
                                  onChanged: (v) => setState(() => _discountPercent = v),
                                ),
                              ),
                              Text('${_discountPercent.toStringAsFixed(0)}%', style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ] else ...[
                          TextField(
                            controller: _discountFixedCtrl,
                            decoration: const InputDecoration(
                              labelText: 'مبلغ الخصم (ج.م)',
                              prefixIcon: Icon(Icons.money_off, color: AppColors.error),
                            ),
                            style: const TextStyle(color: AppColors.text),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: (v) => setState(() => _discountFixed = double.tryParse(v) ?? 0),
                          ),
                        ],
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('قيمة الخصم:', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                            Text('- ${_discountAmount.toStringAsFixed(0)} ج.م', style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                      const Divider(color: AppColors.border),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('الإجمالي النهائي:', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 15)),
                          Text('${_total.toStringAsFixed(0)} ج.م', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 18)),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Client type
          const Text('👤 بيانات العميل', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(color: AppThemeDecorations.cardColor(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _TypeBtn(
                        label: 'عميل مسجل',
                        selected: _clientType == 'registered',
                        onTap: () => setState(() => _clientType = 'registered'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _TypeBtn(
                        label: 'عميل خارجي',
                        selected: _clientType == 'external',
                        onTap: () => setState(() => _clientType = 'external'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_clientType == 'registered') ...[
                  if (_clients.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: AppThemeDecorations.pageBackground(context), borderRadius: BorderRadius.circular(8), border: Border.all(color: AppColors.border)),
                      child: const Row(children: [SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)), SizedBox(width: 10), Text('جاري تحميل العملاء...', style: TextStyle(color: AppColors.muted, fontSize: 13))]),
                    )
                  else ...[
                    TextField(
                      decoration: const InputDecoration(labelText: 'ابحث عن عميل', prefixIcon: Icon(Icons.search, color: AppColors.muted)),
                      style: const TextStyle(color: AppColors.text),
                      onChanged: (v) => setState(() => _clientSearch = v),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 220),
                      child: ListView(
                        shrinkWrap: true,
                        children: _clients.where((c) {
                          if (_clientSearch.isEmpty) return true;
                          final name = (c['name'] ?? '').toString().toLowerCase();
                          final phone = (c['phone'] ?? '').toString();
                          final email = (c['email'] ?? '').toString().toLowerCase();
                          return name.contains(_clientSearch.toLowerCase()) || phone.contains(_clientSearch) || email.contains(_clientSearch.toLowerCase());
                        }).map((c) {
                          final id = c['id'] is int ? c['id'] as int : int.tryParse(c['id'].toString());
                          final selected = _selectedClientId == id;
                          return GestureDetector(
                            onTap: () => setState(() {
                              _selectedClientId = id;
                              _selectedClientName = c['name'];
                            }),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: selected ? AppColors.primary.withOpacity(0.15) : AppThemeDecorations.pageBackground(context),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 1.5 : 1),
                              ),
                              child: Row(children: [
                                CircleAvatar(
                                  radius: 16,
                                  backgroundColor: selected ? AppColors.primary : AppColors.border,
                                  child: Text(
                                    (c['name'] ?? '?').toString().isNotEmpty ? (c['name'] ?? '?').toString()[0].toUpperCase() : '?',
                                    style: TextStyle(color: selected ? Colors.black : AppColors.muted, fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(c['name'] ?? c['email'] ?? '', style: TextStyle(color: selected ? AppColors.primary : AppColors.text, fontWeight: FontWeight.w600, fontSize: 14, decoration: TextDecoration.none)),
                                  if (c['phone'] != null && c['phone'].toString().isNotEmpty)
                                    Text(c['phone'], style: const TextStyle(color: AppColors.muted, fontSize: 12, decoration: TextDecoration.none)),
                                ])),
                                if (selected) const Icon(Icons.check_circle, color: AppColors.primary, size: 20),
                              ]),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ],
                if (_clientType == 'external') ...[
                  TextField(
                    controller: _clientNameCtrl,
                    decoration: const InputDecoration(labelText: 'اسم العميل', prefixIcon: Icon(Icons.person_outline, color: AppColors.muted)),
                    style: const TextStyle(color: AppColors.text),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _clientEmailCtrl,
                    decoration: const InputDecoration(labelText: 'البريد الإلكتروني', prefixIcon: Icon(Icons.email_outlined, color: AppColors.muted)),
                    style: const TextStyle(color: AppColors.text),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _clientPhoneCtrl,
                    decoration: const InputDecoration(labelText: 'رقم الهاتف', prefixIcon: Icon(Icons.phone_outlined, color: AppColors.muted)),
                    style: const TextStyle(color: AppColors.text),
                    keyboardType: TextInputType.phone,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          // Notes
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(
              labelText: 'ملاحظات (اختياري)',
              prefixIcon: Icon(Icons.notes, color: AppColors.muted),
            ),
            style: const TextStyle(color: AppColors.text),
            maxLines: 3,
          ),
          const SizedBox(height: 20),
          // Submit button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _submitting ? null : _submit,
              icon: _submitting
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(Icons.check_circle_outline),
              label: Text(_submitting ? 'جاري الحفظ...' : 'حفظ عرض السعر'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildVariantModal() {
    final product = _variantModalProduct!;
    // variants = ألوان ({color, colorHex, price}), types = أنواع ({name, price})
    final variantsList = (product['variants'] as List?) ?? [];
    final typesList = (product['types'] as List?) ?? [];

    return GestureDetector(
      onTap: () => setState(() => _variantModalProduct = null),
      child: Container(
        color: Colors.black.withOpacity(0.7),
        child: Center(
          child: GestureDetector(
            onTap: () {},
            child: Container(
              margin: const EdgeInsets.all(20),
              padding: const EdgeInsets.all(20),
              constraints: const BoxConstraints(maxWidth: 480),
              decoration: BoxDecoration(
                color: AppThemeDecorations.cardColor(context),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(product['nameAr'] ?? product['name'] ?? '', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 16, decoration: TextDecoration.none)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: AppColors.muted),
                          onPressed: () => setState(() => _variantModalProduct = null),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    // الألوان (variants)
                    if (variantsList.isNotEmpty) ...[
                      const Text('اختر اللون:', style: TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w600, decoration: TextDecoration.none)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: variantsList.map((v) {
                          final colorName = v['color'] as String? ?? '';
                          final colorHex = v['colorHex'] as String? ?? '';
                          final selected = _selectedColor == colorName;
                          final price = double.tryParse(v['price']?.toString() ?? '0') ?? 0;
                          Color? swatch;
                          try {
                            if (colorHex.isNotEmpty) {
                              final hex = colorHex.replaceAll('#', '');
                              swatch = Color(int.parse('FF$hex', radix: 16));
                            }
                          } catch (_) {}
                          return GestureDetector(
                            onTap: () => setState(() => _selectedColor = colorName),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: selected ? AppColors.primary.withOpacity(0.2) : AppThemeDecorations.pageBackground(context),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 2 : 1),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (swatch != null) ...[
                                    Container(
                                      width: 16, height: 16,
                                      decoration: BoxDecoration(
                                        color: swatch,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white.withOpacity(0.3)),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(colorName, style: TextStyle(color: selected ? AppColors.primary : AppColors.text, fontWeight: FontWeight.w600, fontSize: 13, decoration: TextDecoration.none)),
                                      if (price > 0)
                                        Text('${price.toStringAsFixed(0)} ج.م', style: const TextStyle(color: AppColors.muted, fontSize: 11, decoration: TextDecoration.none)),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                    ],
                    // الأنواع (types)
                    if (typesList.isNotEmpty) ...[
                      const Text('اختر النوع:', style: TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w600, decoration: TextDecoration.none)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: typesList.map((t) {
                          final name = t['name'] as String? ?? '';
                          final selected = _selectedVariant == name;
                          final price = double.tryParse(t['price']?.toString() ?? '0') ?? 0;
                          return GestureDetector(
                            onTap: () => setState(() => _selectedVariant = name),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: selected ? AppColors.primary.withOpacity(0.2) : AppThemeDecorations.pageBackground(context),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 2 : 1),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(name, style: TextStyle(color: selected ? AppColors.primary : AppColors.text, fontWeight: FontWeight.w600, fontSize: 13, decoration: TextDecoration.none)),
                                  if (price > 0)
                                    Text('${price.toStringAsFixed(0)} ج.م', style: const TextStyle(color: AppColors.muted, fontSize: 11, decoration: TextDecoration.none)),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                    ],
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          if (variantsList.isNotEmpty && _selectedColor == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('اختر لوناً أولاً'), backgroundColor: AppColors.error),
                            );
                            return;
                          }
                          if (typesList.isNotEmpty && _selectedVariant == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('اختر نوعاً أولاً'), backgroundColor: AppColors.error),
                            );
                            return;
                          }
                          _addToCartDirect(product, _selectedColor, _selectedVariant);
                        },
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.black),
                        child: const Text('إضافة للسلة', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
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

class _TypeBtn extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _TypeBtn({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withOpacity(0.15) : AppThemeDecorations.pageBackground(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? AppColors.primary : AppColors.border, width: selected ? 2 : 1),
        ),
        child: Center(
          child: Text(label, style: TextStyle(color: selected ? AppColors.primary : AppColors.muted, fontWeight: selected ? FontWeight.bold : FontWeight.normal, fontSize: 13)),
        ),
      ),
    );
  }
}
