import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';
import '../technician/task_detail_screen.dart';

class AdminTasksScreen extends StatefulWidget {
  const AdminTasksScreen({super.key});
  @override
  State<AdminTasksScreen> createState() => _AdminTasksScreenState();
}

class _AdminTasksScreenState extends State<AdminTasksScreen> {
  List<dynamic> _tasks = [];
  List<dynamic> _customers = [];
  List<dynamic> _technicians = [];
  bool _loading = true;
  String _filter = 'current'; // current, today, overdue, no_date, completed

  /// تقويم: الشهر المعروض واليوم المحدد لفلترة القائمة
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.query('tasks.list'),
        ApiService.query('clients.list'),
        ApiService.query('clients.staff'),
      ]);
      setState(() {
        _tasks = results[0]['data'] ?? [];
        _customers = results[1]['data'] ?? [];
        _technicians = results[2]['data'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  String _todayStr() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// تاريخ موعد المهمة yyyy-MM-dd أو null
  String? _taskScheduledDateKey(dynamic t) {
    final s = (t['scheduledAt']?.toString() ?? '').trim();
    if (s.isEmpty) return null;
    try {
      if (s.length >= 10) return s.substring(0, 10);
      final dt = DateTime.parse(s);
      return _dateKey(DateTime(dt.year, dt.month, dt.day));
    } catch (_) {
      return null;
    }
  }

  /// عدد المهام (غير الملغاة) في يوم تقويمي
  int _countForDay(DateTime day) {
    final key = _dateKey(day);
    var n = 0;
    for (final t in _tasks) {
      if (t is! Map) continue;
      if (t['status'] == 'cancelled') continue;
      if (_taskScheduledDateKey(t) == key) n++;
    }
    return n;
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
          final sched = (t['scheduledAt']?.toString() ?? '').trim();
          if (sched.isEmpty) return false;
          return sched.startsWith(today);
        }).toList();
      case 'overdue':
        return _tasks.where((t) {
          final s = t['status'];
          if (s == 'completed' || s == 'cancelled') return false;
          final sched = (t['scheduledAt']?.toString() ?? '').trim();
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
      case 'no_date':
        return _tasks.where((t) {
          final s = t['status'];
          if (s == 'completed' || s == 'cancelled') return false;
          final sched = (t['scheduledAt']?.toString() ?? '').trim();
          return sched.isEmpty;
        }).toList();
      case 'completed':
        return _tasks.where((t) => t['status'] == 'completed').toList();
      default:
        return _tasks;
    }
  }

  /// قائمة المهام: فلتر الشريط + (اختياري) يوم محدد من التقويم
  List<dynamic> get _tasksForList {
    final base = _filteredTasks;
    if (_selectedDay == null) return base;
    final key = _dateKey(_selectedDay!);
    return base.where((t) => _taskScheduledDateKey(t) == key).toList();
  }

  Widget? _calendarDayCell(BuildContext context, DateTime day, {required bool selected}) {
    final n = _countForDay(day);
    if (n == 0 && !selected) return null;
    final scheme = Theme.of(context).colorScheme;
    if (n == 0 && selected) {
      return null;
    }
    return Container(
      margin: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? AppColors.primary.withOpacity(0.38) : AppColors.primary.withOpacity(0.14),
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.primary.withOpacity(0.4),
          width: selected ? 2 : 1,
        ),
      ),
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Text(
            '${day.day}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: scheme.onSurface,
            ),
          ),
          if (n > 0)
            Positioned(
              bottom: 1,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$n',
                  style: const TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.w900),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatTime12h(String isoStr) {
    try {
      final dt = DateTime.parse(isoStr);
      final h = dt.hour;
      final m = dt.minute.toString().padLeft(2, '0');
      final period = h >= 12 ? 'م' : 'ص';
      final h12 = h == 0 ? 12 : (h > 12 ? h - 12 : h);
      return '$h12:$m $period';
    } catch (_) {
      return isoStr.length > 16 ? isoStr.substring(11, 16) : isoStr;
    }
  }

  Color _statusColor(BuildContext context, String? status) {
    switch (status) {
      case 'completed': return Colors.green;
      case 'in_progress': return Colors.blue;
      case 'cancelled': return Colors.red;
      case 'assigned': return AppColors.primary;
      default: return AppThemeDecorations.mutedColor(context);
    }
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'completed': return 'مكتملة';
      case 'in_progress': return 'جارية';
      case 'cancelled': return 'ملغاة';
      case 'assigned': return 'معينة';
      case 'pending': return 'معلقة';
      default: return status ?? '';
    }
  }

  void _showTaskDetails(BuildContext context, Map<String, dynamic> task) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TaskDetailScreen(
          task: task,
          onTaskUpdated: _loadAll,
        ),
      ),
    );
  }

  void _showTaskWizard({Map<String, dynamic>? task}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _TaskWizard(
        task: task,
        customers: _customers,
        technicians: _technicians,
        onSaved: () {
          Navigator.pop(ctx);
          _loadAll();
        },
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, IconData icon, {Color? activeColor}) {
    final isSelected = _filter == value;
    final color = activeColor ?? AppColors.primary;
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => setState(() => _filter = value),
      child: Container(
        margin: const EdgeInsets.only(left: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.15) : AppThemeDecorations.cardColor(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isSelected ? color : AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: isSelected ? color : scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : scheme.onSurface,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredTasks = _tasksForList;

    return Scaffold(
      backgroundColor: AppThemeDecorations.pageBackground(context),
      appBar: AppBar(
        backgroundColor: AppThemeDecorations.cardColor(context),
        title: Text('إدارة المهام', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: AppThemeDecorations.mutedColor(context)),
            onPressed: _loadAll,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showTaskWizard(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('مهمة جديدة', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: Column(
        children: [
          Directionality(
            textDirection: TextDirection.rtl,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: TableCalendar(
                firstDay: DateTime.utc(2020, 1, 1),
                lastDay: DateTime.utc(2035, 12, 31),
                focusedDay: _focusedDay,
                selectedDayPredicate: (d) => _selectedDay != null && isSameDay(_selectedDay, d),
                onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                    _selectedDay = selectedDay;
                    _focusedDay = focusedDay;
                  });
                },
                onPageChanged: (focusedDay) {
                  setState(() => _focusedDay = focusedDay);
                },
                calendarFormat: CalendarFormat.month,
                availableCalendarFormats: const {CalendarFormat.month: 'شهر'},
                startingDayOfWeek: StartingDayOfWeek.saturday,
                eventLoader: (_) => const [],
                calendarBuilders: CalendarBuilders(
                  defaultBuilder: (context, day, focusedDay) => _calendarDayCell(context, day, selected: false),
                  selectedBuilder: (context, day, focusedDay) {
                    final n = _countForDay(day);
                    if (n > 0) return _calendarDayCell(context, day, selected: true);
                    return null;
                  },
                ),
                calendarStyle: CalendarStyle(
                  outsideDaysVisible: false,
                  markersMaxCount: 0,
                  cellMargin: const EdgeInsets.all(2),
                  weekendTextStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                ),
                headerStyle: HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                  titleTextStyle: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                  leftChevronIcon: Icon(Icons.chevron_left, color: Theme.of(context).colorScheme.onSurface),
                  rightChevronIcon: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface),
                ),
                daysOfWeekStyle: DaysOfWeekStyle(
                  weekdayStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                  weekendStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
          if (_selectedDay != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'عرض مهام: ${_dateKey(_selectedDay!)}  (${filteredTasks.length} مهمة)',
                      style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 13),
                    ),
                  ),
                  TextButton(
                    onPressed: () => setState(() => _selectedDay = null),
                    child: const Text('كل الأيام', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          SizedBox(
            height: 56,
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                children: [
                  _buildFilterChip('المهام الحالية', 'current', Icons.pending_actions),
                  _buildFilterChip('مهام اليوم', 'today', Icons.today, activeColor: Colors.blue),
                  _buildFilterChip('مهام متأخرة', 'overdue', Icons.warning_amber_rounded, activeColor: Colors.red),
                  _buildFilterChip('بدون موعد', 'no_date', Icons.event_busy, activeColor: Colors.purple),
                  _buildFilterChip('مهام منفذة', 'completed', Icons.check_circle_outline, activeColor: Colors.green),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : filteredTasks.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.assignment_outlined,
                              size: 64,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'لا توجد مهام',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurface,
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: filteredTasks.length,
                  itemBuilder: (ctx, i) {
                    final task = filteredTasks[i];
                    final status = task['status'] ?? 'pending';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppThemeDecorations.cardColor(context),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                            title: Text(
                              task['title'] ?? '',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                if (task['customerName'] != null)
                                  Row(children: [
                                    Icon(Icons.person_outline, size: 13, color: AppThemeDecorations.mutedColor(context)),
                                    const SizedBox(width: 4),
                                    Text(task['customerName'], style: TextStyle(color: AppThemeDecorations.mutedColor(context), fontSize: 12)),
                                  ]),
                                if (task['technicianName'] != null)
                                  Row(children: [
                                    Icon(Icons.engineering_outlined, size: 13, color: AppThemeDecorations.mutedColor(context)),
                                    const SizedBox(width: 4),
                                    Text(task['technicianName'], style: TextStyle(color: AppThemeDecorations.mutedColor(context), fontSize: 12)),
                                  ]),
                                if ((task['scheduledAt']?.toString() ?? '').trim().isNotEmpty)
                                  Row(children: [
                                    Icon(Icons.calendar_today_outlined, size: 13, color: AppThemeDecorations.mutedColor(context)),
                                    const SizedBox(width: 4),
                                    Text(
                                      task['scheduledAt'].toString().substring(0, 10),
                                      style: TextStyle(color: AppThemeDecorations.mutedColor(context), fontSize: 12),
                                    ),
                                  ]),
                                if (task['estimatedArrivalAt'] != null)
                                  Row(children: [
                                    const Icon(Icons.access_time, size: 13, color: AppColors.primary),
                                    const SizedBox(width: 4),
                                    Text(
                                      'وصول: ${_formatTime12h(task['estimatedArrivalAt'].toString())}',
                                      style: const TextStyle(color: AppColors.primary, fontSize: 12),
                                    ),
                                  ]),
                                if (task['amount'] != null)
                                  Row(children: [
                                    Icon(Icons.attach_money, size: 13, color: AppThemeDecorations.mutedColor(context)),
                                    const SizedBox(width: 4),
                                    Text('${task['amount']} ج.م', style: TextStyle(color: AppThemeDecorations.mutedColor(context), fontSize: 12)),
                                  ]),
                              ],
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _statusColor(context, status).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: _statusColor(context, status).withOpacity(0.4)),
                              ),
                              child: Text(
                                _statusLabel(status),
                                style: TextStyle(color: _statusColor(context, status), fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          // Progress bar
                          Builder(builder: (_) {
                            final items = task['items'] is List ? task['items'] as List : [];
                            final overallProgress = task['overallProgress'] is int
                                ? task['overallProgress'] as int
                                : (items.isEmpty
                                    ? 0
                                    : () {
                                        int total = 0;
                                        for (final item in items) {
                                          if (item is Map) {
                                            total += (item['progress'] as int?) ?? ((item['isCompleted'] == true) ? 100 : 0);
                                          }
                                        }
                                        return items.isNotEmpty ? (total / items.length).round() : 0;
                                      }());
                            if (items.isEmpty) return const SizedBox.shrink();
                            final pColor = overallProgress >= 100
                                ? Colors.green
                                : overallProgress >= 75
                                    ? Colors.blue
                                    : overallProgress >= 50
                                        ? Colors.orange
                                        : overallProgress >= 25
                                            ? const Color(0xFFF57C00)
                                            : Colors.red.shade400;
                            final completedCount = items.where((i) => i is Map && ((i['progress'] as int?) ?? 0) >= 100).length;
                            return Padding(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                              child: Column(
                                children: [
                                  Row(children: [
                                    Text('الإنجاز', style: TextStyle(color: AppThemeDecorations.mutedColor(context), fontSize: 11)),
                                    const Spacer(),
                                    Text(
                                      '$completedCount/${items.length} بنود  •  $overallProgress%',
                                      style: TextStyle(color: pColor, fontSize: 11, fontWeight: FontWeight.bold),
                                    ),
                                  ]),
                                  const SizedBox(height: 4),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: overallProgress / 100.0,
                                      backgroundColor: AppColors.border,
                                      valueColor: AlwaysStoppedAnimation<Color>(pColor),
                                      minHeight: 6,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton.icon(
                                  onPressed: () => _showTaskDetails(context, task),
                                  icon: const Icon(Icons.visibility_outlined, size: 16, color: Colors.blue),
                                  label: const Text('التفاصيل', style: TextStyle(color: Colors.blue, fontSize: 13)),
                                ),
                                TextButton.icon(
                                  onPressed: () => _showTaskWizard(task: task),
                                  icon: const Icon(Icons.edit_outlined, size: 16, color: AppColors.primary),
                                  label: const Text('تعديل', style: TextStyle(color: AppColors.primary, fontSize: 13)),
                                ),
                                if (status != 'cancelled')
                                  TextButton.icon(
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (c) => AlertDialog(
                                          backgroundColor: AppThemeDecorations.cardColor(context),
                                          title: const Text('تأكيد الإلغاء', style: TextStyle(color: AppColors.text)),
                                          content: Text('هل تريد إلغاء هذه المهمة؟', style: TextStyle(color: AppThemeDecorations.mutedColor(c))),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('لا')),
                                            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('نعم', style: TextStyle(color: Colors.red))),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        await ApiService.mutate('tasks.update', input: {'id': task['id'], 'status': 'cancelled'});
                                        _loadAll();
                                      }
                                    },
                                    icon: const Icon(Icons.cancel_outlined, size: 16, color: Colors.red),
                                    label: const Text('إلغاء', style: TextStyle(color: Colors.red, fontSize: 13)),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
// TASK WIZARD - نظام 3 خطوات مثل الموقع
// ═══════════════════════════════════════════════════════════
class _TaskWizard extends StatefulWidget {
  final Map<String, dynamic>? task;
  final List<dynamic> customers;
  final List<dynamic> technicians;
  final VoidCallback onSaved;

  const _TaskWizard({
    this.task,
    required this.customers,
    required this.technicians,
    required this.onSaved,
  });

  @override
  State<_TaskWizard> createState() => _TaskWizardState();
}

class _TaskWizardState extends State<_TaskWizard> {
  int _step = 0; // 0, 1, 2
  bool _saving = false;

  // Step 1 - العميل والعنوان
  final _titleCtrl = TextEditingController();
  int? _customerId;

  // Step 2 - التفاصيل
  int? _technicianId;
  DateTime? _scheduledDate;
  TimeOfDay? _estimatedArrivalTime;
  final _amountCtrl = TextEditingController();
  String _collectionType = 'cash';
  String _status = 'assigned';
  final _notesCtrl = TextEditingController();

  // Step 3 - البنود
  final List<TextEditingController> _itemControllers = [TextEditingController()];

  bool get _isEdit => widget.task != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final t = widget.task!;
      _titleCtrl.text = t['title'] ?? '';
      _customerId = t['customerId'] is int ? t['customerId'] : int.tryParse(t['customerId']?.toString() ?? '');
      _technicianId = t['technicianId'] is int ? t['technicianId'] : int.tryParse(t['technicianId']?.toString() ?? '');
      _status = t['status'] ?? 'assigned';
      _collectionType = t['collectionType'] ?? 'cash';
      _amountCtrl.text = t['amount']?.toString() ?? '';
      _notesCtrl.text = t['notes'] ?? '';
      if (t['scheduledAt'] != null) {
        try { _scheduledDate = DateTime.parse(t['scheduledAt'].toString()); } catch (_) {}
      }
      if (t['estimatedArrivalAt'] != null) {
        try {
          final dt = DateTime.parse(t['estimatedArrivalAt'].toString());
          _estimatedArrivalTime = TimeOfDay(hour: dt.hour, minute: dt.minute);
        } catch (_) {}
      }
      if (t['items'] != null && (t['items'] as List).isNotEmpty) {
        _itemControllers.clear();
        for (final item in (t['items'] as List)) {
          final desc = item is Map ? (item['description'] ?? '') : item.toString();
          _itemControllers.add(TextEditingController(text: desc));
        }
      }
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    for (final c in _itemControllers) c.dispose();
    super.dispose();
  }

  InputDecoration _dec({String? label, String? hint, Widget? suffix}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.muted, fontSize: 13),
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.muted),
      suffixIcon: suffix,
      filled: true,
      fillColor: AppThemeDecorations.pageBackground(context),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    );
  }

  Future<void> _save() async {
    // Validate title
    if (_titleCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يرجى إدخال عنوان المهمة في الخطوة الأولى'),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
      // Don't reset step - just show error
      return;
    }

    setState(() => _saving = true);
    try {
      final items = _itemControllers
          .map((c) => c.text.trim())
          .where((t) => t.isNotEmpty)
          .toList();

      String? estimatedArrivalIso;
      if (_estimatedArrivalTime != null) {
        final base = _scheduledDate ?? DateTime.now();
        estimatedArrivalIso = DateTime(
          base.year, base.month, base.day,
          _estimatedArrivalTime!.hour,
          _estimatedArrivalTime!.minute,
        ).toIso8601String();
      }

      if (_isEdit) {
        // Build update payload - only include non-null values
        final updateInput = <String, dynamic>{
          'id': widget.task!['id'],
          'title': _titleCtrl.text.trim(),
          'collectionType': _collectionType,
          'status': _status,
          'items': items,
        };
        if (_customerId != null) updateInput['customerId'] = _customerId;
        if (_technicianId != null) updateInput['technicianId'] = _technicianId!; // same user id as auth.me for technician
        if (_scheduledDate != null) updateInput['scheduledAt'] = _scheduledDate!.toIso8601String();
        if (estimatedArrivalIso != null) updateInput['estimatedArrivalAt'] = estimatedArrivalIso;
        if (_amountCtrl.text.isNotEmpty) updateInput['amount'] = _amountCtrl.text.trim();
        if (_notesCtrl.text.isNotEmpty) updateInput['notes'] = _notesCtrl.text.trim();

        await ApiService.mutate('tasks.update', input: updateInput);
      } else {
        // Build create payload - items is required, others are optional
        final createInput = <String, dynamic>{
          'title': _titleCtrl.text.trim(),
          'collectionType': _collectionType,
          'items': items,
        };
        if (_customerId != null) createInput['customerId'] = _customerId;
        if (_technicianId != null) createInput['technicianId'] = _technicianId!; // staff id = technician user id (matches auth.me)
        if (_scheduledDate != null) createInput['scheduledAt'] = _scheduledDate!.toIso8601String();
        if (estimatedArrivalIso != null) createInput['estimatedArrivalAt'] = estimatedArrivalIso;
        if (_amountCtrl.text.isNotEmpty) createInput['amount'] = _amountCtrl.text.trim();
        if (_notesCtrl.text.isNotEmpty) createInput['notes'] = _notesCtrl.text.trim();

        await ApiService.mutate('tasks.create', input: createInput);
      }
      widget.onSaved();
    } catch (e) {
      setState(() => _saving = false);
      // طباعة الخطأ في الـ log لتسهيل تتبعه أثناء التطوير
      // سيتم عرضه في التيرمنال مع الوسم التالي:
      // TASK_SAVE_ERROR: <message>
      // لا يؤثر على المستخدم النهائي في النسخة النهائية.
      // تجاهل أي تحذير lints هنا لأن هذا مخصص للديبج فقط.
      // ignore: avoid_print
      print('TASK_SAVE_ERROR: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في الحفظ: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        decoration: BoxDecoration(
          color: AppThemeDecorations.cardColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: DraggableScrollableSheet(
          initialChildSize: 0.92,
          minChildSize: 0.5,
          maxChildSize: 0.97,
          expand: false,
          builder: (_, scrollCtrl) => Column(
            children: [
              // Handle
              Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 40, height: 4,
                decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      _isEdit ? 'تعديل المهمة' : 'مهمة جديدة',
                      style: const TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.muted),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              // Step Indicator - مؤشر الخطوات
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: Row(
                  children: [
                    _StepDot(number: 1, label: 'العميل', active: _step == 0, done: _step > 0),
                    _StepLine(done: _step > 0),
                    _StepDot(number: 2, label: 'التفاصيل', active: _step == 1, done: _step > 1),
                    _StepLine(done: _step > 1),
                    _StepDot(number: 3, label: 'البنود', active: _step == 2, done: false),
                  ],
                ),
              ),

              const Divider(color: AppColors.border, height: 1),

              // Content
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                  children: [
                    if (_step == 0) _buildStep1(),
                    if (_step == 1) _buildStep2(),
                    if (_step == 2) _buildStep3(),
                  ],
                ),
              ),

              // Bottom buttons
              Container(
                padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 20),
                decoration: BoxDecoration(
                  color: AppThemeDecorations.cardColor(context),
                  border: const Border(top: BorderSide(color: AppColors.border)),
                ),
                child: Row(
                  children: [
                    if (_step > 0)
                      Expanded(
                        flex: 1,
                        child: OutlinedButton(
                          onPressed: () => setState(() => _step--),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.text,
                            side: const BorderSide(color: AppColors.border),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('السابق'),
                        ),
                      ),
                    if (_step > 0) const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: _saving ? null : () {
                          if (_step < 2) {
                            setState(() => _step++);
                          } else {
                            _save();
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: _saving
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                            : Text(
                                _step < 2 ? 'التالي ←' : (_isEdit ? 'حفظ التعديلات' : 'إضافة المهمة'),
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── الخطوة 1: العميل والعنوان ──────────────────────────────
  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('عنوان المهمة', style: TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 8),
        TextField(
          controller: _titleCtrl,
          style: const TextStyle(color: AppColors.text),
          decoration: _dec(hint: 'مثال: تركيب كاميرات مراقبة'),
        ),
        const SizedBox(height: 20),
        const Text('اختر العميل', style: TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 8),
        // قائمة العملاء كـ cards قابلة للاختيار
        ...widget.customers.map((c) {
          final id = c['id'] is int ? c['id'] as int : int.tryParse(c['id'].toString());
          final selected = _customerId == id;
          return GestureDetector(
            onTap: () => setState(() => _customerId = id),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary.withOpacity(0.1) : AppThemeDecorations.pageBackground(context),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.border,
                  width: selected ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: selected ? AppColors.primary : AppColors.border,
                    child: Text(
                      (c['name'] ?? '?').toString().isNotEmpty ? (c['name'] ?? '?').toString()[0] : '?',
                      style: TextStyle(color: selected ? Colors.black : AppColors.muted, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c['name'] ?? '', style: TextStyle(color: selected ? AppColors.primary : AppColors.text, fontWeight: FontWeight.w600)),
                        if (c['phone'] != null)
                          Text(c['phone'], style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                      ],
                    ),
                  ),
                  if (selected)
                    const Icon(Icons.check_circle, color: AppColors.primary, size: 20),
                ],
              ),
            ),
          );
        }),
        // بدون عميل
        GestureDetector(
          onTap: () => setState(() => _customerId = null),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: _customerId == null ? AppColors.primary.withOpacity(0.1) : AppThemeDecorations.pageBackground(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _customerId == null ? AppColors.primary : AppColors.border,
                width: _customerId == null ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: _customerId == null ? AppColors.primary : AppColors.border,
                  child: Icon(Icons.person_off_outlined, color: _customerId == null ? Colors.black : AppColors.muted, size: 18),
                ),
                const SizedBox(width: 12),
                Text('بدون عميل', style: TextStyle(color: _customerId == null ? AppColors.primary : AppColors.muted)),
                const Spacer(),
                if (_customerId == null)
                  const Icon(Icons.check_circle, color: AppColors.primary, size: 20),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── الخطوة 2: التفاصيل ──────────────────────────────────────
  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // الفني
        const Text('الفني المسؤول', style: TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          value: _technicianId,
          dropdownColor: AppThemeDecorations.cardColor(context),
          style: const TextStyle(color: AppColors.text),
          decoration: _dec(hint: 'اختر الفني'),
          items: [
            const DropdownMenuItem(value: null, child: Text('بدون فني', style: TextStyle(color: AppColors.muted))),
            ...widget.technicians.map((t) => DropdownMenuItem(
              value: t['id'] is int ? t['id'] as int : int.tryParse(t['id'].toString()),
              child: Text(t['name'] ?? '', style: const TextStyle(color: AppColors.text)),
            )),
          ],
          onChanged: (v) => setState(() => _technicianId = v),
        ),
        const SizedBox(height: 16),

        // التاريخ ووقت الوصول
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text('تاريخ الموعد', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                      const Spacer(),
                      TextButton(
                        onPressed: () => setState(() {
                          _scheduledDate = null;
                          _estimatedArrivalTime = null;
                        }),
                        child: const Text('بدون', style: TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _scheduledDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                        builder: (c, child) => Theme(
                          data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: AppColors.primary)),
                          child: child!,
                        ),
                      );
                      if (picked != null) {
                        setState(() => _scheduledDate = picked);
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppThemeDecorations.pageBackground(context),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.muted),
                          const SizedBox(width: 8),
                          Text(
                            _scheduledDate != null
                                ? '${_scheduledDate!.day}/${_scheduledDate!.month}/${_scheduledDate!.year}'
                                : 'اختر تاريخ',
                            style: TextStyle(color: _scheduledDate != null ? AppColors.text : AppColors.muted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('وقت الوصول', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: context,
                        initialTime: _estimatedArrivalTime ?? TimeOfDay.now(),
                        builder: (c, child) => Theme(
                          data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: AppColors.primary)),
                          child: child!,
                        ),
                      );
                      if (picked != null) setState(() => _estimatedArrivalTime = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: AppThemeDecorations.pageBackground(context),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.access_time, size: 16, color: AppColors.muted),
                          const SizedBox(width: 8),
                          Text(
                            _estimatedArrivalTime != null
                                ? _estimatedArrivalTime!.format(context)
                                : 'اختر وقت',
                            style: TextStyle(color: _estimatedArrivalTime != null ? AppColors.text : AppColors.muted, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // المبلغ وطريقة الدفع
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('المبلغ (ج.م)', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _amountCtrl,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: AppColors.text),
                    decoration: _dec(hint: '0.00'),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('طريقة الدفع', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: _collectionType,
                    dropdownColor: AppThemeDecorations.cardColor(context),
                    style: const TextStyle(color: AppColors.text),
                    decoration: _dec(),
                    items: const [
                      DropdownMenuItem(value: 'cash', child: Text('نقداً', style: TextStyle(color: AppColors.text))),
                      DropdownMenuItem(value: 'transfer', child: Text('تحويل بنكي', style: TextStyle(color: AppColors.text))),
                    ],
                    onChanged: (v) => setState(() => _collectionType = v ?? 'cash'),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // الحالة (تعديل فقط)
        if (_isEdit) ...[
          const Text('الحالة', style: TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _status,
            dropdownColor: AppThemeDecorations.cardColor(context),
            style: const TextStyle(color: AppColors.text),
            decoration: _dec(),
            items: const [
              DropdownMenuItem(value: 'pending', child: Text('معلقة', style: TextStyle(color: AppColors.text))),
              DropdownMenuItem(value: 'assigned', child: Text('معينة', style: TextStyle(color: AppColors.text))),
              DropdownMenuItem(value: 'in_progress', child: Text('جارية', style: TextStyle(color: AppColors.text))),
              DropdownMenuItem(value: 'completed', child: Text('مكتملة', style: TextStyle(color: AppColors.text))),
              DropdownMenuItem(value: 'cancelled', child: Text('ملغاة', style: TextStyle(color: AppColors.text))),
            ],
            onChanged: (v) => setState(() => _status = v ?? 'assigned'),
          ),
          const SizedBox(height: 16),
        ],

        // الملاحظات
        const Text('ملاحظات', style: TextStyle(color: AppColors.muted, fontSize: 13)),
        const SizedBox(height: 8),
        TextField(
          controller: _notesCtrl,
          maxLines: 3,
          style: const TextStyle(color: AppColors.text),
          decoration: _dec(hint: 'أي ملاحظات إضافية...'),
        ),
      ],
    );
  }

  // ── الخطوة 3: البنود ──────────────────────────────────────
  Widget _buildStep3() {
    return StatefulBuilder(
      builder: (ctx, setS) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ملخص المهمة
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppThemeDecorations.pageBackground(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ملخص المهمة', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                const SizedBox(height: 8),
                Text(_titleCtrl.text, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 15)),
                const SizedBox(height: 6),
                if (_scheduledDate != null)
                  Row(children: [
                    const Icon(Icons.calendar_today_outlined, size: 13, color: AppColors.muted),
                    const SizedBox(width: 6),
                    Text(
                      '${_scheduledDate!.day}/${_scheduledDate!.month}/${_scheduledDate!.year}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                    if (_estimatedArrivalTime != null) ...[
                      const SizedBox(width: 12),
                      const Icon(Icons.access_time, size: 13, color: AppColors.primary),
                      const SizedBox(width: 4),
                      Text('وصول: ${_estimatedArrivalTime!.format(ctx)}', style: const TextStyle(color: AppColors.primary, fontSize: 12)),
                    ],
                  ]),
                if (_amountCtrl.text.isNotEmpty)
                  Row(children: [
                    const Icon(Icons.attach_money, size: 13, color: AppColors.muted),
                    const SizedBox(width: 4),
                    Text('${_amountCtrl.text} ج.م', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                  ]),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // بنود المهمة
          Row(
            children: [
              const Icon(Icons.checklist_rounded, color: AppColors.primary, size: 18),
              const SizedBox(width: 8),
              const Text('بنود المهمة', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 15)),
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  setState(() => _itemControllers.add(TextEditingController()));
                  setS(() {});
                },
                icon: const Icon(Icons.add, size: 16, color: AppColors.primary),
                label: const Text('إضافة بند', style: TextStyle(color: AppColors.primary, fontSize: 13)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text('أضف خطوات أو بنود العمل المطلوبة في هذه المهمة', style: TextStyle(color: AppColors.muted, fontSize: 12)),
          const SizedBox(height: 12),

          ..._itemControllers.asMap().entries.map((entry) {
            final idx = entry.key;
            final ctrl = entry.value;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text('${idx + 1}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: ctrl,
                      style: const TextStyle(color: AppColors.text),
                      decoration: _dec(hint: 'وصف البند ${idx + 1}...'),
                    ),
                  ),
                  if (_itemControllers.length > 1) ...[
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () {
                        setState(() => _itemControllers.removeAt(idx));
                        setS(() {});
                      },
                      child: Container(
                        width: 32, height: 32,
                        decoration: BoxDecoration(
                          color: Colors.red.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.close, color: Colors.red, size: 16),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── مكونات مؤشر الخطوات ──────────────────────────────────────
class _StepDot extends StatelessWidget {
  final int number;
  final String label;
  final bool active;
  final bool done;

  const _StepDot({required this.number, required this.label, required this.active, required this.done});

  @override
  Widget build(BuildContext context) {
    Color bg = done ? AppColors.primary : (active ? AppColors.primary : AppColors.border);
    Color fg = done ? Colors.black : (active ? Colors.black : AppColors.muted);

    return Column(
      children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Center(
            child: done
                ? const Icon(Icons.check, color: Colors.black, size: 16)
                : Text('$number', style: TextStyle(color: fg, fontWeight: FontWeight.bold, fontSize: 13)),
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: active ? AppColors.primary : AppColors.muted, fontSize: 11)),
      ],
    );
  }
}

class _StepLine extends StatelessWidget {
  final bool done;
  const _StepLine({required this.done});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 18),
        color: done ? AppColors.primary : AppColors.border,
      ),
    );
  }
}
