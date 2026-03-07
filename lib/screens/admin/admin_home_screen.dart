import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../utils/app_theme.dart';
import 'admin_orders_screen.dart';
import 'admin_customers_screen.dart';
import 'admin_products_screen.dart';
import 'admin_tasks_screen.dart';
import 'admin_crm_screen.dart';
import 'admin_notifications_screen.dart';
import 'admin_secretary_screen.dart';
import 'admin_categories_screen.dart';
import 'admin_inbox_screen.dart';
import 'admin_permissions_screen.dart';
import 'admin_reports_screen.dart';
import 'admin_quotations_screen.dart';

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});
  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _selectedIndex = 0;
  Map<String, dynamic>? _stats;
  bool _loadingStats = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loadingStats = true);
    try {
      final res = await ApiService.query('admin.getDashboardStats');
      setState(() {
        _stats = res['data'];
        _loadingStats = false;
      });
    } catch (e) {
      setState(() => _loadingStats = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final screens = [
      _buildDashboard(auth),
      const AdminOrdersScreen(),
      const AdminCustomersScreen(),
      const AdminProductsScreen(),
      const AdminTasksScreen(),
    ];
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        drawer: _buildDrawer(context, auth),
        body: screens[_selectedIndex],
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (i) => setState(() => _selectedIndex = i),
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard_outlined), label: 'الرئيسية'),
            BottomNavigationBarItem(icon: Icon(Icons.receipt_long_outlined), label: 'الطلبات'),
            BottomNavigationBarItem(icon: Icon(Icons.people_outline), label: 'العملاء'),
            BottomNavigationBarItem(icon: Icon(Icons.inventory_2_outlined), label: 'المنتجات'),
            BottomNavigationBarItem(icon: Icon(Icons.build_outlined), label: 'المهام'),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer(BuildContext context, AuthProvider auth) {
    return Drawer(
      backgroundColor: AppColors.card,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.bg,
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 48, height: 48,
                    decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.admin_panel_settings, color: AppColors.primary, size: 26),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(auth.user?.name ?? 'المسؤول', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 15)),
                    const Text('لوحة التحكم', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  ])),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _drawerSection('الأنظمة الرئيسية'),
                  _drawerItem(context, Icons.dashboard_outlined, 'لوحة التحكم', () { Navigator.pop(context); setState(() => _selectedIndex = 0); }),
                  _drawerItem(context, Icons.receipt_long_outlined, 'إدارة الطلبات', () { Navigator.pop(context); setState(() => _selectedIndex = 1); }),
                  _drawerItem(context, Icons.people_outline, 'إدارة العملاء', () { Navigator.pop(context); setState(() => _selectedIndex = 2); }),
                  _drawerItem(context, Icons.inventory_2_outlined, 'إدارة المنتجات', () { Navigator.pop(context); setState(() => _selectedIndex = 3); }),
                  _drawerItem(context, Icons.build_outlined, 'إدارة المهام', () { Navigator.pop(context); setState(() => _selectedIndex = 4); }),
                  const Divider(color: AppColors.border, height: 24),
                  _drawerSection('أنظمة متقدمة'),
                  _drawerItem(context, Icons.request_quote_outlined, 'عروض الأسعار', () { Navigator.pop(context); _navigate(context, const AdminQuotationsScreen()); }, color: Colors.amber),
                  _drawerItem(context, Icons.category_outlined, 'التصنيفات', () { Navigator.pop(context); _navigate(context, const AdminCategoriesScreen()); }, color: Colors.teal),
                  _drawerItem(context, Icons.people_alt_outlined, 'نظام CRM', () { Navigator.pop(context); _navigate(context, const AdminCrmScreen()); }, color: Colors.indigo),
                  _drawerItem(context, Icons.inbox_outlined, 'صندوق الرسائل', () { Navigator.pop(context); _navigate(context, const AdminInboxScreen()); }, color: Colors.blue),
                  _drawerItem(context, Icons.notifications_outlined, 'الإشعارات', () { Navigator.pop(context); _navigate(context, const AdminNotificationsScreen()); }, color: Colors.orange),
                  _drawerItem(context, Icons.calendar_month_outlined, 'السكرتارية', () { Navigator.pop(context); _navigate(context, const AdminSecretaryScreen()); }, color: Colors.pink),
                  _drawerItem(context, Icons.bar_chart_outlined, 'التقارير', () { Navigator.pop(context); _navigate(context, const AdminReportsScreen()); }, color: Colors.green),
                  _drawerItem(context, Icons.admin_panel_settings_outlined, 'الصلاحيات', () { Navigator.pop(context); _navigate(context, const AdminPermissionsScreen()); }, color: Colors.red),
                  const Divider(color: AppColors.border, height: 24),
                  _drawerItem(context, Icons.logout, 'تسجيل الخروج', () async {
                    Navigator.pop(context);
                    await ApiService.clearCookie();
                    final authProvider = context.read<AuthProvider>();
                    authProvider.logout();
                    if (context.mounted) Navigator.pushReplacementNamed(context, '/login');
                  }, color: Colors.red),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigate(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => Directionality(textDirection: TextDirection.rtl, child: screen)));
  }

  Widget _drawerSection(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(title, style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.5)),
    );
  }

  Widget _drawerItem(BuildContext context, IconData icon, String title, VoidCallback onTap, {Color? color}) {
    final c = color ?? AppColors.primary;
    return ListTile(
      leading: Container(width: 36, height: 36, decoration: BoxDecoration(color: c.withOpacity(0.12), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: c, size: 18)),
      title: Text(title, style: const TextStyle(color: AppColors.text, fontSize: 14)),
      onTap: onTap,
      dense: true,
      horizontalTitleGap: 10,
    );
  }

  Widget _buildDashboard(AuthProvider auth) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          backgroundColor: AppColors.card,
          floating: true,
          leading: Builder(builder: (ctx) => IconButton(icon: const Icon(Icons.menu, color: AppColors.text), onPressed: () => Scaffold.of(ctx).openDrawer())),
          title: const Text('لوحة التحكم', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
          actions: [
            Container(
              margin: const EdgeInsets.only(left: 12, top: 8, bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
              child: Text(auth.user?.name ?? 'مسؤول', style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('نظرة عامة', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 12),
                if (_loadingStats)
                  const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(color: AppColors.primary)))
                else
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.3,
                    children: [
                      _StatCard(title: 'الطلبات', value: '${_stats?['totalOrders'] ?? 0}', icon: Icons.receipt_long_outlined, color: const Color(0xFF1565C0)),
                      _StatCard(title: 'العملاء', value: '${_stats?['totalCustomers'] ?? 0}', icon: Icons.people_outline, color: const Color(0xFF2E7D32)),
                      _StatCard(title: 'المنتجات', value: '${_stats?['totalProducts'] ?? 0}', icon: Icons.inventory_2_outlined, color: const Color(0xFFE65100)),
                      _StatCard(title: 'المهام', value: '${_stats?['totalTasks'] ?? 0}', icon: Icons.build_outlined, color: const Color(0xFF6A1B9A)),
                    ],
                  ),
                const SizedBox(height: 24),
                const Text('الأنظمة المتقدمة', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 12),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  childAspectRatio: 0.9,
                  children: [
                    _SystemCard(icon: Icons.category_outlined, label: 'التصنيفات', color: Colors.teal, onTap: () => _navigate(context, const AdminCategoriesScreen())),
                    _SystemCard(icon: Icons.people_alt_outlined, label: 'CRM', color: Colors.indigo, onTap: () => _navigate(context, const AdminCrmScreen())),
                    _SystemCard(icon: Icons.inbox_outlined, label: 'الرسائل', color: Colors.blue, onTap: () => _navigate(context, const AdminInboxScreen())),
                    _SystemCard(icon: Icons.notifications_outlined, label: 'الإشعارات', color: Colors.orange, onTap: () => _navigate(context, const AdminNotificationsScreen())),
                    _SystemCard(icon: Icons.calendar_month_outlined, label: 'السكرتارية', color: Colors.pink, onTap: () => _navigate(context, const AdminSecretaryScreen())),
                    _SystemCard(icon: Icons.bar_chart_outlined, label: 'التقارير', color: Colors.green, onTap: () => _navigate(context, const AdminReportsScreen())),
                    _SystemCard(icon: Icons.admin_panel_settings_outlined, label: 'الصلاحيات', color: Colors.red, onTap: () => _navigate(context, const AdminPermissionsScreen())),
                    _SystemCard(icon: Icons.request_quote_outlined, label: 'عروض الأسعار', color: Colors.amber, onTap: () => _navigate(context, const AdminQuotationsScreen())),
                  ],
                ),
                const SizedBox(height: 24),
                const Text('الإجراءات السريعة', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 18)),
                const SizedBox(height: 12),
                _QuickAction(icon: Icons.receipt_long_outlined, title: 'إدارة الطلبات', subtitle: 'عرض وتحديث حالة الطلبات', onTap: () => setState(() => _selectedIndex = 1)),
                const SizedBox(height: 8),
                _QuickAction(icon: Icons.people_outline, title: 'إدارة العملاء', subtitle: 'عرض وتعديل بيانات العملاء', onTap: () => setState(() => _selectedIndex = 2)),
                const SizedBox(height: 8),
                _QuickAction(icon: Icons.inventory_2_outlined, title: 'إدارة المنتجات', subtitle: 'إضافة وتعديل المنتجات', onTap: () => setState(() => _selectedIndex = 3)),
                const SizedBox(height: 8),
                _QuickAction(icon: Icons.build_outlined, title: 'إدارة المهام', subtitle: 'توزيع المهام على الفنيين', onTap: () => setState(() => _selectedIndex = 4)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _SystemCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _SystemCard({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 22)),
          const SizedBox(height: 8),
          Text(label, style: const TextStyle(color: AppColors.text, fontSize: 12, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard({required this.title, required this.value, required this.icon, required this.color});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Container(width: 36, height: 36, decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(8)), child: Icon(icon, color: color, size: 20)),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: const TextStyle(color: AppColors.text, fontSize: 24, fontWeight: FontWeight.w900)),
          Text(title, style: const TextStyle(color: AppColors.muted, fontSize: 12)),
        ]),
      ]),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _QuickAction({required this.icon, required this.title, required this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
        child: Row(children: [
          Container(width: 40, height: 40, decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: AppColors.primary, size: 20)),
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
