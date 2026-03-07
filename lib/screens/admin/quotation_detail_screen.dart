import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import '../../utils/app_theme.dart';

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

  Future<void> _loadQuotation() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.query('quotations.getById', input: {'id': widget.quotationId});
      setState(() {
        _quotation = res['data'];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _sendWhatsApp() async {
    if (_quotation == null) return;
    setState(() => _generatingPdf = true);
    try {
      final res = await ApiService.mutate('quotations.generatePdf', input: {'id': widget.quotationId});
      final pdfUrl = res['url'] as String? ?? '';
      final refNumber = res['refNumber'] as String? ?? '';
      final clientName = _quotation!['clientName'] as String? ?? '';
      final clientPhone = (_quotation!['clientPhone'] as String? ?? '').replaceAll(RegExp(r'[^0-9]'), '');
      final intlPhone = clientPhone.startsWith('0') ? '2\$clientPhone' : clientPhone;
      final msg = Uri.encodeComponent('مرحباً $clientName,\n\nيسعدنا إرسال عرض السعر رقم $refNumber إليكم.\n\nرابط عرض السعر PDF:\n$pdfUrl\n\nشكراً لثقتكم بنا - Easy Tech');
      final waUrl = intlPhone.isNotEmpty
          ? 'https://wa.me/$intlPhone?text=$msg'
          : 'https://wa.me/?text=$msg';
      final uri = Uri.parse(waUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تعذر فتح WhatsApp'), backgroundColor: AppColors.error),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في توليد PDF: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _generatingPdf = false);
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
          backgroundColor: AppColors.card,
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
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: Text(_quotation?['refNumber'] ?? 'تفاصيل عرض السعر'),
          backgroundColor: AppColors.card,
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
                              color: AppColors.card,
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
                            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
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
                          const SizedBox(height: 20),
                          // Action buttons
                          // WhatsApp PDF button - always visible
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _generatingPdf ? null : _sendWhatsApp,
                              icon: _generatingPdf
                                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.chat, color: Colors.white),
                              label: Text(_generatingPdf ? 'جاري توليد PDF...' : 'إرسال عبر WhatsApp PDF'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF25D366),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
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
