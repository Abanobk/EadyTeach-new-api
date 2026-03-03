import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../utils/app_theme.dart';

class RoleSelectScreen extends StatelessWidget {
  const RoleSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: const Center(
                    child: Text('ET',
                        style: TextStyle(
                            color: Colors.black,
                            fontSize: 22,
                            fontWeight: FontWeight.w900)),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'مرحباً، ${user?.name ?? ''}',
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'اختر كيف تريد الدخول إلى المنصة',
                  style: TextStyle(color: AppColors.muted, fontSize: 14),
                ),
                const SizedBox(height: 40),

                // Client
                _RoleCard(
                  icon: Icons.shopping_bag_outlined,
                  title: 'عميل',
                  subtitle: 'تصفح المنتجات، اطلب الخدمات، وتابع طلباتك',
                  color: const Color(0xFFD4920A),
                  onTap: () => Navigator.pushReplacementNamed(context, '/client'),
                ),
                const SizedBox(height: 12),

                // Technician
                _RoleCard(
                  icon: Icons.build_outlined,
                  title: 'فني',
                  subtitle: 'عرض المهام المعيّنة وتحديث حالتها',
                  color: const Color(0xFF2E7D32),
                  onTap: () => Navigator.pushReplacementNamed(context, '/technician'),
                ),
                const SizedBox(height: 12),

                // Admin - always visible
                _RoleCard(
                  icon: Icons.dashboard_outlined,
                  title: 'مسؤول',
                  subtitle: 'لوحة التحكم الكاملة — المنتجات، العملاء، المهام',
                  color: const Color(0xFF7B4F1A),
                  badge: user?.isAdmin == true ? 'دورك الحالي' : null,
                  onTap: () => Navigator.pushReplacementNamed(context, '/admin'),
                ),

                const SizedBox(height: 24),
                TextButton.icon(
                  onPressed: () async {
                    await auth.logout();
                    if (context.mounted) {
                      Navigator.pushReplacementNamed(context, '/login');
                    }
                  },
                  icon: const Icon(Icons.logout, color: AppColors.muted, size: 16),
                  label: const Text('تسجيل الخروج',
                      style: TextStyle(color: AppColors.muted)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final String? badge;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
    this.badge,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(title,
                          style: const TextStyle(
                              color: AppColors.text,
                              fontWeight: FontWeight.bold,
                              fontSize: 16)),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(badge!,
                              style: TextStyle(
                                  color: color,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style: const TextStyle(
                          color: AppColors.muted, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.arrow_back_ios, color: AppColors.muted, size: 16),
          ],
        ),
      ),
    );
  }
}
