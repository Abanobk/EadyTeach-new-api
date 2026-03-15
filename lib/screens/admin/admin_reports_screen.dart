import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';
import '../../services/api_service.dart';

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
                _reportItem(Icons.bar_chart, 'تقرير المبيعات الشهري', 'عرض إجمالي المبيعات لكل شهر', Colors.blue),
                const SizedBox(height: 10),
                _reportItem(Icons.people_outline, 'تقرير العملاء الجدد', 'عدد العملاء المسجلين هذا الشهر', Colors.green),
                const SizedBox(height: 10),
                _reportItem(Icons.build_outlined, 'تقرير أداء الفنيين', 'عدد المهام المنجزة لكل فني', Colors.orange),
                const SizedBox(height: 10),
                _reportItem(Icons.inventory_outlined, 'تقرير المخزون', 'المنتجات الأكثر مبيعاً', Colors.purple),
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

  Widget _reportItem(IconData icon, String title, String subtitle, Color color) {
    return Container(
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
    );
  }
}
