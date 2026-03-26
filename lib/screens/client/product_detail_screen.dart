import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';
import '../../utils/curtain_pricing.dart';

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

  int? _dealerId;
  bool _loadingTypePrices = false;
  final Map<String, double> _dealerTypeUnitPrice = {};
  final Map<String, String?> _dealerTypeWaiting = {};

  late final TextEditingController _curtainLengthCmCtrl;
  late final TextEditingController _curtainNotesCtrl;
  String _curtainDirection = 'center'; // left | center | right
  bool _curtainWheelWave = false;
  String _curtainMotorId = 'none';

  @override
  void initState() {
    super.initState();
    _curtainLengthCmCtrl = TextEditingController();
    _curtainNotesCtrl = TextEditingController();
    _curtainLengthCmCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _curtainLengthCmCtrl.dispose();
    _curtainNotesCtrl.dispose();
    super.dispose();
  }

  String _normalizeTypeName(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  Future<void> _refreshDealerTypePrices(int dealerId) async {
    if (_isCurtainTrack) return;
    final types = _types;
    if (types.isEmpty) return;

    final rawPid = widget.product['id'] ?? widget.product['productId'];
    final productId =
        rawPid is int ? rawPid : int.tryParse(rawPid?.toString() ?? '');
    if (productId == null || productId <= 0) return;

    setState(() => _loadingTypePrices = true);
    try {
      final items = <Map<String, dynamic>>[];
      for (final t in types) {
        final name = _normalizeTypeName((t['name']?.toString() ?? '').trim());
        final base = double.tryParse(t['price']?.toString() ?? '0') ?? 0.0;
        if (name.isEmpty || base <= 0) continue;
        items.add({
          'productId': productId,
          'unitPrice': base,
          'variantName': name,
        });
      }

      if (items.isEmpty) {
        setState(() => _loadingTypePrices = false);
        return;
      }

      final res = await ApiService.mutate(
        'discounts.previewQuotationItems',
        input: {
          'dealerUserId': dealerId,
          'items': items,
        },
      );

      final data = res['data'];
      final out = data is Map<String, dynamic> ? data['items'] as List? : null;
      if (out == null || out.isEmpty) {
        if (!mounted) return;
        setState(() => _loadingTypePrices = false);
        return;
      }

      final nextPrices = <String, double>{};
      final nextWaiting = <String, String?>{};
      final limit = items.length < out.length ? items.length : out.length;
      for (var i = 0; i < limit; i++) {
        final sentName = items[i]['variantName']?.toString() ?? '';
        if (sentName.isEmpty) continue;
        final row = out[i];
        if (row is! Map) continue;
        final finalUnit = double.tryParse(row['unitPrice']?.toString() ?? '') ?? (items[i]['unitPrice'] as double);
        nextPrices[sentName] = finalUnit;
        nextWaiting[sentName] = row['dealerDiscountWaiting']?.toString();
      }

      if (!mounted) return;
      setState(() {
        _dealerTypeUnitPrice
          ..clear()
          ..addAll(nextPrices);
        _dealerTypeWaiting
          ..clear()
          ..addAll(nextWaiting);
        _loadingTypePrices = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingTypePrices = false);
    }
  }

  bool get _isCurtainTrack =>
      (widget.product['pricingMode']?.toString() == 'curtain_per_meter');

  double get _curtainMinCm =>
      (widget.product['curtainLengthMinCm'] as num?)?.toDouble() ?? 50;
  double get _curtainMaxCm =>
      (widget.product['curtainLengthMaxCm'] as num?)?.toDouble() ?? 1200;
  double get _curtainWaveFee =>
      (widget.product['curtainWaveSurcharge'] as num?)?.toDouble() ?? 200;

  List<Map<String, dynamic>> _curtainMotorsList() {
    final raw = widget.product['curtainMotors'];
    if (raw is List && raw.isNotEmpty) {
      return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return [
      {'id': 'none', 'labelAr': 'بدون موتور', 'price': 0},
      {'id': 'dt82', 'labelAr': 'Dooya DT82', 'price': 0},
      {'id': 'wistar', 'labelAr': 'Wistar', 'price': 0},
      {'id': 'aqara', 'labelAr': 'Aqara', 'price': 0},
      {'id': 'somfy', 'labelAr': 'Somfy', 'price': 0},
      {'id': 'lm', 'labelAr': 'LM', 'price': 0},
    ];
  }

  double? _parsedCurtainLengthCm() {
    final v = double.tryParse(
        _curtainLengthCmCtrl.text.replaceAll('،', '.').replaceAll(',', '.'));
    if (v == null || v <= 0) return null;
    return v;
  }

  bool get _curtainLengthOk {
    final cm = _parsedCurtainLengthCm();
    if (cm == null) return false;
    return cm >= _curtainMinCm && cm <= _curtainMaxCm;
  }

  double _curtainMotorExtra() {
    for (final m in _curtainMotorsList()) {
      if (m['id']?.toString() == _curtainMotorId) {
        final p = m['price'];
        if (p is num) return p.toDouble();
        return double.tryParse(p?.toString() ?? '0') ?? 0;
      }
    }
    return 0;
  }

  /// سعر خط واحد (مسار واحد) بعد اختيار الطول والخيارات.
  double _curtainLineUnitTotal() {
    if (!_isCurtainTrack) return _currentPrice;
    final cm = _parsedCurtainLengthCm();
    if (cm == null || !_curtainLengthOk) return 0;
    final commercialM = curtainCommercialMetersFromCm(cm);
    double total = commercialM * _currentPrice;
    if (_curtainWheelWave) total += _curtainWaveFee;
    total += _curtainMotorExtra();
    return total;
  }

  Map<String, dynamic>? _curtainConfiguration() {
    if (!_isCurtainTrack) return null;
    final cm = _parsedCurtainLengthCm();
    if (cm == null || !_curtainLengthOk) return null;
    final commercialM = curtainCommercialMetersFromCm(cm);
    return {
      'pricingMode': 'curtain_per_meter',
      'curtainLengthCm': cm,
      'curtainCommercialM': commercialM,
      'direction': _curtainDirection,
      'wheel': _curtainWheelWave ? 'wave' : 'normal',
      'motorId': _curtainMotorId,
      if (_curtainNotesCtrl.text.trim().isNotEmpty)
        'notes': _curtainNotesCtrl.text.trim(),
    };
  }

  String _curtainVariantSummary() {
    if (!_isCurtainTrack) return '';
    final cm = _parsedCurtainLengthCm();
    final comm = cm != null && _curtainLengthOk
        ? curtainCommercialMetersFromCm(cm)
        : null;
    final dirAr = _curtainDirection == 'left'
        ? 'يسار'
        : (_curtainDirection == 'right' ? 'يمين' : 'منتصف');
    final wheelAr = _curtainWheelWave ? 'Wave' : 'Normal';
    String motorAr = _curtainMotorId;
    for (final m in _curtainMotorsList()) {
      if (m['id']?.toString() == _curtainMotorId) {
        motorAr = m['labelAr']?.toString() ?? _curtainMotorId;
        break;
      }
    }
    if (cm != null && comm != null) {
      return 'طول فعلي ${cm.toStringAsFixed(0)} سم - $comm م تجاري | $dirAr | $wheelAr | $motorAr';
    }
    return 'مسار ستائر (أكمل الطول)';
  }

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

  double get _originalSelectedPrice {
    final base = double.tryParse(widget.product['price']?.toString() ?? '0') ?? 0;
    final original = double.tryParse(widget.product['originalPrice']?.toString() ?? '0') ?? 0;
    final pOriginalFallback = original > 0 ? original : base;

    if (_selectedVariantIndex != null && _variants.isNotEmpty) {
      final vp = _variants[_selectedVariantIndex!]['price'];
      return double.tryParse(vp?.toString() ?? '') ?? pOriginalFallback;
    }
    if (_selectedTypeIndex != null && _types.isNotEmpty) {
      final tp = _types[_selectedTypeIndex!]['price'];
      return double.tryParse(tp?.toString() ?? '') ?? pOriginalFallback;
    }
    return pOriginalFallback;
  }

  double get _currentPrice {
    if (!_isCurtainTrack &&
        _selectedTypeIndex != null &&
        _selectedVariantIndex == null &&
        _dealerId != null &&
        _dealerTypeUnitPrice.isNotEmpty) {
      final rawTypeName = _types[_selectedTypeIndex!]['name']?.toString() ?? '';
      final typeName = rawTypeName.trim().replaceAll(RegExp(r'\s+'), ' ');
      final dealerPrice = _dealerTypeUnitPrice[typeName];
      if (dealerPrice != null) return dealerPrice;
    }

    final p = widget.product;
    final discountPercent =
        double.tryParse(p['discountPercent']?.toString() ?? '0') ?? 0.0;
    final discountAmount =
        double.tryParse(p['discountAmount']?.toString() ?? '0') ?? 0.0;
    final discountMinStock =
        int.tryParse(p['discountMinStock']?.toString() ?? '0') ?? 0;
    final discountWaitingMessage =
        p['discountWaitingMessage']?.toString().trim();

    final rawPrice = _originalSelectedPrice;
    if (rawPrice <= 0) return 0.0;

    // If backend says discount is waiting (e.g. stock = 0 / minStock not met),
    // do not apply discount in UI.
    if (discountWaitingMessage != null && discountWaitingMessage.isNotEmpty) {
      return rawPrice;
    }

    final stockOk = discountMinStock <= 0 || _availableStock >= discountMinStock;
    if (!stockOk) return rawPrice;
    if (!(discountPercent > 0 || discountAmount > 0)) return rawPrice;

    final discountValue = discountPercent > 0
        ? rawPrice * discountPercent / 100.0
        : discountAmount;
    final discounted = rawPrice - discountValue;
    return discounted < 0 ? 0.0 : discounted;
  }

  int get _availableStock {
    final p = widget.product;
    int baseStock = p['stock'] is int ? p['stock'] as int : int.tryParse(p['stock']?.toString() ?? '0') ?? 0;
    if (_selectedTypeIndex != null && _types.isNotEmpty) {
      final t = _types[_selectedTypeIndex!];
      final ts = t['stock'];
      if (ts != null) {
        final typeStock = ts is int ? ts : int.tryParse(ts.toString()) ?? 0;
        return typeStock;
      }
    }
    return baseStock;
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
    final originalPrice = _originalSelectedPrice;

    final auth = context.watch<AuthProvider>();
    final dealerId = auth.user?.id;
    if (!_loadingTypePrices &&
        dealerId != null &&
        dealerId != _dealerId &&
        types.isNotEmpty) {
      _dealerId = dealerId;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _refreshDealerTypePrices(dealerId);
      });
    }

    if (!_loadingTypePrices &&
        dealerId != null &&
        dealerId == _dealerId &&
        types.isNotEmpty &&
        _dealerTypeUnitPrice.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _refreshDealerTypePrices(dealerId);
      });
    }
    final discountPercent =
        double.tryParse(p['discountPercent']?.toString() ?? '0') ?? 0;
    final discountAmount =
        double.tryParse(p['discountAmount']?.toString() ?? '0') ?? 0;
    final discountMinStock =
        int.tryParse(p['discountMinStock']?.toString() ?? '0') ?? 0;
    final discountWaitingMessage =
        p['discountWaitingMessage']?.toString().trim();
    final bool isWaiting = discountWaitingMessage != null && discountWaitingMessage.isNotEmpty;
    final hasDiscount =
        !isWaiting &&
        originalPrice > 0 &&
        _currentPrice > 0 &&
        _currentPrice < originalPrice;
    final bool isOutOfStock = _availableStock <= 0;

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
              LayoutBuilder(
                builder: (ctx, constraints) {
                  final maxWidth =
                      constraints.maxWidth > 720 ? 600.0 : constraints.maxWidth;
                  return Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: maxWidth),
                      child: AspectRatio(
                        aspectRatio: 4 / 3,
                        child: Stack(
                          children: [
                            GestureDetector(
                              onTap: () {
                                if (images.isEmpty) return;
                                _openImageViewer(
                                    images, _selectedImageIndex);
                              },
                              child: SizedBox(
                                width: double.infinity,
                                child: images.isNotEmpty
                                    ? Image.network(
                                        images[_selectedImageIndex],
                                        fit: BoxFit.contain,
                                        errorBuilder: (_, __, ___) =>
                                            _placeholder(),
                                      )
                                    : _placeholder(),
                              ),
                            ),
                            if (hasDiscount)
                              Positioned(
                                top: 12,
                                right: 12,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    'خصم ${originalPrice > 0 ? (((originalPrice - _currentPrice) / originalPrice) * 100).toStringAsFixed(0) : '0'}%',
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
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
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isCurtainTrack
                                    ? '${_currentPrice.toStringAsFixed(2)} ج.م / متر تجاري'
                                    : '${_currentPrice.toStringAsFixed(2)} ج.م',
                                style: const TextStyle(
                                    color: AppColors.primary, fontSize: 26, fontWeight: FontWeight.w900),
                              ),
                              if (_isCurtainTrack) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'السعر النهائي = (أمتار تجارية × السعر أعلاه) + إضافات',
                                  style: TextStyle(color: AppColors.muted.withOpacity(0.9), fontSize: 12),
                                ),
                              ],
                            ],
                          ),
                        ),
                        if (hasDiscount && !_isCurtainTrack) ...[
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
                    if (_isCurtainTrack && _curtainLengthOk) ...[
                      const SizedBox(height: 8),
                      Text(
                        'إجمالي المسار الواحد: ${_curtainLineUnitTotal().toStringAsFixed(2)} ج.م (بعد الطول والخيارات)',
                        style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ],
                    const SizedBox(height: 16),

                    // ─── مسار ستائر — تخصيص (نفس فكرة المسح) ───
                    if (_isCurtainTrack) ...[
                      const Text('طول المسار (سم) *',
                          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _curtainLengthCmCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          hintText: 'مثال: 260',
                          helperText:
                              'حد أدنى ${_curtainMinCm.toStringAsFixed(0)} — حد أقصى ${_curtainMaxCm.toStringAsFixed(0)} سم',
                          filled: true,
                          fillColor: AppThemeDecorations.pageBackground(context),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text('اتجاه الفتح *',
                          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('يسار'),
                            selected: _curtainDirection == 'left',
                            onSelected: (_) => setState(() => _curtainDirection = 'left'),
                          ),
                          ChoiceChip(
                            label: const Text('منتصف'),
                            selected: _curtainDirection == 'center',
                            onSelected: (_) => setState(() => _curtainDirection = 'center'),
                          ),
                          ChoiceChip(
                            label: const Text('يمين'),
                            selected: _curtainDirection == 'right',
                            onSelected: (_) => setState(() => _curtainDirection = 'right'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text('مسار العجلة *',
                          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Normal'),
                            selected: !_curtainWheelWave,
                            onSelected: (_) => setState(() => _curtainWheelWave = false),
                          ),
                          ChoiceChip(
                            label: Text('Wave (+${_curtainWaveFee.toStringAsFixed(0)} ج.م)'),
                            selected: _curtainWheelWave,
                            onSelected: (_) => setState(() => _curtainWheelWave = true),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      const Text('الموتور',
                          style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 15)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _curtainMotorsList().map((m) {
                          final id = m['id']?.toString() ?? '';
                          final label = m['labelAr']?.toString() ?? id;
                          final extra = (m['price'] as num?)?.toDouble() ??
                              double.tryParse(m['price']?.toString() ?? '0') ??
                              0;
                          final sel = _curtainMotorId == id;
                          return ChoiceChip(
                            label: Text(extra > 0 ? '$label (+${extra.toStringAsFixed(0)})' : label),
                            selected: sel,
                            onSelected: (_) => setState(() => _curtainMotorId = id),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _curtainNotesCtrl,
                        maxLines: 3,
                        maxLength: 500,
                        decoration: InputDecoration(
                          labelText: 'ملاحظات خاصة (اختياري)',
                          filled: true,
                          fillColor: AppThemeDecorations.pageBackground(context),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ─── اختيار اللون ───
                    if (!_isCurtainTrack && variants.isNotEmpty) ...[
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
                    if (!_isCurtainTrack && types.isNotEmpty) ...[
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
                                      (() {
                                        final base =
                                            double.tryParse(t['price'].toString()) ?? 0.0;
                                        final rawTypeName =
                                            t['name']?.toString() ?? '';
                                        final typeName =
                                            _normalizeTypeName(rawTypeName);
                                        final dealerPrice =
                                            _dealerTypeUnitPrice[typeName];
                                        final show = dealerPrice != null
                                            ? dealerPrice
                                            : base;
                                        return '${show.toStringAsFixed(0)} ج.م';
                                      })(),
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

                    // ─── زر إضافة للسلة / طلب مسبق ───
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          // تحديد الـ variant أو type المختار
                          String? selectedVariant;
                          if (_selectedVariantIndex != null && variants.isNotEmpty) {
                            selectedVariant = variants[_selectedVariantIndex!]['color'] as String?;
                          } else if (_selectedTypeIndex != null && types.isNotEmpty) {
                            selectedVariant = types[_selectedTypeIndex!]['name'] as String?;
                          }

                          if (_isCurtainTrack) {
                            final cfg = _curtainConfiguration();
                            if (cfg == null) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'أدخل طولاً بين ${_curtainMinCm.toStringAsFixed(0)} و ${_curtainMaxCm.toStringAsFixed(0)} سم',
                                  ),
                                  backgroundColor: AppColors.error,
                                ),
                              );
                              return;
                            }
                            selectedVariant = _curtainVariantSummary();
                          }

                          final unitLinePrice =
                              _isCurtainTrack ? _curtainLineUnitTotal() : _currentPrice;
                          if (_isCurtainTrack && unitLinePrice <= 0) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('تعذر حساب السعر — تحقق من الطول'),
                                backgroundColor: AppColors.error,
                              ),
                            );
                            return;
                          }

                          if (isOutOfStock) {
                            try {
                              await ApiService.mutate('orders.create', input: {
                                'items': [
                                  {
                                    'productId': p['id'],
                                    'quantity': _qty,
                                    'unitPrice': unitLinePrice.toString(),
                                    'name': (p['nameAr'] ?? p['name'] ?? '').toString(),
                                    if (selectedVariant != null) 'variant': selectedVariant,
                                    if (_isCurtainTrack) 'configuration': _curtainConfiguration(),
                                    'isPreorder': true,
                                  }
                                ],
                                'totalAmount': (unitLinePrice * _qty).toString(),
                                'status': 'preorder',
                                'notes': 'Pre-order from mobile app',
                              });
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('تم تسجيل طلب الحجز (طلب مسبق) وسيتم التواصل معك من الإدارة'),
                                  backgroundColor: AppColors.success,
                                  duration: Duration(seconds: 3),
                                ),
                              );
                              Navigator.pop(context);
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('تعذر إنشاء طلب مسبق: $e'),
                                  backgroundColor: AppColors.error,
                                ),
                              );
                            }
                          } else {
                            context.read<CartProvider>().addItem(CartItem(
                                  productId: p['id'],
                                  name: p['name'] ?? '',
                                  price: unitLinePrice,
                                  originalPrice: (!_isCurtainTrack && originalPrice > 0)
                                      ? originalPrice
                                      : null,
                                  image: images.isNotEmpty ? images[0] : null,
                                  quantity: _qty,
                                  variant: selectedVariant,
                                  configuration: _curtainConfiguration(),
                                ));
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('تمت الإضافة للسلة ✓'),
                                backgroundColor: AppColors.success,
                                duration: Duration(seconds: 2),
                              ),
                            );
                            Navigator.pop(context);
                          }
                        },
                        icon: Icon(
                          isOutOfStock ? Icons.schedule_send_outlined : Icons.shopping_cart_outlined,
                          color: Colors.black,
                        ),
                        label: Text(
                          isOutOfStock
                              ? 'طلب مسبق - ${(_isCurtainTrack ? _curtainLineUnitTotal() * _qty : _currentPrice * _qty).toStringAsFixed(2)} ج.م'
                              : 'أضف للسلة - ${(_isCurtainTrack ? _curtainLineUnitTotal() * _qty : _currentPrice * _qty).toStringAsFixed(2)} ج.م',
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
