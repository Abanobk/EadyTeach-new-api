import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'dart:async';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';
import '../../modules/survey/screens/survey_entry_screen.dart';
import '../admin/admin_notifications_screen.dart';
import 'task_detail_screen.dart';
import 'technician_custody_screen.dart';

class TechnicianHomeScreen extends StatefulWidget {
  const TechnicianHomeScreen({super.key});

  @override
  State<TechnicianHomeScreen> createState() => _TechnicianHomeScreenState();
}

class _TechnicianHomeScreenState extends State<TechnicianHomeScreen> {
  List<dynamic> _tasks = [];
  bool _loading = true;
  String _filter = 'current';
  int _unreadNotifs = 0;
  bool _needsAlwaysLocation = false;
  bool _checkingLocationPerm = false;
  bool _openingSettings = false;
  DateTime? _lastPermRefreshAt;
  late final _LifecycleHook _lifecycleHook;
  Timer? _statusTimer;
  bool _shownLocationSnackOnce = false;

  @override
  void initState() {
    super.initState();
    _lifecycleHook = _LifecycleHook(onResumed: _onAppResumed);
    WidgetsBinding.instance.addObserver(_lifecycleHook);
    _loadUnreadCount();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadTasks(context);
      if (mounted) _checkAndPromptLocationPermission();
    });

    // Auto refresh status + موقع للسيرفر كل 30 دقيقة (التطبيق مفتوح) — بدون هذا لا يُسجَّل مسار يومي.
    _statusTimer = Timer.periodic(const Duration(minutes: 30), (_) async {
      if (!mounted) return;
      await _checkAndPromptLocationPermission(silent: true);
      await _uploadLocationHeartbeat(silent: true);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycleHook);
    _statusTimer?.cancel();
    super.dispose();
  }

  Future<void> _onAppResumed() async {
    // When user comes back from Settings, re-check permission + report to backend.
    final now = DateTime.now();
    final last = _lastPermRefreshAt;
    if (last != null && now.difference(last).inMilliseconds < 1200) return;
    _lastPermRefreshAt = now;
    if (!mounted) return;
    await _checkAndPromptLocationPermission(silent: true);
    await _uploadLocationHeartbeat(silent: true);
  }

  /// يرسل آخر إحداثيات للسيرفر حتى يظهر «مسار اليوم» للإدارة (لا يعتمد على فتح مهمة فقط).
  Future<void> _uploadLocationHeartbeat({bool silent = true}) async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) return;
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.medium);
      await ApiService.mutate('technicianLocation.update', input: {
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'accuracy': pos.accuracy,
        'source': 'heartbeat',
      });
    } catch (_) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذّر إرسال الموقع للسيرفر'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _checkAndPromptLocationPermission({bool silent = false}) async {
    if (_checkingLocationPerm) return;
    setState(() => _checkingLocationPerm = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (mounted) setState(() => _needsAlwaysLocation = true);
        return;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }

      // We need Always to respond to "request location now" when app is closed.
      final ok = perm == LocationPermission.always;
      if (mounted) setState(() => _needsAlwaysLocation = !ok);

      // Report current status to backend so admin can see it.
      final permStr = () {
        switch (perm) {
          case LocationPermission.always:
            return 'always';
          case LocationPermission.whileInUse:
            return 'while_in_use';
          case LocationPermission.denied:
            return 'denied';
          case LocationPermission.deniedForever:
            return 'denied_forever';
          case LocationPermission.unableToDetermine:
            return 'unknown';
        }
      }();
      final platform = () {
        switch (defaultTargetPlatform) {
          case TargetPlatform.android:
            return 'android';
          case TargetPlatform.iOS:
            return 'ios';
          default:
            return 'unknown';
        }
      }();
      try {
        await ApiService.mutate('technicianStatus.update', input: {
          'locationPermission': permStr,
          'locationServiceEnabled': enabled,
          'devicePlatform': platform,
        });
      } catch (_) {}

      // أول نقطة مسار بعد التحقق من الإذن (والجدول الزمني يكمّل لاحقاً).
      if (perm != LocationPermission.denied && perm != LocationPermission.deniedForever) {
        // ignore: unawaited_futures
        _uploadLocationHeartbeat(silent: true);
      }

      // (اختياري) إشعار بسيط مرة واحدة بدون تفاصيل تقنية.
      if (!silent && !ok && mounted && !_shownLocationSnackOnce) {
        _shownLocationSnackOnce = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('فضلاً فعّل استخدام الموقع للتطبيق.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _needsAlwaysLocation = true);
    } finally {
      if (mounted) setState(() => _checkingLocationPerm = false);
    }
  }

  /// يحاول تفعيل "السماح طوال الوقت" بأفضل مسار متاح:
  /// 1) طلب الإذن داخل التطبيق (قد يظهر خيار "طوال الوقت" على بعض الأجهزة/الإصدارات)
  /// 2) إن لم يصبح Always، نفتح إعدادات التطبيق مباشرة.
  Future<void> _enableAlwaysLocationFlow() async {
    if (_openingSettings) return;
    setState(() => _openingSettings = true);
    try {
      // Show the exact steps before jumping to settings (names match many Android skins).
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('افتح: الأذونات → الإشعارات والموقع الجغرافي → السماح طوال الوقت'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 5),
          ),
        );
      }

      // Open app settings (Android doesn't allow enabling "always" programmatically).
      await Geolocator.openAppSettings();

      // بعد الرجوع، أعد الفحص لتحديث البانر وإرسال الحالة للسيرفر.
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) {
        await _checkAndPromptLocationPermission();
      }
    } catch (_) {
      try {
        await Geolocator.openAppSettings();
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _openingSettings = false);
    }
  }

  void _showAlwaysLocationHowTo() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppThemeDecorations.cardColor(ctx),
          title: Text('تفعيل استخدام الموقع', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w900)),
          content: Text(
            'لتفعيل استخدام الموقع:\n'
            '1) افتح: الإعدادات → التطبيقات → Easy Tech\n'
            '2) الأذونات\n'
            '3) الإشعارات والموقع الجغرافي\n'
            '4) السماح طوال الوقت\n\n'
            'ملاحظة: بعض الهواتف بتظهر "السماح طوال الوقت" بعد اختيار "أثناء استخدام التطبيق" مرة أولاً.',
            style: TextStyle(color: AppColors.muted, height: 1.35),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('إغلاق', style: TextStyle(color: AppColors.muted)),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _enableAlwaysLocationFlow();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('فتح الإعدادات', style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openLocationSettings() async {
    try {
      await Geolocator.openAppSettings();
    } catch (_) {}
    try {
      await Geolocator.openLocationSettings();
    } catch (_) {}
    // Re-check after returning.
    if (mounted) {
      await Future.delayed(const Duration(milliseconds: 800));
      await _checkAndPromptLocationPermission();
    }
  }

  static List<dynamic> _parseTasksResponse(dynamic data) {
    if (data is List) return data;
    if (data is Map) {
      final list = data['items'] ?? data['tasks'] ?? data['list'];
      if (list is List) return list;
    }
    return [];
  }

  /// المهمة معيّنة لهذا الفني؟ (حسب technicianId أو technician.id أو technicianName)
  static bool _isTaskAssignedToTechnician(dynamic t, UserModel user, String displayName) {
    final userId = user.id;
    final tid = t['technicianId'];
    final tidInt = tid is int ? tid : (tid != null ? int.tryParse(tid.toString()) : null);
    if (tidInt != null && tidInt == userId) return true;
    final tech = t['technician'];
    if (tech is Map) {
      final techId = tech['id'];
      final techIdInt = techId is int ? techId : (techId != null ? int.tryParse(techId.toString()) : null);
      if (techIdInt != null && techIdInt == userId) return true;
      final techName = tech['name']?.toString().trim();
      if (techName != null && techName.isNotEmpty && (techName == displayName || techName == user.name)) return true;
    }
    final tName = t['technicianName']?.toString().trim();
    if (tName != null && tName.isNotEmpty && (tName == displayName || tName == user.name)) return true;
    return false;
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

  Future<void> _loadTasks(BuildContext context) async {
    setState(() => _loading = true);
    try {
      final user = context.read<AuthProvider>().user;
      final userId = user?.id;

      List<dynamic> raw = [];

      // 1) جلب مهام الفني من getMyTasks
      try {
        final res = await ApiService.query('tasks.getMyTasks');
        raw = _parseTasksResponse(res['data']);
      } catch (_) {}

      // 2) إذا كانت فارغة: جلب كل المهام من tasks.list ثم فلترة حسب الفني الحالي
      // (يدعم technicianId، أو technician.id، أو technicianName لضمان ظهور المهام المعيّنة من المسؤول)
      if (raw.isEmpty && user != null) {
        try {
          final res = await ApiService.query('tasks.list');
          final all = _parseTasksResponse(res['data']);
          final displayName = context.read<AuthProvider>().userDisplayName;
          raw = all.where((t) => _isTaskAssignedToTechnician(t, user, displayName)).toList();
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _tasks = raw;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _todayStr() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  List<dynamic> get _filteredTasks {
    final today = _todayStr();
    switch (_filter) {
      case 'current':
        return _tasks.where((t) {
          final s = t['status'];
          return s != 'completed' && s != 'cancelled';
        }).toList();
      case 'today':
        return _tasks.where((t) {
          final s = t['status'];
          if (s == 'cancelled') return false;
          final sched = t['scheduledAt']?.toString() ?? '';
          return sched.startsWith(today);
        }).toList();
      case 'overdue':
        return _tasks.where((t) {
          final s = t['status'];
          if (s == 'completed' || s == 'cancelled') return false;
          final sched = t['scheduledAt']?.toString() ?? '';
          if (sched.isEmpty) return false;
          try {
            final schedDate = DateTime.parse(sched);
            final todayDate = DateTime.now();
            return DateTime(schedDate.year, schedDate.month, schedDate.day)
                .isBefore(DateTime(todayDate.year, todayDate.month, todayDate.day));
          } catch (_) {
            return false;
          }
        }).toList();
      case 'completed':
        return _tasks.where((t) => t['status'] == 'completed').toList();
      default:
        return _tasks;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Container(
          decoration: AppThemeDecorations.gradientBackground(context),
          child: Column(
            children: [
              AppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                leading: IconButton(
                  icon: Icon(Icons.arrow_back_ios_new, color: Theme.of(context).colorScheme.primary, size: 20),
                  onPressed: () => Navigator.pushReplacementNamed(context, '/role-select'),
                ),
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ThemeToggleLogo(size: 38),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('مهامي',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontWeight: FontWeight.bold,
                                fontSize: 18)),
                        Text(auth.userDisplayName,
                            style:
                                TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
                actions: [
                  Stack(
                    children: [
                      IconButton(
                        icon: Icon(Icons.notifications_outlined, color: Theme.of(context).colorScheme.primary),
                  tooltip: 'الإشعارات',
                  onPressed: () async {
                    await Navigator.push(context, MaterialPageRoute(builder: (_) => const AdminNotificationsScreen()));
                    _loadUnreadCount();
                  },
                ),
                if (_unreadNotifs > 0)
                  Positioned(
                    right: 6, top: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                      child: Text('$_unreadNotifs', style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
            IconButton(
              icon: Icon(Icons.account_balance_wallet_outlined, color: Theme.of(context).colorScheme.primary),
              tooltip: 'عهدتي',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const TechnicianCustodyScreen(),
                  ),
                );
              },
            ),
            IconButton(
              icon: Icon(Icons.home_work_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant),
              tooltip: 'Smart Survey',
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => SurveyEntryScreen(),
                  ),
                );
              },
            ),
            IconButton(
              icon: Icon(Icons.refresh, color: Theme.of(context).colorScheme.onSurfaceVariant),
              onPressed: () => _loadTasks(context),
            ),
            IconButton(
              icon: Icon(Icons.logout, color: Theme.of(context).colorScheme.onSurfaceVariant),
              onPressed: () async {
                await auth.logout();
                if (mounted) {
                  Navigator.pushReplacementNamed(context, '/login');
                }
              },
            ),
          ],
        ),
              if (_needsAlwaysLocation)
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.orange.withOpacity(0.35)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.location_on_outlined, color: Colors.orange, size: 22),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'فضلاً فعّل استخدام الموقع للتطبيق.',
                          style: TextStyle(color: Colors.orange, fontSize: 12.5, fontWeight: FontWeight.w700, height: 1.25),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ElevatedButton(
                            onPressed: _openingSettings ? null : _enableAlwaysLocationFlow,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text(
                              _openingSettings ? 'جاري…' : 'تفعيل طوال الوقت',
                              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                            ),
                          ),
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: _showAlwaysLocationHowTo,
                            child: const Text(
                              'ازاي؟',
                              style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w900, fontSize: 12, decoration: TextDecoration.underline),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            // Custody quick-access banner
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const TechnicianCustodyScreen()),
              ),
              child: Container(
                margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  gradient: AppThemeDecorations.primaryButtonGradient,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.account_balance_wallet, color: Colors.white, size: 28),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('عهدتي والمصاريف',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                          Text('اضغط لعرض العهدة وتسجيل المصاريف',
                              style: TextStyle(color: Colors.white70, fontSize: 11)),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 18),
                  ],
                ),
              ),
            ),
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  _FilterChipNew(
                      label: 'المهام الحالية', icon: Icons.pending_actions,
                      selected: _filter == 'current',
                      onTap: () => setState(() => _filter = 'current')),
                  _FilterChipNew(
                      label: 'مهام اليوم', icon: Icons.today,
                      activeColor: Colors.blue,
                      selected: _filter == 'today',
                      onTap: () => setState(() => _filter = 'today')),
                  _FilterChipNew(
                      label: 'مهام متأخرة', icon: Icons.warning_amber_rounded,
                      activeColor: Colors.red,
                      selected: _filter == 'overdue',
                      onTap: () => setState(() => _filter = 'overdue')),
                  _FilterChipNew(
                      label: 'مهام منفذة', icon: Icons.check_circle_outline,
                      activeColor: Colors.green,
                      selected: _filter == 'completed',
                      onTap: () => setState(() => _filter = 'completed')),
                ],
              ),
            ),
            // Tasks
            Expanded(
              child: _loading
                  ? Center(
                      child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
                  : _filteredTasks.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.task_outlined,
                                  size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
                              const SizedBox(height: 16),
                              Text('لا توجد مهام',
                                  style: TextStyle(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 18)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _filteredTasks.length,
                          itemBuilder: (ctx, i) => _TaskCard(
                            task: _filteredTasks[i],
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TaskDetailScreen(
                                    task: _filteredTasks[i]),
                              ),
                            ).then((_) => _loadTasks(context)),
                          ),
                        ),
            ),
          ],
        ),
      ),
    ),
    );
  }
}

/// Tiny lifecycle hook to re-check permission on resume.
class _LifecycleHook with WidgetsBindingObserver {
  final Future<void> Function() onResumed;
  _LifecycleHook({required this.onResumed});

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // ignore: unawaited_futures
      onResumed();
    }
  }
}

class _FilterChipNew extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final Color? activeColor;

  const _FilterChipNew({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = activeColor ?? Theme.of(context).colorScheme.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.15) : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : Theme.of(context).colorScheme.outline),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: selected ? color : Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(
              color: selected ? color : Theme.of(context).colorScheme.onSurface,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            )),
          ],
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final Map<String, dynamic> task;
  final VoidCallback onTap;

  const _TaskCard({required this.task, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = task['status'] as String? ?? 'pending';
    final priority = task['priority'] as String? ?? 'medium';
    final date = task['scheduledDate'] != null
        ? DateTime.fromMillisecondsSinceEpoch(task['scheduledDate'])
        : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: AppThemeDecorations.card(context, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    task['title'] ?? '',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface,
                        fontWeight: FontWeight.bold,
                        fontSize: 15),
                  ),
                ),
                _PriorityBadge(priority: priority),
              ],
            ),
            if (task['description'] != null) ...[
              const SizedBox(height: 6),
              Text(
                task['description'],
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 10),
            // Progress bar
            Builder(builder: (_) {
              final items = task['items'] is List ? task['items'] as List : [];
              if (items.isEmpty) return const SizedBox.shrink();
              final overallProgress = task['overallProgress'] is int
                  ? task['overallProgress'] as int
                  : () {
                      int total = 0;
                      for (final item in items) {
                        if (item is Map) {
                          total += (item['progress'] as int?) ?? ((item['isCompleted'] == true) ? 100 : 0);
                        }
                      }
                      return items.isNotEmpty ? (total / items.length).round() : 0;
                    }();
              final pColor = overallProgress >= 100
                  ? Colors.green
                  : overallProgress >= 75
                      ? Colors.blue
                      : overallProgress >= 50
                          ? Colors.orange
                          : overallProgress >= 25
                              ? const Color(0xFFF57C00)
                              : Colors.red.shade400;
              return Column(
                children: [
                  Row(children: [
                    Text('$overallProgress%',
                        style: TextStyle(color: pColor, fontWeight: FontWeight.w900, fontSize: 13)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: overallProgress / 100.0,
                          backgroundColor: Theme.of(context).colorScheme.outline,
                          valueColor: AlwaysStoppedAnimation<Color>(pColor),
                          minHeight: 6,
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                ],
              );
            }),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StatusBadge(status: status),
                if (date != null)
                  Text(
                    '${date.day}/${date.month}/${date.year}',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case 'pending':
        color = const Color(0xFFD4920A);
        label = 'جديدة';
        break;
      case 'in_progress':
        color = const Color(0xFF1565C0);
        label = 'جاري';
        break;
      case 'completed':
        color = AppThemeColors.success;
        label = 'مكتملة';
        break;
      case 'cancelled':
        color = AppThemeColors.error;
        label = 'ملغاة';
        break;
      default:
        color = Theme.of(context).colorScheme.onSurfaceVariant;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _PriorityBadge extends StatelessWidget {
  final String priority;
  const _PriorityBadge({required this.priority});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (priority) {
      case 'high':
        color = AppThemeColors.error;
        label = 'عاجل';
        break;
      case 'medium':
        color = const Color(0xFFD4920A);
        label = 'متوسط';
        break;
      case 'low':
        color = AppThemeColors.success;
        label = 'عادي';
        break;
      default:
        color = Theme.of(context).colorScheme.onSurfaceVariant;
        label = priority;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}
