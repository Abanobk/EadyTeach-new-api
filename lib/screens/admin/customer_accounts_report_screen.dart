import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';
import '../../services/api_service.dart';
import '../technician/task_detail_screen.dart';

/// تقرير حسابات العملاء — فهرس العملاء (من عليه بالأحمر) + كشف حساب كامل
class CustomerAccountsReportScreen extends StatefulWidget {
  const CustomerAccountsReportScreen({super.key});

  @override
  State<CustomerAccountsReportScreen> createState() => _CustomerAccountsReportScreenState();
}

class _CustomerAccountsReportScreenState extends State<CustomerAccountsReportScreen> {
  List<Map<String, dynamic>> _customers = [];
  Map<String, dynamic>? _selected;
  Map<String, dynamic>? _statement;
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
      _statement = null;
    });
    try {
      final res = await ApiService.query('reports.customerAccountsList');
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

  Future<void> _loadStatement(int customerId) async {
    setState(() {
      _loadingDetail = true;
      _error = null;
    });
    try {
      final res = await ApiService.query('reports.customerAccountStatement', input: {'customerId': customerId});
      setState(() {
        _statement = res['data'] as Map<String, dynamic>? ?? {};
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
    _loadStatement((c['customerId'] as num?)?.toInt() ?? (c['id'] as num?)?.toInt() ?? 0);
  }

  void _openTask(int taskId) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => TaskDetailScreen(task: {'id': taskId})),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeDecorations.pageBackground(context),
      appBar: AppBar(
        backgroundColor: AppThemeDecorations.cardColor(context),
        title: const Text('حسابات العملاء', style: TextStyle(color: AppColors.text)),
        iconTheme: const IconThemeData(color: AppColors.text),
        actions: [IconButton(icon: const Icon(Icons.refresh, color: AppColors.muted), onPressed: _loadCustomers)],
      ),
      body: _loadingList
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_error != null) _errorCard(_error!),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _sectionTitle('اختر العميل أو التاجر'),
                        const SizedBox(height: 8),
                        _buildCustomerIndex(),
                        if (_selected != null && _loadingDetail) ...[
                          const SizedBox(height: 24),
                          const Center(child: CircularProgressIndicator(color: AppColors.primary)),
                        ],
                        if (_selected != null && _statement != null && !_loadingDetail) ...[
                          const SizedBox(height: 20),
                          _buildStatement(),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(text, style: const TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.bold));
  }

  Widget _errorCard(String msg) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.error.withOpacity(0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.error)),
      child: Row(children: [
        const Icon(Icons.error_outline, color: AppColors.error, size: 24),
        const SizedBox(width: 12),
        Expanded(child: Text(msg, style: const TextStyle(color: AppColors.text))),
      ]),
    );
  }

  Widget _buildCustomerIndex() {
    return Column(
      children: _customers.map((c) {
        final balance = (c['balance'] as num?)?.toDouble() ?? 0;
        final hasDebt = balance > 0;
        final custId = (c['customerId'] as num?)?.toInt() ?? (c['id'] as num?)?.toInt() ?? 0;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: InkWell(
            onTap: () => _onSelectCustomer({...c, 'id': custId, 'customerId': custId}),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppThemeDecorations.cardColor(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: hasDebt ? AppColors.error : AppColors.border, width: hasDebt ? 2 : 1),
              ),
              child: Row(children: [
                Container(
                  width: 8,
                  height: 40,
                  decoration: BoxDecoration(
                    color: hasDebt ? AppColors.error : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(c['customerName'] ?? '', style: TextStyle(color: hasDebt ? AppColors.error : AppColors.text, fontWeight: FontWeight.w600, fontSize: 15)),
                    if ((c['phone'] ?? '').toString().isNotEmpty)
                      Text(c['phone'].toString(), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  ]),
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('${_formatNum(balance)} ج.م', style: TextStyle(color: hasDebt ? AppColors.error : AppColors.text, fontWeight: FontWeight.bold, fontSize: 14)),
                  if (hasDebt) Text('عليه', style: TextStyle(color: AppColors.error, fontSize: 11, fontWeight: FontWeight.w600)),
                ]),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_back_ios, color: AppColors.muted, size: 14),
              ]),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildStatement() {
    final s = _statement!;
    final customer = Map<String, dynamic>.from(s['customer'] as Map? ?? {});
    final orders = List<Map<String, dynamic>>.from((s['orders'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
    final tasks = List<Map<String, dynamic>>.from((s['tasks'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
    final collections = List<Map<String, dynamic>>.from((s['collections'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)));
    final ordersOwed = (s['ordersOwed'] as num?)?.toDouble() ?? 0;
    final tasksDue = (s['tasksDue'] as num?)?.toDouble() ?? 0;
    final collectedTotal = (s['collectedTotal'] as num?)?.toDouble() ?? 0;
    final balance = (s['balance'] as num?)?.toDouble() ?? 0;
    final hasDebt = balance > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _card([
          _row('العميل', customer['name'] ?? '', bold: true),
          if ((customer['phone'] ?? '').toString().isNotEmpty) _row('الهاتف', customer['phone'].toString()),
        ]),
        const SizedBox(height: 16),
        _sectionTitle('طلبات بضاعة'),
        const SizedBox(height: 8),
        if (orders.isEmpty)
          _card([const Text('لا توجد طلبات', style: TextStyle(color: AppColors.muted))])
        else
          ...orders.map((o) => _card([
                _row('طلب #${o['id']}', _statusLabel(o['status'] ?? ''), bold: true),
                _row('المبلغ', '${_formatNum(o['totalAmount'])} ج.م'),
                if (o['createdAt'] != null) _row('التاريخ', _formatDate(o['createdAt'])),
              ])),
        const SizedBox(height: 16),
        _sectionTitle('طلبات مهام'),
        const SizedBox(height: 8),
        if (tasks.isEmpty)
          _card([const Text('لا توجد مهام', style: TextStyle(color: AppColors.muted))])
        else
          ...tasks.map((t) => InkWell(
                onTap: () => _openTask((t['id'] as num).toInt()),
                borderRadius: BorderRadius.circular(12),
                child: _card([
                  _row(t['title'] ?? 'مهمة', _taskStatusLabel(t['status'] ?? ''), bold: true),
                  _row('المبلغ', '${_formatNum(t['amount'])} ج.م'),
                  if (t['technicianName'] != null) _row('الفني', t['technicianName'].toString()),
                ]),
              )),
        const SizedBox(height: 16),
        _sectionTitle('التحصيلات (دفع)'),
        const SizedBox(height: 8),
        if (collections.isEmpty)
          _card([const Text('لا توجد تحصيلات', style: TextStyle(color: AppColors.muted))])
        else
          ...collections.map((c) => _card([
                _row('مبلغ', '${_formatNum(c['amount'])} ج.م', bold: true),
                if (c['taskTitle'] != null) _row('المهمة', c['taskTitle'].toString()),
                if (c['createdAt'] != null) _row('التاريخ', _formatDate(c['createdAt'])),
              ])),
        const SizedBox(height: 20),
        _sectionTitle('الملخص والرصيد'),
        const SizedBox(height: 8),
        _card([
          _row('عليه من الطلبات', '${_formatNum(ordersOwed)} ج.م'),
          _row('عليه من المهام', '${_formatNum(tasksDue)} ج.م'),
          _row('تم تحصيله', '${_formatNum(collectedTotal)} ج.م'),
          const Divider(height: 20),
          _row('الرصيد النهائي', '${_formatNum(balance)} ج.م', bold: true),
        ]),
        if (hasDebt)
          Container(
            margin: const EdgeInsets.only(top: 16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: AppColors.error.withOpacity(0.2), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.error, width: 2)),
            child: Row(children: [
              const Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 32),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('عليه فلوس', style: TextStyle(color: AppColors.error, fontWeight: FontWeight.bold, fontSize: 16)),
                  Text('${_formatNum(balance)} ج.م', style: const TextStyle(color: AppColors.error, fontSize: 18, fontWeight: FontWeight.w900)),
                ]),
              ),
            ]),
          ),
      ],
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(color: AppThemeDecorations.cardColor(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
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
