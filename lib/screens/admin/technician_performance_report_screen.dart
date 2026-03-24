import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';
import '../../services/api_service.dart';

/// تقرير أداء الفني التفصيلي — اختيار الفني ثم تحليل شامل
class TechnicianPerformanceReportScreen extends StatefulWidget {
  const TechnicianPerformanceReportScreen({super.key});

  @override
  State<TechnicianPerformanceReportScreen> createState() => _TechnicianPerformanceReportScreenState();
}

class _TechnicianPerformanceReportScreenState extends State<TechnicianPerformanceReportScreen> {
  List<Map<String, dynamic>> _technicians = [];
  Map<String, dynamic>? _selected;
  Map<String, dynamic>? _detail;
  bool _loadingList = true;
  bool _loadingDetail = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadTechnicians();
  }

  Future<void> _loadTechnicians() async {
    setState(() {
      _loadingList = true;
      _error = null;
      _detail = null;
    });
    try {
      final res = await ApiService.query('reports.technicianList');
      final rows = res['data']?['rows'] as List? ?? [];
      setState(() {
        _technicians = rows.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        _loadingList = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loadingList = false;
      });
    }
  }

  Future<void> _loadDetail(int techId) async {
    setState(() {
      _loadingDetail = true;
      _error = null;
    });
    try {
      final res = await ApiService.query('reports.technicianPerformanceDetail', input: {'technicianId': techId});
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

  void _onSelectTechnician(Map<String, dynamic> tech) {
    setState(() => _selected = tech);
    _loadDetail((tech['id'] as num).toInt());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeDecorations.pageBackground(context),
      appBar: AppBar(
        backgroundColor: AppThemeDecorations.cardColor(context),
        title: const Text('تقرير أداء الفني', style: TextStyle(color: AppColors.text)),
        iconTheme: const IconThemeData(color: AppColors.text),
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: AppColors.muted), onPressed: _loadTechnicians),
        ],
      ),
      body: _loadingList
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _sectionTitle('اختر الفني'),
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
                        hint: const Text('اختر فني للتحليل', style: TextStyle(color: AppColors.muted)),
                        dropdownColor: AppThemeDecorations.cardColor(context),
                        items: _technicians.map((t) {
                          return DropdownMenuItem(
                            value: t,
                            child: Text(
                              '${t['name'] ?? ''} (${t['totalTasks'] ?? 0} مهمة)',
                              style: const TextStyle(color: AppColors.text),
                            ),
                          );
                        }).toList(),
                        onChanged: (v) {
                          if (v != null) _onSelectTechnician(v);
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

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppThemeDecorations.cardColor(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Row(children: [
        Container(width: 44, height: 44, decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 22)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(value, style: const TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold)), Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 12))])),
      ]),
    );
  }

  Widget _buildDetailContent() {
    final d = _detail!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle('ملخص الأداء'),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(width: (MediaQuery.of(context).size.width - 44) / 2 - 6, child: _statCard('إجمالي المهام', '${d['totalAssigned'] ?? 0}', Icons.assignment, Colors.blue)),
            SizedBox(width: (MediaQuery.of(context).size.width - 44) / 2 - 6, child: _statCard('مكتملة', '${d['completed'] ?? 0}', Icons.check_circle, AppColors.success)),
            SizedBox(width: (MediaQuery.of(context).size.width - 44) / 2 - 6, child: _statCard('متأخرة حالياً', '${d['overdue'] ?? 0}', Icons.schedule, AppColors.warning)),
            SizedBox(width: (MediaQuery.of(context).size.width - 44) / 2 - 6, child: _statCard('أُنجزت متأخرة', '${d['delayedCompleted'] ?? 0}', Icons.warning_amber, Colors.orange)),
            SizedBox(width: (MediaQuery.of(context).size.width - 44) / 2 - 6, child: _statCard('في الموعد', '${d['onTimeCompleted'] ?? 0}', Icons.timelapse, Colors.teal)),
            SizedBox(width: (MediaQuery.of(context).size.width - 44) / 2 - 6, child: _statCard('ملغاة', '${d['cancelled'] ?? 0}', Icons.cancel, AppColors.muted)),
          ],
        ),
        const SizedBox(height: 20),
        _sectionTitle('التحليل الزمني'),
        const SizedBox(height: 12),
        _card([
          _row('نسبة الإنجاز في الموعد', '${d['onTimeRate'] ?? 0}%'),
          if (d['avgCompletionHours'] != null) _row('متوسط وقت الإنجاز (من التعيين لـ تم)', '${d['avgCompletionHours']} ساعة'),
          if (d['avgDelayHours'] != null) _row('متوسط التأخر عن الموعد عند الإنجاز', '${d['avgDelayHours']} ساعة'),
        ]),
        const SizedBox(height: 20),
        _sectionTitle('التحصيلات'),
        const SizedBox(height: 12),
        _statCard('إجمالي التحصيل من العملاء', '${_formatNum(d['totalCollections'])} ج.م', Icons.account_balance_wallet, Colors.indigo),
        const SizedBox(height: 20),
        _sectionTitle('آخر المهام'),
        const SizedBox(height: 12),
        ...((d['recentTasks'] as List?) ?? []).map<Widget>((t) {
          final task = Map<String, dynamic>.from(t as Map);
          final status = _statusLabel(task['status']);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _card([
              _row(task['title'] ?? 'مهمة', status, bold: true),
              if (task['completedAt'] != null) _row('تم الإنجاز', _formatDate(task['completedAt'])),
              if (task['amount'] != null && (task['amount'] as num) > 0) _row('المبلغ', '${_formatNum(task['amount'])} ج.م'),
            ]),
          );
        }),
      ],
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppThemeDecorations.cardColor(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: bold ? FontWeight.w600 : FontWeight.normal)),
        Text(value, style: TextStyle(color: AppColors.text, fontSize: 13, fontWeight: bold ? FontWeight.w600 : FontWeight.normal)),
      ]),
    );
  }

  String _statusLabel(String? s) {
    switch (s?.toLowerCase()) {
      case 'completed': return 'مكتملة';
      case 'cancelled': return 'ملغاة';
      case 'in_progress': return 'جاري العمل';
      case 'assigned': return 'معيّنة';
      case 'pending': return 'معلقة';
      default: return s ?? '';
    }
  }

  String _formatNum(dynamic n) {
    if (n == null) return '0';
    final x = n is num ? n.toDouble() : double.tryParse(n.toString()) ?? 0;
    return x.toStringAsFixed(x.truncateToDouble() == x ? 0 : 2);
  }

  String _formatDate(dynamic v) {
    if (v == null) return '';
    final s = v.toString();
    if (s.length >= 10) return s.substring(0, 10);
    return s;
  }
}
