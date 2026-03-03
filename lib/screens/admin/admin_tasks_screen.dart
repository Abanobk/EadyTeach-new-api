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
        ApiService.query('tasks.list'),
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

  InputDecoration _inputDecoration({String hint = '', String? label}) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.muted),
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
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'completed': return Colors.green;
      case 'in_progress': return Colors.blue;
      case 'cancelled': return Colors.red;
      case 'assigned': return AppColors.primary;
      default: return AppColors.muted;
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

  void _showTaskDialog({Map<String, dynamic>? task}) {
    final isEdit = task != null;
    final titleCtrl = TextEditingController(text: task?['title'] ?? '');
    final notesCtrl = TextEditingController(text: task?['notes'] ?? '');
    final amountCtrl = TextEditingController(text: task?['amount']?.toString() ?? '');

    int? selectedCustomerId = task?['customerId'] is int ? task!['customerId'] : null;
    int? selectedTechnicianId = task?['technicianId'] is int ? task!['technicianId'] : null;
    String selectedStatus = task?['status'] ?? 'assigned';
    String selectedCollectionType = task?['collectionType'] ?? 'cash';
    DateTime? scheduledDate;
    if (task?['scheduledAt'] != null) {
      try { scheduledDate = DateTime.parse(task!['scheduledAt'].toString()); } catch (_) {}
    }

    // Dynamic items list - قائمة البنود القابلة للزيادة
    final List<TextEditingController> itemControllers = [];
    if (task?['items'] != null && (task!['items'] as List).isNotEmpty) {
      for (final item in (task['items'] as List)) {
        final desc = item is Map ? (item['description'] ?? '') : item.toString();
        itemControllers.add(TextEditingController(text: desc));
      }
    } else {
      itemControllers.add(TextEditingController()); // بند واحد افتراضي
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => DraggableScrollableSheet(
          initialChildSize: 0.92,
          minChildSize: 0.5,
          maxChildSize: 0.97,
          expand: false,
          builder: (_, scrollCtrl) => Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              children: [
                // Handle bar
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
                        isEdit ? 'تعديل المهمة' : 'إضافة مهمة جديدة',
                        style: const TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close, color: AppColors.muted),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                ),
                const Divider(color: AppColors.border),
                // Form
                Expanded(
                  child: ListView(
                    controller: scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
                    children: [
                      // العنوان
                      TextField(
                        controller: titleCtrl,
                        style: const TextStyle(color: AppColors.text),
                        decoration: _inputDecoration(label: 'عنوان المهمة *', hint: 'مثال: تركيب كاميرات مراقبة'),
                      ),
                      const SizedBox(height: 14),

                      // العميل
                      DropdownButtonFormField<int>(
                        value: selectedCustomerId,
                        dropdownColor: AppColors.card,
                        style: const TextStyle(color: AppColors.text),
                        decoration: _inputDecoration(label: 'العميل'),
                        hint: const Text('اختر العميل', style: TextStyle(color: AppColors.muted)),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('بدون عميل', style: TextStyle(color: AppColors.muted))),
                          ..._customers.map((c) => DropdownMenuItem(
                            value: c['id'] is int ? c['id'] as int : int.tryParse(c['id'].toString()),
                            child: Text(c['name'] ?? '', style: const TextStyle(color: AppColors.text)),
                          )),
                        ],
                        onChanged: (v) => setModalState(() => selectedCustomerId = v),
                      ),
                      const SizedBox(height: 14),

                      // الفني
                      DropdownButtonFormField<int>(
                        value: selectedTechnicianId,
                        dropdownColor: AppColors.card,
                        style: const TextStyle(color: AppColors.text),
                        decoration: _inputDecoration(label: 'الفني المسؤول'),
                        hint: const Text('اختر الفني', style: TextStyle(color: AppColors.muted)),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('بدون فني', style: TextStyle(color: AppColors.muted))),
                          ..._technicians.map((t) => DropdownMenuItem(
                            value: t['id'] is int ? t['id'] as int : int.tryParse(t['id'].toString()),
                            child: Text(t['name'] ?? '', style: const TextStyle(color: AppColors.text)),
                          )),
                        ],
                        onChanged: (v) => setModalState(() => selectedTechnicianId = v),
                      ),
                      const SizedBox(height: 14),

                      // الحالة (تعديل فقط)
                      if (isEdit) ...[
                        DropdownButtonFormField<String>(
                          value: selectedStatus,
                          dropdownColor: AppColors.card,
                          style: const TextStyle(color: AppColors.text),
                          decoration: _inputDecoration(label: 'الحالة'),
                          items: const [
                            DropdownMenuItem(value: 'pending', child: Text('معلقة', style: TextStyle(color: AppColors.text))),
                            DropdownMenuItem(value: 'assigned', child: Text('معينة', style: TextStyle(color: AppColors.text))),
                            DropdownMenuItem(value: 'in_progress', child: Text('جارية', style: TextStyle(color: AppColors.text))),
                            DropdownMenuItem(value: 'completed', child: Text('مكتملة', style: TextStyle(color: AppColors.text))),
                            DropdownMenuItem(value: 'cancelled', child: Text('ملغاة', style: TextStyle(color: AppColors.text))),
                          ],
                          onChanged: (v) => setModalState(() => selectedStatus = v ?? 'assigned'),
                        ),
                        const SizedBox(height: 14),
                      ],

                      // التاريخ والمبلغ
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: ctx,
                                  initialDate: scheduledDate ?? DateTime.now(),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                  builder: (c, child) => Theme(
                                    data: ThemeData.dark().copyWith(
                                      colorScheme: const ColorScheme.dark(primary: AppColors.primary),
                                    ),
                                    child: child!,
                                  ),
                                );
                                if (picked != null) setModalState(() => scheduledDate = picked);
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                decoration: BoxDecoration(
                                  color: AppColors.bg,
                                  border: Border.all(color: AppColors.border),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(children: [
                                  const Icon(Icons.calendar_today, color: AppColors.muted, size: 16),
                                  const SizedBox(width: 8),
                                  Text(
                                    scheduledDate != null
                                        ? '${scheduledDate!.day}/${scheduledDate!.month}/${scheduledDate!.year}'
                                        : 'تاريخ الموعد',
                                    style: TextStyle(color: scheduledDate != null ? AppColors.text : AppColors.muted, fontSize: 13),
                                  ),
                                ]),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: amountCtrl,
                              style: const TextStyle(color: AppColors.text),
                              decoration: _inputDecoration(label: 'المبلغ (ج.م)', hint: '0.00'),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // طريقة الدفع
                      DropdownButtonFormField<String>(
                        value: selectedCollectionType,
                        dropdownColor: AppColors.card,
                        style: const TextStyle(color: AppColors.text),
                        decoration: _inputDecoration(label: 'طريقة الدفع'),
                        items: const [
                          DropdownMenuItem(value: 'cash', child: Text('نقداً', style: TextStyle(color: AppColors.text))),
                          DropdownMenuItem(value: 'transfer', child: Text('تحويل بنكي', style: TextStyle(color: AppColors.text))),
                        ],
                        onChanged: (v) => setModalState(() => selectedCollectionType = v ?? 'cash'),
                      ),
                      const SizedBox(height: 14),

                      // الملاحظات
                      TextField(
                        controller: notesCtrl,
                        style: const TextStyle(color: AppColors.text),
                        maxLines: 3,
                        decoration: _inputDecoration(label: 'ملاحظات', hint: 'أي تفاصيل إضافية...'),
                      ),
                      const SizedBox(height: 20),

                      // ===== قسم بنود المهمة =====
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.bg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.checklist_rtl, color: AppColors.primary, size: 20),
                                const SizedBox(width: 8),
                                const Text(
                                  'بنود المهمة',
                                  style: TextStyle(color: AppColors.text, fontSize: 15, fontWeight: FontWeight.bold),
                                ),
                                const Spacer(),
                                GestureDetector(
                                  onTap: () => setModalState(() => itemControllers.add(TextEditingController())),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(color: AppColors.primary.withOpacity(0.4)),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.add, color: AppColors.primary, size: 16),
                                        SizedBox(width: 4),
                                        Text('إضافة بند', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'أضف خطوات أو بنود العمل المطلوبة في هذه المهمة',
                              style: TextStyle(color: AppColors.muted, fontSize: 12),
                            ),
                            const SizedBox(height: 14),

                            // قائمة البنود
                            ...itemControllers.asMap().entries.map((entry) {
                              final idx = entry.key;
                              final ctrl = entry.value;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  children: [
                                    // رقم البند
                                    Container(
                                      width: 30, height: 30,
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                                      ),
                                      child: Center(
                                        child: Text(
                                          '${idx + 1}',
                                          style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold, fontSize: 13),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    // حقل النص
                                    Expanded(
                                      child: TextField(
                                        controller: ctrl,
                                        style: const TextStyle(color: AppColors.text, fontSize: 14),
                                        decoration: InputDecoration(
                                          hintText: 'وصف البند ${idx + 1}...',
                                          hintStyle: const TextStyle(color: AppColors.muted, fontSize: 13),
                                          filled: true,
                                          fillColor: AppColors.card,
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: const BorderSide(color: AppColors.border),
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: const BorderSide(color: AppColors.border),
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(8),
                                            borderSide: const BorderSide(color: AppColors.primary),
                                          ),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        ),
                                      ),
                                    ),
                                    // زر الحذف
                                    if (itemControllers.length > 1) ...[
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: () => setModalState(() => itemControllers.removeAt(idx)),
                                        child: Container(
                                          width: 30, height: 30,
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
                            }).toList(),
                          ],
                        ),
                      ),

                      const SizedBox(height: 24),

                      // زر الحفظ
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: () async {
                            if (titleCtrl.text.trim().isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('يرجى إدخال عنوان المهمة'), backgroundColor: Colors.red),
                              );
                              return;
                            }
                            final items = itemControllers
                                .map((c) => c.text.trim())
                                .where((t) => t.isNotEmpty)
                                .toList();

                            try {
                              if (isEdit) {
                                await ApiService.mutate('tasks.update', input: {
                                  'id': task!['id'],
                                  'title': titleCtrl.text.trim(),
                                  'customerId': selectedCustomerId,
                                  'technicianId': selectedTechnicianId,
                                  'status': selectedStatus,
                                  'scheduledAt': scheduledDate?.toIso8601String(),
                                  'amount': amountCtrl.text.isNotEmpty ? amountCtrl.text.trim() : null,
                                  'collectionType': selectedCollectionType,
                                  'notes': notesCtrl.text.isNotEmpty ? notesCtrl.text.trim() : null,
                                  'items': items,
                                });
                              } else {
                                await ApiService.mutate('tasks.create', input: {
                                  'title': titleCtrl.text.trim(),
                                  'customerId': selectedCustomerId,
                                  'technicianId': selectedTechnicianId,
                                  'scheduledAt': scheduledDate?.toIso8601String(),
                                  'amount': amountCtrl.text.isNotEmpty ? amountCtrl.text.trim() : null,
                                  'collectionType': selectedCollectionType,
                                  'notes': notesCtrl.text.isNotEmpty ? notesCtrl.text.trim() : null,
                                  'items': items,
                                });
                              }
                              if (ctx.mounted) Navigator.pop(ctx);
                              _loadAll();
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(isEdit ? 'تم تحديث المهمة ✓' : 'تمت إضافة المهمة بنجاح ✓'),
                                    backgroundColor: Colors.green,
                                  ),
                                );
                              }
                            } catch (e) {
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
                                );
                              }
                            }
                          },
                          child: Text(
                            isEdit ? 'حفظ التعديلات' : 'إضافة المهمة',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.card,
        title: const Text('إدارة المهام', style: TextStyle(color: AppColors.text)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.muted),
            onPressed: _loadAll,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showTaskDialog(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('مهمة جديدة', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _tasks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.assignment_outlined, size: 64, color: AppColors.muted.withOpacity(0.4)),
                      const SizedBox(height: 16),
                      const Text('لا توجد مهام', style: TextStyle(color: AppColors.muted, fontSize: 16)),
                      const SizedBox(height: 8),
                      const Text('اضغط + لإضافة مهمة جديدة', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _tasks.length,
                  itemBuilder: (ctx, i) {
                    final task = _tasks[i];
                    final status = task['status'] ?? 'pending';
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
                            title: Text(
                              task['title'] ?? '',
                              style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const SizedBox(height: 4),
                                if (task['customerName'] != null)
                                  Row(children: [
                                    const Icon(Icons.person_outline, size: 13, color: AppColors.muted),
                                    const SizedBox(width: 4),
                                    Text(task['customerName'], style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                                  ]),
                                if (task['technicianName'] != null)
                                  Row(children: [
                                    const Icon(Icons.engineering_outlined, size: 13, color: AppColors.muted),
                                    const SizedBox(width: 4),
                                    Text(task['technicianName'], style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                                  ]),
                                if (task['scheduledAt'] != null)
                                  Row(children: [
                                    const Icon(Icons.calendar_today_outlined, size: 13, color: AppColors.muted),
                                    const SizedBox(width: 4),
                                    Text(
                                      task['scheduledAt'].toString().substring(0, 10),
                                      style: const TextStyle(color: AppColors.muted, fontSize: 12),
                                    ),
                                  ]),
                                if (task['amount'] != null)
                                  Row(children: [
                                    const Icon(Icons.attach_money, size: 13, color: AppColors.muted),
                                    const SizedBox(width: 4),
                                    Text('${task['amount']} ج.م', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                                  ]),
                              ],
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: _statusColor(status).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: _statusColor(status).withOpacity(0.4)),
                              ),
                              child: Text(
                                _statusLabel(status),
                                style: TextStyle(color: _statusColor(status), fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton.icon(
                                  onPressed: () => _showTaskDialog(task: task),
                                  icon: const Icon(Icons.edit_outlined, size: 16, color: AppColors.primary),
                                  label: const Text('تعديل', style: TextStyle(color: AppColors.primary, fontSize: 13)),
                                ),
                                if (status != 'cancelled')
                                  TextButton.icon(
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (c) => AlertDialog(
                                          backgroundColor: AppColors.card,
                                          title: const Text('تأكيد الإلغاء', style: TextStyle(color: AppColors.text)),
                                          content: const Text('هل تريد إلغاء هذه المهمة؟', style: TextStyle(color: AppColors.muted)),
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
    );
  }
}
