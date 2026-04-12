import 'package:flutter/material.dart';

import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import 'product_detail_screen.dart';

class PublicProductScreen extends StatefulWidget {
  final int productId;

  const PublicProductScreen({super.key, required this.productId});

  @override
  State<PublicProductScreen> createState() => _PublicProductScreenState();
}

class _PublicProductScreenState extends State<PublicProductScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _product;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      setState(() {
        _loading = true;
        _error = null;
      });

      final list = await ApiService.query('products.list');
      final products = (list is List) ? list.cast<dynamic>() : const [];
      Map<String, dynamic>? found;

      for (final raw in products) {
        if (raw is! Map) continue;
        final map = Map<String, dynamic>.from(raw);
        final id = int.tryParse(map['id']?.toString() ?? '');
        if (id == widget.productId) {
          found = map;
          break;
        }
      }

      if (!mounted) return;
      setState(() {
        _product = found;
        _error = found == null ? 'المنتج المطلوب غير موجود أو لم يعد متاحًا.' : null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'تعذر تحميل بيانات المنتج الآن. حاول مرة أخرى بعد قليل.';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (_product == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('تفاصيل المنتج'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error ?? 'تعذر فتح المنتج.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: _load,
                  child: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ProductDetailScreen(
      product: _product!,
      isPublicView: true,
    );
  }
}
