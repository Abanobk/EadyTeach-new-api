import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';
import '../../providers/auth_provider.dart';
import 'client_quotations_screen.dart';
import '../admin/create_quotation_screen.dart';

class MyTasksScreen extends StatefulWidget {
  const MyTasksScreen({super.key});

  @override
  State<MyTasksScreen> createState() => _MyTasksScreenState();
}

class _MyTasksScreenState extends State<MyTasksScreen> {
  List<dynamic> _tasks = [];
  List<dynamic> _surveys = [];
  List<dynamic> _quotations = [];
  bool _loading = true;
  bool _loadingSurveys = false;
  bool _loadingQuotations = false;
  String _tab = 'tasks'; // tasks | surveys | quotations
  String _quotationFilterStatus = 'all'; // all | draft | sent | accepted | rejected | expired

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadSurveys() async {
    setState(() => _loadingSurveys = true);
    try {
      final res = await ApiService.query('surveys.mySurveys');
      setState(() {
        _surveys = res['data'] ?? res ?? [];
        if (_surveys is! List) _surveys = [];
        _loadingSurveys = false;
      });
    } catch (e) {
      setState(() => _loadingSurveys = false);
    }
  }

  Future<void> _loadQuotations() async {
    setState(() => _loadingQuotations = true);
    try {
      final res = await ApiService.query('quotations.myQuotations');
      setState(() {
        _quotations = res['data'] ?? [];
        _loadingQuotations = false;
      });
    } catch (e) {
      setState(() => _loadingQuotations = false);
    }
  }

  List<dynamic> get _filteredQuotations {
    if (_quotationFilterStatus == 'all') return _quotations;
    return _quotations.where((q) => q['status'] == _quotationFilterStatus).toList();
  }

  Map<String, int> get _quotationStats {
    final counts = <String, int>{'draft': 0, 'sent': 0, 'accepted': 0, 'rejected': 0};
    for (final q in _quotations) {
      final s = q['status'] as String? ?? 'draft';
      counts[s] = (counts[s] ?? 0) + 1;
    }
    return counts;
  }

  static const _quotationStatusLabels = <String, String>{
    'all': 'الكل',
    'draft': 'مسودة',
    'sent': 'مرسل',
    'accepted': 'مقبول',
    'rejected': 'مرفوض',
    'expired': 'منتهي',
  };

  Future<void> _loadTasks() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.query('tasks.myTasks');
      setState(() {
        _tasks = res['data'] ?? res ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isDealer = auth.user?.role == 'dealer' || auth.user?.role == 'reseller';
    final canViewQuotations = auth.hasPermission('quotations.view') && isDealer;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    return Scaffold(
      backgroundColor: AppThemeDecorations.pageBackground(context),
      appBar: AppBar(
        title: Text(
          'منطقتي',
          style: theme.textTheme.titleMedium?.copyWith(
                color: colors.onSurface,
                fontWeight: FontWeight.w700,
              ) ??
              const TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.w700,
                fontSize: 18,
              ),
        ),
        backgroundColor: AppThemeDecorations.cardColor(context),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.muted),
            onPressed: () {
              if (_tab == 'tasks') _loadTasks();
              else if (_tab == 'surveys') _loadSurveys();
              else if (_tab == 'quotations') _loadQuotations();
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Container(
            color: AppThemeDecorations.cardColor(context),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _TabChip(
                  label: 'مهامي',
                  icon: Icons.assignment_outlined,
                  selected: _tab == 'tasks',
                  onTap: () => setState(() => _tab = 'tasks'),
                ),
                const SizedBox(width: 8),
                _TabChip(
                  label: 'معايناتي',
                  icon: Icons.home_work_outlined,
                  selected: _tab == 'surveys',
                  onTap: () {
                    setState(() => _tab = 'surveys');
                    _loadSurveys();
                  },
                ),
                const SizedBox(width: 8),
                if (canViewQuotations)
                  _TabChip(
                    label: 'عروض الأسعار',
                    icon: Icons.request_quote_outlined,
                    selected: _tab == 'quotations',
                    onTap: () {
                      setState(() => _tab = 'quotations');
                      _loadQuotations();
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
      body: _buildCurrentTab(context, canViewQuotations),
    );
  }

  Widget _buildCurrentTab(BuildContext context, bool canViewQuotations) {
    if (_tab == 'surveys') {
      return _buildSurveysTab();
    }
    if (_tab == 'quotations') {
      if (!canViewQuotations) {
        return const Center(
          child: Text('عروض الأسعار متاحة للتجار فقط'),
        );
      }
      return _buildQuotationsTab();
    }

    // مهامي
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_outlined, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'لا توجد مهام بعد',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'يمكنك طلب خدمة من قسم "طلب خدمة"',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadTasks,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _tasks.length,
        itemBuilder: (ctx, i) => _TaskCard(
          task: _tasks[i],
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TaskDetailScreen(task: _tasks[i]),
            ),
          ).then((_) => _loadTasks()),
        ),
      ),
    );
  }

  Widget _buildSurveysTab() {
    if (_loadingSurveys && _surveys.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_surveys.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.home_work_outlined, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                'معايناتي',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'لا توجد معاينات مسجلة بعد.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadSurveys,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _surveys.length,
        itemBuilder: (ctx, i) => _SurveyCard(survey: _surveys[i]),
      ),
    );
  }

  Widget _buildQuotationsTab() {
    final colors = Theme.of(context).colorScheme;
    if (_loadingQuotations && _quotations.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }
    if (_quotations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.request_quote_outlined, size: 64, color: colors.onSurfaceVariant),
              const SizedBox(height: 16),
              Text('لا توجد عروض أسعار بعد', style: TextStyle(color: colors.onSurface, fontSize: 18)),
              const SizedBox(height: 8),
              Text('أي عرض سعر يتم إرساله لك سيظهر هنا.', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 13), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _loadQuotations,
      color: AppColors.primary,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: ElevatedButton.icon(
                      onPressed: () {
                        final user = context.read<AuthProvider>().user;
                        if (user == null) return;
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => CreateQuotationScreen(
                              preselectedClientUserId: user.id,
                              preselectedClientName: user.name,
                            ),
                          ),
                        ).then((_) => _loadQuotations());
                      },
                      icon: const Icon(Icons.add, color: Colors.black),
                      label: const Text(
                        'إضافة عرض سعر جديد',
                        style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary.withOpacity(0.95),
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _QuotationStatChip(label: 'مرفوض', count: _quotationStats['rejected'] ?? 0, color: Colors.red),
                      const SizedBox(width: 8),
                      _QuotationStatChip(label: 'مقبول', count: _quotationStats['accepted'] ?? 0, color: Colors.green),
                      const SizedBox(width: 8),
                      _QuotationStatChip(label: 'مرسل', count: _quotationStats['sent'] ?? 0, color: Colors.blue),
                      const SizedBox(width: 8),
                      _QuotationStatChip(label: 'مسودة', count: _quotationStats['draft'] ?? 0, color: Colors.grey),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _quotationStatusLabels.entries.map((e) {
                        final selected = _quotationFilterStatus == e.key;
                        return Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: FilterChip(
                            label: Text(e.value),
                            selected: selected,
                            onSelected: (_) => setState(() => _quotationFilterStatus = e.key),
                            backgroundColor: colors.surface,
                            selectedColor: AppColors.primary.withOpacity(0.2),
                            checkmarkColor: AppColors.primary,
                            labelStyle: TextStyle(
                              color: selected ? AppColors.primary : colors.onSurface,
                              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                            ),
                            side: BorderSide(
                              color: selected ? AppColors.primary : colors.outline,
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_filteredQuotations.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.request_quote_outlined, size: 64, color: colors.onSurfaceVariant.withOpacity(0.5)),
                    const SizedBox(height: 16),
                    Text('لا توجد عروض أسعار بهذا الفلتر', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 16)),
                  ],
                ),
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) {
                    final q = _filteredQuotations[i] as Map<String, dynamic>;
                    return InkWell(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ClientQuotationDetailScreen(quotationId: q['id'] as int),
                        ),
                      ).then((_) => _loadQuotations()),
                      borderRadius: BorderRadius.circular(12),
                      child: _QuotationCard(quotation: q),
                    );
                  },
                  childCount: _filteredQuotations.length,
                ),
              ),
            ),
        ],
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
    final colors = Theme.of(context).colorScheme;
    final status = task['status'] as String? ?? 'pending';
    final scheduledAt = task['scheduledAt'] != null
        ? DateTime.fromMillisecondsSinceEpoch(task['scheduledAt'])
        : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    task['title'] ?? 'مهمة #${task['id']}',
                    style: TextStyle(
                      color: colors.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _StatusBadge(status: status),
              ],
            ),
            if (task['technicianName'] != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.engineering_outlined, size: 14, color: colors.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    'الفني: ${task['technicianName']}',
                    style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ),
            ],
            if (scheduledAt != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.calendar_today_outlined, size: 14, color: colors.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    'الموعد: ${scheduledAt.day}/${scheduledAt.month}/${scheduledAt.year}',
                    style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  'اضغط لعرض التفاصيل والملاحظات',
                  style: TextStyle(
                    color: AppColors.primary.withOpacity(0.8),
                    fontSize: 11,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.arrow_forward_ios, size: 11, color: AppColors.primary),
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
    IconData icon;
    switch (status) {
      case 'pending':
        color = const Color(0xFFD4920A);
        label = 'قيد الانتظار';
        icon = Icons.hourglass_empty;
        break;
      case 'assigned':
        color = const Color(0xFF1565C0);
        label = 'تم تعيين فني';
        icon = Icons.person_pin;
        break;
      case 'in_progress':
        color = AppColors.primary;
        label = 'جاري التنفيذ';
        icon = Icons.build_circle_outlined;
        break;
      case 'completed':
        color = AppColors.success;
        label = 'مكتمل';
        icon = Icons.check_circle_outline;
        break;
      case 'cancelled':
        color = AppColors.error;
        label = 'ملغي';
        icon = Icons.cancel_outlined;
        break;
      default:
        color = AppColors.muted;
        label = status;
        icon = Icons.info_outline;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TabChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? colors.primary : colors.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? colors.primary : colors.outline,
          ),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? Colors.black : colors.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.black : colors.onSurface,
                fontSize: 13,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuotationStatChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _QuotationStatChip({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Text('$count', style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w900)),
            Text(label, style: TextStyle(color: colors.onSurface, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _QuotationCard extends StatelessWidget {
  final Map<String, dynamic> quotation;

  const _QuotationCard({required this.quotation});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final status = quotation['status'] as String? ?? 'sent';
    final total = double.tryParse(quotation['totalAmount']?.toString() ?? '0') ?? 0;
    final createdAt = quotation['createdAt'];
    DateTime? dt;
    if (createdAt != null) {
      try {
        dt = DateTime.fromMillisecondsSinceEpoch(createdAt is int ? createdAt : int.parse(createdAt.toString()));
      } catch (_) {}
    }
    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'accepted':
        statusColor = AppColors.success;
        statusLabel = 'مقبول';
        break;
      case 'rejected':
        statusColor = AppColors.error;
        statusLabel = 'مرفوض';
        break;
      case 'expired':
        statusColor = Colors.orange;
        statusLabel = 'منتهي';
        break;
      case 'draft':
        statusColor = Colors.grey;
        statusLabel = 'مسودة';
        break;
      case 'sent':
        statusColor = Colors.blue;
        statusLabel = 'مرسل';
        break;
      default:
        statusColor = Colors.blue;
        statusLabel = 'في الانتظار';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                quotation['refNumber'] ?? 'عرض سعر #${quotation['id']}',
                style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withOpacity(0.4)),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(Icons.attach_money, size: 16, color: colors.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                '${total.toStringAsFixed(0)} ج.م',
                style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 15),
              ),
              const Spacer(),
              if (dt != null) ...[
                Icon(Icons.calendar_today_outlined, size: 12, color: colors.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  '${dt.day}/${dt.month}/${dt.year}',
                  style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _SurveyCard extends StatelessWidget {
  final Map<String, dynamic> survey;

  const _SurveyCard({required this.survey});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final projectName = survey['projectName'] ?? 'معاينة بدون اسم';
    final createdAt = survey['createdAt'] != null
        ? DateTime.fromMillisecondsSinceEpoch(survey['createdAt'])
        : null;
    final lightingLines = survey['lightingLines'] ?? 0;
    final curtains = survey['curtains'] ?? 0;
    final acUnits = survey['acUnits'] ?? 0;
    final tvUnits = survey['tvUnits'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            projectName,
            style: TextStyle(
              color: colors.onSurface,
              fontWeight: FontWeight.bold,
              fontSize: 15,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (createdAt != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.calendar_today_outlined, size: 14, color: colors.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  '${createdAt.day}/${createdAt.month}/${createdAt.year}',
                  style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              if (lightingLines > 0)
                _SurveyChip(
                  icon: Icons.lightbulb_outline,
                  label: '$lightingLines خط إضاءة',
                ),
              if (curtains > 0)
                _SurveyChip(
                  icon: Icons.curtains,
                  label: '$curtains ستارة',
                ),
              if (acUnits > 0)
                _SurveyChip(
                  icon: Icons.ac_unit,
                  label: '$acUnits تكييف',
                ),
              if (tvUnits > 0)
                _SurveyChip(
                  icon: Icons.tv,
                  label: '$tvUnits تلفزيون',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SurveyChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SurveyChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppColors.primary),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(color: AppColors.text, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

// ─── Task Detail Screen ──────────────────────────────────────────────────────

class TaskDetailScreen extends StatefulWidget {
  final Map<String, dynamic> task;
  const TaskDetailScreen({super.key, required this.task});

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  List<dynamic> _notes = [];
  bool _loadingNotes = true;

  @override
  void initState() {
    super.initState();
    _loadNotes();
  }

  Future<void> _loadNotes() async {
    setState(() => _loadingNotes = true);
    try {
      final res = await ApiService.query(
        'taskNotes.listForClient',
        input: {'taskId': widget.task['id']},
      );
      setState(() {
        _notes = res['data'] ?? res ?? [];
        _loadingNotes = false;
      });
    } catch (e) {
      setState(() => _loadingNotes = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final task = widget.task;
    final status = task['status'] as String? ?? 'pending';
    final scheduledAt = task['scheduledAt'] != null
        ? DateTime.fromMillisecondsSinceEpoch(task['scheduledAt'])
        : null;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppThemeDecorations.pageBackground(context),
        appBar: AppBar(
          title: Text(
            task['title'] ?? 'تفاصيل المهمة',
            style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.bold),
          ),
          backgroundColor: AppThemeDecorations.cardColor(context),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios, color: AppColors.text),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: RefreshIndicator(
          onRefresh: _loadNotes,
          color: AppColors.primary,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Task Info Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppThemeDecorations.cardColor(context),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'مهمة #${task['id']}',
                            style: const TextStyle(color: AppColors.muted, fontSize: 12),
                          ),
                          _StatusBadge(status: status),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        task['title'] ?? '',
                        style: const TextStyle(
                          color: AppColors.text,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      if (task['notes'] != null && task['notes'].toString().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          task['notes'],
                          style: const TextStyle(color: AppColors.muted, fontSize: 13),
                        ),
                      ],
                      const Divider(height: 24),
                      if (task['technicianName'] != null)
                        _InfoRow(
                          icon: Icons.engineering_outlined,
                          label: 'الفني المعين',
                          value: task['technicianName'],
                        ),
                      if (scheduledAt != null)
                        _InfoRow(
                          icon: Icons.calendar_today_outlined,
                          label: 'الموعد',
                          value:
                              '${scheduledAt.day}/${scheduledAt.month}/${scheduledAt.year}',
                        ),
                      if (task['amount'] != null)
                        _InfoRow(
                          icon: Icons.payments_outlined,
                          label: 'المبلغ',
                          value: '${task['amount']} ج.م',
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Notes Section
                const Text(
                  'ملاحظات الفني',
                  style: TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 12),

                if (_loadingNotes)
                  const Center(child: CircularProgressIndicator(color: AppColors.primary))
                else if (_notes.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppThemeDecorations.cardColor(context),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.notes_outlined, size: 40, color: AppColors.muted),
                        SizedBox(height: 8),
                        Text(
                          'لا توجد ملاحظات بعد',
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ],
                    ),
                  )
                else
                  ..._notes.map((note) => _NoteCard(note: note)).toList(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.muted),
          const SizedBox(width: 8),
          Text(
            '$label: ',
            style: const TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  final Map<String, dynamic> note;

  const _NoteCard({required this.note});

  @override
  Widget build(BuildContext context) {
    final createdAt = note['createdAt'] != null
        ? DateTime.fromMillisecondsSinceEpoch(note['createdAt'])
        : null;
    final mediaUrls = (note['mediaUrls'] as List<dynamic>?) ?? [];
    final mediaTypes = (note['mediaTypes'] as List<dynamic>?) ?? [];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeDecorations.cardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.engineering_outlined, size: 16, color: AppColors.primary),
              const SizedBox(width: 6),
              Text(
                note['authorName'] ?? 'الفني',
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              const Spacer(),
              if (createdAt != null)
                Text(
                  '${createdAt.day}/${createdAt.month} '
                  '${createdAt.hour}:${createdAt.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            note['content'] ?? '',
            style: const TextStyle(color: AppColors.text, fontSize: 14),
          ),
          if (mediaUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List.generate(mediaUrls.length, (i) {
                final url = mediaUrls[i].toString();
                final type = i < mediaTypes.length ? mediaTypes[i].toString() : 'image';
                return GestureDetector(
                  onTap: () => _showMedia(context, url, type),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: type.startsWith('video')
                        ? Container(
                            width: 80,
                            height: 80,
                            color: Colors.black,
                            child: const Center(
                              child: Icon(
                                Icons.play_circle_outline,
                                color: Colors.white,
                                size: 36,
                              ),
                            ),
                          )
                        : Image.network(
                            ApiService.proxyImageUrl(url),
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 80,
                              height: 80,
                              color: AppColors.border,
                              child: const Icon(
                                Icons.broken_image_outlined,
                                color: AppColors.muted,
                              ),
                            ),
                          ),
                  ),
                );
              }),
            ),
          ],
        ],
      ),
    );
  }

  void _showMedia(BuildContext context, String url, String type) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        child: type.startsWith('video')
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'افتح الفيديو في المتصفح',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              )
            : InteractiveViewer(
                child: Image.network(ApiService.proxyImageUrl(url), fit: BoxFit.contain),
              ),
      ),
    );
  }
}

