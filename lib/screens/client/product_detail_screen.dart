import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/cart_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';

class ProductDetailScreen extends StatefulWidget {
  final Map<String, dynamic> product;
  const ProductDetailScreen({super.key, required this.product});

  @override
  State<ProductDetailScreen> createState() => _ProductDetailScreenState();
}

class _ProductDetailScreenState extends State<ProductDetailScreen> {
  int _qty = 1;
  int _selectedImageIndex = 0;
  int? _selectedVariantIndex;
  int? _selectedTypeIndex;

  List<Map<String, dynamic>> get _variants {
    final v = widget.product['variants'];
    if (v == null) return [];
    if (v is List) return v.map((e) => Map<String, dynamic>.from(e)).toList();
    return [];
  }

  List<Map<String, dynamic>> get _types {
    final t = widget.product['types'];
    if (t == null) return [];
    if (t is List) return t.map((e) => Map<String, dynamic>.from(e)).toList();
    return [];
  }

  List<String> get _images {
    final imgs = widget.product['images'];
    final main = widget.product['mainImageUrl'] as String?;
    String? override;
    if (_selectedTypeIndex != null && _types.isNotEmpty) {
      override = _types[_selectedTypeIndex!]['imageUrl'] as String?;
    } else if (_selectedVariantIndex != null && _variants.isNotEmpty) {
      override = _variants[_selectedVariantIndex!]['imageUrl'] as String?;
    }
    List<String> result = [];
    if (override != null && override.isNotEmpty) {
      result.add(ApiService.proxyImageUrl(override));
    }
    if (main != null && main.isNotEmpty && main != override) {
      result.add(ApiService.proxyImageUrl(main));
    }
    if (imgs is List) {
      for (var img in imgs) {
        if (img is String && img.isNotEmpty && img != main && img != override) {
          result.add(ApiService.proxyImageUrl(img));
        }
      }
    }
    return result;
  }

  double get _currentPrice {
    double base = double.tryParse(widget.product['price']?.toString() ?? '0') ?? 0;
    if (_selectedVariantIndex != null && _variants.isNotEmpty) {
      final vp = _variants[_selectedVariantIndex!]['price'];
      if (vp != null) return double.tryParse(vp.toString()) ?? base;
    }
    if (_selectedTypeIndex != null && _types.isNotEmpty) {
      final tp = _types[_selectedTypeIndex!]['price'];
      if (tp != null) return double.tryParse(tp.toString()) ?? base;
    }
    return base;
  }

  Color _parseColor(String? hex) {
    if (hex == null || hex.isEmpty) return Colors.grey;
    try {
      String h = hex.replaceAll('#', '');
      if (h.length == 6) h = 'FF$h';
      return Color(int.parse(h, radix: 16));
    } catch (_) {
      return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final images = _images;
    final variants = _variants;
    final types = _types;
    final originalPrice = double.tryParse(p['originalPrice']?.toString() ?? '0') ?? 0;
    final hasDiscount = originalPrice > 0 && originalPrice > _currentPrice;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppThemeDecorations.pageBackground(context),
        appBar: AppBar(
          title: Text(p['name'] ?? '', style: const TextStyle(fontSize: 16)),
          backgroundColor: AppThemeDecorations.cardColor(context),
          elevation: 0,
        ),
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── صور المنتج ───
              Stack(
                children: [
                  GestureDetector(
                    onTap: () {
                      if (images.isEmpty) return;
                      _openImageViewer(images, _selectedImageIndex);
                    },
                    child: SizedBox(
                      height: 300,
                      width: double.infinity,
                      child: images.isNotEmpty
                          ? Image.network(
                              images[_selectedImageIndex],
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => _placeholder(),
                            )
                          : _placeholder(),
                    ),
                  ),
                  if (hasDiscount)
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          'خصم ${(((originalPrice - _currentPrice) / originalPrice) * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),

              // ─── صور مصغرة ───
              if (images.length > 1)
                SizedBox(
                  height: 70,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: images.length,
                    itemBuilder: (ctx, i) => GestureDetector(
                      onTap: () => setState(() => _selectedImageIndex = i),
                      child: Container(
                        width: 56,
                        height: 56,
                        margin: const EdgeInsets.only(left: 8),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: i == _selectedImageIndex ? AppColors.primary : AppColors.border,
                            width: i == _selectedImageIndex ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: Image.network(images[i], fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(Icons.image, color: AppColors.muted)),
                        ),
                      ),
                    ),
                  ),
                ),

              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ─── اسم المنتج ───
                    Text(
                      p['name'] ?? '',
                      style: const TextStyle(color: AppColors.text, fontSize: 20, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 10),

                    // ─── السعر ───
                    Row(
                      children: [
                        Text(
                          '${_currentPrice.toStringAsFixed(2)} ج.م',
                          style: const TextStyle(color: AppColors.primary, fontSize: 26, fontWeight: FontWeight.w900),
                        ),
                        if (hasDiscount) ...[
                          const SizedBox(width: 10),
                          Text(
                            '${originalPrice.toStringAsFixed(2)} ج.م',
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: 16,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ─── اختيار اللون ───
                    if (variants.isNotEmpty) ...[
                      const Text('اختر اللون:',
                          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: List.generate(variants.length, (i) {
                          final v = variants[i];
                          final isSelected = _selectedVariantIndex == i;
                          final color = _parseColor(v['colorHex'] as String?);
                          return GestureDetector(
                            onTap: () => setState(() {
                              _selectedVariantIndex = i;
                              _selectedTypeIndex = null;
                              _selectedImageIndex = 0;
                            }),
                            child: Column(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected ? AppColors.primary : AppColors.border,
                                      width: isSelected ? 3 : 1.5,
                                    ),
                                    boxShadow: isSelected
                                        ? [BoxShadow(color: AppColors.primary.withOpacity(0.4), blurRadius: 8)]
                                        : [],
                                  ),
                                  child: isSelected
                                      ? const Icon(Icons.check, color: Colors.white, size: 20)
                                      : null,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  v['color'] as String? ?? '',
                                  style: TextStyle(
                                    color: isSelected ? AppColors.primary : AppColors.muted,
                                    fontSize: 11,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ─── اختيار النوع ───
                    if (types.isNotEmpty) ...[
                      const Text('اختر النوع:',
                          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: List.generate(types.length, (i) {
                          final t = types[i];
                          final isSelected = _selectedTypeIndex == i;
                          return GestureDetector(
                            onTap: () => setState(() {
                              _selectedTypeIndex = i;
                              _selectedVariantIndex = null;
                              _selectedImageIndex = 0;
                            }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                              decoration: BoxDecoration(
                                color: isSelected ? AppColors.primary : AppThemeDecorations.cardColor(context),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected ? AppColors.primary : AppColors.border,
                                  width: isSelected ? 2 : 1,
                                ),
                                boxShadow: isSelected
                                    ? [BoxShadow(color: AppColors.primary.withOpacity(0.3), blurRadius: 6)]
                                    : [],
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    t['name'] as String? ?? '',
                                    style: TextStyle(
                                      color: isSelected ? Colors.black : AppColors.text,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  if (t['price'] != null) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      '${double.tryParse(t['price'].toString())?.toStringAsFixed(0)} ج.م',
                                      style: TextStyle(
                                        color: isSelected ? Colors.black87 : AppColors.primary,
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ─── الوصف ───
                    if (p['description'] != null && (p['description'] as String).isNotEmpty) ...[
                      const Divider(color: AppColors.border),
                      const SizedBox(height: 8),
                      const Text('وصف المنتج',
                          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 8),
                      Text(
                        p['description'],
                        style: const TextStyle(color: AppColors.muted, fontSize: 14, height: 1.7),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ─── الكمية ───
                    Row(
                      children: [
                        const Text('الكمية:',
                            style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 15)),
                        const SizedBox(width: 12),
                        Container(
                          decoration: BoxDecoration(
                            color: AppThemeDecorations.cardColor(context),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove, color: AppColors.text, size: 18),
                                onPressed: () { if (_qty > 1) setState(() => _qty--); },
                              ),
                              Text('$_qty',
                                  style: const TextStyle(
                                      color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 16)),
                              IconButton(
                                icon: const Icon(Icons.add, color: AppColors.text, size: 18),
                                onPressed: () => setState(() => _qty++),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // ─── زر إضافة للسلة ───
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          // تحديد الـ variant أو type المختار
                          String? selectedVariant;
                          if (_selectedVariantIndex != null && variants.isNotEmpty) {
                            selectedVariant = variants[_selectedVariantIndex!]['color'] as String?;
                          } else if (_selectedTypeIndex != null && types.isNotEmpty) {
                            selectedVariant = types[_selectedTypeIndex!]['name'] as String?;
                          }

                          context.read<CartProvider>().addItem(CartItem(
                                productId: p['id'],
                                name: p['name'] ?? '',
                                price: _currentPrice,
                                image: images.isNotEmpty ? images[0] : null,
                                quantity: _qty,
                                variant: selectedVariant,
                              ));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تمت الإضافة للسلة ✓'),
                              backgroundColor: AppColors.success,
                              duration: Duration(seconds: 2),
                            ),
                          );
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.shopping_cart_outlined, color: Colors.black),
                        label: Text(
                          'أضف للسلة - ${_currentPrice.toStringAsFixed(2)} ج.م',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.border,
      child: const Center(
          child: Icon(Icons.image_outlined, color: AppColors.muted, size: 64)),
    );
  }

  void _openImageViewer(List<String> images, int initialIndex) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) {
        int currentIndex = initialIndex;
        final controller = PageController(initialPage: initialIndex);
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return GestureDetector(
              onTap: () => Navigator.of(ctx).pop(),
              child: Stack(
                children: [
                  Container(
                    color: Colors.black,
                    child: PageView.builder(
                      controller: controller,
                      onPageChanged: (i) => setStateDialog(() => currentIndex = i),
                      itemCount: images.length,
                      itemBuilder: (_, i) => Center(
                        child: InteractiveViewer(
                          child: Image.network(
                            images[i],
                            fit: BoxFit.contain,
                            errorBuilder: (_, __, ___) =>
                                const Icon(Icons.broken_image, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 40,
                    right: 20,
                    child: IconButton(
                      icon: const Icon(Icons.close, color: Colors.white),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ),
                  Positioned(
                    bottom: 30,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Text(
                        '${currentIndex + 1} / ${images.length}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
