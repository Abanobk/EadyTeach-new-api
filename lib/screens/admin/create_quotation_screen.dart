import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';
import '../../utils/curtain_pricing.dart';

class CreateQuotationScreen extends StatefulWidget {
  final int? preselectedClientUserId;
  final String? preselectedClientName;
  final bool forceExternalClient;
  final int? quotationIdToEdit;

  const CreateQuotationScreen({
    super.key,
    this.preselectedClientUserId,
    this.preselectedClientName,
    this.forceExternalClient = false,
    this.quotationIdToEdit,
  });

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

  List<Map<String, dynamic>> _dealers = [];
  int? _selectedDealerId;
  String? _selectedDealerName;
  bool _previewingDealer = false;

  // Variant selection modal
  Map<String, dynamic>? _variantModalProduct;
  String? _selectedColor;
  String? _selectedVariant;

  @override
  void initState() {
    super.initState();
    if (widget.forceExternalClient) {
      // التاجر لازم يبقى عميل خارجي فقط (بدون اختيار مسجلين).
      _clientType = 'external';
      _selectedClientId = null;
      _selectedClientName = null;
    } else if (widget.preselectedClientUserId != null) {
      // دعم قديم: لو تم فتح الشاشة preselected لعميل مسجل.
      _clientType = 'registered';
      _selectedClientId = widget.preselectedClientUserId;
      _selectedClientName = widget.preselectedClientName;
    }
    _loadCategories();
    if (!widget.forceExternalClient) _loadClients();
    _loadDealers();

    if (widget.quotationIdToEdit != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;
        await _loadQuotationForEdit(widget.quotationIdToEdit!);
      });
    } else {
      // الجلسة قد تكتمل بعد أول إطار — نعيد محاولة ربط التاجر بالحساب الحالي.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _autoSelectDealerForCurrentUser();
        Future<void>.delayed(const Duration(milliseconds: 600), () {
          if (mounted) _autoSelectDealerForCurrentUser();
        });
      });
    }
  }

  bool _loggedInUserIsDealer() {
    final r = context.read<AuthProvider>().user?.role.trim().toLowerCase() ?? '';
    return r == 'dealer' || r == 'reseller';
  }

  Future<void> _loadQuotationForEdit(int id) async {
    setState(() => _submitting = true);
    try {
      final res = await ApiService.query('quotations.getById', input: {'id': id});
      final q = res['data'];
      if (!mounted || q is! Map) return;

      final purchaseStatus = (q['purchaseRequestStatus'] ?? 'none').toString().trim().toLowerCase();
      if (purchaseStatus == 'requested' || purchaseStatus == 'accepted') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('لا يمكن تعديل عرض السعر بعد بدء/اعتماد طلب الشراء'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        return;
      }

      final items = (q['items'] as List? ?? []);
      setState(() {
        _step = 2; // Jump to client info + cart summary

        _selectedDealerId = int.tryParse(q['dealerUserId']?.toString() ?? '');
        _selectedDealerName = q['dealerName']?.toString();

        _clientType = 'external';
        _selectedClientId = null;
        _selectedClientName = null;
        _clientNameCtrl.text = (q['clientName'] ?? '').toString();
        _clientEmailCtrl.text = (q['clientEmail'] ?? '').toString();
        _clientPhoneCtrl.text = (q['clientPhone'] ?? '').toString();
        _notesCtrl.text = (q['notes'] ?? '').toString();

        _addInstallation = (double.tryParse(q['installationPercent']?.toString() ?? '0') ?? 0) > 0;
        _installationPercent = double.tryParse(q['installationPercent']?.toString() ?? '0') ?? 0.0;

        _addDiscount = (double.tryParse(q['discountAmount']?.toString() ?? '0') ?? 0) > 0;
        _discountPercent = double.tryParse(q['discountPercent']?.toString() ?? '0') ?? 0.0;
        _discountFixed = double.tryParse(q['discountAmount']?.toString() ?? '0') ?? 0.0;
        _discountIsPercent = _discountPercent > 0;
        _discountFixedCtrl.text = _discountFixed.toStringAsFixed(0);

        _cartItems.clear();
        for (final raw in items) {
          if (raw is! Map) continue;
          final m = Map<String, dynamic>.from(raw);
          final pid = int.tryParse(m['productId']?.toString() ?? '') ?? 0;
          if (pid <= 0) continue;
          _cartItems.add({
            'productId': pid,
            'productName': m['productName'] ?? '',
            'productDescription': m['description'] ?? '',
            'productImage': m['imageUrl'],
            'selectedColor': m['selectedColor'],
            'selectedVariant': m['selectedVariant'] ?? m['variantName'] ?? m['variant'],
            if (m['configuration'] != null) 'configuration': m['configuration'],
            if (m['configurationSummary'] != null) 'configurationSummary': m['configurationSummary'],
            'unitPrice': (double.tryParse(m['unitPrice']?.toString() ?? '') ?? 0.0),
            if (m['officialUnitPrice'] != null)
              'officialUnitPrice': (double.tryParse(m['officialUnitPrice'].toString()) ?? (double.tryParse(m['unitPrice']?.toString() ?? '') ?? 0.0)),
            if (m['dealerUnitPrice'] != null) 'dealerUnitPrice': double.tryParse(m['dealerUnitPrice'].toString()) ?? 0.0,
            if (m['manualDiscountPercent'] != null) 'manualDiscountPercent': double.tryParse(m['manualDiscountPercent'].toString()) ?? 0.0,
            if (m['manualDiscountAmount'] != null) 'manualDiscountAmount': double.tryParse(m['manualDiscountAmount'].toString()) ?? 0.0,
            'qty': int.tryParse(m['qty']?.toString() ?? m['quantity']?.toString() ?? '1') ?? 1,
          });
        }
      });

      if (_selectedDealerId != null) {
        await _applyDealerPricesToCart();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _loadDealers() async {
    try {
      final res = await ApiService.query('clients.allUsers', input: {});
      final users = (res['data'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (!mounted) return;
      setState(() {
        _dealers = users
            .where((u) => (u['role'] == 'dealer' || u['role'] == 'reseller'))
            .map((u) => u)
            .toList();
      });
      _autoSelectDealerForCurrentUser();
    } catch (_) {}
  }

  /// يُعرَف التاجر من الحساب الحالي (دور dealer/reseller) دون اختيار يدوي.
  /// إن لم يظهر المستخدم في `clients.allUsers` نستخدم `user.id` مباشرة لمعاينة الخصم.
  void _autoSelectDealerForCurrentUser() {
    if (!mounted) return;
    if (widget.quotationIdToEdit != null) return;
    if (_selectedDealerId != null) return;
    final auth = context.read<AuthProvider>();
    final u = auth.user;
    if (u == null) return;
    final r = u.role.trim().toLowerCase();
    if (r != 'dealer' && r != 'reseller') return;

    int? matchId;
    String? matchName;
    for (final d in _dealers) {
      final id = d['id'] is int ? d['id'] as int : int.tryParse(d['id'].toString());
      if (id == u.id) {
        matchId = id;
        matchName = d['name']?.toString();
        break;
      }
    }
    matchId ??= u.id;
    matchName ??= u.name;

    setState(() {
      _selectedDealerId = matchId;
      _selectedDealerName = matchName;
    });
    if (_cartItems.isNotEmpty) {
      _applyDealerPricesToCart();
    }
  }

  bool _sameConfigurationMap(dynamic a, dynamic b) {
    if (a == null && b == null) return true;
    if (a == null || b == null) return false;
    if (a is! Map || b is! Map) return false;
    final ma = Map<String, dynamic>.from(a as Map);
    final mb = Map<String, dynamic>.from(b as Map);
    if (ma.length != mb.length) return false;
    for (final k in ma.keys) {
      if (ma[k]?.toString() != mb[k]?.toString()) return false;
    }
    return true;
  }

  /// Normalize type name for matching price rules (product_type) and discount rules.
  /// Some names may contain invisible chars / extra spaces that look identical in UI.
  String _normalizeTypeNameForMatch(String raw) {
    final s = raw
        .toString()
        // Remove zero-width characters commonly found in copy/pasted text.
        .replaceAll(RegExp(r'[\u200B-\u200D\uFEFF]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    return s.toLowerCase();
  }

  Future<void> _applyDealerPricesToCart() async {
    if (_selectedDealerId == null || _cartItems.isEmpty) return;
    setState(() => _previewingDealer = true);
    try {
      final res = await ApiService.mutate('discounts.previewQuotationItems', input: {
        'dealerUserId': _selectedDealerId,
        'items': _cartItems
            .map((e) => {
                  'productId': e['productId'],
                  'unitPrice': ((e['officialUnitPrice'] ?? e['unitPrice']) as num).toDouble(),
                  if (e['selectedVariant'] != null &&
                      e['selectedVariant'].toString().trim().isNotEmpty)
                    'variantName': _normalizeTypeNameForMatch(e['selectedVariant'].toString()),
                })
            .toList(),
      });
      final data = res['data'];
      final out = data is Map<String, dynamic> ? data['items'] as List? : null;
      if (out == null || out.length != _cartItems.length) return;
      setState(() {
        for (var i = 0; i < _cartItems.length; i++) {
          final m = out[i];
          if (m is! Map) continue;
          final up = double.tryParse(m['unitPrice']?.toString() ?? '') ??
              (( _cartItems[i]['unitPrice'] as num?)?.toDouble() ?? 0);
          final off = double.tryParse(m['officialUnitPrice']?.toString() ?? '') ??
              (( _cartItems[i]['officialUnitPrice'] ?? _cartItems[i]['unitPrice']) as num).toDouble();
          _cartItems[i]['officialUnitPrice'] = off;
          // خصم الموديول خاص بسعر شراء التاجر من الإدارة، وليس سعر بيع العميل.
          _cartItems[i]['dealerUnitPrice'] = up;
          _cartItems[i]['dealerDiscountPercent'] = m['dealerDiscountPercent'];
          _cartItems[i]['dealerDiscountWaiting'] = m['dealerDiscountWaiting'];
        }
      });
    } catch (_) {
      /* ignore */
    } finally {
      if (mounted) setState(() => _previewingDealer = false);
    }
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
    if (product['pricingMode']?.toString() == 'curtain_per_meter') {
      _showCurtainConfigurator(product);
      return;
    }
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

  List<Map<String, dynamic>> _curtainMotorsForProduct(Map<String, dynamic> p) {
    final raw = p['curtainMotors'];
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

  void _showCurtainConfigurator(Map<String, dynamic> product) {
    final lenCtrl = TextEditingController();
    String direction = 'center';
    bool wave = false;
    String motorId = 'none';
    final notesCtrl = TextEditingController();
    final minCm = (product['curtainLengthMinCm'] as num?)?.toDouble() ?? 50;
    final maxCm = (product['curtainLengthMaxCm'] as num?)?.toDouble() ?? 1200;
    final waveFee = (product['curtainWaveSurcharge'] as num?)?.toDouble() ?? 200;
    final motors = _curtainMotorsForProduct(product);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppThemeDecorations.cardColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: StatefulBuilder(
            builder: (ctx, setModal) {
              double? cm() => double.tryParse(lenCtrl.text.replaceAll('،', '.').replaceAll(',', '.'));
              double motorExtra() {
                for (final m in motors) {
                  if (m['id']?.toString() == motorId) {
                    final p = m['price'];
                    if (p is num) return p.toDouble();
                    return double.tryParse(p?.toString() ?? '0') ?? 0;
                  }
                }
                return 0;
              }

              double? lineUnit() {
                final c = cm();
                if (c == null || c < minCm || c > maxCm) return null;
                final rate = double.tryParse((product['originalPrice'] ?? product['price'])?.toString() ?? '0') ?? 0;
                final comm = curtainCommercialMetersFromCm(c);
                var t = comm * rate;
                if (wave) t += waveFee;
                t += motorExtra();
                return t;
              }

              String summary() {
                final c = cm();
                if (c == null) return '';
                final comm = curtainCommercialMetersFromCm(c);
                final dirAr = direction == 'left'
                    ? 'يسار'
                    : (direction == 'right' ? 'يمين' : 'منتصف');
                final wAr = wave ? 'Wave' : 'عادي';
                String mAr = motorId;
                for (final m in motors) {
                  if (m['id']?.toString() == motorId) {
                    mAr = m['labelAr']?.toString() ?? motorId;
                    break;
                  }
                }
                return 'طول فعلي ${c.toStringAsFixed(0)} سم - $comm م تجاري | $dirAr | $wAr | $mAr';
              }

              return SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(product['nameAr'] ?? product['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 8),
                    Text('سعر المتر التجاري: ${(double.tryParse((product['originalPrice'] ?? product['price'])?.toString() ?? '0') ?? 0).toStringAsFixed(0)} ج.م',
                        style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: lenCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setModal(() {}),
                      decoration: InputDecoration(
                        labelText: 'الطول (سم)',
                        hintText: '$minCm – $maxCm',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text('الاتجاه', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    Row(
                      children: [
                        for (final d in ['left', 'center', 'right'])
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: ChoiceChip(
                                label: Text(d == 'left' ? 'يسار' : (d == 'right' ? 'يمين' : 'منتصف')),
                                selected: direction == d,
                                onSelected: (_) => setModal(() => direction = d),
                              ),
                            ),
                          ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: FilterChip(
                            label: const Text('عادي'),
                            selected: !wave,
                            onSelected: (_) => setModal(() => wave = false),
                          ),
                        ),
                        Expanded(
                          child: FilterChip(
                            label: Text('Wave (+${waveFee.toStringAsFixed(0)})'),
                            selected: wave,
                            onSelected: (_) => setModal(() => wave = true),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      children: motors.map((m) {
                        final id = m['id']?.toString() ?? '';
                        return ChoiceChip(
                          label: Text(m['labelAr']?.toString() ?? id, style: const TextStyle(fontSize: 11)),
                          selected: motorId == id,
                          onSelected: (_) => setModal(() => motorId = id),
                        );
                      }).toList(),
                    ),
                    TextField(
                      controller: notesCtrl,
                      maxLines: 2,
                      decoration: const InputDecoration(labelText: 'ملاحظات (اختياري)', border: OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    if (lineUnit() != null)
                      Text('سعر السطر: ${lineUnit()!.toStringAsFixed(2)} ج.م',
                          style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        final c = cm();
                        if (c == null || c < minCm || c > maxCm) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('أدخل طولاً بين $minCm و $maxCm سم'), backgroundColor: AppColors.error),
                          );
                          return;
                        }
                        final u = lineUnit();
                        if (u == null || u <= 0) return;
                        final comm = curtainCommercialMetersFromCm(c);
                        final cfg = <String, dynamic>{
                          'pricingMode': 'curtain_per_meter',
                          'curtainLengthCm': c,
                          'curtainCommercialM': comm,
                          'direction': direction,
                          'wheel': wave ? 'wave' : 'normal',
                          'motorId': motorId,
                          if (notesCtrl.text.trim().isNotEmpty) 'notes': notesCtrl.text.trim(),
                        };
                        _addToCartDirect(product, null, null, configuration: cfg, configurationSummary: summary());
                        Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: const Text('إضافة للسلة'),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    ).then((_) {
      lenCtrl.dispose();
      notesCtrl.dispose();
    });
  }

  void _addToCartDirect(
    Map<String, dynamic> product,
    String? color,
    String? variant, {
    Map<String, dynamic>? configuration,
    String? configurationSummary,
  }) {
    // When the dealer module applies discounts, backend may return:
    // - `price` = discounted price
    // - `originalPrice` = official price
    // For quotation creation we always want to start from the official price.
    final basePrice = double.tryParse((product['originalPrice'] ?? product['price'])?.toString() ?? '0') ?? 0;
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
      final normVariant = _normalizeTypeNameForMatch(variant);
      dynamic variantData;
      for (final v in types) {
        final rawName = v['name'];
        if (rawName == null) continue;
        final normName = _normalizeTypeNameForMatch(rawName.toString());
        // Exact match first; fallback to "contains" to be robust against formatting differences.
        final isMatch =
            normName == normVariant || normName.contains(normVariant) || normVariant.contains(normName);
        if (isMatch) {
          variantData = v;
          break;
        }
      }
      if (variantData != null && variantData['price'] != null) {
        final vp = double.tryParse(variantData['price'].toString()) ?? 0;
        if (vp > 0) unitPrice = vp;
      }
    }

    setState(() {
      final existing = _cartItems.indexWhere((item) =>
          item['productId'] == product['id'] &&
          item['selectedColor'] == color &&
          item['selectedVariant'] == variant &&
          _sameConfigurationMap(item['configuration'], configuration));
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
          if (configuration != null) 'configuration': configuration,
          if (configurationSummary != null && configurationSummary.isNotEmpty) 'configurationSummary': configurationSummary,
          'unitPrice': unitPrice,
          'officialUnitPrice': unitPrice,
          'qty': 1,
        });
      }
      _variantModalProduct = null;
    });
    if (_selectedDealerId != null) {
      _applyDealerPricesToCart();
    }
  }

  void _removeFromCart(int index) {
    setState(() => _cartItems.removeAt(index));
  }

  double _clientUnitPrice(Map<String, dynamic> item) =>
      (item['unitPrice'] as num?)?.toDouble() ?? 0.0;

  double _officialUnitPrice(Map<String, dynamic> item) =>
      (item['officialUnitPrice'] as num?)?.toDouble() ?? _clientUnitPrice(item);

  double _dealerPurchaseUnitPrice(Map<String, dynamic> item) =>
      (item['dealerUnitPrice'] as num?)?.toDouble() ?? _officialUnitPrice(item);

  double _itemManualDiscountPercent(Map<String, dynamic> item) =>
      (item['manualDiscountPercent'] as num?)?.toDouble() ?? 0.0;

  double _itemManualDiscountAmount(Map<String, dynamic> item) =>
      (item['manualDiscountAmount'] as num?)?.toDouble() ?? 0.0;

  bool _hasManualDiscount(Map<String, dynamic> item) =>
      _itemManualDiscountPercent(item) > 0 || _itemManualDiscountAmount(item) > 0;

  double _effectiveUnitPrice(Map<String, dynamic> item) {
    final clientBase = _clientUnitPrice(item);
    if (!_hasManualDiscount(item)) return clientBase;
    final base = clientBase;
    final pct = _itemManualDiscountPercent(item);
    final amt = _itemManualDiscountAmount(item);
    final discountValue = pct > 0 ? (base * pct / 100.0) : amt;
    final out = base - discountValue;
    return out < 0 ? 0 : out;
  }

  /// متر تجاري لمسار واحد × عدد المسارات؛ `null` إن لم يكن بند مسار بالمتر.
  double? _curtainCommercialMetersTotal(Map<String, dynamic> item) {
    final cfg = item['configuration'];
    if (cfg is! Map) return null;
    if (cfg['pricingMode']?.toString() != 'curtain_per_meter') return null;
    final commRaw = cfg['curtainCommercialM'];
    double? comm;
    if (commRaw is num) {
      comm = commRaw.toDouble();
    } else {
      comm = double.tryParse(commRaw?.toString() ?? '');
    }
    if (comm == null || comm <= 0) return null;
    final q = (item['qty'] as int?) ?? 1;
    return comm * q;
  }

  /// إجمالي سطر السلة: للمسار = سعر/م فعّال × إجمالي الأمتار التجارية؛ وإلا سعر × كمية.
  double _lineAmountForCartItem(Map<String, dynamic> item) {
    final up = _effectiveUnitPrice(item);
    final q = (item['qty'] as int?) ?? 1;
    final meters = _curtainCommercialMetersTotal(item);
    if (meters != null) return up * meters;
    return up * q;
  }

  double get _subtotal => _cartItems.fold(0.0, (sum, item) => sum + _lineAmountForCartItem(item));
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
          if (item['configurationSummary'] != null && item['configurationSummary'].toString().isNotEmpty) {
            descParts.add(item['configurationSummary'].toString());
          }
          final cfg = item['configuration'];
          if (cfg is Map) {
            final cm = cfg['curtainLengthCm'];
            if (cm != null) descParts.add('المقاس الفعلي: ${cm is num ? (cm as num).toStringAsFixed(0) : cm} سم');
            final comm = cfg['curtainCommercialM'];
            if (comm != null) {
              descParts.add('المتر التجاري: ${comm is num ? (comm as num).toStringAsFixed(1) : comm} م');
            }
            final dir = cfg['direction']?.toString();
            if (dir != null && dir.isNotEmpty) {
              final dirAr = dir == 'left' ? 'يسار' : (dir == 'right' ? 'يمين' : 'منتصف');
              descParts.add('الاتجاه: $dirAr');
            }
            final wh = cfg['wheel']?.toString();
            if (wh != null && wh.isNotEmpty) {
              descParts.add(wh == 'wave' ? 'ويفي' : 'عادي');
            }
            if (cfg['motorId'] != null && cfg['motorId'].toString().isNotEmpty && cfg['motorId'].toString() != 'none') {
              descParts.add('الموتور: ${cfg['motorId']}');
            }
            if (cfg['notes'] != null && cfg['notes'].toString().trim().isNotEmpty) {
              descParts.add('ملاحظات: ${cfg['notes']}');
            }
          }
          return {
            'productId': item['productId'] is int ? item['productId'] as int : int.tryParse(item['productId'].toString()),
            'productName': item['productName'] as String,
            'productNameAr': item['productName'] as String,
            'description': descParts.isEmpty ? null : descParts.join(' | '),
            'imageUrl': item['productImage'],
            'quantity': item['qty'] as int,
            'unitPrice': _effectiveUnitPrice(item),
            if (item['officialUnitPrice'] != null) 'officialUnitPrice': (item['officialUnitPrice'] as num).toDouble(),
            if (item['dealerUnitPrice'] != null) 'dealerUnitPrice': (item['dealerUnitPrice'] as num).toDouble(),
            if (item['selectedVariant'] != null && item['selectedVariant'].toString().trim().isNotEmpty)
              'variantName': item['selectedVariant'].toString(),
            if (_itemManualDiscountPercent(item) > 0) 'manualDiscountPercent': _itemManualDiscountPercent(item),
            if (_itemManualDiscountAmount(item) > 0) 'manualDiscountAmount': _itemManualDiscountAmount(item),
            if (cfg is Map) 'configuration': Map<String, dynamic>.from(cfg as Map),
            'sortOrder': idx,
          };
        }).toList(),
        'installationPercent': _addInstallation ? _installationPercent : 0.0,
        'discountPercent': _addDiscount && _discountIsPercent ? _discountPercent : 0.0,
        'discountAmount': _addDiscount && !_discountIsPercent ? _discountFixed : 0.0,
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      };

      if (_selectedDealerId != null) {
        input['dealerUserId'] = _selectedDealerId;
      }

      if (_clientType == 'registered' && _selectedClientId != null) {
        input['clientUserId'] = _selectedClientId;
        input['clientName'] = _selectedClientName;
      } else {
        input['clientName'] = _clientNameCtrl.text.trim().isEmpty ? null : _clientNameCtrl.text.trim();
        input['clientEmail'] = _clientEmailCtrl.text.trim().isEmpty ? null : _clientEmailCtrl.text.trim();
        input['clientPhone'] = _clientPhoneCtrl.text.trim().isEmpty ? null : _clientPhoneCtrl.text.trim();
      }

      if (widget.quotationIdToEdit != null) {
        input['id'] = widget.quotationIdToEdit;
        await ApiService.mutate('quotations.update', input: input);
      } else {
        await ApiService.mutate('quotations.create', input: input);
      }
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(widget.quotationIdToEdit != null ? '✅ تم تعديل عرض السعر بنجاح' : '✅ تم إنشاء عرض السعر بنجاح'),
            backgroundColor: AppColors.success,
          ),
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

  Future<void> _showItemDiscountDialog(int index) async {
    final item = _cartItems[index];
    final pctCtrl = TextEditingController(
      text: _itemManualDiscountPercent(item) > 0
          ? _itemManualDiscountPercent(item).toStringAsFixed(2)
          : '',
    );
    final amtCtrl = TextEditingController(
      text: _itemManualDiscountAmount(item) > 0
          ? _itemManualDiscountAmount(item).toStringAsFixed(2)
          : '',
    );

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('خصم يدوي للبند'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item['productName']?.toString() ?? '',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'السعر الرسمي: ${_officialUnitPrice(item).toStringAsFixed(2)} ج.م',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pctCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'خصم نسبة % (اختياري)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: amtCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'خصم مبلغ ثابت ج.م (اختياري)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'لو كتبت النسبة والمبلغ معاً، سيتم تطبيق النسبة فقط.',
              style: TextStyle(color: AppColors.muted, fontSize: 11),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _cartItems[index].remove('manualDiscountPercent');
                _cartItems[index].remove('manualDiscountAmount');
              });
              Navigator.pop(ctx);
            },
            child: const Text('مسح الخصم'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              final pct = double.tryParse(pctCtrl.text.replaceAll(',', '.')) ?? 0;
              final amt = double.tryParse(amtCtrl.text.replaceAll(',', '.')) ?? 0;
              setState(() {
                if (pct > 0) {
                  _cartItems[index]['manualDiscountPercent'] = pct;
                  _cartItems[index]['manualDiscountAmount'] = 0.0;
                } else if (amt > 0) {
                  _cartItems[index]['manualDiscountPercent'] = 0.0;
                  _cartItems[index]['manualDiscountAmount'] = amt;
                } else {
                  _cartItems[index].remove('manualDiscountPercent');
                  _cartItems[index].remove('manualDiscountAmount');
                }
              });
              Navigator.pop(ctx);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
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
              title: Text(widget.quotationIdToEdit != null
                  ? (_step == 1 ? 'تعديل عرض السعر — اختيار المنتجات' : 'تعديل عرض السعر — بيانات العميل')
                  : (_step == 1 ? 'اختيار المنتجات' : 'بيانات العميل')),
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
                            final cartLines = _cartItems.where((c) => c['productId'] == p['id']).length;
                            final cartQty = _cartItems
                                .where((c) => c['productId'] == p['id'])
                                .fold<int>(0, (sum, c) => sum + ((c['qty'] as int?) ?? 1));
                            final price = double.tryParse((p['originalPrice'] ?? p['price'])?.toString() ?? '0') ?? 0;
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
                                    color: cartLines > 0 ? AppColors.primary.withOpacity(0.5) : AppColors.border,
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
                                  trailing: cartLines > 0
                                      ? Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                                          ),
                                          child: Text(
                                            cartQty <= 1
                                                ? '1 قطعة في السلة'
                                                : '$cartQty قطعة في السلة',
                                            style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
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
          if (_dealers.isNotEmpty || _loggedInUserIsDealer()) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppThemeDecorations.pageBackground(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('تطبيق قواعد خصم الموزع على التسعير الرسمي', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 6),
                  Builder(
                    builder: (ctx) {
                      final uid = ctx.watch<AuthProvider>().user?.id;
                      final selfLocked =
                          _loggedInUserIsDealer() && _selectedDealerId != null && uid != null && uid == _selectedDealerId;
                      if (selfLocked) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'الموزع: ${_selectedDealerName ?? "حسابك"}',
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'تم ربط العرض بحسابك — لا حاجة لاختيار التاجر يدوياً.',
                              style: TextStyle(color: AppColors.muted, fontSize: 12),
                            ),
                          ],
                        );
                      }
                      return DropdownButtonFormField<int?>(
                        value: _selectedDealerId,
                        decoration: const InputDecoration(
                          labelText: 'اختياري — خصم حسب قواعد الموزع',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text('بدون موزع')),
                          ..._dealers.map((d) {
                            final id = d['id'] is int ? d['id'] as int : int.tryParse(d['id'].toString());
                            if (id == null) return const DropdownMenuItem<int?>(value: null, child: SizedBox.shrink());
                            return DropdownMenuItem<int?>(
                              value: id,
                              child: Text(d['name']?.toString() ?? '#$id', overflow: TextOverflow.ellipsis),
                            );
                          }),
                        ],
                        onChanged: _previewingDealer
                            ? null
                            : (v) async {
                                setState(() {
                                  _selectedDealerId = v;
                                  if (v == null) {
                                    _selectedDealerName = null;
                                    for (final item in _cartItems) {
                                      item.remove('dealerUnitPrice');
                                      item.remove('dealerDiscountPercent');
                                      item.remove('dealerDiscountWaiting');
                                    }
                                  } else {
                                    _selectedDealerName = null;
                                    for (final d in _dealers) {
                                      final id = d['id'] is int ? d['id'] as int : int.tryParse(d['id'].toString());
                                      if (id == v) {
                                        _selectedDealerName = d['name']?.toString();
                                        break;
                                      }
                                    }
                                  }
                                });
                                if (v != null) await _applyDealerPricesToCart();
                              },
                      );
                    },
                  ),
                  if (_previewingDealer) const Padding(padding: EdgeInsets.only(top: 8), child: LinearProgressIndicator()),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
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
                              if (item['configurationSummary'] != null && item['configurationSummary'].toString().isNotEmpty)
                                Text(item['configurationSummary'].toString(), style: const TextStyle(color: AppColors.text, fontSize: 11)),
                              Builder(
                                builder: (_) {
                                  final officialForDealerUi = item['officialUnitPrice'];
                                  final dealerUnitForUi = item['dealerUnitPrice'];
                                  if (officialForDealerUi == null ||
                                      dealerUnitForUi == null) {
                                    return const SizedBox.shrink();
                                  }
                                  final offVal = (officialForDealerUi as num).toDouble();
                                  final dealerVal = (dealerUnitForUi as num).toDouble();
                                  final showDealerPricing = offVal > 0 &&
                                      dealerVal > 0 &&
                                      dealerVal < offVal;
                                  if (!showDealerPricing) {
                                    return const SizedBox.shrink();
                                  }
                                  return Text(
                                    'سعر شراء التاجر: ${_dealerPurchaseUnitPrice(item).toStringAsFixed(2)} ج.م (السعر الرسمي ${offVal.toStringAsFixed(2)})',
                                    style: const TextStyle(color: AppColors.success, fontSize: 10),
                                  );
                                },
                              ),
                              if (_hasManualDiscount(item))
                                Text(
                                  _itemManualDiscountPercent(item) > 0
                                      ? 'خصم يدوي للعميل ${_itemManualDiscountPercent(item).toStringAsFixed(2)}%'
                                      : 'خصم يدوي للعميل ${_itemManualDiscountAmount(item).toStringAsFixed(2)} ج.م',
                                  style: const TextStyle(color: AppColors.error, fontSize: 10, fontWeight: FontWeight.w600),
                                ),
                              if (item['dealerDiscountWaiting'] != null && item['dealerDiscountWaiting'].toString().isNotEmpty)
                                Text(item['dealerDiscountWaiting'].toString(), style: const TextStyle(color: AppColors.error, fontSize: 10)),
                              Text(
                                  (() {
                                    final im = Map<String, dynamic>.from(item);
                                    final up = _effectiveUnitPrice(im);
                                    final line = _lineAmountForCartItem(im);
                                    final m = _curtainCommercialMetersTotal(im);
                                    if (m != null) {
                                      return '${up.toStringAsFixed(0)} ج.م/م × ${m.toStringAsFixed(1)} م = ${line.toStringAsFixed(0)} ج.م';
                                    }
                                    final q = (item['qty'] as int?) ?? 1;
                                    return '${up.toStringAsFixed(0)} × $q = ${line.toStringAsFixed(0)} ج.م';
                                  })(),
                                  style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                        Row(
                          children: [
                            IconButton(
                              icon: const Icon(Icons.local_offer_outlined, color: AppColors.primary, size: 20),
                              onPressed: () => _showItemDiscountDialog(i),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                            const SizedBox(width: 6),
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
                if (!widget.forceExternalClient)
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
