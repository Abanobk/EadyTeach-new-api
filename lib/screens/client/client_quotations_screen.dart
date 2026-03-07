import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../utils/app_theme.dart';

class ClientQuotationsScreen extends StatefulWidget {
  const ClientQuotationsScreen({super.key});

  @override
  State<ClientQuotationsScreen> createState() => _ClientQuotationsScreenState();
}

class _ClientQuotationsScreenState extends State<ClientQuotationsScreen> {
  List<dynamic> _quotations = [];
  bool _loading = true;

  final _statusLabels = {
    'draft': 'مسودة',
    'sent': 'في الانتظار',
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
    _loadQuotations();
  }

  Future<void> _loadQuotations() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.query('quotations.myQuotations');
      setState(() {
        _quotations = res['data'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  String _formatDate(dynamic ts) {
    if (ts == null) return '-';
    try {
      final dt = DateTime.fromMillisecondsSinceEpoch(ts is int ? ts : int.parse(ts.toString()));
      return '${dt.day}/${dt.month}/${dt.year}';
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
          title: const Text('عروض الأسعار'),
          backgroundColor: AppColors.card,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: AppColors.primary),
              onPressed: _loadQuotations,
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : RefreshIndicator(
                onRefresh: _loadQuotations,
                color: AppColors.primary,
                child: _quotations.isEmpty
                    ? ListView(
                        children: [
                          SizedBox(
                            height: MediaQuery.of(context).size.height * 0.6,
                            child: Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.request_quote_outlined, size: 72, color: AppColors.muted.withOpacity(0.4)),
                                  const SizedBox(height: 16),
                                  const Text('لا توجد عروض أسعار', style: TextStyle(color: AppColors.muted, fontSize: 16)),
                                  const SizedBox(height: 8),
                                  const Text('سيظهر هنا أي عرض سعر يرسله لك المندوب', style: TextStyle(color: AppColors.muted, fontSize: 13), textAlign: TextAlign.center),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _quotations.length,
                        itemBuilder: (context, index) {
                          final q = _quotations[index];
                          final status = q['status'] as String? ?? 'sent';
                          final statusColor = _statusColors[status] ?? Colors.grey;
                          final statusLabel = _statusLabels[status] ?? status;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: InkWell(
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(builder: (_) => ClientQuotationDetailScreen(quotationId: q['id'])),
                              ).then((_) => _loadQuotations()),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: AppColors.card,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: status == 'sent' ? AppColors.primary.withOpacity(0.4) : AppColors.border,
                                    width: status == 'sent' ? 1.5 : 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: statusColor.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(color: statusColor.withOpacity(0.4)),
                                          ),
                                          child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold)),
                                        ),
                                        const Spacer(),
                                        Text(q['refNumber'] ?? '', style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        const Icon(Icons.attach_money, size: 16, color: AppColors.muted),
                                        const SizedBox(width: 4),
                                        Text(
                                          '${double.tryParse(q['totalAmount']?.toString() ?? '0')?.toStringAsFixed(0) ?? 0} ج.م',
                                          style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 16),
                                        ),
                                        const Spacer(),
                                        const Icon(Icons.calendar_today_outlined, size: 12, color: AppColors.muted),
                                        const SizedBox(width: 4),
                                        Text(_formatDate(q['createdAt']), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                                      ],
                                    ),
                                    if (status == 'sent') ...[
                                      const SizedBox(height: 10),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: ElevatedButton(
                                              onPressed: () => _respond(q['id'], 'accepted'),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: AppColors.success,
                                                foregroundColor: Colors.white,
                                                padding: const EdgeInsets.symmetric(vertical: 8),
                                              ),
                                              child: const Text('قبول', style: TextStyle(fontWeight: FontWeight.bold)),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: OutlinedButton(
                                              onPressed: () => _respond(q['id'], 'rejected'),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: AppColors.error,
                                                side: const BorderSide(color: AppColors.error),
                                                padding: const EdgeInsets.symmetric(vertical: 8),
                                              ),
                                              child: const Text('رفض', style: TextStyle(fontWeight: FontWeight.bold)),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
      ),
    );
  }

  Future<void> _respond(int id, String response) async {
    try {
      await ApiService.mutate('quotations.respond', input: {'id': id, 'response': response});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response == 'accepted' ? '✅ تم قبول عرض السعر' : '❌ تم رفض عرض السعر'),
            backgroundColor: response == 'accepted' ? AppColors.success : AppColors.error,
          ),
        );
        _loadQuotations();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }
}

class ClientQuotationDetailScreen extends StatefulWidget {
  final int quotationId;
  const ClientQuotationDetailScreen({super.key, required this.quotationId});

  @override
  State<ClientQuotationDetailScreen> createState() => _ClientQuotationDetailScreenState();
}

class _ClientQuotationDetailScreenState extends State<ClientQuotationDetailScreen> {
  Map<String, dynamic>? _quotation;
  bool _loading = true;
  final _noteCtrl = TextEditingController();
  bool _responding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.query('quotations.getByIdForClient', input: {'id': widget.quotationId});
      setState(() {
        _quotation = res['data'];
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _respond(String response) async {
    setState(() => _responding = true);
    try {
      await ApiService.mutate('quotations.respond', input: {
        'id': widget.quotationId,
        'response': response,
        'clientNote': _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(response == 'accepted' ? '✅ تم قبول عرض السعر' : '❌ تم رفض عرض السعر'),
            backgroundColor: response == 'accepted' ? AppColors.success : AppColors.error,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error),
        );
        setState(() => _responding = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: Text(_quotation?['refNumber'] ?? 'عرض السعر'),
          backgroundColor: AppColors.card,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: AppColors.text),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _quotation == null
                ? const Center(child: Text('لم يتم العثور على عرض السعر', style: TextStyle(color: AppColors.muted)))
                : SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Items table
                        const Text('📦 تفاصيل العرض', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
                          child: Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                child: Row(
                                  children: const [
                                    Expanded(flex: 3, child: Text('#  المنتج', style: TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.bold))),
                                    Expanded(flex: 1, child: Text('الكمية', style: TextStyle(color: AppColors.muted, fontSize: 11), textAlign: TextAlign.center)),
                                    Expanded(flex: 2, child: Text('الإجمالي', style: TextStyle(color: AppColors.muted, fontSize: 11), textAlign: TextAlign.end)),
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
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text('${idx + 1}. ${item['productName'] ?? ''}', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13)),
                                                if (item['selectedColor'] != null)
                                                  Text('لون: ${item['selectedColor']}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                                                if (item['selectedVariant'] != null)
                                                  Text('نوع: ${item['selectedVariant']}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                                                Text('${unitPrice.toStringAsFixed(0)} ج.م / قطعة', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                                              ],
                                            ),
                                          ),
                                          Expanded(flex: 1, child: Text('$qty', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                                          Expanded(flex: 2, child: Text('${total.toStringAsFixed(0)} ج.م', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13), textAlign: TextAlign.end)),
                                        ],
                                      ),
                                    ),
                                    if (idx < (_quotation!['items'] as List).length - 1)
                                      const Divider(color: AppColors.border, height: 1),
                                  ],
                                );
                              }),
                              const Divider(color: AppColors.border, height: 1),
                              Padding(
                                padding: const EdgeInsets.all(12),
                                child: Column(
                                  children: [
                                    if (double.tryParse(_quotation!['installationAmount']?.toString() ?? '0') != 0) ...[
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text('تركيبات (${double.tryParse(_quotation!['installationPercent']?.toString() ?? '0')?.toStringAsFixed(0)}%)', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                                          Text('${double.tryParse(_quotation!['installationAmount']?.toString() ?? '0')?.toStringAsFixed(0)} ج.م', style: const TextStyle(color: AppColors.text, fontSize: 13)),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                    ],
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('الإجمالي النهائي', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w900, fontSize: 15)),
                                        Text('${double.tryParse(_quotation!['totalAmount']?.toString() ?? '0')?.toStringAsFixed(0)} ج.م',
                                            style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w900, fontSize: 18)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Response section
                        if (_quotation!['status'] == 'sent') ...[
                          const Text('💬 ردك على العرض', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _noteCtrl,
                            decoration: const InputDecoration(
                              hintText: 'ملاحظة (اختياري)...',
                              prefixIcon: Icon(Icons.chat_bubble_outline, color: AppColors.muted),
                            ),
                            style: const TextStyle(color: AppColors.text),
                            maxLines: 3,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _responding ? null : () => _respond('accepted'),
                                  icon: _responding ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.check_circle_outline),
                                  label: const Text('قبول العرض', style: TextStyle(fontWeight: FontWeight.bold)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.success,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _responding ? null : () => _respond('rejected'),
                                  icon: const Icon(Icons.cancel_outlined),
                                  label: const Text('رفض العرض', style: TextStyle(fontWeight: FontWeight.bold)),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.error,
                                    side: const BorderSide(color: AppColors.error),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        if (_quotation!['status'] == 'accepted') ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.success.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.success.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.check_circle, color: AppColors.success),
                                const SizedBox(width: 10),
                                const Text('تم قبول هذا العرض', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                        if (_quotation!['status'] == 'rejected') ...[
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: AppColors.error.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.error.withOpacity(0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.cancel, color: AppColors.error),
                                const SizedBox(width: 10),
                                const Text('تم رفض هذا العرض', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
      ),
    );
  }
}
