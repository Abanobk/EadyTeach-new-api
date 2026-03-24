import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';
import '../../services/api_service.dart';

/// نوع التقرير
enum ReportType {
  monthlySales,
  newCustomers,
  technicianPerformance,
  topProducts,
  customerSummary,
  customerAccounts,
  customerRevenue,
}

class AdminReportDetailScreen extends StatefulWidget {
  final ReportType type;
  final String title;

  const AdminReportDetailScreen({
    super.key,
    required this.type,
    required this.title,
  });

  @override
  State<AdminReportDetailScreen> createState() => _AdminReportDetailScreenState();
}

class _AdminReportDetailScreenState extends State<AdminReportDetailScreen> {
  List<dynamic> _rows = [];
  bool _loading = true;
  String? _error;

  String get _procedure {
    switch (widget.type) {
      case ReportType.monthlySales:
        return 'reports.monthlySales';
      case ReportType.newCustomers:
        return 'reports.newCustomers';
      case ReportType.technicianPerformance:
        return 'reports.technicianPerformance';
      case ReportType.topProducts:
        return 'reports.topProducts';
      case ReportType.customerSummary:
        return 'reports.customerSummary';
      case ReportType.customerAccounts:
        return 'reports.customerAccounts';
      case ReportType.customerRevenue:
        return 'reports.customerRevenue';
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService.query(_procedure);
      final rows = res['data']?['rows'] as List? ?? [];
      setState(() {
        _rows = rows;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeDecorations.pageBackground(context),
      appBar: AppBar(
        backgroundColor: AppThemeDecorations.cardColor(context),
        title: Text(widget.title, style: const TextStyle(color: AppColors.text)),
        iconTheme: const IconThemeData(color: AppColors.text),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.muted),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 48, color: AppColors.error),
                        const SizedBox(height: 16),
                        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.muted)),
                        const SizedBox(height: 16),
                        TextButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  ),
                )
              : _rows.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.inbox_outlined, size: 64, color: AppColors.muted.withOpacity(0.5)),
                          const SizedBox(height: 16),
                          Text('لا توجد بيانات', style: TextStyle(color: AppColors.muted, fontSize: 16)),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _rows.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => _buildRowCard(_rows[i]),
                    ),
    );
  }

  Widget _buildRowCard(Map<String, dynamic> row) {
    switch (widget.type) {
      case ReportType.monthlySales:
        return _card([
          _rowText('${row['monthName'] ?? ''} ${row['year'] ?? ''}', bold: true),
          _rowText('عدد الطلبات: ${row['count'] ?? 0}'),
          _rowText('الإجمالي: ${_formatNum(row['total'])} ج.م'),
        ]);
      case ReportType.newCustomers:
        return _card([
          _rowText('${row['monthName'] ?? ''} ${row['year'] ?? ''}', bold: true),
          _rowText('عدد العملاء: ${row['count'] ?? 0}'),
        ]);
      case ReportType.technicianPerformance:
        return _card([
          _rowText(row['technicianName'] ?? 'غير معروف', bold: true),
          _rowText('المهام المنجزة: ${row['completedCount'] ?? 0}'),
        ]);
      case ReportType.topProducts:
        return _card([
          _rowText(row['productName'] ?? 'غير معروف', bold: true),
          _rowText('الكمية المباعة: ${row['soldCount'] ?? 0}'),
          if ((row['price'] ?? 0) > 0) _rowText('السعر: ${_formatNum(row['price'])} ج.م'),
        ]);
      case ReportType.customerSummary:
        return _card([
          _rowText(row['customerName'] ?? 'غير معروف', bold: true),
          if ((row['phone'] ?? '').toString().isNotEmpty) _rowText('هاتف: ${row['phone']}'),
          _rowText('الطلبات: ${row['ordersCount'] ?? 0} — إجمالي: ${_formatNum(row['ordersTotal'])} ج.م'),
          _rowText('المهام: ${row['tasksCount'] ?? 0} — إجمالي: ${_formatNum(row['tasksTotal'])} ج.م'),
          _rowText('الإجمالي الكلي: ${_formatNum(row['totalRevenue'])} ج.م'),
        ]);
      case ReportType.customerAccounts:
        return _card([
          _rowText(row['customerName'] ?? 'غير معروف', bold: true),
          if ((row['phone'] ?? '').toString().isNotEmpty) _rowText('هاتف: ${row['phone']}'),
          _rowText('المستحق: ${_formatNum(row['dueTotal'])} ج.م'),
          _rowText('تم تحصيله: ${_formatNum(row['collectedTotal'])} ج.م'),
          _rowText('المتبقي: ${_formatNum(row['balance'])} ج.م', bold: true),
        ]);
      case ReportType.customerRevenue:
        return _card([
          _rowText(row['customerName'] ?? 'غير معروف', bold: true),
          if ((row['phone'] ?? '').toString().isNotEmpty) _rowText('هاتف: ${row['phone']}'),
          _rowText('من الطلبات: ${_formatNum(row['ordersTotal'])} ج.م'),
          _rowText('من المهام: ${_formatNum(row['tasksTotal'])} ج.م'),
          _rowText('إجمالي الإيرادات: ${_formatNum(row['totalRevenue'])} ج.م', bold: true),
        ]);
    }
  }

  Widget _card(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeDecorations.cardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _rowText(String text, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        text,
        style: TextStyle(
          color: AppColors.text,
          fontSize: 14,
          fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }

  String _formatNum(dynamic n) {
    if (n == null) return '0';
    final x = n is num ? n.toDouble() : double.tryParse(n.toString()) ?? 0;
    return x.toStringAsFixed(x.truncateToDouble() == x ? 0 : 2);
  }
}
