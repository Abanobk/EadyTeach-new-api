import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';

class RoleSelectScreen extends StatelessWidget {
  const RoleSelectScreen({super.key});

  int? _urlProductId() {
    return int.tryParse(Uri.base.queryParameters['productId'] ?? '');
  }

  void _openClient(BuildContext context, AuthProvider auth) {
    final pendingProductId = auth.consumePendingProductId();
    Navigator.pushReplacementNamed(
      context,
      '/client',
      arguments: pendingProductId != null ? {'productId': pendingProductId} : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final c = Theme.of(context).colorScheme;
    final urlProductId = _urlProductId();
    final effectiveProductId = auth.pendingProductId ?? ((urlProductId != null && urlProductId > 0) ? urlProductId : null);
    if (effectiveProductId != null && effectiveProductId > 0) {
      auth.setPendingProductId(effectiveProductId);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) _openClient(context, auth);
      });
    }
    final items = <_RoleEntry>[
      _RoleEntry(
        title: 'عميل',
        subtitle: 'تصفح المنتجات والخدمات، راجع العروض، وتابع الطلبات بسهولة.',
        icon: Icons.shopping_bag_rounded,
        badge: 'الواجهة التجارية',
        gradient: const [Color(0xFF2563EB), Color(0xFF1D4ED8)],
        onTap: () => _openClient(context, auth),
      ),
      _RoleEntry(
        title: 'فني',
        subtitle: 'وصول سريع للمهام اليومية، التحديثات الميدانية، وحالة التنفيذ.',
        icon: Icons.handyman_rounded,
        badge: 'العمليات',
        gradient: const [Color(0xFF14B8A6), Color(0xFF0F766E)],
        onTap: () => Navigator.pushReplacementNamed(context, '/technician'),
      ),
      if (auth.canAccessAdmin)
        _RoleEntry(
          title: 'مسؤول',
          subtitle: 'لوحة قيادة كاملة لإدارة العملاء والطلبات والتقارير والمنصة.',
          icon: Icons.space_dashboard_rounded,
          badge: 'إدارة متقدمة',
          gradient: const [Color(0xFFF59E0B), Color(0xFFD97706)],
          highlight: true,
          onTap: () => Navigator.pushReplacementNamed(context, '/admin'),
        ),
    ];

    return Scaffold(
      body: Container(
        decoration: AppThemeDecorations.gradientBackground(context),
        child: SafeArea(
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                  child: Column(
                    children: [
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final wide = constraints.maxWidth >= 880;
                            return Row(
                              children: [
                                Expanded(
                                  flex: wide ? 6 : 1,
                                  child: _HeroPanel(userName: auth.userDisplayName),
                                ),
                                SizedBox(width: wide ? 24 : 0),
                                if (wide)
                                  Expanded(
                                    flex: 5,
                                    child: _RoleList(items: items),
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                      if (MediaQuery.of(context).size.width < 880) ...[
                        const SizedBox(height: 18),
                        Expanded(child: _RoleList(items: items)),
                      ],
                      const SizedBox(height: 14),
                      TextButton.icon(
                        onPressed: () async {
                          await auth.logout();
                          if (context.mounted) {
                            Navigator.pushReplacementNamed(context, '/login');
                          }
                        },
                        icon: Icon(Icons.logout_rounded, color: c.onSurfaceVariant, size: 18),
                        label: Text(
                          'تسجيل الخروج',
                          style: TextStyle(color: c.onSurfaceVariant, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  final String userName;

  const _HeroPanel({required this.userName});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      decoration: AppThemeDecorations.heroPanel(context),
      padding: const EdgeInsets.all(28),
      child: Stack(
        children: [
          Positioned(
            top: -40,
            left: -30,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.08),
              ),
            ),
          ),
          Positioned(
            bottom: -60,
            right: -25,
            child: Container(
              width: 190,
              height: 190,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.07),
              ),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const ThemeToggleLogo(size: 82),
              const SizedBox(height: 28),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'منصة ذكية لإدارة الخدمات والمنتجات',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'اختر وضع الدخول المناسب لعملك اليومي',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'مرحبًا $userName، تم تحسين تجربة التنقل لتكون أسرع وأوضح وأكثر احترافية عبر كل دور داخل المنصة.',
                style: const TextStyle(
                  color: Color(0xFFE2E8F0),
                  fontSize: 15,
                  height: 1.7,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 28),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: const [
                  _MiniMetric(label: 'واجهة حديثة', icon: Icons.auto_awesome_rounded),
                  _MiniMetric(label: 'تنقل أسرع', icon: Icons.route_rounded),
                  _MiniMetric(label: 'عرض أوضح', icon: Icons.visibility_rounded),
                ],
              ),
              const Spacer(),
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.swipe_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'يمكنك دائمًا العودة وتبديل الوضع لاحقًا بدون فقدان سياق العمل.',
                      style: TextStyle(color: c.onPrimary.withOpacity(0.85), fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoleList extends StatelessWidget {
  final List<_RoleEntry> items;

  const _RoleList({required this.items});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: AppThemeDecorations.loginStyleCard(context, 30),
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'اختر الدور',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'تم ترتيب الصلاحيات في بطاقات واضحة لتصل مباشرةً إلى المسار المناسب داخل التطبيق.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: ListView.separated(
                  itemBuilder: (context, index) => _RoleCard(entry: items[index]),
                  separatorBuilder: (_, __) => const SizedBox(height: 14),
                  itemCount: items.length,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final _RoleEntry entry;

  const _RoleCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: entry.onTap,
        borderRadius: BorderRadius.circular(24),
        child: Ink(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: entry.highlight ? entry.gradient.last.withOpacity(0.28) : c.outline.withOpacity(0.8),
            ),
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                entry.gradient.first.withOpacity(0.12),
                Theme.of(context).brightness == Brightness.dark
                    ? c.surface.withOpacity(0.95)
                    : Colors.white.withOpacity(0.96),
              ],
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: entry.gradient),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: entry.gradient.last.withOpacity(0.22),
                      blurRadius: 18,
                      spreadRadius: -6,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Icon(entry.icon, color: Colors.white, size: 30),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.title,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: entry.gradient.first.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            entry.badge,
                            style: TextStyle(
                              color: entry.gradient.last,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      entry.subtitle,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: c.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: c.surfaceContainerHighest.withOpacity(0.65),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.arrow_back_ios_new_rounded, color: c.onSurface, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final IconData icon;

  const _MiniMetric({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.1),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _RoleEntry {
  final String title;
  final String subtitle;
  final IconData icon;
  final String badge;
  final List<Color> gradient;
  final bool highlight;
  final VoidCallback onTap;

  const _RoleEntry({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.badge,
    required this.gradient,
    required this.onTap,
    this.highlight = false,
  });
}
