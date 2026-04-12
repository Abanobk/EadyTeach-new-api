import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../theme/app_theme.dart';

class RoleSelectScreen extends StatelessWidget {
  const RoleSelectScreen({super.key});

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

    return Scaffold(
      body: Container(
        decoration: AppThemeDecorations.gradientBackground(context),
        child: SafeArea(
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ThemeToggleLogo(size: 70),
                  const SizedBox(height: 20),
                  Text(
                    'مرحباً، ${auth.userDisplayName}',
                    style: TextStyle(
                      color: c.onSurface,
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'اختر كيف تريد الدخول إلى المنصة',
                    style: TextStyle(
                      color: c.onSurfaceVariant,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 36),
                  _UnifiedCard(
                    padding: const EdgeInsets.all(24),
                    child: _RoleCardContent(
                      icon: Icons.shopping_bag_outlined,
                      title: 'عميل',
                      subtitle: 'تصفح المنتجات، اطلب الخدمات، وتابع طلباتك',
                      color: c.primary,
                      onTap: () => _openClient(context, auth),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _UnifiedCard(
                    padding: const EdgeInsets.all(24),
                    child: _RoleCardContent(
                      icon: Icons.build_outlined,
                      title: 'فني',
                      subtitle: 'عرض المهام المعيّنة وتحديث حالتها',
                      color: c.primary,
                      onTap: () => Navigator.pushReplacementNamed(context, '/technician'),
                    ),
                  ),
                  if (auth.canAccessAdmin) ...[
                    const SizedBox(height: 12),
                    _UnifiedCard(
                      padding: const EdgeInsets.all(24),
                      child: _RoleCardContent(
                        icon: Icons.dashboard_outlined,
                        title: 'مسؤول',
                        subtitle: 'لوحة التحكم الكاملة — المنتجات، العملاء، المهام',
                        color: c.primary,
                        badge: 'دورك الحالي',
                        onTap: () => Navigator.pushReplacementNamed(context, '/admin'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 28),
                  TextButton.icon(
                    onPressed: () async {
                      await auth.logout();
                      if (context.mounted) {
                        Navigator.pushReplacementNamed(context, '/login');
                      }
                    },
                    icon: Icon(Icons.logout, color: c.onSurfaceVariant, size: 18),
                    label: Text(
                      'تسجيل الخروج',
                      style: TextStyle(color: c.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnifiedCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const _UnifiedCard({required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: AppThemeDecorations.loginStyleCard(context, 24),
      child: child,
    );
  }
}

class _RoleCardContent extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final String? badge;
  final VoidCallback onTap;

  const _RoleCardContent({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurface,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            badge!,
                            style: TextStyle(
                              color: color,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_back_ios_new, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 16),
          ],
        ),
      ),
    );
  }
}
