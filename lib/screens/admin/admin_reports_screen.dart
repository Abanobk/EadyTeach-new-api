import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';
import '../../services/api_service.dart';
import 'admin_report_detail_screen.dart';
import 'technician_performance_report_screen.dart';
import 'customer_detail_report_screen.dart';
import 'customer_accounts_report_screen.dart';

class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});
  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  Map<String, dynamic>? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.query('admin.getDashboardStats');
      setState(() => _stats = res['data']);
    } catch (_) {}
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeDecorations.pageBackground(context),
      appBar: AppBar(
        backgroundColor: AppThemeDecorations.cardColor(context),
        title: const Text('التقارير', style: TextStyle(color: AppColors.text)),
        iconTheme: const IconThemeData(color: AppColors.text),
        actions: [IconButton(icon: const Icon(Icons.refresh, color: AppColors.muted), onPressed: _load)],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('ملخص الأداء', style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                GridView.count(crossAxisCount: 2, shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.4, children: [
                  _statCard('إجمالي الطلبات', '${_stats?['totalOrders'] ?? 0}', Icons.receipt_long, Colors.blue),
                  _statCard('العملاء', '${_stats?['totalCustomers'] ?? 0}', Icons.people, Colors.green),
                  _statCard('المنتجات', '${_stats?['totalProducts'] ?? 0}', Icons.inventory_2, Colors.orange),
                  _statCard('المهام', '${_stats?['totalTasks'] ?? 0}', Icons.build, Colors.purple),
                ]),
                const SizedBox(height: 20),
                const Text('تقارير تفصيلية', style: TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                _reportItem(context, Icons.bar_chart, 'تقرير المبيعات الشهري', 'عرض إجمالي المبيعات لكل شهر', Colors.blue, ReportType.monthlySales),
                const SizedBox(height: 10),
                _reportItem(context, Icons.people_outline, 'تقرير العملاء الجدد', 'عدد العملاء المسجلين كل شهر', Colors.green, ReportType.newCustomers),
                const SizedBox(height: 10),
                _reportItemTechnician(context),
                const SizedBox(height: 10),
                _reportItem(context, Icons.inventory_outlined, 'تقرير المنتجات الأكثر مبيعاً', 'المنتجات الأكثر مبيعاً', Colors.purple, ReportType.topProducts),
                const SizedBox(height: 10),
                _reportItemCustomer(context),
                const SizedBox(height: 10),
                _reportItemCustomerAccounts(context),
                const SizedBox(height: 10),
                _reportItem(context, Icons.trending_up, 'تقرير إيرادات العملاء', 'ترتيب العملاء حسب الإنفاق', Colors.deepOrange, ReportType.customerRevenue),
              ]),
            ),
    );
  }

  Widget _statCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppThemeDecorations.cardColor(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Container(width: 32, height: 32, decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: color, size: 18)),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: const TextStyle(color: AppColors.text, fontSize: 22, fontWeight: FontWeight.w900)),
          Text(title, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
        ]),
      ]),
    );
  }

  Widget _reportItemCustomerAccounts(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const CustomerAccountsReportScreen()),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppThemeDecorations.cardColor(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
        child: Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.indigo.withOpacity(0.15), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.account_balance_wallet_outlined, color: Colors.indigo, size: 20)),
          const SizedBox(width: 12),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('تقرير حسابات العملاء', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 14)),
            Text('فهرس العملاء، كشف حساب كامل، من عليه بالأحمر', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ])),
          const Icon(Icons.arrow_back_ios, color: AppColors.muted, size: 14),
        ]),
      ),
    );
  }

  Widget _reportItemCustomer(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const CustomerDetailReportScreen(),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppThemeDecorations.cardColor(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
        child: Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.teal.withOpacity(0.15), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.people, color: Colors.teal, size: 20)),
          const SizedBox(width: 12),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('تقرير إجمالي العملاء', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 14)),
            Text('اختر عميلاً واعرض الطلبات والمهام والتفاصيل', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ])),
          const Icon(Icons.arrow_back_ios, color: AppColors.muted, size: 14),
        ]),
      ),
    );
  }

  Widget _reportItemTechnician(BuildContext context) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const TechnicianPerformanceReportScreen(),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppThemeDecorations.cardColor(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
        child: Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: Colors.orange.withOpacity(0.15), borderRadius: BorderRadius.circular(10)), child: const Icon(Icons.build_outlined, color: Colors.orange, size: 20)),
          const SizedBox(width: 12),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('تقرير أداء الفنيين', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 14)),
            Text('تحليل شامل: المهام، التأخير، وقت الإنجاز', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          ])),
          const Icon(Icons.arrow_back_ios, color: AppColors.muted, size: 14),
        ]),
      ),
    );
  }

  Widget _reportItem(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    Color color,
    ReportType type,
  ) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => AdminReportDetailScreen(type: type, title: title),
          ),
        );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppThemeDecorations.cardColor(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
        child: Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 20)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 14)),
            Text(subtitle, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ])),
          const Icon(Icons.arrow_back_ios, color: AppColors.muted, size: 14),
        ]),
      ),
    );
  }
}
