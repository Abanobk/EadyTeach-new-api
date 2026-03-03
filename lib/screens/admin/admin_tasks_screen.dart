import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../utils/app_theme.dart';

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

  @override
  void initState() {
    super.initState();
    _loadAll();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        ApiService.query('tasks.getAll'),
        ApiService.query('clients.list'),
        ApiService.query('clients.technicians'),
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

  InputDecoration _inputDecoration({String hint = ''}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.muted),
      filled: true,
      fillColor: AppColors.bg,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  void _showTaskDialog(Map<String, dynamic>? task) {
    final isEdit = task != null;
    final titleCtrl = TextEditingController(text: task?['title'] ?? '');
    final notesCtrl = TextEditingController(text: task?['notes'] ?? '');
    final amountCtrl = TextEditingController(text: task?['amount']?.toString() ?? '');
    String? selectedCustomerId = task?['customerId']?.toString();
    String? selectedTechnicianId = task?['technicianId']?.toString();
    String selectedStatus = task?['status'] ?? 'pending';
    DateTime? scheduledDate;
    if (task?['scheduledDate'] != null) {
      scheduledDate = DateTime.fromMillisecondsSinceEpoch(task!['scheduledDate']);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Directionality(
              textDirection: TextDirection.rtl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(isEdit ? 'تعديل المهمة' : 'إضافة مهمة جديدة',
                          style: const TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold)),
                      IconButton(icon: const Icon(Icons.close, color: AppColors.muted), onPressed: () => Navigator.pop(ctx)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('عنوان المهمة *', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(controller: titleCtrl, style: const TextStyle(color: AppColors.text), decoration: _inputDecoration(hint: 'مثال: تركيب كاميرا مراقبة')),
                  const SizedBox(height: 12),
                  const Text('العميل', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: selectedCustomerId,
                    dropdownColor: AppColors.card,
                    style: const TextStyle(color: AppColors.text),
                    decoration: _inputDecoration(),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('-- اختر عميل --')),
                      ..._customers.map((u) => DropdownMenuItem(value: u['id'].toString(), child: Text(u['name'] ?? ''))),
                    ],
                    onChanged: (v) => setModalState(() => selectedCustomerId = v),
                  ),
                  const SizedBox(height: 12),
                  const Text('الفني', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: selectedTechnicianId,
                    dropdownColor: AppColors.card,
                    style: const TextStyle(color: AppColors.text),
                    decoration: _inputDecoration(),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('-- اختر فني --')),
                      ..._technicians.map((u) => DropdownMenuItem(value: u['id'].toString(), child: Text(u['name'] ?? ''))),
                    ],
                    onChanged: (v) => setModalState(() => selectedTechnicianId = v),
                  ),
                  const SizedBox(height: 12),
                  if (isEdit) ...[
                    const Text('الحالة', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      value: selectedStatus,
                      dropdownColor: AppColors.card,
                      style: const TextStyle(color: AppColors.text),
                      decoration: _inputDecoration(),
                      items: const [
                        DropdownMenuItem(value: 'pending', child: Text('جديدة')),
                        DropdownMenuItem(value: 'assigned', child: Text('معيّنة')),
                        DropdownMenuItem(value: 'in_progress', child: Text('جاري')),
                        DropdownMenuItem(value: 'completed', child: Text('مكتملة')),
                        DropdownMenuItem(value: 'cancelled', child: Text('ملغاة')),
                      ],
                      onChanged: (v) => setModalState(() => selectedStatus = v!),
                    ),
                    const SizedBox(height: 12),
                  ],
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: scheduledDate ?? DateTime.now(),
                        firstDate: DateTime.now().subtract(const Duration(days: 365)),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setModalState(() => scheduledDate = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(10)),
                      child: Row(children: [
                        const Icon(Icons.calendar_today, color: AppColors.muted, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          scheduledDate != null ? '${scheduledDate!.day}/${scheduledDate!.month}/${scheduledDate!.year}' : 'اختر تاريخ الموعد',
                          style: TextStyle(color: scheduledDate != null ? AppColors.text : AppColors.muted),
                        ),
                      ]),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text('المبلغ (ج.م)', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(controller: amountCtrl, keyboardType: TextInputType.number, style: const TextStyle(color: AppColors.text), decoration: _inputDecoration(hint: '0.00')),
                  const SizedBox(height: 12),
                  const Text('ملاحظات', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  const SizedBox(height: 6),
                  TextField(controller: notesCtrl, maxLines: 3, style: const TextStyle(color: AppColors.text), decoration: _inputDecoration(hint: 'أي تفاصيل إضافية...')),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        if (titleCtrl.text.trim().isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('عنوان المهمة مطلوب')));
                          return;
                        }
                        Navigator.pop(ctx);
                        try {
                          if (isEdit) {
                            final body = <String, dynamic>{'id': task!['id'], 'title': titleCtrl.text.trim(), 'status': selectedStatus};
                            if (selectedTechnicianId != null) body['technicianId'] = int.parse(selectedTechnicianId!);
                            if (scheduledDate != null) body['scheduledAt'] = scheduledDate!.toIso8601String();
                            if (amountCtrl.text.isNotEmpty) body['amount'] = amountCtrl.text.trim();
                            if (notesCtrl.text.isNotEmpty) body['notes'] = notesCtrl.text.trim();
                            await ApiService.mutate('tasks.update', input: body);
                          } else {
                            final body = <String, dynamic>{'title': titleCtrl.text.trim(), 'items': []};
                            if (selectedCustomerId != null) body['customerId'] = int.parse(selectedCustomerId!);
                            if (selectedTechnicianId != null) body['technicianId'] = int.parse(selectedTechnicianId!);
                            if (scheduledDate != null) body['scheduledAt'] = scheduledDate!.toIso8601String();
                            if (amountCtrl.text.isNotEmpty) body['amount'] = amountCtrl.text.trim();
                            if (notesCtrl.text.isNotEmpty) body['notes'] = notesCtrl.text.trim();
                            await ApiService.mutate('tasks.create', input: body);
                          }
                          _loadAll();
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isEdit ? 'تم تحديث المهمة' : 'تمت إضافة المهمة'), backgroundColor: AppColors.success));
                        } catch (e) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error));
                        }
                      },
                      style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: Text(isEdit ? 'حفظ التعديلات' : 'إضافة المهمة'),
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

  void _deleteTask(Map<String, dynamic> task) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppColors.card,
          title: const Text('إلغاء المهمة', style: TextStyle(color: AppColors.text)),
          content: Text('هل تريد إلغاء "${task['title']}"؟', style: const TextStyle(color: AppColors.muted)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('لا')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('نعم، إلغاء', style: TextStyle(color: AppColors.error))),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      try {
        await ApiService.mutate('tasks.update', input: {'id': task['id'], 'status': 'cancelled'});
        _loadAll();
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم إلغاء المهمة'), backgroundColor: AppColors.success));
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('خطأ: $e'), backgroundColor: AppColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('إدارة المهام'),
        backgroundColor: AppColors.card,
        automaticallyImplyLeading: false,
        actions: [IconButton(icon: const Icon(Icons.refresh, color: AppColors.muted), onPressed: _loadAll)],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showTaskDialog(null),
        backgroundColor: AppColors.primary,
        child: const Icon(Icons.add, color: Colors.black),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _tasks.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.task_outlined, color: AppColors.muted, size: 48),
                  const SizedBox(height: 12),
                  const Text('لا توجد مهام', style: TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(onPressed: () => _showTaskDialog(null), icon: const Icon(Icons.add, color: Colors.black), label: const Text('إضافة مهمة')),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _tasks.length,
                  itemBuilder: (ctx, i) => _TaskRow(task: _tasks[i], onEdit: () => _showTaskDialog(_tasks[i]), onDelete: () => _deleteTask(_tasks[i])),
                ),
    );
  }
}

class _TaskRow extends StatelessWidget {
  final Map<String, dynamic> task;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  const _TaskRow({required this.task, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final status = task['status'] as String? ?? 'pending';
    final date = task['scheduledDate'] != null ? DateTime.fromMillisecondsSinceEpoch(task['scheduledDate']) : null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Expanded(child: Text(task['title'] ?? '', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 14))),
          Row(children: [
            GestureDetector(onTap: onEdit, child: const Icon(Icons.edit_outlined, color: AppColors.muted, size: 20)),
            const SizedBox(width: 12),
            GestureDetector(onTap: onDelete, child: const Icon(Icons.delete_outline, color: AppColors.error, size: 20)),
          ]),
        ]),
        const SizedBox(height: 6),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          _StatusBadge(status: status),
          Row(children: [
            if (task['technicianName'] != null) ...[
              const Icon(Icons.person_outline, color: AppColors.muted, size: 14),
              const SizedBox(width: 4),
              Text(task['technicianName'], style: const TextStyle(color: AppColors.muted, fontSize: 11)),
              const SizedBox(width: 8),
            ],
            if (date != null) Text('${date.day}/${date.month}/${date.year}', style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          ]),
        ]),
      ]),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});
  @override
  Widget build(BuildContext context) {
    Color color; String label;
    switch (status) {
      case 'pending': color = const Color(0xFFD4920A); label = 'جديدة'; break;
      case 'assigned': color = const Color(0xFF1565C0); label = 'معيّنة'; break;
      case 'in_progress': color = const Color(0xFF6A1B9A); label = 'جاري'; break;
      case 'completed': color = AppColors.success; label = 'مكتملة'; break;
      case 'cancelled': color = AppColors.error; label = 'ملغاة'; break;
      default: color = AppColors.muted; label = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
