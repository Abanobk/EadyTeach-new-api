import 'dart:typed_data';
import 'package:flutter/material.dart';
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
import '../../utils/pdf_saver_stub.dart'
    if (dart.library.html) '../../utils/pdf_saver_web.dart' as pdf_saver;

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

  Map<String, dynamic>? _dealerPurchasePreview;
  bool _dealerPreviewLoadedForCurrentQuotation = false;

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
    if (_quotation == null) return;
    if (_loadingDealerPreview) return;
    if (_dealerPreviewLoadedForCurrentQuotation) return;

    final auth = context.read<AuthProvider>();
    final role = auth.user?.role ?? '';
    if (!_isDealerRole(role)) return;

    await _loadDealerPurchasePreview();
  }

  Future<void> _loadQuotation() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.query('quotations.getById', input: {'id': widget.quotationId});
      setState(() {
        _quotation = res['data'];
        _loading = false;
        _dealerPreviewLoadedForCurrentQuotation = false;
      });
      // Preview loading is handled by `_maybeLoadDealerPurchasePreview()` (see didChangeDependencies).
    } catch (e) {
      setState(() => _loading = false);
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
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _dealerPurchasePreview = <String, dynamic>{};
        _dealerPreviewLoadedForCurrentQuotation = true;
        _loadingDealerPreview = false;
      });
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
      await ApiService.mutate('quotations.acceptPurchaseRequest', input: {'id': widget.quotationId});
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

  Future<pw.ImageProvider?> _fetchPdfImage(String? rawUrl) async {
    if (rawUrl == null || rawUrl.isEmpty) return null;
    try {
      final url = ApiService.proxyImageUrl(rawUrl);
      final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
        return pw.MemoryImage(resp.bodyBytes);
      }
    } catch (_) {}
    return null;
  }

  Future<Uint8List> _buildPdfBytes() async {
    final q = _quotation!;
    final arabicFont = await PdfGoogleFonts.cairoRegular();
    final arabicBold = await PdfGoogleFonts.cairoBold();
    final items = (q['items'] as List? ?? []);
    final subtotal = double.tryParse(q['subtotal']?.toString() ?? '0') ?? 0;
    final installPct = double.tryParse(q['installationPercent']?.toString() ?? '0') ?? 0;
    final installAmt = double.tryParse(q['installationAmount']?.toString() ?? '0') ?? 0;
    final discountPct = double.tryParse(q['discountPercent']?.toString() ?? '0') ?? 0;
    final discountAmt = double.tryParse(q['discountAmount']?.toString() ?? '0') ?? 0;
    final totalAmt = double.tryParse(q['totalAmount']?.toString() ?? '0') ?? 0;

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
        theme: pw.ThemeData.withFont(base: arabicFont, bold: arabicBold),
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (ctx) => pw.Column(children: [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Text('Easy Tech', style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('عرض سعر', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.Text(q['refNumber'] ?? '', style: const pw.TextStyle(fontSize: 12, color: PdfColors.grey700)),
            ]),
          ]),
          pw.Divider(thickness: 2, color: PdfColors.blue800),
          pw.SizedBox(height: 10),
        ]),
        build: (ctx) => [
          pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Text('العميل: ${q['clientName'] ?? '-'}', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              if (q['clientPhone'] != null) pw.Text('الهاتف: ${q['clientPhone']}', style: const pw.TextStyle(fontSize: 11)),
              if (q['clientEmail'] != null) pw.Text('البريد: ${q['clientEmail']}', style: const pw.TextStyle(fontSize: 11)),
            ]),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
              pw.Text('التاريخ: ${_formatDate(q['createdAt'])}', style: const pw.TextStyle(fontSize: 11)),
            ]),
          ]),
          pw.SizedBox(height: 20),
          // Table header
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: const pw.BoxDecoration(color: PdfColors.blue800),
            child: pw.Row(children: [
              pw.Expanded(flex: 1, child: pw.Text('#', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center)),
              pw.Expanded(flex: 2, child: pw.Text('الصورة', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center)),
              pw.Expanded(flex: 4, child: pw.Text('المنتج', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center)),
              pw.Expanded(flex: 1, child: pw.Text('الكمية', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center)),
              pw.Expanded(flex: 2, child: pw.Text('سعر الوحدة', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center)),
              pw.Expanded(flex: 2, child: pw.Text('الإجمالي', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white), textAlign: pw.TextAlign.center)),
            ]),
          ),
          // Table rows with images
          ...List.generate(items.length, (i) {
            final item = items[i] as Map;
            final up = double.tryParse(item['unitPrice']?.toString() ?? '0') ?? 0;
            final qty = int.tryParse(item['qty']?.toString() ?? item['quantity']?.toString() ?? '1') ?? 1;
            final tp = double.tryParse(item['totalPrice']?.toString() ?? '0') ?? (up * qty);
            final hasImage = itemImages.containsKey(i);
            return pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300, width: 0.5),
                color: i % 2 == 0 ? PdfColors.white : PdfColors.grey50,
              ),
              child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.center, children: [
                pw.Expanded(flex: 1, child: pw.Text('${i + 1}', style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.center)),
                pw.Expanded(flex: 2, child: pw.Center(
                  child: hasImage
                      ? pw.ClipRRect(
                          horizontalRadius: 4, verticalRadius: 4,
                          child: pw.Image(itemImages[i]!, width: 50, height: 50, fit: pw.BoxFit.cover))
                      : pw.Container(
                          width: 50, height: 50,
                          decoration: pw.BoxDecoration(color: PdfColors.grey200, borderRadius: pw.BorderRadius.circular(4)),
                          child: pw.Center(child: pw.Text('--', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey500)))),
                )),
                pw.Expanded(flex: 4, child: pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 4),
                  child: pw.Text(item['productName'] ?? '', style: const pw.TextStyle(fontSize: 10)),
                )),
                pw.Expanded(flex: 1, child: pw.Text('$qty', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center)),
                pw.Expanded(flex: 2, child: pw.Text('${up.toStringAsFixed(0)} ج.م', style: const pw.TextStyle(fontSize: 9), textAlign: pw.TextAlign.center)),
                pw.Expanded(flex: 2, child: pw.Text('${tp.toStringAsFixed(0)} ج.م', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800), textAlign: pw.TextAlign.center)),
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
                pw.Text('الإجمالي الجزئي', style: const pw.TextStyle(fontSize: 11)),
                pw.Text('${subtotal.toStringAsFixed(0)} ج.م', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
              ]),
              if (installAmt > 0) ...[
                pw.SizedBox(height: 4),
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text('تركيبات (${installPct.toStringAsFixed(0)}%)', style: const pw.TextStyle(fontSize: 11)),
                  pw.Text('${installAmt.toStringAsFixed(0)} ج.م', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
                ]),
              ],
              if (discountAmt > 0) ...[
                pw.SizedBox(height: 4),
                pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                  pw.Text(discountPct > 0 ? 'خصم (${discountPct.toStringAsFixed(0)}%)' : 'خصم', style: const pw.TextStyle(fontSize: 11, color: PdfColors.red)),
                  pw.Text('- ${discountAmt.toStringAsFixed(0)} ج.م', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.red)),
                ]),
              ],
              pw.Divider(),
              pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
                pw.Text('الإجمالي النهائي', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                pw.Text('${totalAmt.toStringAsFixed(0)} ج.م', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800)),
              ]),
            ]),
          ),
          if (q['notes'] != null && q['notes'].toString().isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Text('ملاحظات: ${q['notes']}', style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
          ],
          pw.SizedBox(height: 30),
          pw.Center(child: pw.Text('شكراً لثقتكم بنا - Easy Tech', style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: PdfColors.blue800))),
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
          final totalAmt = double.tryParse(_quotation!['totalAmount']?.toString() ?? '0') ?? 0;
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
    final isDealer = _isDealerRole(role);
    final canAcceptPurchase = auth.user?.canAccessAdmin ?? false;
    final purchaseRequestStatus = _quotation?['purchaseRequestStatus'] ?? 'none';
    final qSubtotal = double.tryParse(_quotation?['subtotal']?.toString() ?? '0') ?? 0.0;
    final qInstallationAmount = double.tryParse(_quotation?['installationAmount']?.toString() ?? '0') ?? 0.0;
    final qOriginalTotal = qSubtotal + qInstallationAmount;
    final qFinalTotal = double.tryParse(_quotation?['totalAmount']?.toString() ?? '0') ?? 0.0;
    final dealerTotalRaw = _dealerPurchasePreview?['purchaseTotalAmount'] ?? _quotation?['purchaseTotalAmount'];
    final qDealerTotal = double.tryParse(dealerTotalRaw?.toString() ?? '0') ?? 0.0;
    final qProfit = qFinalTotal - qDealerTotal;
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
                                  final unitPrice = double.tryParse(item['unitPrice']?.toString() ?? '0') ?? 0;
                                  final qty = item['qty'] as int? ?? 1;
                                  final total = double.tryParse(item['totalPrice']?.toString() ?? '0') ?? (unitPrice * qty);
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
                                                        Text('${unitPrice.toStringAsFixed(0)} ج.م / قطعة', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
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
                                      _TotalRow(label: 'الإجمالي الجزئي', value: '${double.tryParse(_quotation!['subtotal']?.toString() ?? '0')?.toStringAsFixed(0) ?? 0} ج.م'),
                                      if (double.tryParse(_quotation!['installationAmount']?.toString() ?? '0') != 0)
                                        _TotalRow(
                                          label: 'تركيبات (${double.tryParse(_quotation!['installationPercent']?.toString() ?? '0')?.toStringAsFixed(0)}%)',
                                          value: '${double.tryParse(_quotation!['installationAmount']?.toString() ?? '0')?.toStringAsFixed(0) ?? 0} ج.م',
                                        ),
                                      if ((double.tryParse(_quotation!['discountAmount']?.toString() ?? '0') ?? 0) > 0)
                                        _TotalRow(
                                          label: (double.tryParse(_quotation!['discountPercent']?.toString() ?? '0') ?? 0) > 0
                                              ? 'خصم (${double.tryParse(_quotation!['discountPercent']?.toString() ?? '0')?.toStringAsFixed(0)}%)'
                                              : 'خصم',
                                          value: '- ${double.tryParse(_quotation!['discountAmount']?.toString() ?? '0')?.toStringAsFixed(0) ?? 0} ج.م',
                                        ),
                                      const SizedBox(height: 4),
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Text('الإجمالي النهائي', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w900, fontSize: 15)),
                                          Text('${double.tryParse(_quotation!['totalAmount']?.toString() ?? '0')?.toStringAsFixed(0) ?? 0} ج.م',
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
                                  if (_loadingDealerPreview)
                                    const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: AppColors.primary)))
                                  else ...[
                                    _TotalRow(label: 'السعر الأصلي', value: '${qOriginalTotal.toStringAsFixed(0)} ج.م'),
                                    _TotalRow(label: 'سعر التاجر', value: '${qDealerTotal.toStringAsFixed(0)} ج.م'),
                                    _TotalRow(label: 'بعد خصم التاجر لعميله', value: '${qFinalTotal.toStringAsFixed(0)} ج.م'),
                                    _TotalRow(label: 'مكسبك', value: '${qProfit.toStringAsFixed(0)} ج.م'),
                                  ],
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
                          const SizedBox(height: 10),
                          // Dealer: request purchase to admin
                          if (isDealer) ...[
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: (_requestingPurchase || purchaseRequestStatus == 'requested' || purchaseRequestStatus == 'accepted')
                                    ? null
                                    : _requestPurchase,
                                icon: _requestingPurchase
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.shopping_cart),
                                label: Text(
                                  _requestingPurchase
                                      ? 'جاري إرسال الطلب...'
                                      : (purchaseRequestStatus == 'requested'
                                          ? 'بانتظار اعتماد الإدارة'
                                          : (purchaseRequestStatus == 'accepted' ? 'تم اعتماد الطلب' : 'طلب شراء')),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.black,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          // Admin/staff: accept purchase request
                          if (canAcceptPurchase && purchaseRequestStatus == 'requested') ...[
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _acceptingPurchase ? null : _acceptPurchaseRequest,
                                icon: _acceptingPurchase
                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Icon(Icons.check_circle_outline),
                                label: Text(_acceptingPurchase ? 'جاري القبول...' : 'قبول طلب الشراء'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
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
