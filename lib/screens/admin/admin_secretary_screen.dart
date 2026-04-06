import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';

const _kSecretaryAptColors = <String, Color>{
  'blue': Colors.blue,
  'green': Colors.green,
  'orange': Colors.orange,
  'purple': Colors.purple,
  'teal': Colors.teal,
  'red': Colors.red,
};

class AdminSecretaryScreen extends StatefulWidget {
  const AdminSecretaryScreen({super.key});
  @override
  State<AdminSecretaryScreen> createState() => _AdminSecretaryScreenState();
}

class _AdminSecretaryScreenState extends State<AdminSecretaryScreen> {
  DateTime _selectedDate = DateTime.now();
  DateTime _focusedMonth = DateTime.now();
  List<Map<String, dynamic>> _appointments = [];
  List<Map<String, dynamic>> _staffList = [];
  bool _loading = true;
  /// عرض مواعيد اليوم المعيّنة للمستخدم الحالي فقط (تذكيري / تذكير لشخص معيّن).
  bool _filterMineOnly = false;

  final List<Map<String, dynamic>> _quickActions = [
    {'icon': Icons.event_available_outlined, 'label': 'حجز موعد', 'color': Colors.blue, 'type': 'booking'},
    {'icon': Icons.phone_callback_outlined, 'label': 'مكالمة', 'color': Colors.green, 'type': 'call'},
    {'icon': Icons.home_repair_service_outlined, 'label': 'زيارة منزلية', 'color': Colors.orange, 'type': 'visit'},
    {'icon': Icons.engineering_outlined, 'label': 'صيانة', 'color': Colors.purple, 'type': 'maintenance'},
    {'icon': Icons.receipt_long_outlined, 'label': 'متابعة طلب', 'color': Colors.teal, 'type': 'followup'},
    {'icon': Icons.meeting_room_outlined, 'label': 'اجتماع', 'color': Colors.red, 'type': 'meeting'},
  ];

  static const _typeIcons = <String, IconData>{
    'booking': Icons.event_available_outlined,
    'call': Icons.phone_callback_outlined,
    'visit': Icons.home_repair_service_outlined,
    'maintenance': Icons.engineering_outlined,
    'followup': Icons.receipt_long_outlined,
    'meeting': Icons.meeting_room_outlined,
  };

  @override
  void initState() {
    super.initState();
    _loadStaff();
    _loadAppointments();
  }

  Future<void> _loadStaff() async {
    try {
      final res = await ApiService.query('appointments.staffList');
      if (res['success'] == true && res['data'] is List) {
        setState(() => _staffList = List<Map<String, dynamic>>.from(res['data']));
      }
    } catch (e) {
      debugPrint('Staff load error: $e');
    }
  }

  Future<void> _loadAppointments() async {
    try {
      final res = await ApiService.query('appointments.list', input: {
        'month': _focusedMonth.month,
        'year': _focusedMonth.year,
      });
      if (res['success'] == true && res['data'] is List) {
        setState(() {
          _appointments = List<Map<String, dynamic>>.from(res['data']);
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Appointments load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _todayAppointments {
    return _appointments.where((a) {
      final d = DateTime.tryParse(a['appointmentDate'] ?? '');
      if (d == null) return false;
      return d.year == _selectedDate.year && d.month == _selectedDate.month && d.day == _selectedDate.day;
    }).toList()
      ..sort((a, b) {
        final da = DateTime.tryParse(a['appointmentDate'] ?? '') ?? DateTime(2000);
        final db = DateTime.tryParse(b['appointmentDate'] ?? '') ?? DateTime(2000);
        return da.compareTo(db);
      });
  }

  bool _hasAppointments(DateTime day) {
    return _appointments.any((a) {
      final d = DateTime.tryParse(a['appointmentDate'] ?? '');
      if (d == null) return false;
      return d.year == day.year && d.month == day.month && d.day == day.day;
    });
  }

  String _typeLabel(String? type) {
    const map = {
      'booking': 'حجز موعد',
      'call': 'مكالمة',
      'visit': 'زيارة منزلية',
      'maintenance': 'صيانة',
      'followup': 'متابعة طلب',
      'meeting': 'اجتماع',
    };
    return map[type ?? ''] ?? (type ?? 'موعد');
  }

  List<Map<String, dynamic>> _filteredTodayAppointments(BuildContext context) {
    final base = _todayAppointments;
    if (!_filterMineOnly) return base;
    final uid = context.watch<AuthProvider>().user?.id;
    if (uid == null) return base;
    return base.where((a) {
      final at = a['assignedTo'];
      if (at == null) return false;
      final ai = at is int ? at : (at as num).toInt();
      return ai == uid;
    }).toList();
  }

  String _colorNameFromFlutter(Color c) {
    if (c == Colors.blue) return 'blue';
    if (c == Colors.green) return 'green';
    if (c == Colors.orange) return 'orange';
    if (c == Colors.purple) return 'purple';
    if (c == Colors.teal) return 'teal';
    if (c == Colors.red) return 'red';
    return 'blue';
  }

  void _showAppointmentDetail(Map<String, dynamic> apt) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SecretaryAppointmentDetailSheet(
        apt: apt,
        typeLabel: _typeLabel(apt['type'] as String?),
        onParentRefresh: _loadAppointments,
      ),
    );
  }

  Future<void> _deleteAppointment(int id) async {
    try {
      await ApiService.mutate('appointments.delete', input: {'id': id});
      setState(() => _appointments.removeWhere((a) => a['id'] == id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في الحذف: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showAddAppointmentDialog({String? presetType}) {
    final titleCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    DateTime selDT = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 9, 0);
    String selType = presetType ?? 'booking';
    int? selectedStaffId;

    if (presetType != null) {
      final action = _quickActions.firstWhere((q) => q['type'] == presetType, orElse: () => _quickActions.first);
      titleCtrl.text = action['label'];
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setS) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx2).viewInsets.bottom),
          child: Container(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx2).size.height * 0.85),
            decoration: BoxDecoration(
              color: AppThemeDecorations.cardColor(ctx2),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(2)))),
                  const SizedBox(height: 16),
                  const Text('موعد جديد', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 16),

                  // -- نوع الموعد --
                  const Text('نوع الموعد', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 56,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: _quickActions.map((qa) {
                        final isSel = selType == qa['type'];
                        return GestureDetector(
                          onTap: () {
                            setS(() => selType = qa['type']);
                            if (titleCtrl.text.isEmpty) titleCtrl.text = qa['label'];
                          },
                          child: Container(
                            margin: const EdgeInsets.only(left: 8),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSel ? (qa['color'] as Color).withOpacity(0.2) : AppThemeDecorations.pageBackground(context),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isSel ? qa['color'] as Color : AppColors.border, width: isSel ? 1.5 : 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(qa['icon'] as IconData, color: isSel ? qa['color'] as Color : AppColors.muted, size: 16),
                                const SizedBox(width: 6),
                                Text(qa['label'] as String, style: TextStyle(color: isSel ? qa['color'] as Color : AppColors.muted, fontSize: 12, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // -- عنوان الموعد --
                  TextField(
                    controller: titleCtrl,
                    style: const TextStyle(color: AppColors.text),
                    decoration: InputDecoration(
                      labelText: 'عنوان الموعد',
                      labelStyle: const TextStyle(color: AppColors.muted),
                      filled: true, fillColor: AppThemeDecorations.pageBackground(context),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // -- اختيار موظف --
                  const Text('تعيين موظف (مشترك)', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: AppThemeDecorations.pageBackground(context),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int?>(
                        value: selectedStaffId,
                        isExpanded: true,
                        dropdownColor: AppThemeDecorations.cardColor(context),
                        hint: const Text('اختر موظف (اختياري)', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                        icon: const Icon(Icons.person_add_outlined, color: AppColors.primary, size: 20),
                        items: [
                          const DropdownMenuItem<int?>(value: null, child: Text('بدون تعيين', style: TextStyle(color: AppColors.muted, fontSize: 13))),
                          ..._staffList.map((s) {
                            final roleLabel = s['role'] == 'admin' ? 'مدير' : s['role'] == 'technician' ? 'فني' : 'موظف';
                            return DropdownMenuItem<int?>(
                              value: s['id'] as int,
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 14,
                                    backgroundColor: AppColors.primary.withOpacity(0.2),
                                    child: Text((s['name'] as String).isNotEmpty ? (s['name'] as String)[0] : '?', style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(s['name'] as String, style: const TextStyle(color: AppColors.text, fontSize: 13), overflow: TextOverflow.ellipsis)),
                                  Text(roleLabel, style: const TextStyle(color: AppColors.muted, fontSize: 10)),
                                ],
                              ),
                            );
                          }),
                        ],
                        onChanged: (v) => setS(() => selectedStaffId = v),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // -- التاريخ والوقت --
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            final picked = await showDatePicker(
                              context: ctx2,
                              initialDate: selDT,
                              firstDate: DateTime.now().subtract(const Duration(days: 365)),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                              builder: (c, child) => Theme(data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: AppColors.primary)), child: child!),
                            );
                            if (picked != null) setS(() => selDT = DateTime(picked.year, picked.month, picked.day, selDT.hour, selDT.minute));
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: AppThemeDecorations.pageBackground(context), borderRadius: BorderRadius.circular(10)),
                            child: Row(children: [
                              const Icon(Icons.calendar_today_outlined, color: AppColors.primary, size: 18),
                              const SizedBox(width: 8),
                              Text('${selDT.day}/${selDT.month}/${selDT.year}', style: const TextStyle(color: AppColors.text, fontSize: 13)),
                            ]),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: GestureDetector(
                          onTap: () async {
                            final picked = await showTimePicker(
                              context: ctx2,
                              initialTime: TimeOfDay(hour: selDT.hour, minute: selDT.minute),
                              builder: (c, child) => Theme(data: ThemeData.dark().copyWith(colorScheme: const ColorScheme.dark(primary: AppColors.primary)), child: child!),
                            );
                            if (picked != null) setS(() => selDT = DateTime(selDT.year, selDT.month, selDT.day, picked.hour, picked.minute));
                          },
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: AppThemeDecorations.pageBackground(context), borderRadius: BorderRadius.circular(10)),
                            child: Row(children: [
                              const Icon(Icons.access_time, color: AppColors.primary, size: 18),
                              const SizedBox(width: 8),
                              Text('${selDT.hour.toString().padLeft(2, '0')}:${selDT.minute.toString().padLeft(2, '0')}', style: const TextStyle(color: AppColors.text, fontSize: 13)),
                            ]),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // -- ملاحظات --
                  TextField(
                    controller: notesCtrl,
                    style: const TextStyle(color: AppColors.text),
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'ملاحظات (اختياري)',
                      labelStyle: const TextStyle(color: AppColors.muted),
                      filled: true, fillColor: AppThemeDecorations.pageBackground(context),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary)),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // -- زر الحفظ --
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        if (titleCtrl.text.trim().isEmpty) return;
                        final action = _quickActions.firstWhere((q) => q['type'] == selType);
                        final dateStr = '${selDT.year}-${selDT.month.toString().padLeft(2, '0')}-${selDT.day.toString().padLeft(2, '0')} ${selDT.hour.toString().padLeft(2, '0')}:${selDT.minute.toString().padLeft(2, '0')}:00';

                        try {
                          await ApiService.mutate('appointments.create', input: {
                            'title': titleCtrl.text.trim(),
                            'type': selType,
                            'appointmentDate': dateStr,
                            'notes': notesCtrl.text.trim(),
                            'assignedTo': selectedStaffId,
                            'color': _colorNameFromFlutter(action['color'] as Color),
                          });

                          if (mounted) {
                            Navigator.pop(ctx2);
                            setState(() {
                              _selectedDate = DateTime(selDT.year, selDT.month, selDT.day);
                              _focusedMonth = DateTime(selDT.year, selDT.month);
                            });
                            _loadAppointments();
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('حفظ الموعد', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeDecorations.pageBackground(context),
      appBar: AppBar(
        backgroundColor: AppThemeDecorations.cardColor(context),
        title: const Text('السكرتارية', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: AppColors.text),
        actions: [
          IconButton(icon: const Icon(Icons.add, color: AppColors.primary), onPressed: () => _showAddAppointmentDialog(), tooltip: 'موعد جديد'),
        ],
      ),
      body: Column(
        children: [
          // ── الكالندر ──
          Container(
            color: AppThemeDecorations.cardColor(context),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(icon: const Icon(Icons.chevron_right, color: AppColors.text), onPressed: () {
                      setState(() => _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1));
                      _loadAppointments();
                    }),
                    Text('${_monthName(_focusedMonth.month)} ${_focusedMonth.year}', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 16)),
                    IconButton(icon: const Icon(Icons.chevron_left, color: AppColors.text), onPressed: () {
                      setState(() => _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1));
                      _loadAppointments();
                    }),
                  ],
                ),
                Row(
                  children: ['أح', 'إث', 'ثل', 'أر', 'خم', 'جم', 'سب'].map((d) =>
                    Expanded(child: Center(child: Text(d, style: const TextStyle(color: AppColors.muted, fontSize: 11, fontWeight: FontWeight.w600))))
                  ).toList(),
                ),
                const SizedBox(height: 4),
                _buildCalendarGrid(),
              ],
            ),
          ),
          // ── الإجراءات السريعة ──
          Container(
            color: AppThemeDecorations.pageBackground(context),
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Text('إجراء سريع', style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 80,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    children: _quickActions.map((qa) => GestureDetector(
                      onTap: () => _showAddAppointmentDialog(presetType: qa['type']),
                      child: Container(
                        width: 72,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(color: AppThemeDecorations.cardColor(context), borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.border)),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(width: 38, height: 38, decoration: BoxDecoration(color: (qa['color'] as Color).withOpacity(0.15), borderRadius: BorderRadius.circular(10)), child: Icon(qa['icon'] as IconData, color: qa['color'] as Color, size: 20)),
                            const SizedBox(height: 4),
                            Text(qa['label'] as String, style: const TextStyle(color: AppColors.text, fontSize: 10), textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    )).toList(),
                  ),
                ),
              ],
            ),
          ),
          // ── مواعيد اليوم ──
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Row(
                          children: [
                            const Icon(Icons.today_outlined, color: AppColors.primary, size: 18),
                            const SizedBox(width: 8),
                            Text('مواعيد ${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 15)),
                            const Spacer(),
                            Text('${_filteredTodayAppointments(context).length} موعد', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Row(
                          children: [
                            FilterChip(
                              label: const Text('الكل', style: TextStyle(fontSize: 12)),
                              selected: !_filterMineOnly,
                              onSelected: (_) => setState(() => _filterMineOnly = false),
                              selectedColor: AppColors.primary.withOpacity(0.25),
                              checkmarkColor: AppColors.primary,
                            ),
                            const SizedBox(width: 8),
                            FilterChip(
                              label: const Text('المعيّنة لي', style: TextStyle(fontSize: 12)),
                              selected: _filterMineOnly,
                              onSelected: (_) => setState(() => _filterMineOnly = true),
                              selectedColor: AppColors.primary.withOpacity(0.25),
                              checkmarkColor: AppColors.primary,
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: _filteredTodayAppointments(context).isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.event_available_outlined, size: 48, color: AppColors.muted.withOpacity(0.4)),
                                    const SizedBox(height: 12),
                                    const Text('لا توجد مواعيد في هذا اليوم', style: TextStyle(color: AppColors.muted, fontSize: 14)),
                                    const SizedBox(height: 8),
                                    TextButton.icon(
                                      onPressed: () => _showAddAppointmentDialog(),
                                      icon: const Icon(Icons.add, color: AppColors.primary, size: 16),
                                      label: const Text('إضافة موعد', style: TextStyle(color: AppColors.primary)),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: _filteredTodayAppointments(context).length,
                                itemBuilder: (ctx, i) {
                                  final apt = _filteredTodayAppointments(context)[i];
                                  final dt = DateTime.tryParse(apt['appointmentDate'] ?? '') ?? DateTime.now();
                                  final color = _kSecretaryAptColors[apt['color']] ?? Colors.blue;
                                  final icon = _typeIcons[apt['type']] ?? Icons.event;
                                  final assigneeName = (apt['assigneeName'] ?? '') as String;
                                  final completed = apt['completedAt'] != null && apt['completedAt'].toString().isNotEmpty;

                                  return Dismissible(
                                    key: Key('apt_${apt['id']}'),
                                    direction: DismissDirection.endToStart,
                                    background: Container(
                                      alignment: Alignment.centerLeft,
                                      padding: const EdgeInsets.only(left: 20),
                                      decoration: BoxDecoration(color: Colors.red.withOpacity(0.2), borderRadius: BorderRadius.circular(14)),
                                      child: const Icon(Icons.delete_outline, color: Colors.red),
                                    ),
                                    confirmDismiss: (_) async {
                                      return await showDialog<bool>(
                                        context: context,
                                        builder: (c) => AlertDialog(
                                          backgroundColor: AppThemeDecorations.cardColor(context),
                                          title: const Text('حذف الموعد؟', style: TextStyle(color: AppColors.text)),
                                          content: const Text('هل أنت متأكد من حذف هذا الموعد؟', style: TextStyle(color: AppColors.muted)),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('إلغاء')),
                                            TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('حذف', style: TextStyle(color: Colors.red))),
                                          ],
                                        ),
                                      ) ?? false;
                                    },
                                    onDismissed: (_) => _deleteAppointment(apt['id'] as int),
                                    child: Opacity(
                                      opacity: completed ? 0.55 : 1,
                                      child: Material(
                                        color: Colors.transparent,
                                        child: InkWell(
                                          borderRadius: BorderRadius.circular(14),
                                          onTap: () => _showAppointmentDetail(apt),
                                          child: Container(
                                      margin: const EdgeInsets.only(bottom: 10),
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: AppThemeDecorations.cardColor(context),
                                        borderRadius: BorderRadius.circular(14),
                                        border: Border.all(color: completed ? Colors.green.withOpacity(0.4) : AppColors.border),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(width: 42, height: 42, decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(10)), child: Icon(icon, color: color, size: 22)),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(child: Text(apt['title'] ?? '', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 14))),
                                                    if (completed)
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                        decoration: BoxDecoration(color: Colors.green.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                                                        child: const Text('تم التنفيذ', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.w600)),
                                                      ),
                                                  ],
                                                ),
                                                Padding(
                                                  padding: const EdgeInsets.only(top: 2),
                                                  child: Text(_typeLabel(apt['type'] as String?), style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                                                ),
                                                if (assigneeName.isNotEmpty)
                                                  Padding(
                                                    padding: const EdgeInsets.only(top: 2),
                                                    child: Row(
                                                      children: [
                                                        const Icon(Icons.person_outline, color: AppColors.primary, size: 13),
                                                        const SizedBox(width: 4),
                                                        Text(assigneeName, style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.w600)),
                                                      ],
                                                    ),
                                                  ),
                                                if ((apt['notes'] ?? '').toString().isNotEmpty)
                                                  Padding(
                                                    padding: const EdgeInsets.only(top: 2),
                                                    child: Text(
                                                      apt['notes'].toString(),
                                                      style: const TextStyle(color: AppColors.muted, fontSize: 12),
                                                      maxLines: 3,
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                              ],
                                            ),
                                          ),
                                          if (!completed)
                                            IconButton(
                                              tooltip: 'التفاصيل والمتابعة',
                                              icon: const Icon(Icons.chat_bubble_outline, color: AppColors.primary, size: 24),
                                              onPressed: () => _showAppointmentDetail(apt),
                                            ),
                                          if ((apt['followupCount'] as int? ?? 0) > 0)
                                            Padding(
                                              padding: const EdgeInsets.only(left: 4),
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                decoration: BoxDecoration(color: Colors.teal.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                                                child: Text('${apt['followupCount']}', style: const TextStyle(color: Colors.teal, fontSize: 11, fontWeight: FontWeight.bold)),
                                              ),
                                            ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                                            child: Text('${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                                          ),
                                        ],
                                      ),
                                    ),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddAppointmentDialog(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.black,
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildCalendarGrid() {
    final firstDay = DateTime(_focusedMonth.year, _focusedMonth.month, 1);
    final lastDay = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0);
    final startWeekday = firstDay.weekday % 7;
    final totalCells = startWeekday + lastDay.day;
    final rows = (totalCells / 7).ceil();

    return Column(
      children: List.generate(rows, (row) {
        return Row(
          children: List.generate(7, (col) {
            final dayIndex = row * 7 + col - startWeekday + 1;
            if (dayIndex < 1 || dayIndex > lastDay.day) return const Expanded(child: SizedBox(height: 36));
            final day = DateTime(_focusedMonth.year, _focusedMonth.month, dayIndex);
            final isSel = day.year == _selectedDate.year && day.month == _selectedDate.month && day.day == _selectedDate.day;
            final isToday = day.year == DateTime.now().year && day.month == DateTime.now().month && day.day == DateTime.now().day;
            final hasApt = _hasAppointments(day);
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() { _selectedDate = day; _focusedMonth = DateTime(day.year, day.month); }),
                child: Container(
                  height: 36,
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: isSel ? AppColors.primary : (isToday ? AppColors.primary.withOpacity(0.15) : Colors.transparent),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('$dayIndex', style: TextStyle(color: isSel ? Colors.black : (isToday ? AppColors.primary : AppColors.text), fontWeight: isSel || isToday ? FontWeight.bold : FontWeight.normal, fontSize: 13)),
                      if (hasApt) Container(width: 4, height: 4, decoration: BoxDecoration(color: isSel ? Colors.black : AppColors.primary, shape: BoxShape.circle)),
                    ],
                  ),
                ),
              ),
            );
          }),
        );
      }),
    );
  }

  String _monthName(int month) {
    const names = ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
    return names[month - 1];
  }
}

/// تفاصيل الموعد + سجل متابعة (من اتصل، ماذا قال) قبل إنهاء مهمة السكرتارية.
class _SecretaryAppointmentDetailSheet extends StatefulWidget {
  const _SecretaryAppointmentDetailSheet({
    required this.apt,
    required this.typeLabel,
    required this.onParentRefresh,
  });

  final Map<String, dynamic> apt;
  final String typeLabel;
  final Future<void> Function() onParentRefresh;

  @override
  State<_SecretaryAppointmentDetailSheet> createState() => _SecretaryAppointmentDetailSheetState();
}

class _SecretaryAppointmentDetailSheetState extends State<_SecretaryAppointmentDetailSheet> {
  final TextEditingController _followupCtrl = TextEditingController();
  List<Map<String, dynamic>> _followups = [];
  bool _loadingFollowups = true;
  bool _saving = false;
  bool _completing = false;

  int get _followupCount => _followups.length;

  @override
  void initState() {
    super.initState();
    _loadFollowups();
  }

  @override
  void dispose() {
    _followupCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFollowups() async {
    setState(() => _loadingFollowups = true);
    try {
      final id = widget.apt['id'];
      final res = await ApiService.query('appointments.followups', input: {'id': id});
      if (!mounted) return;
      if (res['success'] == true && res['data'] is List) {
        setState(() {
          _followups = List<Map<String, dynamic>>.from(res['data'] as List);
          _loadingFollowups = false;
        });
      } else {
        setState(() => _loadingFollowups = false);
      }
    } catch (e) {
      if (mounted) setState(() => _loadingFollowups = false);
    }
  }

  Future<void> _addFollowup() async {
    final text = _followupCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _saving = true);
    try {
      await ApiService.mutate('appointments.addFollowup', input: {
        'id': widget.apt['id'],
        'body': text,
      });
      _followupCtrl.clear();
      await _loadFollowups();
      await widget.onParentRefresh();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _complete() async {
    setState(() => _completing = true);
    try {
      await ApiService.mutate('appointments.complete', input: {'id': widget.apt['id']});
      await widget.onParentRefresh();
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _completing = false);
    }
  }

  String _fmtTime(String? s) {
    final d = DateTime.tryParse(s ?? '');
    if (d == null) return s ?? '';
    return '${d.day}/${d.month} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final apt = widget.apt;
    final dt = DateTime.tryParse(apt['appointmentDate'] ?? '') ?? DateTime.now();
    final notes = (apt['notes'] ?? '').toString();
    final creatorName = (apt['creatorName'] ?? '').toString();
    final assigneeName = (apt['assigneeName'] ?? '').toString();
    final completed = apt['completedAt'] != null && apt['completedAt'].toString().isNotEmpty;
    final color = _kSecretaryAptColors[apt['color']] ?? Colors.blue;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.92),
        decoration: BoxDecoration(
          color: AppThemeDecorations.cardColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 0),
              child: Row(
                children: [
                  IconButton(icon: const Icon(Icons.close, color: AppColors.muted), onPressed: () => Navigator.pop(context)),
                  const Expanded(
                    child: Text(
                      'تفاصيل الموعد والمتابعة',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  const SizedBox(width: 48),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: color.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                          child: Text(widget.typeLabel, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
                        ),
                        const SizedBox(width: 8),
                        if (completed)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.green.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                            child: const Text('تم التنفيذ', style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.w600)),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(apt['title']?.toString() ?? '', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 17)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.access_time, size: 16, color: AppColors.muted),
                        const SizedBox(width: 6),
                        Text(
                          '${dt.day}/${dt.month}/${dt.year} — ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}',
                          style: const TextStyle(color: AppColors.muted, fontSize: 13),
                        ),
                      ],
                    ),
                    if (creatorName.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.edit_note_outlined, size: 16, color: AppColors.muted),
                          const SizedBox(width: 6),
                          Expanded(child: Text('من أنشأ: $creatorName', style: const TextStyle(color: AppColors.muted, fontSize: 13))),
                        ],
                      ),
                    ],
                    if (assigneeName.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.person_outline, size: 16, color: AppColors.primary),
                          const SizedBox(width: 6),
                          Expanded(child: Text('المعيّن: $assigneeName', style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.w600))),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    const Text('الوصف والملاحظات الأصلية', style: TextStyle(color: AppColors.muted, fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppThemeDecorations.pageBackground(context),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Text(
                        notes.isEmpty ? '— لا توجد ملاحظات إضافية —' : notes,
                        style: TextStyle(color: notes.isEmpty ? AppColors.muted : AppColors.text, fontSize: 14, height: 1.35),
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        const Icon(Icons.forum_outlined, color: AppColors.primary, size: 20),
                        const SizedBox(width: 8),
                        const Text('سجل المتابعة', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 15)),
                        const Spacer(),
                        if (_followupCount > 0)
                          Text('$_followupCount', style: TextStyle(color: Colors.teal.shade700, fontWeight: FontWeight.bold, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'سجّل ماذا تم (مثال: اتصل فلان وقال كذا، أو تم التواصل مع…). لا يمكن إنهاء المهمة قبل تسجيل متابعة واحدة على الأقل.',
                      style: TextStyle(color: AppColors.muted.withOpacity(0.9), fontSize: 11, height: 1.3),
                    ),
                    const SizedBox(height: 10),
                    if (_loadingFollowups)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator(color: AppColors.primary, strokeWidth: 2)),
                      )
                    else if (_followups.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text('لا توجد متابعات بعد.', style: TextStyle(color: AppColors.muted.withOpacity(0.8), fontSize: 13)),
                      )
                    else
                      ..._followups.map((f) {
                        final author = (f['authorName'] ?? '').toString().trim();
                        final body = (f['body'] ?? '').toString();
                        final at = _fmtTime(f['createdAt']?.toString());
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppThemeDecorations.pageBackground(context),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border.withOpacity(0.6)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      author.isEmpty ? 'موظف' : author,
                                      style: const TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                  Text(at, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(body, style: const TextStyle(color: AppColors.text, fontSize: 13, height: 1.35)),
                            ],
                          ),
                        );
                      }),
                    if (!completed) ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: _followupCtrl,
                        style: const TextStyle(color: AppColors.text),
                        minLines: 2,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: 'إضافة متابعة (ردّ الموظف)',
                          hintText: 'مثال: اتصل المهندس X وحدّد موعد…',
                          labelStyle: const TextStyle(color: AppColors.muted),
                          filled: true,
                          fillColor: AppThemeDecorations.pageBackground(context),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _saving ? null : _addFollowup,
                          icon: _saving
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                              : const Icon(Icons.add_comment_outlined, size: 18),
                          label: Text(_saving ? 'جاري الحفظ…' : 'حفظ المتابعة'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: (_completing || _followupCount < 1) ? null : _complete,
                          icon: _completing
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                              : const Icon(Icons.task_alt, size: 20),
                          label: Text(_completing ? 'جاري الإنهاء…' : 'إنهاء مهمة السكرتارية'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.black,
                            disabledBackgroundColor: AppColors.muted.withOpacity(0.35),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      if (_followupCount < 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'سجّل متابعة واحدة على الأقل لتفعيل زر الإنهاء.',
                            style: TextStyle(color: Colors.orange.shade800, fontSize: 12),
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
