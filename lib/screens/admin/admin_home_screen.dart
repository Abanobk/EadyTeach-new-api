import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../modules/survey/screens/survey_entry_screen.dart';
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
import 'admin_accounting_screen.dart';

/// السايدبار مندمج مع الثيم — ألوان من الثيم مع لمسة برتقالية للعنصر النشط

class AdminHomeScreen extends StatefulWidget {
  const AdminHomeScreen({super.key});
  @override
  State<AdminHomeScreen> createState() => _AdminHomeScreenState();
}

class _AdminHomeScreenState extends State<AdminHomeScreen> {
  int _selectedIndex = 0;
  Map<String, dynamic>? _stats;
  bool _loadingStats = true;
  int _unreadNotifs = 0;
  bool _sidebarExpanded = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadUnreadCount();
  }

  Future<void> _loadUnreadCount() async {
    try {
      final res = await ApiService.query('notifications.getUnreadCount');
      final raw = res['data'];
      int count = 0;
      if (raw is int) count = raw;
      else if (raw is Map) count = (raw['count'] is int) ? raw['count'] : int.tryParse('${raw['count']}') ?? 0;
      if (mounted) setState(() => _unreadNotifs = count);
    } catch (_) {}
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
    if (!auth.canAccessAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.of(context).pushReplacementNamed('/role-select');
        }
      });
      return Scaffold(
        body: Container(
          decoration: AppThemeDecorations.gradientBackground(context),
          child: Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
        ),
      );
    }
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
        body: Row(
          children: [
            _buildSidebar(context, auth),
            Expanded(
              child: Container(
                decoration: AppThemeDecorations.gradientBackground(context),
                child: Column(
                  children: [
                    Expanded(child: screens[_selectedIndex]),
                    _buildBottomNav(context),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSidebar(BuildContext context, AuthProvider auth) {
    final width = _sidebarExpanded ? 220.0 : 0.0;
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sidebarBg = isDark ? const Color(0xFF0D2137) : scheme.surface;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      width: width,
      child: width == 0
          ? const SizedBox.shrink()
         : Material(
              elevation: 0,
              color: sidebarBg,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16),
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(16),
                    bottomLeft: Radius.circular(16),
                  ),
                  border: Border(
                    right: BorderSide(color: scheme.primary.withOpacity(0.4), width: 2),
                  ),
                ),
                child: SafeArea(
                  right: false,
                  child: Column(
                    children: [
                      const SizedBox(height: 12),
                      IconButton(
                        icon: Icon(Icons.menu_open, color: scheme.onSurface, size: 24),
                        onPressed: () => setState(() => _sidebarExpanded = false),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor: scheme.primary.withOpacity(0.3),
                              child: Text(
                                (auth.user?.name ?? 'م').substring(0, 1).toUpperCase(),
                                style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                auth.user?.name ?? 'المسؤول',
                                style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w600, fontSize: 14),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      children: [
                        _sidebarSection(context, 'الأنظمة الرئيسية'),
                        if (auth.hasPermission('dashboard.view'))
                          _sidebarItem(context, Icons.dashboard_outlined, 'لوحة التحكم', () => setState(() => _selectedIndex = 0), _selectedIndex == 0),
                        if (auth.hasPermission('orders.view'))
                          _sidebarItem(context, Icons.receipt_long_outlined, 'إدارة الطلبات', () => setState(() => _selectedIndex = 1), _selectedIndex == 1),
                        if (auth.hasPermission('customers.view'))
                          _sidebarItem(context, Icons.people_outline, 'إدارة العملاء', () => setState(() => _selectedIndex = 2), _selectedIndex == 2),
                        if (auth.hasPermission('products.view'))
                          _sidebarItem(context, Icons.inventory_2_outlined, 'إدارة المنتجات', () => setState(() => _selectedIndex = 3), _selectedIndex == 3),
                        if (auth.hasPermission('tasks.view'))
                          _sidebarItem(context, Icons.build_outlined, 'إدارة المهام', () => setState(() => _selectedIndex = 4), _selectedIndex == 4),
                        const SizedBox(height: 8),
                        _sidebarSection(context, 'أنظمة متقدمة'),
                        if (auth.hasPermission('quotations.view'))
                          _sidebarItem(context, Icons.request_quote_outlined, 'عروض الأسعار', () => _navigate(context, const AdminQuotationsScreen()), false, color: Colors.amber),
                        if (auth.hasPermission('categories.view'))
                          _sidebarItem(context, Icons.category_outlined, 'التصنيفات', () => _navigate(context, const AdminCategoriesScreen()), false, color: Colors.teal),
                        if (auth.hasPermission('accounting.view'))
                          _sidebarItem(context, Icons.account_balance_wallet_outlined, 'الحسابات والعهد', () => _navigate(context, const AdminAccountingScreen()), false, color: Colors.deepOrange),
                        if (auth.hasPermission('crm.view'))
                          _sidebarItem(context, Icons.people_alt_outlined, 'CRM', () => _navigate(context, const AdminCrmScreen()), false, color: Colors.indigo),
                        if (auth.hasPermission('inbox.view'))
                          _sidebarItem(context, Icons.inbox_outlined, 'صندوق الرسائل', () => _navigate(context, const AdminInboxScreen()), false, color: Colors.blue),
                        if (auth.hasPermission('notifications.view'))
                          _sidebarItem(context, Icons.notifications_outlined, 'الإشعارات', () => _navigate(context, const AdminNotificationsScreen()), false, color: Colors.orange),
                        if (auth.hasPermission('secretary.view'))
                          _sidebarItem(context, Icons.calendar_month_outlined, 'السكرتارية', () => _navigate(context, const AdminSecretaryScreen()), false, color: Colors.pink),
                        if (auth.hasPermission('reports.view'))
                          _sidebarItem(context, Icons.bar_chart_outlined, 'التقارير', () => _navigate(context, const AdminReportsScreen()), false, color: Colors.green),
                        if (auth.hasPermission('surveys.view'))
                          _sidebarItem(context, Icons.home_work_outlined, 'Smart Survey', () => _navigate(context, const SurveyEntryScreen()), false, color: Colors.cyan),
                        if (auth.hasPermission('permissions.view'))
                          _sidebarItem(context, Icons.admin_panel_settings_outlined, 'الصلاحيات', () => _navigate(context, const AdminPermissionsScreen()), false, color: Colors.red),
                        const SizedBox(height: 16),
                        _sidebarItem(context, Icons.logout, 'تسجيل الخروج', () async {
                          await ApiService.clearCookie();
                          if (!mounted) return;
                          context.read<AuthProvider>().logout();
                          if (context.mounted) Navigator.pushReplacementNamed(context, '/login');
                        }, false, color: Colors.red),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    );
  }

  Widget _sidebarSection(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Text(
        title,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _sidebarItem(BuildContext context, IconData icon, String title, VoidCallback onTap, bool selected, {Color? color}) {
    final scheme = Theme.of(context).colorScheme;
    final accent = color ?? scheme.primary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? scheme.primary.withOpacity(0.2) : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(icon, color: selected ? scheme.primary : scheme.onSurfaceVariant, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                      fontSize: 14,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const labels = ['الرئيسية', 'الطلبات', 'العملاء', 'المنتجات', 'المهام'];
    const icons = [
      Icons.dashboard_outlined,
      Icons.receipt_long_outlined,
      Icons.people_outline,
      Icons.inventory_2_outlined,
      Icons.build_outlined,
    ];
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.25),
            border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
          ),
          child: SafeArea(
            top: false,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(5, (i) {
                final selected = _selectedIndex == i;
                return Expanded(
                  child: InkWell(
                    onTap: () => setState(() => _selectedIndex = i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            icons[i],
                            size: 24,
                            color: selected ? scheme.primary : Colors.white70,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            labels[i],
                            style: TextStyle(
                              fontSize: 11,
                              color: selected ? scheme.primary : Colors.white70,
                              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  void _navigate(BuildContext context, Widget screen) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => Directionality(textDirection: TextDirection.rtl, child: screen)));
  }

  Widget _buildDashboard(AuthProvider auth) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          floating: true,
          centerTitle: false,
          titleSpacing: 0,
          title: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Right side (in RTL): ET logo + menu + notifications
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ThemeToggleLogo(size: 34),
                      const SizedBox(width: 10),
                      IconButton(
                        icon: Icon(Icons.menu, color: Theme.of(context).colorScheme.onSurface),
                        onPressed: () => setState(() => _sidebarExpanded = !_sidebarExpanded),
                      ),
                      const SizedBox(width: 4),
                      Stack(
                        children: [
                          IconButton(
                            icon: Icon(Icons.notifications_outlined, color: Theme.of(context).colorScheme.primary),
                            onPressed: () {
                              Navigator
                                  .push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => const Directionality(
                                        textDirection: TextDirection.rtl,
                                        child: AdminNotificationsScreen(),
                                      ),
                                    ),
                                  )
                                  .then((_) => _loadUnreadCount());
                            },
                          ),
                          if (_unreadNotifs > 0)
                            Positioned(
                              right: 6,
                              top: 6,
                              child: Container(
                                padding: const EdgeInsets.all(4),
                                decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                                child: Text(
                                  '$_unreadNotifs',
                                  style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  // Center title
                  Expanded(
                    child: Center(
                      child: Text(
                        'لوحة التحكم',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  // Left side: user name (flexible to avoid right overflow when sidebar open)
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        auth.user?.name ?? 'Abanob Kamal',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'نظرة عامة',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 12),
                if (_loadingStats)
                  Center(child: Padding(padding: const EdgeInsets.all(20), child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)))
                else
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.85,
                    children: [
                      _StatCard(
                        title: 'العملاء',
                        value: '${_stats?['totalCustomers'] ?? 0}',
                        icon: Icons.people_outline,
                        color: const Color(0xFF2E7D32),
                      ),
                      _StatCard(
                        title: 'الطلبات',
                        value: '${_stats?['totalOrders'] ?? 0}',
                        icon: Icons.receipt_long_outlined,
                        color: const Color(0xFF1565C0),
                      ),
                      _StatCard(
                        title: 'المهام',
                        value: '${_stats?['totalTasks'] ?? 0}',
                        icon: Icons.build_outlined,
                        color: const Color(0xFF6A1B9A),
                      ),
                      _StatCard(
                        title: 'المنتجات',
                        value: '${_stats?['totalProducts'] ?? 0}',
                        icon: Icons.inventory_2_outlined,
                        color: const Color(0xFFE65100),
                      ),
                    ],
                  ),
                const SizedBox(height: 24),
                Text(
                  'الأنظمة المتقدمة',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 12),
                Builder(builder: (_) {
                  final p = auth;
                  final cards = <Widget>[
                    if (p.hasPermission('quotations.view'))
                      _DashboardCard(
                        icon: Icons.request_quote_outlined,
                        title: 'عروض الأسعار',
                        color: Colors.amber,
                        onTap: () => _navigate(context, const AdminQuotationsScreen()),
                      ),
                    if (p.hasPermission('permissions.view'))
                      _DashboardCard(
                        icon: Icons.admin_panel_settings_outlined,
                        title: 'الصلاحيات',
                        color: Colors.red,
                        onTap: () => _navigate(context, const AdminPermissionsScreen()),
                      ),
                    if (p.hasPermission('reports.view'))
                      _DashboardCard(
                        icon: Icons.bar_chart_outlined,
                        title: 'التقارير',
                        color: Colors.green,
                        onTap: () => _navigate(context, const AdminReportsScreen()),
                      ),
                    if (p.hasPermission('categories.view'))
                      _DashboardCard(
                        icon: Icons.category_outlined,
                        title: 'التصنيفات',
                        color: Colors.teal,
                        onTap: () => _navigate(context, const AdminCategoriesScreen()),
                      ),
                    if (p.hasPermission('accounting.view'))
                      _DashboardCard(
                        icon: Icons.account_balance_wallet_outlined,
                        title: 'الحسابات',
                        color: Colors.deepOrange,
                        onTap: () => _navigate(context, const AdminAccountingScreen()),
                      ),
                    if (p.hasPermission('crm.view'))
                      _DashboardCard(
                        icon: Icons.people_alt_outlined,
                        title: 'CRM',
                        color: Colors.indigo,
                        onTap: () => _navigate(context, const AdminCrmScreen()),
                      ),
                    if (p.hasPermission('inbox.view'))
                      _DashboardCard(
                        icon: Icons.inbox_outlined,
                        title: 'صندوق الرسائل',
                        color: Colors.blue,
                        onTap: () => _navigate(context, const AdminInboxScreen()),
                      ),
                    if (p.hasPermission('notifications.view'))
                      _DashboardCard(
                        icon: Icons.notifications_outlined,
                        title: 'الإشعارات',
                        color: Colors.orange,
                        onTap: () => _navigate(context, const AdminNotificationsScreen()),
                      ),
                    if (p.hasPermission('secretary.view'))
                      _DashboardCard(
                        icon: Icons.calendar_month_outlined,
                        title: 'السكرتارية',
                        color: Colors.pink,
                        onTap: () => _navigate(context, const AdminSecretaryScreen()),
                      ),
                    if (p.hasPermission('surveys.view'))
                      _DashboardCard(
                        icon: Icons.home_work_outlined,
                        title: 'Smart Survey',
                        color: Colors.cyan,
                        onTap: () => _navigate(context, const SurveyEntryScreen()),
                      ),
                  ];
                  return GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 0.85,
                    children: cards,
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Compact dashboard card: icon + title, theme-aware, no fixed height.
class _DashboardCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  final VoidCallback onTap;

  const _DashboardCard({
    required this.icon,
    required this.title,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Theme.of(context).colorScheme.surface,
            boxShadow: isDark
                ? null
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Theme.of(context).colorScheme.surface,
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
