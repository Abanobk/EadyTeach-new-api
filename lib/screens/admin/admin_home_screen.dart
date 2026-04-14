import 'dart:async';
import 'dart:math' as math;
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
import 'admin_discounts_screen.dart';
import 'home_assistant_provision_screen.dart';
import 'home_assistant_clients_screen.dart';
import 'admin_reports_screen.dart';
import 'admin_quotations_screen.dart';
import 'admin_accounting_screen.dart';
import 'admin_technician_tracking_screen.dart';

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
  Timer? _statsTimer;
  Timer? _notifsTimer;

  @override
  void initState() {
    super.initState();
    _loadStats();
    _loadUnreadCount();
    _startPolling();
  }

  void _startPolling() {
    // Periodically refresh because this screen can remain open for long periods.
    _statsTimer?.cancel();
    _notifsTimer?.cancel();

    _statsTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      _loadStats(silent: true);
    });

    _notifsTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      _loadUnreadCount();
    });
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

  /// [silent]: تحديث دوري بدون إخفاء الجرافيك وإظهار مؤشر التحميل (كان يبدو كـ refresh للشاشة).
  Future<void> _loadStats({bool silent = false}) async {
    if (!silent) {
      setState(() => _loadingStats = true);
    }
    try {
      final res = await ApiService.query('admin.getDashboardStats');
      if (!mounted) return;
      setState(() {
        _stats = res['data'];
        _loadingStats = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (!silent) _loadingStats = false;
      });
    }
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    _notifsTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.canAccessAdmin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.of(context).pushReplacementNamed(auth.defaultLandingRoute);
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
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1200),
                    child: Column(
                      children: [
                        Expanded(child: screens[_selectedIndex]),
                        _buildBottomNav(context),
                      ],
                    ),
                  ),
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
                        if (auth.hasPermission('tasks.view'))
                          _sidebarItem(context, Icons.location_on_outlined, 'تحركات الفنيين', () => _navigate(context, const AdminTechnicianTrackingScreen()), false, color: Colors.lightBlue),
                        if (auth.hasPermission('reports.view'))
                          _sidebarItem(context, Icons.bar_chart_outlined, 'التقارير', () => _navigate(context, const AdminReportsScreen()), false, color: Colors.green),
                        if (auth.hasPermission('surveys.view'))
                          _sidebarItem(context, Icons.home_work_outlined, 'Smart Survey', () => _navigate(context, const SurveyEntryScreen()), false, color: Colors.cyan),
                        if (auth.canAccessAdmin)
                          _sidebarItem(
                            context,
                            Icons.home_work_rounded,
                            'Home Assistant (Provision)',
                            () => _navigate(context, const HomeAssistantProvisionScreen()),
                            false,
                            color: Colors.blueGrey,
                          ),
                        if (auth.canAccessAdmin)
                          _sidebarItem(
                            context,
                            Icons.manage_accounts_rounded,
                            'Home Assistant Clients',
                            () => _navigate(context, const HomeAssistantClientsScreen()),
                            false,
                            color: Colors.blueGrey,
                          ),
                        if (auth.hasPermission('discounts.view'))
                          _sidebarItem(
                            context,
                            Icons.percent,
                            'خصومات التجار / العملاء',
                            () => _navigate(context, const AdminDiscountsScreen()),
                            false,
                            color: Colors.deepPurple,
                          ),
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 40) {
                  return Icon(icon, color: selected ? scheme.primary : scheme.onSurfaceVariant, size: 22);
                }
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, color: selected ? scheme.primary : scheme.onSurfaceVariant, size: 22),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        title,
                        style: TextStyle(
                          color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
                          fontSize: 14,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                );
              },
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
                if (_loadingStats)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary),
                    ),
                  )
                else
                  _PerformanceInsightsCard(stats: _stats),
                const SizedBox(height: 24),
                Text(
                  'وصول سريع',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 640;
                    final cards = [
                      _DashboardCard(
                        icon: Icons.storefront_outlined,
                        title: 'المتجر',
                        color: const Color(0xFF00695C),
                        onTap: () => Navigator.pushNamed(context, '/client'),
                      ),
                      _DashboardCard(
                        icon: Icons.engineering_outlined,
                        title: 'صفحة الفني',
                        color: const Color(0xFF6A1B9A),
                        onTap: () => Navigator.pushNamed(context, '/technician'),
                      ),
                    ];
                    return GridView.count(
                      crossAxisCount: isWide ? 2 : 1,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: isWide ? 2.3 : 3.0,
                      children: cards,
                    );
                  },
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
                    if (p.hasPermission('orders.view'))
                      _DashboardCard(
                        icon: Icons.receipt_long_outlined,
                        title: 'إدارة الطلبات',
                        color: const Color(0xFF1565C0),
                        onTap: () => _navigate(context, const AdminOrdersScreen()),
                      ),
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
                    if (p.hasPermission('tasks.view'))
                      _DashboardCard(
                        icon: Icons.location_on_outlined,
                        title: 'تحركات الفنيين',
                        color: Colors.lightBlue,
                        onTap: () => _navigate(context, const AdminTechnicianTrackingScreen()),
                      ),
                    if (p.hasPermission('surveys.view'))
                      _DashboardCard(
                        icon: Icons.home_work_outlined,
                        title: 'Smart Survey',
                        color: Colors.cyan,
                        onTap: () => _navigate(context, const SurveyEntryScreen()),
                      ),
                    if (p.hasPermission('discounts.view'))
                      _DashboardCard(
                        icon: Icons.percent,
                        title: 'خصومات التجار / العملاء',
                        color: Colors.deepPurple,
                        onTap: () => _navigate(context, const AdminDiscountsScreen()),
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

int _dashboardInt(Map<String, dynamic>? s, String key) {
  final raw = s?[key];
  if (raw is int) return raw;
  return int.tryParse('${raw ?? 0}') ?? 0;
}

double _dashboardRatio(num numerator, num denominator) {
  if (denominator <= 0) return 0;
  return (numerator / denominator).clamp(0.0, 1.0);
}

String _dashboardPercent(double ratio) => '${(ratio * 100).round()}٪';

class _PerformanceInsightsCard extends StatelessWidget {
  final Map<String, dynamic>? stats;

  const _PerformanceInsightsCard({required this.stats});

  String _smartSummary({
    required bool taskBreakdownReady,
    required int effectiveTasks,
    required double completionRatio,
    required int ordersPending,
    required double pendingRatio,
  }) {
    if (!taskBreakdownReady) {
      return 'البيانات الأساسية متاحة، لكن قراءة المهام الذكية تحتاج حقول التوزيع التفصيلي من الخادم.';
    }
    if (effectiveTasks == 0 && ordersPending == 0) {
      return 'الوضع التشغيلي هادئ حالياً؛ لا توجد مهام فعّالة أو طلبات معلقة تحتاج تدخلاً فورياً.';
    }
    if (completionRatio >= 0.75 && pendingRatio <= 0.25) {
      return 'الأداء مستقر؛ نسبة الإنجاز مرتفعة والضغط على الطلبات ما زال ضمن النطاق المريح.';
    }
    if (ordersPending > 0 && pendingRatio >= 0.45) {
      return 'يوجد ضغط تشغيلي واضح في الطلبات، ويُفضَّل مراجعة الطلبات المعلقة قبل توسعة الحمل الحالي.';
    }
    if (completionRatio < 0.45) {
      return 'سرعة الإغلاق منخفضة مقارنة بعدد المهام الفعّالة، ويُنصح بمراجعة توزيع العمل على الفريق.';
    }
    return 'الصورة العامة متوازنة، ويمكن الضغط على أي بطاقة لقراءة التفاصيل واتخاذ قرار أدق.';
  }

  void _showDetailsSheet(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required List<_DetailFact> facts,
    String? note,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: scheme.outlineVariant.withOpacity(0.35)),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 46,
                        height: 5,
                        decoration: BoxDecoration(
                          color: scheme.outlineVariant.withOpacity(0.65),
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(icon, color: color, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: TextStyle(
                                  color: scheme.onSurface,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                style: TextStyle(
                                  color: scheme.onSurfaceVariant,
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    ...facts.map((fact) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _DetailFactTile(fact: fact),
                        )),
                    if (note != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: scheme.primary.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          note,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12.5,
                            height: 1.4,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                    if (onAction != null && actionLabel != null) ...[
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(sheetContext).pop();
                            onAction();
                          },
                          icon: const Icon(Icons.open_in_new_rounded),
                          label: Text(actionLabel),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final totalTasks = _dashboardInt(stats, 'totalTasks');
    final taskBreakdownReady = stats != null && stats!.containsKey('tasksCompleted');
    final tasksCompleted = _dashboardInt(stats, 'tasksCompleted');
    final tasksActive = _dashboardInt(stats, 'tasksActive');
    final tasksCancelled = _dashboardInt(stats, 'tasksCancelled');
    final effectiveTasks = math.max(totalTasks - tasksCancelled, 0);
    final completionRatio = taskBreakdownReady ? _dashboardRatio(tasksCompleted, effectiveTasks) : 0.0;
    final activeRatio = taskBreakdownReady ? _dashboardRatio(tasksActive, effectiveTasks) : 0.0;

    final totalOrders = _dashboardInt(stats, 'totalOrders');
    final ordersPending = _dashboardInt(stats, 'ordersPending');
    final totalCustomers = _dashboardInt(stats, 'totalCustomers');
    final totalProducts = _dashboardInt(stats, 'totalProducts');

    final pendingOrdersRatio = _dashboardRatio(ordersPending, totalOrders);
    final productsPerCustomer = totalCustomers > 0 ? (totalProducts / totalCustomers) : 0.0;
    final opsMax = [totalOrders, totalCustomers, totalProducts, 1].reduce(math.max);
    final orderRatio = _dashboardRatio(totalOrders, opsMax);
    final customerRatio = _dashboardRatio(totalCustomers, opsMax);
    final productRatio = _dashboardRatio(totalProducts, opsMax);

    final smartSummary = _smartSummary(
      taskBreakdownReady: taskBreakdownReady,
      effectiveTasks: effectiveTasks,
      completionRatio: completionRatio,
      ordersPending: ordersPending,
      pendingRatio: pendingOrdersRatio,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: scheme.surface,
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.35)),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: scheme.primary.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(Icons.insights_outlined, color: scheme.primary, size: 30),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'تحليل سريع للأداء',
                      style: TextStyle(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w900,
                        fontSize: 21,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'قراءة تشغيلية تفاعلية تتحدث تلقائياً — اضغط على أي بطاقة لعرض التفاصيل.',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  scheme.primary.withOpacity(0.14),
                  scheme.secondary.withOpacity(0.08),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'قراءة ذكية',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  smartSummary,
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 13,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InsightChip(
                      label: 'إنجاز فعلي ${_dashboardPercent(completionRatio)}',
                      color: const Color(0xFF2E7D32),
                    ),
                    _InsightChip(
                      label: 'طلبات معلقة ${_dashboardPercent(pendingOrdersRatio)}',
                      color: const Color(0xFF1565C0),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (!taskBreakdownReady) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'لعرض التوزيع الكامل للمهام والرسومات الدقيقة: حدّث ملف السيرفر tasks_procedures.php (admin.getDashboardStats) لآخر نسخة.',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, height: 1.35),
              ),
            ),
          ],
          const SizedBox(height: 18),
          _SectionShell(
            title: 'صحة المهام',
            subtitle: 'المؤشرات المعروضة هنا تعتمد فقط على المهام الفعّالة غير التجريبية.',
            child: Column(
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 760;
                    final cards = [
                      _InsightMetricCard(
                        icon: Icons.assignment_outlined,
                        color: const Color(0xFF6A1B9A),
                        title: 'المهام الفعالة',
                        value: '$effectiveTasks',
                        subtitle: taskBreakdownReady
                            ? 'إجمالي المهام المعتمدة في القراءة التشغيلية الحالية'
                            : 'الإجمالي المتاح حالياً للقراءة التشغيليّة',
                        footer: 'إجمالي السجل: $totalTasks',
                        onTap: () => _showDetailsSheet(
                          context,
                          icon: Icons.assignment_outlined,
                          color: const Color(0xFF6A1B9A),
                          title: 'تفاصيل المهام الفعالة',
                          subtitle: 'هذا الرقم يمثل المهام المستخدمة في الحسابات التشغيلية الحالية.',
                          facts: [
                            _DetailFact(label: 'إجمالي السجل', value: '$totalTasks'),
                            _DetailFact(label: 'المهام الفعالة المعتمدة', value: '$effectiveTasks', color: const Color(0xFF6A1B9A)),
                          ],
                          note: 'أي نسبة إنجاز أو ضغط تشغيلي في هذه البطاقة تعتمد فقط على المهام الفعالة المعتمدة.',
                          actionLabel: 'فتح صفحة المهام',
                          onAction: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const AdminTasksScreen()),
                          ),
                        ),
                      ),
                      _InsightMetricCard(
                        icon: Icons.task_alt_outlined,
                        color: const Color(0xFF2E7D32),
                        title: 'الإنجاز الفعلي',
                        value: taskBreakdownReady ? _dashboardPercent(completionRatio) : '--',
                        subtitle: taskBreakdownReady
                            ? '$tasksCompleted مهمة مكتملة من أصل $effectiveTasks مهمة فعالة'
                            : 'بانتظار توفر توزيع المهام التفصيلي',
                        footer: 'المهام المكتملة: $tasksCompleted',
                        onTap: () => _showDetailsSheet(
                          context,
                          icon: Icons.task_alt_outlined,
                          color: const Color(0xFF2E7D32),
                          title: 'تفاصيل الإنجاز',
                          subtitle: 'نسبة الإنجاز مبنية فقط على المهام غير الملغاة.',
                          facts: [
                            _DetailFact(label: 'المهام المكتملة', value: '$tasksCompleted'),
                            _DetailFact(label: 'المهام الفعالة', value: '$effectiveTasks'),
                            _DetailFact(label: 'نسبة الإنجاز الحالية', value: taskBreakdownReady ? _dashboardPercent(completionRatio) : '--', color: const Color(0xFF2E7D32)),
                          ],
                          note: 'المعادلة الحالية = المهام المكتملة ÷ المهام الفعالة بعد استبعاد الإلغاء.',
                          actionLabel: 'فتح صفحة المهام',
                          onAction: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const AdminTasksScreen()),
                          ),
                        ),
                      ),
                      _InsightMetricCard(
                        icon: Icons.engineering_outlined,
                        color: const Color(0xFFEF6C00),
                        title: 'الضغط الحالي',
                        value: taskBreakdownReady ? _dashboardPercent(activeRatio) : '--',
                        subtitle: taskBreakdownReady
                            ? '$tasksActive مهمة قيد التنفيذ أو بانتظار التنفيذ'
                            : 'بانتظار توفر توزيع المهام التفصيلي',
                        footer: 'المهام المفتوحة: $tasksActive',
                        onTap: () => _showDetailsSheet(
                          context,
                          icon: Icons.engineering_outlined,
                          color: const Color(0xFFEF6C00),
                          title: 'تفاصيل الضغط التشغيلي',
                          subtitle: 'هذا المؤشر يوضح حجم الحمل الجاري مقارنة بإجمالي المهام الفعالة.',
                          facts: [
                            _DetailFact(label: 'المهام المفتوحة', value: '$tasksActive'),
                            _DetailFact(label: 'المهام الفعالة', value: '$effectiveTasks'),
                            _DetailFact(label: 'مؤشر الضغط', value: taskBreakdownReady ? _dashboardPercent(activeRatio) : '--', color: const Color(0xFFEF6C00)),
                          ],
                          note: 'كلما ارتفع هذا المؤشر مع انخفاض الإنجاز، زادت الحاجة لإعادة توزيع أو متابعة التنفيذ.',
                          actionLabel: 'فتح صفحة المهام',
                          onAction: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const AdminTasksScreen()),
                          ),
                        ),
                      ),
                    ];
                    return GridView.builder(
                      itemCount: cards.length,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: wide ? 2 : 1,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: wide ? 1.45 : 1.22,
                      ),
                      itemBuilder: (_, index) => cards[index],
                    );
                  },
                ),
                const SizedBox(height: 14),
                _SegmentedInsightBar(
                  scheme: scheme,
                  completedRatio: completionRatio,
                  activeRatio: activeRatio,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionShell(
            title: 'ملخص العمليات',
            subtitle: 'مقارنة بصرية سريعة بين الطلبات والعملاء والمنتجات مع إمكان فتح التفاصيل.',
            child: Column(
              children: [
                _MiniComparisonChart(
                  scheme: scheme,
                  items: [
                    _ChartBarData(label: 'طلبات', value: totalOrders, ratio: orderRatio, color: const Color(0xFF1565C0)),
                    _ChartBarData(label: 'عملاء', value: totalCustomers, ratio: customerRatio, color: const Color(0xFF2E7D32)),
                    _ChartBarData(label: 'منتجات', value: totalProducts, ratio: productRatio, color: const Color(0xFFE65100)),
                  ],
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    final cards = [
                      _OperationsInsightCard(
                        icon: Icons.receipt_long_outlined,
                        color: const Color(0xFF1565C0),
                        title: 'الطلبات',
                        value: '$totalOrders',
                        subtitle: ordersPending > 0
                            ? '$ordersPending طلباً ما زال يحتاج معالجة أو تجهيز'
                            : 'لا توجد طلبات معلقة حالياً',
                        ratioLabel: 'ضغط الطلبات ${_dashboardPercent(pendingOrdersRatio)}',
                        ratio: pendingOrdersRatio,
                        onTap: () => _showDetailsSheet(
                          context,
                          icon: Icons.receipt_long_outlined,
                          color: const Color(0xFF1565C0),
                          title: 'تفاصيل الطلبات',
                          subtitle: 'قراءة سريعة لعبء الطلبات داخل النظام.',
                          facts: [
                            _DetailFact(label: 'إجمالي الطلبات', value: '$totalOrders'),
                            _DetailFact(label: 'طلبات معلقة / قيد المعالجة', value: '$ordersPending', color: const Color(0xFF1565C0)),
                            _DetailFact(label: 'نسبة الضغط', value: _dashboardPercent(pendingOrdersRatio)),
                          ],
                          note: 'يُحتسب ضغط الطلبات من خلال مقارنة عدد الطلبات المعلقة بإجمالي الطلبات الحالية.',
                          actionLabel: 'فتح صفحة الطلبات',
                          onAction: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const AdminOrdersScreen()),
                          ),
                        ),
                      ),
                      _OperationsInsightCard(
                        icon: Icons.people_alt_outlined,
                        color: const Color(0xFF2E7D32),
                        title: 'العملاء',
                        value: '$totalCustomers',
                        subtitle: 'إجمالي الحسابات التي تعمل بدور عميل أو مستخدم',
                        ratioLabel: 'حصة المقارنة ${_dashboardPercent(customerRatio)}',
                        ratio: customerRatio,
                        onTap: () => _showDetailsSheet(
                          context,
                          icon: Icons.people_alt_outlined,
                          color: const Color(0xFF2E7D32),
                          title: 'تفاصيل العملاء',
                          subtitle: 'حجم قاعدة العملاء مقارنة بباقي عناصر التشغيل المعروضة.',
                          facts: [
                            _DetailFact(label: 'عدد العملاء', value: '$totalCustomers', color: const Color(0xFF2E7D32)),
                            _DetailFact(label: 'مقارنة بالطلبات', value: '$totalOrders'),
                            _DetailFact(label: 'مقارنة بالمنتجات', value: '$totalProducts'),
                          ],
                          note: 'يساعد هذا الرقم في فهم اتساع قاعدة العملاء مقابل المخزون والطلبات النشطة.',
                          actionLabel: 'فتح صفحة العملاء',
                          onAction: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const AdminCustomersScreen()),
                          ),
                        ),
                      ),
                      _OperationsInsightCard(
                        icon: Icons.inventory_2_outlined,
                        color: const Color(0xFFE65100),
                        title: 'المنتجات',
                        value: '$totalProducts',
                        subtitle: 'اتساع الكتالوج الحالي داخل التطبيق',
                        ratioLabel: totalCustomers > 0
                            ? 'منتجات لكل عميل ${productsPerCustomer.toStringAsFixed(1)}'
                            : 'لا توجد قاعدة عملاء للمقارنة بعد',
                        ratio: productRatio,
                        onTap: () => _showDetailsSheet(
                          context,
                          icon: Icons.inventory_2_outlined,
                          color: const Color(0xFFE65100),
                          title: 'تفاصيل المنتجات',
                          subtitle: 'قراءة لحجم الكتالوج الحالي ومدى تغطيته أمام قاعدة العملاء.',
                          facts: [
                            _DetailFact(label: 'إجمالي المنتجات', value: '$totalProducts', color: const Color(0xFFE65100)),
                            _DetailFact(label: 'إجمالي العملاء', value: '$totalCustomers'),
                            _DetailFact(label: 'متوسط المنتجات لكل عميل', value: totalCustomers > 0 ? productsPerCustomer.toStringAsFixed(1) : '0.0'),
                          ],
                          note: 'هذا المؤشر لا يقيس المبيعات، لكنه يعطي انطباعاً سريعاً عن سعة الكتالوج أمام قاعدة العملاء الحالية.',
                          actionLabel: 'فتح صفحة المنتجات',
                          onAction: () => Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const AdminProductsScreen()),
                          ),
                        ),
                      ),
                    ];
                    return GridView.builder(
                      itemCount: cards.length,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: wide ? 3 : 1,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: wide ? 1.02 : 1.28,
                      ),
                      itemBuilder: (_, index) => cards[index],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionShell extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  const _SectionShell({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest.withOpacity(0.65),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: scheme.onSurface,
              fontWeight: FontWeight.w900,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _InsightMetricCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final String subtitle;
  final String footer;
  final VoidCallback onTap;

  const _InsightMetricCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.footer,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const Spacer(),
                  Icon(Icons.touch_app_outlined, color: scheme.onSurfaceVariant, size: 18),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12.5,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                footer,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SegmentedInsightBar extends StatelessWidget {
  final ColorScheme scheme;
  final double completedRatio;
  final double activeRatio;

  const _SegmentedInsightBar({
    required this.scheme,
    required this.completedRatio,
    required this.activeRatio,
  });

  @override
  Widget build(BuildContext context) {
    final completedWidth = completedRatio.clamp(0.0, 1.0);
    final activeWidth = activeRatio.clamp(0.0, 1.0);
    final spacerRatio = math.max(0.0, 1 - completedWidth - activeWidth);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'رسم توضيحي للمهام الفعالة',
          style: TextStyle(
            color: scheme.onSurface,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: 16,
            child: Row(
              children: [
                if (completedWidth > 0)
                  Expanded(
                    flex: (completedWidth * 1000).round(),
                    child: Container(color: const Color(0xFF2E7D32)),
                  ),
                if (activeWidth > 0)
                  Expanded(
                    flex: (activeWidth * 1000).round(),
                    child: Container(color: const Color(0xFFEF6C00)),
                  ),
                if (spacerRatio > 0)
                  Expanded(
                    flex: (spacerRatio * 1000).round(),
                    child: Container(color: scheme.surfaceContainerHighest.withOpacity(0.85)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _InsightChip(label: 'منجز ${_dashboardPercent(completedRatio)}', color: const Color(0xFF2E7D32)),
            _InsightChip(label: 'مفتوح ${_dashboardPercent(activeRatio)}', color: const Color(0xFFEF6C00)),
          ],
        ),
      ],
    );
  }
}

class _OperationsInsightCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String value;
  final String subtitle;
  final String ratioLabel;
  final double ratio;
  final VoidCallback onTap;

  const _OperationsInsightCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.ratioLabel,
    required this.ratio,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(0.18)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: color.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const Spacer(),
                  Text(
                    value,
                    style: TextStyle(
                      color: scheme.onSurface,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12.5,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  minHeight: 8,
                  value: ratio,
                  backgroundColor: scheme.surfaceContainerHighest.withOpacity(0.65),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                ratioLabel,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChartBarData {
  final String label;
  final int value;
  final double ratio;
  final Color color;

  const _ChartBarData({
    required this.label,
    required this.value,
    required this.ratio,
    required this.color,
  });
}

class _MiniComparisonChart extends StatelessWidget {
  final ColorScheme scheme;
  final List<_ChartBarData> items;

  const _MiniComparisonChart({
    required this.scheme,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.2)),
      ),
      child: SizedBox(
        height: 170,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: items
              .map(
                (item) => Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '${item.value}',
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 350),
                          curve: Curves.easeOut,
                          height: 30 + (item.ratio.clamp(0.0, 1.0) * 86),
                          decoration: BoxDecoration(
                            color: item.color,
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.label,
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        ),
      ),
    );
  }
}

class _InsightChip extends StatelessWidget {
  final String label;
  final Color color;

  const _InsightChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 11.5,
        ),
      ),
    );
  }
}

class _DetailFact {
  final String label;
  final String value;
  final Color? color;

  const _DetailFact({
    required this.label,
    required this.value,
    this.color,
  });
}

class _DetailFactTile extends StatelessWidget {
  final _DetailFact fact;

  const _DetailFactTile({required this.fact});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest.withOpacity(0.85),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              fact.label,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            fact.value,
            style: TextStyle(
              color: fact.color ?? scheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
