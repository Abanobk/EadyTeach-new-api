import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';
import '../../services/api_service.dart';
import '../technician/task_detail_screen.dart';

/// تقرير تفصيلي للعميل — اختيار العميل ثم الطلبات والمهام والحالة الحالية
class CustomerDetailReportScreen extends StatefulWidget {
  const CustomerDetailReportScreen({super.key});

  @override
  State<CustomerDetailReportScreen> createState() => _CustomerDetailReportScreenState();
}

class _CustomerDetailReportScreenState extends State<CustomerDetailReportScreen> {
  List<Map<String, dynamic>> _customers = [];
  Map<String, dynamic>? _selected;
  Map<String, dynamic>? _detail;
  bool _loadingList = true;
  bool _loadingDetail = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  Future<void> _loadCustomers() async {
    setState(() {
      _loadingList = true;
      _error = null;
      _detail = null;
    });
    try {
      final res = await ApiService.query('reports.customerList');
      final rows = res['data']?['rows'] as List? ?? [];
      setState(() {
        _customers = rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loadingList = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loadingList = false;
      });
    }
  }

  Future<void> _loadDetail(int customerId) async {
    setState(() {
      _loadingDetail = true;
      _error = null;
    });
    try {
      final res = await ApiService.query('reports.customerDetail', input: {'customerId': customerId});
      setState(() {
        _detail = res['data'] as Map<String, dynamic>? ?? {};
        _loadingDetail = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loadingDetail = false;
      });
    }
  }

  void _onSelectCustomer(Map<String, dynamic> c) {
    setState(() => _selected = c);
    _loadDetail((c['id'] as num).toInt());
  }

  void _openTask(int taskId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TaskDetailScreen(task: {'id': taskId}),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeDecorations.pageBackground(context),
      appBar: AppBar(
        backgroundColor: AppThemeDecorations.cardColor(context),
        title: const Text('تقرير عميل', style: TextStyle(color: AppColors.text)),
        iconTheme: const IconThemeData(color: AppColors.text),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: AppColors.muted), onPressed: _loadCustomers),
        ],
      ),
      body: _loadingList
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionTitle('اختر العميل'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppThemeDecorations.cardColor(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<Map<String, dynamic>>(
                        value: _selected,
                        isExpanded: true,
                        hint: const Text('اختر عميل', style: TextStyle(color: AppColors.muted)),
                        dropdownColor: AppThemeDecorations.cardColor(context),
                        items: _customers.map((c) {
                          return DropdownMenuItem(
                            value: c,
                            child: Text(
                              '${c['name'] ?? ''} (${c['ordersCount'] ?? 0} طلب، ${c['tasksCount'] ?? 0} مهمة)',
                              style: const TextStyle(color: AppColors.text),
                            ),
                          );
                        }).toList(),
                        onChanged: (v) {
                          if (v != null) _onSelectCustomer(v);
                        },
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _errorCard(_error!),
                  ],
                  if (_selected != null && _loadingDetail) ...[
                    const SizedBox(height: 24),
                    const Center(child: CircularProgressIndicator(color: AppColors.primary)),
                  ],
                  if (_selected != null && _detail != null && !_loadingDetail) ...[
                    const SizedBox(height: 20),
                    _buildDetailContent(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(text, style: const TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.bold));
  }

  Widget _errorCard(String msg) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.error.withOpacity(0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.error)),
      child: Row(children: [
        const Icon(Icons.error_outline, color: AppColors.error, size: 24),
        const SizedBox(width: 12),
        Expanded(child: Text(msg, style: const TextStyle(color: AppColors.text))),
      ]),
    );
  }

  Widget _card({required List<Widget> children, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppThemeDecorations.cardColor(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ),
    );
  }

  Widget _buildDetailContent() {
    final d = _detail!;
    final customer = Map<String, dynamic>.from(d['customer'] as Map? ?? {});
    final orders = List<Map<String, dynamic>>.from((d['orders'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
    final tasks = List<Map<String, dynamic>>.from((d['tasks'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
    final lastTx = d['lastTransaction'] as Map<String, dynamic>?;
    final activeRequests = List<Map<String, dynamic>>.from((d['activeRequests'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card(children: [
          _row('الاسم', customer['name'] ?? ''),
          if ((customer['phone'] ?? '').toString().isNotEmpty) _row('الهاتف', customer['phone'].toString()),
          if ((customer['address'] ?? '').toString().isNotEmpty) _row('العنوان', customer['address'].toString()),
        ]),
        const SizedBox(height: 20),

        _sectionTitle('الطلبات (${orders.length})'),
        const SizedBox(height: 8),
        if (orders.isEmpty)
          _card(children: [const Text('لا توجد طلبات', style: TextStyle(color: AppColors.muted))])
        else
          ...orders.map((o) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _card(
                  onTap: () => _showOrderDetail(o),
                  children: [
                    _row('طلب #${o['id']}', _statusLabel(o['status'] ?? ''), bold: true),
                    _row('المبلغ', '${_formatNum(o['totalAmount'])} ج.م'),
                    if (o['createdAt'] != null) _row('التاريخ', _formatDate(o['createdAt'])),
                  ],
                ),
              )),
        const SizedBox(height: 20),

        _sectionTitle('المهام (${tasks.length})'),
        const SizedBox(height: 8),
        if (tasks.isEmpty)
          _card(children: [const Text('لا توجد مهام', style: TextStyle(color: AppColors.muted))])
        else
          ...tasks.map((t) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _card(
                  onTap: () => _openTask((t['id'] as num).toInt()),
                  children: [
                    _row(t['title'] ?? 'مهمة', _taskStatusLabel(t['status'] ?? ''), bold: true),
                    if ((t['technicianName'] ?? '').toString().isNotEmpty) _row('الفني', t['technicianName'].toString()),
                    if ((t['amount'] ?? 0) != 0) _row('المبلغ', '${_formatNum(t['amount'])} ج.م'),
                    if (t['scheduledAt'] != null) _row('الموعد', t['scheduledAt'].toString().substring(0, 16)),
                  ],
                ),
              )),
        const SizedBox(height: 20),

        _sectionTitle('آخر معاملة'),
        const SizedBox(height: 8),
        if (lastTx == null)
          _card(children: [const Text('لا توجد معاملات', style: TextStyle(color: AppColors.muted))])
        else
          _card(
            onTap: () {
              final type = lastTx['type'] ?? '';
              final data = lastTx['data'] as Map<String, dynamic>? ?? {};
              if (type == 'task') {
                _openTask((data['id'] as num?)?.toInt() ?? 0);
              } else {
                _showOrderDetail(data);
              }
            },
            children: [
              _row('النوع', lastTx['type'] == 'task' ? 'مهمة' : 'طلب', bold: true),
              if (lastTx['type'] == 'task') ...[
                _row('العنوان', (lastTx['data'] as Map?)?['title']?.toString() ?? 'مهمة'),
                _row('الحالة', _taskStatusLabel((lastTx['data'] as Map?)?['status']?.toString() ?? '')),
              ] else ...[
                _row('طلب', '#${(lastTx['data'] as Map?)?['id']}'),
                _row('المبلغ', '${_formatNum((lastTx['data'] as Map?)?['totalAmount'])} ج.م'),
              ],
            ],
          ),
        const SizedBox(height: 20),

        _sectionTitle('حالة العميل'),
        const SizedBox(height: 8),
        if (activeRequests.isEmpty)
          _card(children: [
            Row(children: [
              Icon(Icons.check_circle, color: AppColors.success, size: 24),
              const SizedBox(width: 12),
              const Text('لا يوجد طلب حالياً', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
            ]),
          ])
        else
          _card(
            onTap: () => _showActiveRequests(activeRequests),
            children: [
              Row(children: [
                Icon(Icons.pending_actions, color: AppColors.warning, size: 24),
                const SizedBox(width: 12),
                Text('لديه ${activeRequests.length} طلب/مهمة قيد التنفيذ', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 8),
              ...activeRequests.take(3).map((r) => Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(children: [
                      Icon(r['type'] == 'task' ? Icons.build : Icons.shopping_cart, size: 16, color: AppColors.muted),
                      const SizedBox(width: 8),
                      Expanded(child: Text(r['type'] == 'task' ? (r['data']?['title'] ?? 'مهمة') : 'طلب #${r['data']?['id']}', style: const TextStyle(color: AppColors.muted, fontSize: 12))),
                    ]),
                  )),
            ],
          ),
      ],
    );
  }

  void _showOrderDetail(Map<String, dynamic> order) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppThemeDecorations.cardColor(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, controller) => SingleChildScrollView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(width: 40, height: 4, color: AppColors.muted)),
              const SizedBox(height: 16),
              Text('طلب #${order['id']}', style: const TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _row('الحالة', _statusLabel(order['status'] ?? '')),
              _row('المبلغ', '${_formatNum(order['totalAmount'])} ج.م'),
              if (order['createdAt'] != null) _row('التاريخ', _formatDate(order['createdAt'])),
              if ((order['shippingAddress'] ?? '').toString().isNotEmpty) _row('العنوان', order['shippingAddress'].toString()),
              const Divider(height: 24),
              const Text('العناصر', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              ...((order['items'] as List?) ?? []).map<Widget>((i) {
                final it = Map<String, dynamic>.from(i as Map);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• ${it['productId'] ?? ''} × ${it['quantity'] ?? 1} — ${it['unitPrice'] ?? ''} ج.م', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _showActiveRequests(List<Map<String, dynamic>> requests) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppThemeDecorations.cardColor(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.all(20),
          children: [
            Center(child: Container(width: 40, height: 4, color: AppColors.muted)),
            const SizedBox(height: 16),
            const Text('الطلبات والمهام الحالية', style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ...requests.map((r) {
              final type = r['type'] ?? '';
              final data = Map<String, dynamic>.from(r['data'] as Map? ?? {});
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: InkWell(
                  onTap: () {
                    Navigator.pop(ctx);
                    if (type == 'task') {
                      _openTask((data['id'] as num?)?.toInt() ?? 0);
                    } else {
                      _showOrderDetail(data);
                    }
                  },
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(12)),
                    child: Row(children: [
                      Icon(type == 'task' ? Icons.build : Icons.shopping_cart, color: AppColors.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(type == 'task' ? (data['title'] ?? 'مهمة') : 'طلب #${data['id']}', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600)),
                          Text(type == 'task' ? _taskStatusLabel(data['status'] ?? '') : _statusLabel(data['status'] ?? ''), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                        ]),
                      ),
                      const Icon(Icons.arrow_back_ios, size: 14, color: AppColors.muted),
                    ]),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: bold ? FontWeight.w600 : FontWeight.normal)),
        Expanded(child: Text(value, textAlign: TextAlign.end, style: TextStyle(color: AppColors.text, fontSize: 13, fontWeight: bold ? FontWeight.w600 : FontWeight.normal))),
      ]),
    );
  }

  String _statusLabel(String s) {
    switch (s.toLowerCase()) {
      case 'pending': return 'انتظار';
      case 'confirmed': return 'مؤكد';
      case 'processing': return 'جاري';
      case 'delivered': return 'مُسلَّم';
      case 'cancelled': return 'ملغي';
      default: return s;
    }
  }

  String _taskStatusLabel(String s) {
    switch (s.toLowerCase()) {
      case 'completed': return 'مكتملة';
      case 'cancelled': return 'ملغاة';
      case 'in_progress': return 'جاري العمل';
      case 'assigned': return 'معيّنة';
      case 'pending': return 'معلقة';
      default: return s;
    }
  }

  String _formatNum(dynamic n) {
    if (n == null) return '0';
    final x = n is num ? n.toDouble() : double.tryParse(n.toString()) ?? 0;
    return x.toStringAsFixed(x.truncateToDouble() == x ? 0 : 2);
  }

  String _formatDate(dynamic v) {
    if (v == null) return '';
    final ms = v is int ? v : int.tryParse(v.toString());
    if (ms == null) return v.toString();
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.day}/${d.month}/${d.year}';
  }
}
