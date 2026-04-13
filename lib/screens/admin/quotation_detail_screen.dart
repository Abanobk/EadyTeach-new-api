import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import 'create_quotation_screen.dart';
import '../../utils/pdf_saver_stub.dart'
    if (dart.library.html) '../../utils/pdf_saver_web.dart' as pdf_saver;
import '../../utils/quotation_line_pricing.dart';
import 'package:arabic_reshaper/arabic_reshaper.dart';
import 'package:bidi/bidi.dart' as bidi;

class QuotationDetailScreen extends StatefulWidget {
  final int quotationId;
  const QuotationDetailScreen({super.key, required this.quotationId});

  @override
  State<QuotationDetailScreen> createState() => _QuotationDetailScreenState();
}

class _QuotationDetailScreenState extends State<QuotationDetailScreen> {
  Map<String, dynamic>? _quotation;
  bool _loading = true;
  bool _sending = false;
  bool _deleting = false;
  bool _generatingPdf = false;
  bool _downloadingPdf = false;
  bool _loadingDealerPreview = false;
  bool _requestingPurchase = false;
  bool _acceptingPurchase = false;
  bool _finishingOrder = false;

  Map<String, dynamic>? _dealerPurchasePreview;
  bool _dealerPreviewLoadedForCurrentQuotation = false;
  String? _dealerPurchasePreviewError;

  Timer? _dealerPollTimer;
  bool _cartSyncedForThisQuote = false;
  bool _didAutoRecomputeRequestedPricing = false;

  // Admin/supervisor: override dealer unit prices per product before accepting.
  final Map<int, TextEditingController> _adminDealerPriceControllers = {};
  int? _adminDealerPriceControllersForQuotationId;

  // Toggle UI for dealer price override inputs.
  bool _showAdminDealerPriceEditor = false;

  pw.Font? _pdfLatinRegular;
  pw.Font? _pdfLatinBold;
  pw.Font? _pdfArabicRegular;
  pw.Font? _pdfArabicBold;
  pw.Font? _pdfSymbols;

  final _statusLabels = {
    'draft': 'مسودة',
    'sent': 'مُرسل',
    'accepted': 'مقبول',
    'rejected': 'مرفوض',
    'expired': 'منتهي',
  };

  final _statusColors = {
    'draft': Colors.grey,
    'sent': Colors.blue,
    'accepted': Colors.green,
    'rejected': Colors.red,
    'expired': Colors.orange,
  };

  @override
  void initState() {
    super.initState();
    _loadQuotation();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // `AuthProvider` may finish loading after `initState`, so trigger preview later too.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await _maybeLoadDealerPurchasePreview();
    });
  }

  Future<void> _maybeLoadDealerPurchasePreview() async {
    // Load dealer pricing preview so the dealer sees totals even before admin acceptance.
    if (!_isDealerForCurrentQuote) return;
    await _loadDealerPurchasePreview();
  }

  /// [silent]: background refresh (e.g. polling) — لا يظهر شاشة التحميل الكاملة ولا يعيد ضبط مزامنة السلة.
  Future<void> _loadQuotation({bool silent = false}) async {
    if (!silent) {
      setState(() => _loading = true);
    }
    try {
      final res = await ApiService.query('quotations.getById', input: {'id': widget.quotationId});
      if (!mounted) return;
      setState(() {
        _quotation = res['data'];
        if (!silent) {
          _loading = false;
          _dealerPreviewLoadedForCurrentQuotation = false;
          _dealerPurchasePreviewError = null;
        }
        // لا نعيد _cartSyncedForThisQuote ولا _didAutoRecomputeRequestedPricing هنا — كان يسبب
        // إعادة مزامنة السلة وطلبات شراء متكررة مع كل poll + وميض الشاشة.
      });

      // If dealer opened a quotation that is still "requested" but dealerTotal is 0 (old payload),
      // recompute purchaseItems on the backend once so the pricing details show correctly
      // before admin acceptance.
      final statusNorm = (_quotation?['purchaseRequestStatus'] ?? 'none').toString().trim().toLowerCase();
      final dealerTotalRaw = _quotation?['purchaseTotalAmount'];
      final dealerTotal = dealerTotalRaw == null ? 0.0 : (double.tryParse(dealerTotalRaw.toString()) ?? 0.0);
      if (_isDealerForCurrentQuote && statusNorm == 'requested' && dealerTotal <= 0 && !_didAutoRecomputeRequestedPricing) {
        _didAutoRecomputeRequestedPricing = true;
        try {
          await ApiService.mutate('quotations.requestPurchase', input: {'id': widget.quotationId});
          if (!mounted) return;
          // Reload quotation to reflect updated purchase_total_amount and purchase_items.
          if (mounted) {
            setState(() => _dealerPreviewLoadedForCurrentQuotation = false);
          }
          await _loadQuotation(silent: true);
        } catch (_) {
          // Ignore; UI will keep showing waiting state.
        } finally {
          // التحميل بدأ بـ !silent؛ إعادة التحميل الداخلية silent ولا تطفئ _loading.
          if (mounted) setState(() => _loading = false);
        }
        return;
      }

      // Dealer pricing will be computed from stored purchase values.
      _maybeStartDealerPolling();

      // مع silent: نحدّث الـ preview فقط إذا لم يُحمَّل بعد (تجنب طلبات متكررة كل 4 ثواني).
      if (_isDealerForCurrentQuote && (!silent || !_dealerPreviewLoadedForCurrentQuotation)) {
        await _loadDealerPurchasePreview();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silent) _loading = false;
      });
    }
  }

  bool _isDealerRole(String role) {
    final normalized = role.toLowerCase().trim().replaceAll(
          RegExp(r'[^a-z0-9\u0600-\u06FF]'),
          '',
        );
    const dealerTerms = <String>[
      'dealer',
      'reseller',
      'merchant',
      'tager',
      'seller',
      'vendor',
      'deal',
      'تاجر',
      'موزع',
      'وكيل',
      'تاج',
    ];
    return dealerTerms.any((t) => normalized.contains(t.toLowerCase()));
  }

  Future<void> _loadDealerPurchasePreview() async {
    if (_dealerPreviewLoadedForCurrentQuotation) return;
    setState(() => _loadingDealerPreview = true);
    try {
      final res = await ApiService.query('quotations.previewDealerPurchase', input: {'id': widget.quotationId});
      final data = res['data'];
      if (!mounted) return;
      setState(() {
        _dealerPurchasePreview = (data is Map<String, dynamic>) ? data : <String, dynamic>{};
        _dealerPreviewLoadedForCurrentQuotation = true;
        _loadingDealerPreview = false;
        _dealerPurchasePreviewError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dealerPurchasePreview = <String, dynamic>{};
        _dealerPreviewLoadedForCurrentQuotation = true;
        _loadingDealerPreview = false;
      });
      setState(() => _dealerPurchasePreviewError = e.toString());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حساب سعر التاجر: $e'), backgroundColor: AppColors.error),
      );
    }
  }

  Future<void> _requestPurchase() async {
    if (_quotation == null) return;
    setState(() => _requestingPurchase = true);
    try {
      await ApiService.mutate('quotations.requestPurchase', input: {'id': widget.quotationId});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ تم إرسال طلب الشراء للإدارة'), backgroundColor: AppColors.success),
        );
        await _loadQuotation();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في طلب الشراء: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _requestingPurchase = false);
    }
  }

  Future<void> _acceptPurchaseRequest() async {
    if (_quotation == null) return;
    setState(() => _acceptingPurchase = true);
    try {
      final overrides = _collectAdminPurchasePriceOverrides();
      final input = overrides.isNotEmpty
          ? {'id': widget.quotationId, 'purchaseItems': overrides}
          : {'id': widget.quotationId};
      await ApiService.mutate('quotations.acceptPurchaseRequest', input: input);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ تم قبول طلب الشراء'), backgroundColor: AppColors.success),
        );
        await _loadQuotation();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في قبول طلب الشراء: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _acceptingPurchase = false);
    }
  }

  void _ensureAdminDealerPriceControllers() {
    final purchaseStatusNorm = (_quotation?['purchaseRequestStatus'] ?? 'none')
        .toString()
        .trim()
        .toLowerCase();
    if (purchaseStatusNorm != 'requested') return;

    final canAcceptPurchaseNow = context.read<AuthProvider>().user?.canAccessAdmin ?? false;
    if (!canAcceptPurchaseNow) return;

    final purchaseItems = (_quotation?['purchaseItems'] as List? ?? []);
    if (purchaseItems.isEmpty) return;

    if (_adminDealerPriceControllersForQuotationId == widget.quotationId &&
        _adminDealerPriceControllers.isNotEmpty) {
      return;
    }

    // Reset controllers for this quotation
    for (final c in _adminDealerPriceControllers.values) {
      c.dispose();
    }
    _adminDealerPriceControllers.clear();

    for (final raw in purchaseItems) {
      if (raw is! Map) continue;
      final pid = int.tryParse(raw['productId']?.toString() ?? '') ?? 0;
      if (pid <= 0) continue;
      final dealerUnitPrice = double.tryParse(raw['dealerUnitPrice']?.toString() ?? '') ?? 0.0;
      _adminDealerPriceControllers[pid] = TextEditingController(
        text: dealerUnitPrice.toStringAsFixed(2),
      );
    }

    _adminDealerPriceControllersForQuotationId = widget.quotationId;
  }

  String _normalizeNumericInput(String input) {
    // Convert Arabic-Indic digits to Latin digits and normalize decimal separators.
    const arabicIndic = {
      '٠': '0',
      '١': '1',
      '٢': '2',
      '٣': '3',
      '٤': '4',
      '٥': '5',
      '٦': '6',
      '٧': '7',
      '٨': '8',
      '٩': '9',
    };
    var s = input.trim();
    s = s.replaceAll('،', '.').replaceAll(',', '.');
    s = s.split('').map((ch) => arabicIndic[ch] ?? ch).join();
    // Keep only digits, dot, and minus.
    s = s.replaceAll(RegExp(r'[^0-9\.\-]'), '');
    return s;
  }

  double _parseMoney(String input) {
    final s = _normalizeNumericInput(input);
    if (s.isEmpty) return 0.0;
    return double.tryParse(s) ?? 0.0;
  }

  List<Map<String, dynamic>> _collectAdminPurchasePriceOverrides() {
    final purchaseItems = (_quotation?['purchaseItems'] as List? ?? []);
    if (purchaseItems.isEmpty) return const [];

    final overrides = <Map<String, dynamic>>[];
    for (final raw in purchaseItems) {
      if (raw is! Map) continue;
      final pid = int.tryParse(raw['productId']?.toString() ?? '') ?? 0;
      if (pid <= 0) continue;
      final qty = int.tryParse(raw['qty']?.toString() ?? '') ?? 1;
      final ctrl = _adminDealerPriceControllers[pid];
      if (ctrl == null) continue;
      final price = _parseMoney(ctrl.text);
      if (price < 0) continue;
      overrides.add({
        'productId': pid,
        'qty': qty,
        'dealerUnitPrice': price,
      });
    }
    return overrides;
  }

  bool get _isDealerForCurrentQuote {
    final auth = context.read<AuthProvider>();
    final dealerId = auth.user?.id;
    final createdBy = _quotation?['createdBy'];
    final createdById = createdBy == null ? null : int.tryParse(createdBy.toString());
    return dealerId != null && createdById != null && dealerId == createdById;
  }

  void _maybeStartDealerPolling() {
    // Cancel old timer
    _dealerPollTimer?.cancel();
    _dealerPollTimer = null;

    if (!_isDealerForCurrentQuote) return;
    final purchaseStatus = _quotation?['purchaseRequestStatus'] ?? 'none';
    final purchaseStatusNorm = purchaseStatus.toString().trim().toLowerCase();

    if (purchaseStatusNorm == 'accepted') {
      _syncCartFromPurchaseItemsIfNeeded();
      return;
    }

    if (purchaseStatusNorm != 'requested') return;

    // Poll until admin accepts (then we sync cart).
    _dealerPollTimer = Timer.periodic(const Duration(seconds: 8), (t) async {
      if (!mounted) return;
      try {
        await _loadQuotation(silent: true);
      } catch (_) {
        // ignore
      }
    });
  }

  Future<void> _syncCartFromPurchaseItemsIfNeeded() async {
    if (_cartSyncedForThisQuote) return;
    final purchaseStatus = _quotation?['purchaseRequestStatus'] ?? 'none';
    final purchaseStatusNorm = purchaseStatus.toString().trim().toLowerCase();
    if (purchaseStatusNorm != 'accepted') return;

    final purchaseItems = _quotation?['purchaseItems'] as List? ?? [];
    if (purchaseItems.isEmpty) return;

    final cart = context.read<CartProvider>();
    await cart.loadCart();
    // لا نُمسح السلة الحالية؛ التاجر قد يكون عنده طلبات سابقة في السلة
    // ونريد إضافة عناصر الطلب الجديد فوق الموجود فقط.

    for (final raw in purchaseItems) {
      if (raw is! Map) continue;
      final pid = int.tryParse(raw['productId']?.toString() ?? '') ?? 0;
      if (pid <= 0) continue;
      final qty = int.tryParse(raw['qty']?.toString() ?? '') ?? 1;
      final unitPrice = double.tryParse(raw['dealerUnitPrice']?.toString() ?? '') ?? 0.0;
      final name = raw['productName']?.toString() ?? 'منتج';
      final officialPrice = double.tryParse(raw['officialUnitPrice']?.toString() ?? '') ?? 0.0;
      cart.addItem(CartItem(
        productId: pid,
        name: name,
        price: unitPrice,
        originalPrice: officialPrice > 0 ? officialPrice : null,
        image: raw['imageUrl']?.toString(),
        quantity: qty,
      ));
    }

    if (mounted) {
      setState(() => _cartSyncedForThisQuote = true);
      final count = cart.items.fold<int>(0, (sum, e) => sum + e.quantity);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم مزامنة السلة: $count قطعة/قطع', style: const TextStyle(fontWeight: FontWeight.w600)), backgroundColor: AppColors.success),
      );
    } else {
      _cartSyncedForThisQuote = true;
    }
  }

  Future<void> _finishOrderFromCart() async {
    setState(() => _finishingOrder = true);
    try {
      final cart = context.read<CartProvider>();
      if (cart.items.isEmpty) {
        await _syncCartFromPurchaseItemsIfNeeded();
      }
      if (cart.items.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('السلة فارغة'), backgroundColor: AppColors.error),
          );
        }
        return;
      }

      final purchaseStatus = _quotation?['purchaseRequestStatus'] ?? 'none';
      if (purchaseStatus != 'accepted') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('لا يمكن إنهاء الطلب قبل اعتماد الإدارة'), backgroundColor: AppColors.error),
          );
        }
        return;
      }

      final items = cart.items
          .map((i) => {
                'productId': i.productId,
                'quantity': i.quantity,
                'unitPrice': i.price.toString(),
                if (i.name.isNotEmpty) 'name': i.name,
                if (i.variant != null && i.variant!.trim().isNotEmpty)
                  'variant': i.variant!.trim(),
                if (i.configuration != null && i.configuration!.isNotEmpty)
                  'configuration': i.configuration,
              })
          .toList();

      await ApiService.mutate('orders.create', input: {
        'items': items,
        'totalAmount': cart.total.toString(),
        'notes': 'طلب تجهيز من عرض سعر: ${_quotation?['refNumber'] ?? ''}',
      });

      cart.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ تم إرسال طلب التجهيز للإدارة'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إنهاء الطلب: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _finishingOrder = false);
    }
  }

  @override
  void dispose() {
    _dealerPollTimer?.cancel();
    for (final c in _adminDealerPriceControllers.values) {
      c.dispose();
    }
    _adminDealerPriceControllers.clear();
    super.dispose();
  }

  /// فتح واتساب برسالة جاهزة (مع أو بدون رابط PDF)
  Future<bool> _openWhatsAppWithMessage({
    required String msgText,
    String? phone,
  }) async {
    final msg = Uri.encodeComponent(msgText);
    if (phone != null && phone.isNotEmpty) {
      final waUrl = 'https://wa.me/$phone?text=$msg';
      final uri = Uri.parse(waUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return true;
      }
    }
    final intentUri = Uri.parse('whatsapp://send?text=$msg');
    if (await canLaunchUrl(intentUri)) {
      await launchUrl(intentUri, mode: LaunchMode.externalApplication);
      return true;
    }
    final webUri = Uri.parse('https://api.whatsapp.com/send?text=$msg');
    if (await canLaunchUrl(webUri)) {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
      return true;
    }
    return false;
  }

  static final ArabicReshaper _arabicReshaper = ArabicReshaper.instance;

  Future<void> _ensurePdfFontsLoaded() async {
    if (_pdfLatinRegular != null &&
        _pdfLatinBold != null &&
        _pdfArabicRegular != null &&
        _pdfArabicBold != null &&
        _pdfSymbols != null) {
      return;
    }

    Future<pw.Font> loadFont(String assetPath) async {
      final data = await rootBundle.load(assetPath);
      return pw.Font.ttf(data);
    }

    _pdfLatinRegular ??= await loadFont('assets/fonts/NotoSans-Regular.ttf');
    _pdfLatinBold ??= await loadFont('assets/fonts/NotoSans-Bold.ttf');
    _pdfArabicRegular ??= await loadFont('assets/fonts/NotoSansArabic-Regular.ttf');
    _pdfArabicBold ??= await loadFont('assets/fonts/NotoSansArabic-Bold.ttf');
    _pdfSymbols ??= await loadFont('assets/fonts/NotoSansSymbols2-Regular.ttf');
  }

  List<pw.Font> _pdfFallbackFonts({bool bold = false}) => [
        bold ? _pdfArabicBold! : _pdfArabicRegular!,
        _pdfSymbols!,
      ];

  static bool _hasArabic(String text) => RegExp(r'[\u0600-\u06FF]').hasMatch(text);

  static String _reshapeArabicRuns(String text) {
    return text.replaceAllMapped(RegExp(r'[\u0600-\u06FF]+'), (match) {
      final value = match.group(0) ?? '';
      if (value.isEmpty) return value;
      final dynamic reshaped = _arabicReshaper.reshape(value);
      if (reshaped is String) return reshaped;
      if (reshaped is Iterable<int>) return String.fromCharCodes(reshaped);
      return reshaped.toString();
    });
  }

  /// تنظيف النص قبل الطباعة داخل PDF مع الإبقاء على الأحرف اللاتينية والرموز الصالحة.
  static String _pdfSafeText(String? raw, {bool preserveNewLines = false}) {
    if (raw == null) return '';
    var s = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    s = s
        .replaceAll('\u2190', ' ← ')
        .replaceAll('\u2192', ' → ')
        .replaceAll('—', '-')
        .replaceAll('–', '-')
        .replaceAll('“', '"')
        .replaceAll('”', '"')
        .replaceAll('‘', "'")
        .replaceAll('’', "'")
        .replaceAll('•', '- ')
        .replaceAll('●', '- ')
        .replaceAll('▪', '- ')
        .replaceAll('✔', 'تم ')
        .replaceAll('✅', 'تم ')
        .replaceAll('☑', 'تم ')
        .replaceAll('✓', 'تم ')
        .replaceAll('✦', '- ')
        .replaceAll('★', '- ')
        .replaceAll('☆', '- ')
        .replaceAll('■', '- ')
        .replaceAll('□', '')
        .replaceAll('▪️', '- ');
    s = s.replaceAll(RegExp(r'[\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]'), '');
    s = s.replaceAll(RegExp(r'[\u0000-\u0008\u000B\u000C\u000E-\u001F]'), '');
    s = s.replaceAll(RegExp(r'[\uE000-\uF8FF\uFFF0-\uFFFF]'), '');
    if (preserveNewLines) {
      final lines = s
          .split('\n')
          .map((line) => line.trim().replaceAll(RegExp(r'\s+'), ' '))
          .where((line) => line.isNotEmpty)
          .toList();
      s = lines.join('\n');
    } else {
      s = s.trim().replaceAll(RegExp(r'\s+'), ' ');
    }
    if (s.isEmpty || !_hasArabic(s)) return s;
    return s
        .split('\n')
        .map((line) => line.trim().isEmpty
            ? line
            : String.fromCharCodes(bidi.logicalToVisual(_reshapeArabicRuns(line))))
        .join('\n');
  }

  static pw.TextDirection _pdfTextDirectionFor(String text) {
    if (_hasArabic(text)) {
      // بعد تحويل السطر العربي إلى العرض البصري لا نريد من محرك PDF أن يعيد ترتيبه مرة أخرى.
      return pw.TextDirection.ltr;
    }
    return pw.TextDirection.ltr;
  }

  pw.Widget _pdfText(
    String text, {
      pw.TextStyle? style,
      pw.TextAlign? textAlign,
      int? maxLines,
  }) {
    final cleanedText = _pdfSafeText(text, preserveNewLines: true);
    final resolvedStyle = style ?? const pw.TextStyle();
    final isBold = resolvedStyle.fontWeight != null && resolvedStyle.fontWeight!.index >= pw.FontWeight.bold.index;
    final hasArabic = _hasArabic(cleanedText);
    final direction = _pdfTextDirectionFor(cleanedText);
    final resolvedAlign = textAlign ?? (hasArabic ? pw.TextAlign.right : pw.TextAlign.left);
    final primaryFont = hasArabic
        ? (isBold ? _pdfArabicBold : _pdfArabicRegular)
        : (isBold ? _pdfLatinBold : _pdfLatinRegular);
    final fallbackFonts = hasArabic
        ? <pw.Font>[isBold ? _pdfLatinBold! : _pdfLatinRegular!, _pdfSymbols!]
        : _pdfFallbackFonts(bold: isBold);
    return pw.Text(
      cleanedText,
      style: resolvedStyle.copyWith(
        font: primaryFont,
        fontFallback: fallbackFonts,
      ),
      textAlign: resolvedAlign,
      textDirection: direction,
      maxLines: maxLines,
    );
  }


  /// إجماليات عرض السعر للعميل: مبنية على سعر البيع للعميل في كل بند.
  /// إذا كان `subtotal` المخزّن يطابق مجموع البنود (ضمن هامش) نستخدم المخزن؛ وإلا نُعيد حساب التركيبات والخصم والنهائي (عروض قديمة خُزن فيها الإجمالي على أساس سعر التاجر).
  Map<String, double> _clientDisplayTotals() {
    final q = _quotation;
    if (q == null) {
      return {'subtotal': 0, 'installationAmount': 0, 'discountAmount': 0, 'totalAmount': 0};
    }
    final items = (q['items'] as List? ?? []);
    var lineSum = 0.0;
    for (final raw in items) {
      if (raw is! Map) continue;
      final im = Map<String, dynamic>.from(raw);
      lineSum += quotationPdfClientLineAmount(im);
    }
    final storedSub = double.tryParse(q['subtotal']?.toString() ?? '0') ?? 0.0;
    final instPct = double.tryParse(q['installationPercent']?.toString() ?? '0') ?? 0.0;
    final discPct = double.tryParse(q['discountPercent']?.toString() ?? '0') ?? 0.0;
    final instStored = double.tryParse(q['installationAmount']?.toString() ?? '0') ?? 0.0;
    final discStored = double.tryParse(q['discountAmount']?.toString() ?? '0') ?? 0.0;
    final totalStored = double.tryParse(q['totalAmount']?.toString() ?? '0') ?? 0.0;

    const tol = 1.5;
    if ((lineSum - storedSub).abs() <= tol) {
      return {
        'subtotal': storedSub,
        'installationAmount': instStored,
        'discountAmount': discStored,
        'totalAmount': totalStored,
      };
    }

    final sub = lineSum;
    final inst = instPct > 0 ? sub * instPct / 100.0 : (storedSub > 0 ? instStored * (sub / storedSub) : instStored);
    final disc = discPct > 0 ? sub * discPct / 100.0 : (storedSub > 0 ? discStored * (sub / storedSub) : discStored);
    var tot = sub + inst - disc;
    if (tot < 0) tot = 0;
    return {
      'subtotal': sub,
      'installationAmount': inst,
      'discountAmount': disc,
      'totalAmount': tot,
    };
  }

  /// اسم الموزع: من السيرفر (`dealer_user_id` → `dealerName`). لا نستبدله باسم المستخدم الحالي لو كان مسؤولاً (يُظهر الموزع المختار عند إنشاء العرض وليس اسم المسجل).
  String _resolvedDealerNameForPdf(Map<String, dynamic> q) {
    final dn = q['dealerName']?.toString().trim();
    if (dn != null && dn.isNotEmpty) return dn;
    try {
      final auth = context.read<AuthProvider>();
      final u = auth.user;
      if (u == null) return '-';
      if (u.canAccessAdmin) return '-';
      final cb = int.tryParse(q['createdBy']?.toString() ?? '');
      if (cb != null && u.id == cb) {
        final n = u.name.trim();
        if (n.isNotEmpty) return n;
      }
    } catch (_) {}
    return '-';
  }

  /// سعر شراء التاجر للبند: من JSON العرض أولاً، ثم نفس الترتيب في preview / purchase_items (لا نستخدم productId فقط — قد يتكرر المنتج).
  double? _dealerPurchaseUnitForLine(
    int index,
    Map<String, dynamic> item,
    List<dynamic> quoteItems,
    List<dynamic>? previewPurchaseItems,
    List<dynamic>? storedPurchaseItems,
    Map<int, Map<String, dynamic>> purchaseByProductId,
  ) {
    final fromItem = item['dealerUnitPrice'];
    if (fromItem != null && fromItem.toString().trim().isNotEmpty) {
      final v = double.tryParse(fromItem.toString());
      if (v != null && v >= 0) return v;
    }
    if (previewPurchaseItems != null && index < previewPurchaseItems.length) {
      final row = previewPurchaseItems[index];
      if (row is Map) {
        final v = double.tryParse(row['dealerUnitPrice']?.toString() ?? '');
        if (v != null && v >= 0) return v;
      }
    }
    if (storedPurchaseItems != null && index < storedPurchaseItems.length) {
      final row = storedPurchaseItems[index];
      if (row is Map) {
        final v = double.tryParse(row['dealerUnitPrice']?.toString() ?? '');
        if (v != null && v >= 0) return v;
      }
    }
    final pid = int.tryParse(item['productId']?.toString() ?? '');
    if (pid != null) {
      final n = quoteItems.where((e) {
        if (e is! Map) return false;
        return int.tryParse(e['productId']?.toString() ?? '') == pid;
      }).length;
      if (n == 1) {
        final row = purchaseByProductId[pid];
        final v = double.tryParse(row?['dealerUnitPrice']?.toString() ?? '');
        if (v != null && v >= 0) return v;
      }
    }
    return null;
  }

  /// هل يمكن حساب إجمالي سعر شراء التاجر من البنود دون الاعتماد على preview فقط؟
  bool _allQuotationLinesHaveDealerPrice() {
    if (_quotation == null) return false;
    final st = (_quotation!['purchaseRequestStatus'] ?? 'none').toString().trim().toLowerCase();
    if (st == 'accepted') return true;

    final quoteItems = (_quotation!['items'] as List?) ?? [];
    if (quoteItems.isEmpty) return false;
    final previewPi = _dealerPurchasePreview?['purchaseItems'] as List?;
    final storedPi = _quotation!['purchaseItems'] as List?;
    final purchaseRaw = storedPi ?? [];
    final purchaseByProductId = <int, Map<String, dynamic>>{};
    for (final raw in purchaseRaw) {
      if (raw is! Map) continue;
      final pid = int.tryParse(raw['productId']?.toString() ?? '');
      if (pid != null) purchaseByProductId[pid] = Map<String, dynamic>.from(raw);
    }
    for (var i = 0; i < quoteItems.length; i++) {
      final raw = quoteItems[i];
      if (raw is! Map) return false;
      final item = Map<String, dynamic>.from(raw);
      if (_dealerPurchaseUnitForLine(i, item, quoteItems, previewPi, storedPi, purchaseByProductId) == null) {
        return false;
      }
    }
    return true;
  }

  Map<String, double> _dealerPricingSnapshot() {
    final ct = _clientDisplayTotals();
    final qSubtotal = ct['subtotal'] ?? 0.0;
    final qDiscountAmount = ct['discountAmount'] ?? 0.0;
    final qInstallationAmount = ct['installationAmount'] ?? 0.0;
    final purchaseRequestStatusNorm = (_quotation?['purchaseRequestStatus'] ?? 'none')
        .toString()
        .trim()
        .toLowerCase();

    final qOriginalTotal = qSubtotal;
    final qFinalTotal = (qSubtotal - qDiscountAmount).clamp(0.0, double.infinity);

    final quoteItems = (_quotation?['items'] as List?) ?? [];
    final previewPi = _dealerPurchasePreview?['purchaseItems'] as List?;
    final storedPi = _quotation?['purchaseItems'] as List?;
    final purchaseRaw = (storedPi ?? []);
    final purchaseByProductId = <int, Map<String, dynamic>>{};
    for (final raw in purchaseRaw) {
      if (raw is! Map) continue;
      final pid = int.tryParse(raw['productId']?.toString() ?? '');
      if (pid != null) purchaseByProductId[pid] = Map<String, dynamic>.from(raw);
    }

    double qDealerTotal = 0.0;
    if (purchaseRequestStatusNorm == 'accepted') {
      final dealerTotalRaw = _quotation?['purchaseTotalAmount'];
      qDealerTotal = (dealerTotalRaw == null) ? 0.0 : (double.tryParse(dealerTotalRaw.toString()) ?? 0.0);
    } else {
      double sumLines = 0.0;
      var allLinesResolved = quoteItems.isNotEmpty;
      for (var i = 0; i < quoteItems.length; i++) {
        final raw = quoteItems[i];
        if (raw is! Map) {
          allLinesResolved = false;
          continue;
        }
        final item = Map<String, dynamic>.from(raw);
        final qty = int.tryParse(item['qty']?.toString() ?? item['quantity']?.toString() ?? '1') ?? 1;
        final du = _dealerPurchaseUnitForLine(i, item, quoteItems, previewPi, storedPi, purchaseByProductId);
        if (du == null) {
          allLinesResolved = false;
          break;
        }
        final curtainM = quotationCurtainCommercialMetersForLine(item);
        sumLines += du * (curtainM ?? qty);
      }
      if (allLinesResolved) {
        qDealerTotal = sumLines;
      } else {
        final previewTotalRaw = _dealerPurchasePreview?['purchaseTotalAmount'];
        qDealerTotal = (previewTotalRaw == null) ? 0.0 : (double.tryParse(previewTotalRaw.toString()) ?? 0.0);
      }
    }
    final qProfit = (qFinalTotal + qInstallationAmount) - qDealerTotal;
    return {
      'officialTotal': qOriginalTotal,
      'clientDiscount': qDiscountAmount,
      'soldTotal': qFinalTotal,
      'installation': qInstallationAmount,
      'dealerTotal': qDealerTotal,
      'profit': qProfit,
    };
  }

  Future<pw.ImageProvider?> _fetchPdfImage(String? rawUrl) async {
    if (rawUrl == null || rawUrl.trim().isEmpty) return null;
    final direct = rawUrl.trim();
    final candidates = <String>{
      if (direct.startsWith('http')) direct,
      ApiService.proxyImageUrl(direct),
    };
    for (final url in candidates) {
      try {
        final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
          return pw.MemoryImage(resp.bodyBytes);
        }
      } catch (_) {}
    }
    return null;
  }

  String? _quotationProductWebUrl(Map<String, dynamic> item) {
    final productId = int.tryParse(item['productId']?.toString() ?? item['id']?.toString() ?? '');
    if (productId == null || productId <= 0) return null;
    final base = Uri.parse(ApiService.baseUrl);
    return base.replace(path: '/app/', queryParameters: {'productId': '$productId'}, fragment: '').toString();
  }

  Future<Uint8List> _buildPdfBytes() async {
    final q = _quotation!;
    await _ensurePdfFontsLoaded();
    final items = (q['items'] as List? ?? []);
    final installPct = double.tryParse(q['installationPercent']?.toString() ?? '0') ?? 0;
    final discountPct = double.tryParse(q['discountPercent']?.toString() ?? '0') ?? 0;
    final ct = _clientDisplayTotals();
    final subtotal = ct['subtotal'] ?? 0.0;
    final installAmt = ct['installationAmount'] ?? 0.0;
    final discountAmt = ct['discountAmount'] ?? 0.0;
    final totalAmt = ct['totalAmount'] ?? 0.0;

    final Map<int, pw.ImageProvider> itemImages = {};
    for (int i = 0; i < items.length; i++) {
      final item = items[i] as Map;
      final imgUrl = item['imageUrl'] as String? ?? item['productImage'] as String?;
      final img = await _fetchPdfImage(imgUrl);
      if (img != null) itemImages[i] = img;
    }

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: _pdfLatinRegular!, bold: _pdfLatinBold!),
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (ctx) => pw.Column(children: [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('Easy Tech', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              _pdfText('عرض سعر', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              _pdfText(q['refNumber']?.toString() ?? '', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700), textAlign: pw.TextAlign.center),
            ]),
          ]),
          pw.Divider(thickness: 2, color: PdfColors.blue800),
          pw.SizedBox(height: 10),
        ]),
        build: (ctx) => [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              _pdfText('العميل: ${q['clientName'] ?? '-'}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              if (q['clientPhone'] != null) _pdfText('الهاتف: ${q['clientPhone']}', style: const pw.TextStyle(fontSize: 11)),
              if (q['clientEmail'] != null) _pdfText('البريد: ${q['clientEmail']}', style: const pw.TextStyle(fontSize: 11)),
              if (q['dealerName'] != null && q['dealerName'].toString().isNotEmpty)
                _pdfText('الموزع المعتمد: ${q['dealerName']}', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.blue700)),
            ]),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              _pdfText('التاريخ: ${_formatDate(q['createdAt'])}', style: const pw.TextStyle(fontSize: 11)),
            ]),
          ]),
          pw.SizedBox(height: 20),
          // Table header
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: const pw.BoxDecoration(color: PdfColors.blue800),
            child: pw.Row(children: [
              pw.Expanded(flex: 1, child: _pdfText('#', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center)),
              pw.Expanded(flex: 3, child: _pdfText('الصورة', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center)),
              pw.Expanded(flex: 5, child: _pdfText('المنتج', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center)),
              pw.Expanded(flex: 1, child: _pdfText('الكمية', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center)),
              pw.Expanded(flex: 2, child: _pdfText('سعر الوحدة', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center)),
              pw.Expanded(flex: 2, child: _pdfText('الإجمالي', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center)),
            ]),
          ),
          // Table rows with images
          ...List.generate(items.length, (i) {
            final item = items[i] as Map;
            final itemMap = Map<String, dynamic>.from(item);
            final rawUp = double.tryParse(item['unitPrice']?.toString() ?? '0') ?? 0;
            final up = quotationPdfClientUnitPriceForItem(itemMap);
            final qty = int.tryParse(item['qty']?.toString() ?? item['quantity']?.toString() ?? '1') ?? 1;
            final storedLine = double.tryParse(item['totalPrice']?.toString() ?? '0') ?? 0;
            final curtainM = quotationCurtainCommercialMetersForLine(itemMap);
            final tp = curtainM != null
                ? quotationPdfClientLineAmount(itemMap)
                : ((up - rawUp).abs() > 0.02 ? (up * qty) : (storedLine > 0 ? storedLine : (rawUp * qty)));
            final descriptionText = _pdfSafeText(item['description']?.toString(), preserveNewLines: true);
            final productUrl = _quotationProductWebUrl(itemMap);
            final hasImage = itemImages.containsKey(i);
            return pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                color: i % 2 == 0 ? PdfColors.white : PdfColors.grey50,
              ),
              child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                pw.Expanded(flex: 1, child: _pdfText('${i + 1}', style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.center)),
                _pdfCellImage(
                  hasImage ? itemImages[i] : null,
                  3,
                  link: productUrl,
                  size: 74,
                ),
                pw.Expanded(flex: 5, child: pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 4),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      _pdfText(item['productName']?.toString() ?? '', style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
                      if (descriptionText.isNotEmpty)
                        pw.Padding(
                          padding: const pw.EdgeInsets.only(top: 3),
                          child: _pdfText(
                            descriptionText,
                            style: const pw.TextStyle(fontSize: 8.2, color: PdfColors.grey800, lineSpacing: 1.3),
                            maxLines: 4,
                          ),
                        ),
                    ],
                  ),
                )),
                pw.Expanded(flex: 1, child: _pdfText('$qty', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                pw.Expanded(flex: 2, child: _pdfText('${up.toStringAsFixed(0)} ج.م', style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.center)),
                pw.Expanded(flex: 2, child: _pdfText('${tp.toStringAsFixed(0)} ج.م', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800), textAlign: pw.TextAlign.center)),
              ]),
            );
          }),
          pw.SizedBox(height: 16),
          pw.Container(
            alignment: pw.Alignment.centerLeft,
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey400), borderRadius: pw.BorderRadius.circular(4)),
            child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                _pdfText('الإجمالي الجزئي', style: const pw.TextStyle(fontSize: 11)),
                _pdfText('${subtotal.toStringAsFixed(0)} ج.م', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              ]),
              if (installAmt > 0) ...[
                pw.SizedBox(height: 4),
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  _pdfText('تركيبات (${installPct.toStringAsFixed(0)}%)', style: const pw.TextStyle(fontSize: 11)),
                  _pdfText('${installAmt.toStringAsFixed(0)} ج.م', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                ]),
              ],
              if (discountAmt > 0) ...[
                pw.SizedBox(height: 4),
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  _pdfText(discountPct > 0 ? 'خصم (${discountPct.toStringAsFixed(0)}%)' : 'خصم', style: const pw.TextStyle(fontSize: 11, color: PdfColors.red)),
                  _pdfText('- ${discountAmt.toStringAsFixed(0)} ج.م', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.red)),
                ]),
              ],
              pw.Divider(),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                _pdfText('الإجمالي النهائي', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                _pdfText('${totalAmt.toStringAsFixed(0)} ج.م', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
              ]),
            ]),
          ),
          if (q['notes'] != null && q['notes'].toString().isNotEmpty) ...[
            pw.SizedBox(height: 16),
            _pdfText('ملاحظات: ${q['notes']}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          ],
          pw.SizedBox(height: 30),
          pw.Center(child: _pdfText('شكراً لثقتكم بنا - Easy Tech', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800), textAlign: pw.TextAlign.center)),
        ],
      ),
    );
    return pdf.save();
  }

  Future<void> _sendWhatsApp() async {
    if (_quotation == null) return;
    setState(() => _generatingPdf = true);
    try {
      final bytes = await _buildPdfBytes();
      final refNumber = (_quotation!['refNumber'] as String? ?? 'quote').replaceAll(RegExp(r'[^\w\-]'), '_');

      if (kIsWeb) {
        // On web: try Web Share API (works on mobile browsers with file sharing)
        // Falls back to downloading the PDF if not supported
        final shared = await pdf_saver.sharePdfBytes(bytes, '$refNumber.pdf');
        if (!shared && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم تحميل PDF - افتح واتساب وأرفق الملف يدويًا'),
              backgroundColor: AppColors.primary,
              duration: Duration(seconds: 4),
            ),
          );
          // Open WhatsApp with text message so user can attach the downloaded PDF
          final clientName = _quotation!['clientName'] as String? ?? '';
          final rawPhone = (_quotation!['clientPhone'] as String? ?? '').replaceAll(RegExp(r'[^0-9]'), '');
          final intlPhone = rawPhone.startsWith('0') ? '2$rawPhone' : (rawPhone.startsWith('2') ? rawPhone : '2$rawPhone');
          final totalAmt = _clientDisplayTotals()['totalAmount'] ?? 0;
          final msgText = 'مرحباً $clientName,\n\nمرفق عرض السعر رقم $refNumber\nالإجمالي: ${totalAmt.toStringAsFixed(0)} ج.م\n\nشكراً لثقتكم بنا - Easy Tech';
          await _openWhatsAppWithMessage(msgText: msgText, phone: intlPhone.isNotEmpty ? intlPhone : null);
        }
      } else {
        // On native mobile: share PDF via system share sheet
        await Printing.sharePdf(bytes: bytes, filename: '$refNumber.pdf');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  /// ملاحظة مسار ستائر: متر فعلي vs متر تجاري (تسعير) وسعر/م تقريبي — يُعرض تحت اسم المنتج في PDF التاجر.
  String _dealerPdfCurtainNote(
    Map<String, dynamic> item, {
    double? soldUnit,
    double? dealerUnit,
    int qty = 1,
  }) {
    final cfg = parseQuotationItemConfiguration(item['configuration']);
    if (cfg == null || cfg['pricingMode']?.toString() != 'curtain_per_meter') return '';
    final cmRaw = cfg['curtainLengthCm'];
    final commRaw = cfg['curtainCommercialM'];
    double? cmVal;
    if (cmRaw is num) {
      cmVal = cmRaw.toDouble();
    } else if (cmRaw != null) {
      cmVal = double.tryParse(cmRaw.toString());
    }
    double? commVal;
    if (commRaw is num) {
      commVal = commRaw.toDouble();
    } else if (commRaw != null) {
      commVal = double.tryParse(commRaw.toString());
    }
    final actualM = (cmVal != null && cmVal > 0) ? cmVal / 100.0 : null;
    final lines = <String>[];
    if (actualM != null) {
      lines.add('متر فعلي للمسار: ${actualM.toStringAsFixed(2)} م');
    }
    if (commVal != null && commVal > 0) {
      lines.add('متر تجاري (تسعير البيع، ليس الطول الفعلي فقط): ${commVal.toStringAsFixed(1)} م');
      if (soldUnit != null && soldUnit > 0) {
        lines.add('${soldUnit.toStringAsFixed(0)} ج.م/م (بيع للعميل)');
      }
      if (dealerUnit != null && dealerUnit > 0) {
        lines.add('${dealerUnit.toStringAsFixed(0)} ج.م/م (شراء التاجر)');
      }
    }
    if (qty > 1) {
      if (actualM != null) {
        lines.add('إجمالي أمتار فعلية ($qty مسار): ${(actualM * qty).toStringAsFixed(2)} م');
      }
      if (commVal != null && commVal > 0) {
        lines.add('إجمالي أمتار تجارية ($qty مسار): ${(commVal * qty).toStringAsFixed(1)} م');
      }
    }
    return lines.join('\n');
  }

  Future<Uint8List> _buildDealerPricingPdfBytes() async {
    final q = _quotation!;
    await _ensurePdfFontsLoaded();
    final totals = _dealerPricingSnapshot();
    final revenueForMargin = totals['soldTotal']! + totals['installation']!;
    final profitPercent = revenueForMargin > 0 ? ((totals['profit']! / revenueForMargin) * 100.0) : 0.0;
    final items = (q['items'] as List? ?? []);
    final purchaseItems = (q['purchaseItems'] as List? ?? []);
    final previewPi = _dealerPurchasePreview?['purchaseItems'] as List?;
    final purchaseByProductId = <int, Map<String, dynamic>>{};
    for (final raw in purchaseItems) {
      if (raw is! Map) continue;
      final pid = int.tryParse(raw['productId']?.toString() ?? '');
      if (pid != null) purchaseByProductId[pid] = Map<String, dynamic>.from(raw);
    }

    final Map<int, pw.ImageProvider> itemImages = {};
    for (var ii = 0; ii < items.length; ii++) {
      final row = items[ii] as Map;
      final imgUrl = row['imageUrl'] as String? ?? row['productImage'] as String?;
      final img = await _fetchPdfImage(imgUrl);
      if (img != null) itemImages[ii] = img;
    }

    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        textDirection: pw.TextDirection.rtl,
        theme: pw.ThemeData.withFont(base: _pdfLatinRegular!, bold: _pdfLatinBold!),
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        build: (ctx) => [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Easy Tech', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  _pdfText('تقرير أسعار التاجر', style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold)),
                  _pdfText(q['refNumber']?.toString() ?? '', style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700), textAlign: pw.TextAlign.center),
                ],
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Divider(thickness: 1.2, color: PdfColors.blue700),
          pw.SizedBox(height: 8),
          _pdfText('الموزع المعتمد: ${_resolvedDealerNameForPdf(q)}', style: const pw.TextStyle(fontSize: 11)),
          _pdfText('العميل: ${q['clientName'] ?? '-'}', style: const pw.TextStyle(fontSize: 11)),
          _pdfText('التاريخ: ${_formatDate(q['createdAt'])}', style: const pw.TextStyle(fontSize: 11)),
          pw.SizedBox(height: 14),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
              borderRadius: pw.BorderRadius.circular(6),
            ),
            child: pw.Column(
              children: [
                _pdfMoneyRow('إجمالي السعر الرسمي', totals['officialTotal']!),
                _pdfMoneyRow('خصم التاجر للعميل', -totals['clientDiscount']!),
                _pdfMoneyRow('إجمالي البيع للعميل (بعد الخصم)', totals['soldTotal']!),
                _pdfMoneyRow('سعر شراء التاجر', totals['dealerTotal']!),
                _pdfMoneyRow('التركيبات', totals['installation']!),
                pw.Divider(),
                _pdfMoneyRow('مكسب التاجر', totals['profit']!, emphasize: true),
                _pdfMoneyRow('نسبة المكسب', profitPercent, emphasize: true, asPercent: true),
              ],
            ),
          ),
          pw.SizedBox(height: 14),
          _pdfText('تفاصيل البنود', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Container(
            color: PdfColors.blue800,
            padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            child: pw.Row(
              children: [
                _pdfHeaderCell('#', 1),
                _pdfHeaderCell('صورة', 3),
                _pdfHeaderCell('المنتج', 5),
                _pdfHeaderCell('الكمية', 1),
                _pdfHeaderCell('سعر شراء (وحدة)', 1),
                _pdfHeaderCell('سعر بيع (وحدة)', 1),
                _pdfHeaderCell('إجمالي شراء', 1),
                _pdfHeaderCell('إجمالي بيع', 1),
                _pdfHeaderCell('مكسب البند', 1),
              ],
            ),
          ),
          ...List.generate(items.length, (i) {
            final item = items[i] as Map;
            final itemMap = Map<String, dynamic>.from(item);
            final qty = int.tryParse(item['qty']?.toString() ?? item['quantity']?.toString() ?? '1') ?? 1;
            final soldUnit = quotationPdfClientUnitPriceForItem(itemMap);
            final dealerUnit = _dealerPurchaseUnitForLine(
                  i,
                  itemMap,
                  items,
                  previewPi,
                  purchaseItems,
                  purchaseByProductId,
                ) ??
                0.0;
            final curtainM = quotationCurtainCommercialMetersForLine(itemMap);
            final lineMult = curtainM ?? qty.toDouble();
            final lineProfit = (soldUnit - dealerUnit) * lineMult;
            final dealerLineTotal = dealerUnit * lineMult;
            final soldLineTotal = soldUnit * lineMult;
            final summary = itemMap['configurationSummary']?.toString().trim();
            final curtainNote = _dealerPdfCurtainNote(
              itemMap,
              soldUnit: soldUnit,
              dealerUnit: dealerUnit,
              qty: qty,
            );
            final subLines = <String>[];
            if (summary != null && summary.isNotEmpty) {
              subLines.add(summary);
            } else if (curtainNote.isNotEmpty) {
              subLines.add(curtainNote);
            }
            return pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                color: i.isEven ? PdfColors.white : PdfColors.grey50,
              ),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _pdfCell('${i + 1}', 1),
                  _pdfCellImage(
                    itemImages[i],
                    3,
                    link: _quotationProductWebUrl(itemMap),
                    size: 60,
                  ),
                  _pdfProductCell(
                    item['productName']?.toString() ?? '-',
                    subLines.isEmpty ? null : subLines.join('\n'),
                    5,
                  ),
                  _pdfCell('$qty', 1),
                  _pdfCell('${dealerUnit.toStringAsFixed(0)} ج.م', 1),
                  _pdfCell('${soldUnit.toStringAsFixed(0)} ج.م', 1),
                  _pdfCell('${dealerLineTotal.toStringAsFixed(0)} ج.م', 1),
                  _pdfCell('${soldLineTotal.toStringAsFixed(0)} ج.م', 1),
                  _pdfCell('${lineProfit.toStringAsFixed(0)} ج.م', 1),
                ],
              ),
            );
          }),
        ],
      ),
    );
    return pdf.save();
  }

  pw.Widget _pdfHeaderCell(String text, int flex) => pw.Expanded(
        flex: flex,
        child: _pdfText(
          text,
          style: pw.TextStyle(color: PdfColors.white, fontSize: 9, fontWeight: pw.FontWeight.bold),
          textAlign: pw.TextAlign.center,
        ),
      );

  pw.Widget _pdfCell(String text, int flex) => pw.Expanded(
        flex: flex,
        child: _pdfText(
          text,
          style: const pw.TextStyle(fontSize: 9),
          textAlign: pw.TextAlign.center,
        ),
      );

  pw.Widget _pdfProductCell(String title, String? subtitle, int flex) => pw.Expanded(
        flex: flex,
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            _pdfText(
              title,
              style: pw.TextStyle(fontSize: 9.4, fontWeight: pw.FontWeight.bold),
              textAlign: pw.TextAlign.center,
            ),
            if (subtitle != null && subtitle.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 4),
                child: _pdfText(
                  subtitle,
                  style: pw.TextStyle(fontSize: 7.8, color: PdfColors.grey800, lineSpacing: 1.3),
                  textAlign: pw.TextAlign.center,
                  maxLines: 4,
                ),
              ),
          ],
        ),
      );

  pw.Widget _pdfCellImage(
    pw.ImageProvider? img,
    int flex, {
    String? link,
    double size = 40,
  }) {
    if (img == null) {
      return pw.Expanded(
        flex: flex,
        child: pw.Center(
          child: _pdfText('—', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500), textAlign: pw.TextAlign.center),
        ),
      );
    }

    final imageWidget = pw.ClipRRect(
      horizontalRadius: 4,
      verticalRadius: 4,
      child: pw.Image(img, width: size, height: size, fit: pw.BoxFit.cover),
    );

    return pw.Expanded(
      flex: flex,
      child: pw.Center(
        child: (link != null && link.trim().isNotEmpty)
            ? pw.UrlLink(destination: link.trim(), child: imageWidget)
            : imageWidget,
      ),
    );
  }

  pw.Widget _pdfMoneyRow(String label, double amount, {bool emphasize = false, bool asPercent = false}) {
    final color = emphasize ? PdfColors.blue800 : PdfColors.black;
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          _pdfText(label, style: pw.TextStyle(fontSize: 11, color: color, fontWeight: emphasize ? pw.FontWeight.bold : pw.FontWeight.normal)),
          _pdfText(
            asPercent ? '${amount.toStringAsFixed(1)}%' : '${amount.toStringAsFixed(0)} ج.م',
            style: pw.TextStyle(fontSize: 11, color: color, fontWeight: emphasize ? pw.FontWeight.bold : pw.FontWeight.normal),
          ),
        ],
      ),
    );
  }

  Future<void> _shareDealerPricingPdf() async {
    if (_quotation == null) return;
    setState(() => _generatingPdf = true);
    try {
      if (_isDealerForCurrentQuote && !_dealerPreviewLoadedForCurrentQuotation) {
        await _loadDealerPurchasePreview();
      }
      final bytes = await _buildDealerPricingPdfBytes();
      final refNumber = (_quotation!['refNumber'] as String? ?? 'quote').replaceAll(RegExp(r'[^\w\-]'), '_');
      if (kIsWeb) {
        await pdf_saver.savePdfBytes(bytes, '${refNumber}_dealer_pricing.pdf');
      } else {
        await Printing.sharePdf(bytes: bytes, filename: '${refNumber}_dealer_pricing.pdf');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في إنشاء PDF التاجر: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
    }
  }

  Future<void> _downloadPdf() async {
    if (_quotation == null) return;
    setState(() => _downloadingPdf = true);
    try {
      final bytes = await _buildPdfBytes();
      final refNumber = (_quotation!['refNumber'] as String? ?? 'quote').replaceAll(RegExp(r'[^\w\-]'), '_');
      if (kIsWeb) {
        await pdf_saver.savePdfBytes(bytes, '$refNumber.pdf');
      } else {
        await Printing.layoutPdf(
          onLayout: (_) async => bytes,
          name: '$refNumber.pdf',
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم توليد PDF بنجاح'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في توليد PDF: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _downloadingPdf = false);
    }
  }

  Future<void> _sendQuotation() async {
    if (_quotation == null) return;
    final email = _quotation!['clientEmail'] as String?;
    final clientUserId = _quotation!['clientUserId'];
    if (email == null && clientUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا يوجد بريد إلكتروني للعميل'), backgroundColor: AppColors.error),
      );
      return;
    }
    setState(() => _sending = true);
    try {
      await ApiService.mutate('quotations.send', input: {'id': widget.quotationId});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ تم إرسال عرض السعر بنجاح'), backgroundColor: AppColors.success),
        );
        _loadQuotation();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في الإرسال: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _deleteQuotation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppThemeDecorations.cardColor(context),
          title: const Text('حذف عرض السعر', style: TextStyle(color: AppColors.text)),
          content: const Text('هل أنت متأكد من حذف هذا العرض؟', style: TextStyle(color: AppColors.muted)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('إلغاء', style: TextStyle(color: AppColors.muted))),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('حذف', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    setState(() => _deleting = true);
    try {
      await ApiService.mutate('quotations.delete', input: {'id': widget.quotationId});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف عرض السعر'), backgroundColor: AppColors.success),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في الحذف: $e'), backgroundColor: AppColors.error),
        );
        setState(() => _deleting = false);
      }
    }
  }

  Future<void> _openEditQuotation() async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => CreateQuotationScreen(
          quotationIdToEdit: widget.quotationId,
        ),
      ),
    );
    if (ok == true && mounted) await _loadQuotation();
  }

  String _formatDate(dynamic ts) {
    if (ts == null) return '-';
    try {
      final dt = DateTime.fromMillisecondsSinceEpoch(ts is int ? ts : int.parse(ts.toString()));
      return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '-';
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final role = auth.user?.role ?? '';
    final dealerId = auth.user?.id;
    final quoteCreatedBy = _quotation?['createdBy'];
    final quoteCreatedById = quoteCreatedBy == null ? null : int.tryParse(quoteCreatedBy.toString());
    final isDealer = (dealerId != null && quoteCreatedById != null) ? (dealerId == quoteCreatedById) : _isDealerRole(role);
    final canAcceptPurchase = auth.user?.canAccessAdmin ?? false;
    final purchaseRequestStatus = _quotation?['purchaseRequestStatus'] ?? 'none';
    final purchaseRequestStatusNorm = purchaseRequestStatus.toString().trim().toLowerCase();
    final purchaseRequestStatusRaw = purchaseRequestStatus.toString().trim();
    final canAccessAdmin = auth.user?.canAccessAdmin ?? false;
    final isQuoteOwner = dealerId != null && quoteCreatedById != null && dealerId == quoteCreatedById;
    final canEditQuotation = (canAccessAdmin || isQuoteOwner) &&
        purchaseRequestStatusNorm != 'requested' &&
        purchaseRequestStatusNorm != 'accepted';
    final purchaseItems = (_quotation?['purchaseItems'] as List? ?? []);
    final clientTotals = _quotation != null ? _clientDisplayTotals() : null;
    final qSubtotal = clientTotals?['subtotal'] ?? 0.0;
    final qDiscountAmount = clientTotals?['discountAmount'] ?? 0.0;
    final qClientInstallation = clientTotals?['installationAmount'] ?? 0.0;
    final qClientTotalAmount = clientTotals?['totalAmount'] ?? 0.0;
    final qOriginalTotal = qSubtotal;
    final qFinalTotal = (qSubtotal - qDiscountAmount).clamp(0.0, double.infinity);
    // نفس منطق PDF: مجموع سعر شراء التاجر من البنود (dealerUnitPrice + محاذاة بالفهرس)، وليس purchaseTotalAmount من المعاينة فقط.
    final dealerSnap = _quotation != null ? _dealerPricingSnapshot() : null;
    final qDealerTotal = dealerSnap?['dealerTotal'] ?? 0.0;
    final qProfit = dealerSnap?['profit'] ?? 0.0;
    final linesHaveDealerPrice = _allQuotationLinesHaveDealerPrice();
    final isDealerPriceLoading = purchaseRequestStatusNorm != 'accepted' &&
        !linesHaveDealerPrice &&
        _loadingDealerPreview &&
        !_dealerPreviewLoadedForCurrentQuotation;
    final hasDealerPreviewError = purchaseRequestStatusNorm != 'accepted' &&
        !linesHaveDealerPrice &&
        (_dealerPurchasePreviewError != null && _dealerPurchasePreviewError!.toString().trim().isNotEmpty);
    final dealerPriceValue = isDealerPriceLoading
        ? 'جاري الحساب...'
        : (hasDealerPreviewError ? 'تعذر حساب سعر التاجر' : '${qDealerTotal.toStringAsFixed(0)} ج.م');
    final dealerProfitValue = isDealerPriceLoading
        ? 'جاري الحساب...'
        : (hasDealerPreviewError ? 'تعذر حساب مكسبك' : '${qProfit.toStringAsFixed(0)} ج.م');
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppThemeDecorations.pageBackground(context),
        appBar: AppBar(
          title: Text(_quotation?['refNumber'] ?? 'تفاصيل عرض السعر'),
          backgroundColor: AppThemeDecorations.cardColor(context),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: AppColors.text),
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            if (_quotation != null && canEditQuotation)
              IconButton(
                tooltip: 'تعديل عرض السعر',
                icon: const Icon(Icons.edit_note, color: AppColors.primary),
                onPressed: _openEditQuotation,
              ),
            if (_quotation != null && _quotation!['status'] != 'accepted')
              IconButton(
                icon: _deleting
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.error))
                    : const Icon(Icons.delete_outline, color: AppColors.error),
                onPressed: _deleting ? null : _deleteQuotation,
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _quotation == null
                ? const Center(child: Text('لم يتم العثور على عرض السعر', style: TextStyle(color: AppColors.muted)))
                : RefreshIndicator(
                    onRefresh: _loadQuotation,
                    color: AppColors.primary,
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Header card
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppThemeDecorations.cardColor(context),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: (_statusColors[_quotation!['status']] ?? Colors.grey).withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(20),
                                        border: Border.all(color: (_statusColors[_quotation!['status']] ?? Colors.grey).withOpacity(0.4)),
                                      ),
                                      child: Text(
                                        _statusLabels[_quotation!['status']] ?? _quotation!['status'],
                                        style: TextStyle(color: _statusColors[_quotation!['status']] ?? Colors.grey, fontWeight: FontWeight.bold, fontSize: 12),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(_quotation!['refNumber'] ?? '', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 14)),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _InfoRow(icon: Icons.person_outline, label: 'العميل', value: _quotation!['clientName'] ?? _quotation!['clientEmail'] ?? 'غير محدد'),
                                if (_quotation!['clientEmail'] != null)
                                  _InfoRow(icon: Icons.email_outlined, label: 'البريد', value: _quotation!['clientEmail']),
                                if (_quotation!['clientPhone'] != null)
                                  _InfoRow(icon: Icons.phone_outlined, label: 'الهاتف', value: _quotation!['clientPhone']),
                                _InfoRow(icon: Icons.calendar_today_outlined, label: 'التاريخ', value: _formatDate(_quotation!['createdAt'])),
                                if (_quotation!['sentAt'] != null)
                                  _InfoRow(icon: Icons.send_outlined, label: 'تاريخ الإرسال', value: _formatDate(_quotation!['sentAt'])),
                                if (_quotation!['notes'] != null && _quotation!['notes'].toString().isNotEmpty)
                                  _InfoRow(icon: Icons.notes, label: 'ملاحظات', value: _quotation!['notes']),
                                if (_quotation!['clientNote'] != null && _quotation!['clientNote'].toString().isNotEmpty)
                                  _InfoRow(icon: Icons.chat_bubble_outline, label: 'رد العميل', value: _quotation!['clientNote']),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          // Items
                          const Text('📦 المنتجات', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(height: 8),
                          Container(
                            decoration: BoxDecoration(color: AppThemeDecorations.cardColor(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                            child: Column(
                              children: [
                                // Table header
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  child: Row(
                                    children: const [
                                      Expanded(flex: 3, child: Text('#  المنتج', style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.bold))),
                                      Expanded(flex: 1, child: Text('الكمية', style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                                      Expanded(flex: 2, child: Text('الإجمالي', style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.end)),
                                    ],
                                  ),
                                ),
                                const Divider(color: AppColors.border, height: 1),
                                ...(_quotation!['items'] as List? ?? []).asMap().entries.map((entry) {
                                  final idx = entry.key;
                                  final item = entry.value as Map;
                                  final itemMap = Map<String, dynamic>.from(item);
                                  final unitPriceRaw = double.tryParse(item['unitPrice']?.toString() ?? '0') ?? 0;
                                  final unitPrice = quotationPdfClientUnitPriceForItem(itemMap);
                                  final qty = int.tryParse(item['qty']?.toString() ?? item['quantity']?.toString() ?? '1') ?? 1;
                                  final curtainM = quotationCurtainCommercialMetersForLine(itemMap);
                                  final total = curtainM != null
                                      ? quotationPdfClientLineAmount(itemMap)
                                      : ((unitPrice - unitPriceRaw).abs() > 0.02
                                          ? (unitPrice * qty)
                                          : (double.tryParse(item['totalPrice']?.toString() ?? '0') ?? (unitPriceRaw * qty)));
                                  final purchaseItemsList = (_quotation?['purchaseItems'] as List? ?? []);
                                  final purchaseByProductId = <int, Map<String, dynamic>>{};
                                  for (final raw in purchaseItemsList) {
                                    if (raw is! Map) continue;
                                    final pid = int.tryParse(raw['productId']?.toString() ?? '') ?? 0;
                                    if (pid > 0) purchaseByProductId[pid] = Map<String, dynamic>.from(raw);
                                  }
                                  final quoteItemsList = (_quotation!['items'] as List? ?? []);
                                  final previewPiRows = _dealerPurchasePreview?['purchaseItems'] as List?;
                                  final dealerUnitResolved = _dealerPurchaseUnitForLine(
                                    idx,
                                    itemMap,
                                    quoteItemsList,
                                    previewPiRows,
                                    purchaseItemsList,
                                    purchaseByProductId,
                                  );
                                  String? waitingMsg;
                                  if (previewPiRows != null && idx < previewPiRows.length && previewPiRows[idx] is Map) {
                                    waitingMsg = (previewPiRows[idx] as Map)['discountWaitingMessage']?.toString();
                                  }
                                  return Column(
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Expanded(
                                              flex: 3,
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text('${idx + 1}. ', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Text(item['productName'] ?? '', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13)),
                                                        if (item['selectedColor'] != null)
                                                          Text('لون: ${item['selectedColor']}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                                                        if (item['selectedVariant'] != null)
                                                          Text('نوع: ${item['selectedVariant']}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                                                        Text(
                                                          curtainM != null
                                                              ? '${unitPrice.toStringAsFixed(0)} ج.م / م (تجاري)'
                                                              : '${unitPrice.toStringAsFixed(0)} ج.م / قطعة',
                                                          style: const TextStyle(color: AppColors.muted, fontSize: 11),
                                                        ),
                                                        if (isDealer && dealerUnitResolved != null)
                                                          Builder(
                                                            builder: (_) {
                                                              final officialUnit = double.tryParse(itemMap['officialUnitPrice']?.toString() ?? '') ??
                                                                  unitPrice;
                                                              final dealerUnit = dealerUnitResolved;
                                                              final profitPerUnit = unitPrice - dealerUnit;
                                                              final lineMult = curtainM ?? qty.toDouble();
                                                              final profitTotal = profitPerUnit * lineMult;
                                                              final wm = waitingMsg?.trim() ?? '';

                                                              return Column(
                                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                                children: [
                                                                  if (wm.isNotEmpty)
                                                                    Text(wm, style: const TextStyle(color: AppColors.error, fontSize: 10)),
                                                                  Text(
                                                                    'سعر شراء التاجر: ${dealerUnit.toStringAsFixed(0)} ج.م (السعر الرسمي ${officialUnit.toStringAsFixed(0)})',
                                                                    style: TextStyle(
                                                                      color: dealerUnit < unitPrice ? AppColors.success : AppColors.muted,
                                                                      fontSize: 10,
                                                                    ),
                                                                  ),
                                                                  if (unitPrice > 0)
                                                                    Text(
                                                                      'مكسب البند: ${profitTotal.toStringAsFixed(0)} ج.م',
                                                                      style: TextStyle(
                                                                        color: profitPerUnit >= 0 ? AppColors.success : AppColors.error,
                                                                        fontSize: 10,
                                                                        fontWeight: FontWeight.w600,
                                                                      ),
                                                                    ),
                                                                ],
                                                              );
                                                            },
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Expanded(
                                              flex: 1,
                                              child: Text('$qty', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                                            ),
                                            Expanded(
                                              flex: 2,
                                              child: Text('${total.toStringAsFixed(0)} ج.م', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.end),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (idx < (_quotation!['items'] as List).length - 1)
                                        const Divider(color: AppColors.border, height: 1),
                                    ],
                                  );
                                }),
                                const Divider(color: AppColors.border, height: 1),
                                // Totals
                                Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    children: [
                                      _TotalRow(label: 'الإجمالي الجزئي', value: '${qSubtotal.toStringAsFixed(0)} ج.م'),
                                      if (qClientInstallation != 0)
                                        _TotalRow(
                                          label: 'تركيبات (${double.tryParse(_quotation!['installationPercent']?.toString() ?? '0')?.toStringAsFixed(0) ?? 0}%)',
                                          value: '${qClientInstallation.toStringAsFixed(0)} ج.م',
                                        ),
                                      if (qDiscountAmount > 0)
                                        _TotalRow(
                                          label: (double.tryParse(_quotation!['discountPercent']?.toString() ?? '0') ?? 0) > 0
                                              ? 'خصم (${double.tryParse(_quotation!['discountPercent']?.toString() ?? '0')?.toStringAsFixed(0)}%)'
                                              : 'خصم',
                                          value: '- ${qDiscountAmount.toStringAsFixed(0)} ج.م',
                                        ),
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text('الإجمالي النهائي', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w900, fontSize: 15)),
                                          Text('${qClientTotalAmount.toStringAsFixed(0)} ج.م',
                                              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900, fontSize: 18)),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (isDealer) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppThemeDecorations.cardColor(context),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: AppColors.border),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'تفاصيل الأسعار للتاجر',
                                    style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'حالة طلب الشراء: $purchaseRequestStatusRaw',
                                    style: const TextStyle(
                                      color: AppColors.primary,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  if (purchaseRequestStatusNorm != 'accepted')
                                    const Text(
                                      'تفاصيل سعر التاجر تحت المراجعة والموافقة من إدارة إيزي تك',
                                      style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w900, fontSize: 14),
                                    ),
                                  _TotalRow(label: 'السعر الأصلي', value: '${qOriginalTotal.toStringAsFixed(0)} ج.م'),
                                  _TotalRow(label: 'سعر التاجر', value: dealerPriceValue),
                                  _TotalRow(
                                      label: 'بعد خصم التاجر لعميله', value: '${qFinalTotal.toStringAsFixed(0)} ج.م'),
                                  _TotalRow(label: 'مكسبك', value: dealerProfitValue),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                          ] else
                            const SizedBox(height: 20),
                          // تحميل PDF على الجهاز
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: (_downloadingPdf || _generatingPdf) ? null : _downloadPdf,
                              icon: _downloadingPdf
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.download, color: Colors.white),
                              label: Text(_downloadingPdf ? 'جاري التحميل...' : 'تحميل PDF على الجهاز'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          // WhatsApp PDF button
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: (_generatingPdf || _downloadingPdf) ? null : _sendWhatsApp,
                              icon: _generatingPdf
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.chat, color: Colors.white),
                              label: Text(_generatingPdf ? 'جاري توليد PDF...' : 'مشاركة PDF عبر WhatsApp'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF25D366),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                          if (canEditQuotation) ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _openEditQuotation,
                                icon: const Icon(Icons.edit_note, color: Colors.white),
                                label: const Text('تعديل عرض السعر'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF1D4ED8),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                              ),
                            ),
                          ],
                          if (isDealer ||
                              canAccessAdmin ||
                              ((_quotation?['purchaseItems'] as List?)?.isNotEmpty ?? false))
                            ...[
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: (_generatingPdf || _downloadingPdf) ? null : _shareDealerPricingPdf,
                                icon: _generatingPdf
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.request_quote, color: Colors.white),
                                label: const Text('مشاركة PDF أسعار التاجر ومكسبه'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF0F766E),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 10),
                          // Dealer: request purchase to admin
                          if (isDealer) ...[
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: (_requestingPurchase || purchaseRequestStatusNorm == 'requested' || purchaseRequestStatusNorm == 'accepted')
                                    ? null
                                    : _requestPurchase,
                                icon: _requestingPurchase
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.shopping_cart),
                                label: Text(
                                  _requestingPurchase
                                      ? 'جاري إرسال الطلب...'
                                      : (purchaseRequestStatusNorm == 'requested'
                                          ? 'بانتظار اعتماد الإدارة'
                                          : (purchaseRequestStatusNorm == 'accepted' ? 'تم اعتماد الطلب' : 'طلب شراء')),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (purchaseRequestStatusNorm == 'accepted') ...[
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: _finishingOrder ? null : _finishOrderFromCart,
                                  icon: _finishingOrder
                                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                      : const Icon(Icons.done_all),
                                  label: Text(_finishingOrder ? 'جاري الإنهاء...' : 'إنهاء الطلب وإرسال للتجهيز'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                          ],
                          // Admin/staff: accept purchase request
                          if (canAcceptPurchase && purchaseRequestStatusNorm == 'requested') ...[
                            if (purchaseItems.isEmpty)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 10),
                                child: Text(
                                  'لا توجد تفاصيل سعر تاجر لتعديلها.',
                                  style: TextStyle(color: AppColors.muted, fontWeight: FontWeight.w600),
                                ),
                              )
                            else ...[
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    if (!mounted) return;
                                    final next = !_showAdminDealerPriceEditor;
                                    setState(() => _showAdminDealerPriceEditor = next);
                                    if (next) {
                                      // Ensure controllers exist before showing inputs.
                                      _ensureAdminDealerPriceControllers();
                                    }
                                  },
                                  icon: const Icon(Icons.edit),
                                  label: Text(_showAdminDealerPriceEditor ? 'إخفاء تعديل سعر التاجر' : 'تعديل سعر التاجر (للمنتجات)'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              if (_showAdminDealerPriceEditor) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppThemeDecorations.cardColor(context),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: AppColors.border),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'تعديل سعر التاجر (للمنتجات)',
                                        style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 14),
                                      ),
                                      const SizedBox(height: 10),
                                      ...purchaseItems.map((raw) {
                                        if (raw is! Map) return const SizedBox.shrink();
                                        final pid = int.tryParse(raw['productId']?.toString() ?? '') ?? 0;
                                        if (pid <= 0) return const SizedBox.shrink();
                                        final name = raw['productName']?.toString() ?? 'منتج';
                                        final qty = int.tryParse(raw['qty']?.toString() ?? '') ?? 1;
                                        final ctrl = _adminDealerPriceControllers[pid];
                                        final officialUnitPrice = double.tryParse(raw['officialUnitPrice']?.toString() ?? '') ?? 0.0;
                                        if (ctrl == null) return const SizedBox.shrink();
                                        return Padding(
                                          padding: const EdgeInsets.only(bottom: 10),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(name,
                                                        style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13)),
                                                    Text('الكمية: $qty', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                                                    if (officialUnitPrice > 0)
                                                      Text(
                                                        'السعر الأصلي: ${officialUnitPrice.toStringAsFixed(0)} ج.م',
                                                        style: const TextStyle(color: AppColors.muted, fontSize: 12),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 10),
                                              SizedBox(
                                                width: 130,
                                                child: TextField(
                                                  controller: ctrl,
                                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                  textDirection: TextDirection.ltr,
                                                  decoration: const InputDecoration(
                                                    labelText: 'سعر التاجر',
                                                    isDense: true,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _acceptingPurchase ? null : _acceptPurchaseRequest,
                                icon: _acceptingPurchase
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.check_circle_outline),
                                label: Text(_acceptingPurchase ? 'جاري القبول...' : 'قبول طلب الشراء'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          if (_quotation!['status'] == 'draft' || _quotation!['status'] == 'sent') ...[
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _sending ? null : _sendQuotation,
                                icon: _sending
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                                    : const Icon(Icons.send),
                                label: Text(_sending ? 'جاري الإرسال...' : (_quotation!['status'] == 'sent' ? 'إعادة الإرسال' : 'إرسال للعميل')),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final dynamic value;
  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: AppColors.muted),
          const SizedBox(width: 6),
          Text('$label: ', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          Expanded(
            child: Text(value?.toString() ?? '-', style: const TextStyle(color: AppColors.text, fontSize: 12, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  final String label;
  final String value;
  const _TotalRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          Text(value, style: const TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
