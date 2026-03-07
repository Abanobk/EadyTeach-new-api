import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../utils/app_theme.dart';

class MyTasksScreen extends StatefulWidget {
  const MyTasksScreen({super.key});

  @override
  State<MyTasksScreen> createState() => _MyTasksScreenState();
}

class _MyTasksScreenState extends State<MyTasksScreen> {
  List<dynamic> _tasks = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

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
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('مهامي', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.card,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.muted),
            onPressed: _loadTasks,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _tasks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.assignment_outlined, size: 64, color: AppColors.muted),
                      const SizedBox(height: 16),
                      const Text('لا توجد مهام بعد',
                          style: TextStyle(color: AppColors.muted, fontSize: 18)),
                      const SizedBox(height: 8),
                      const Text('يمكنك طلب خدمة من قسم "طلب خدمة"',
                          style: TextStyle(color: AppColors.muted, fontSize: 13)),
                    ],
                  ),
                )
              : RefreshIndicator(
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
    final scheduledAt = task['scheduledAt'] != null
        ? DateTime.fromMillisecondsSinceEpoch(task['scheduledAt'])
        : null;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
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
                    style: const TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.bold,
                        fontSize: 15),
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
                  const Icon(Icons.engineering_outlined, size: 14, color: AppColors.muted),
                  const SizedBox(width: 4),
                  Text('الفني: ${task['technicianName']}',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                ],
              ),
            ],
            if (scheduledAt != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.calendar_today_outlined, size: 14, color: AppColors.muted),
                  const SizedBox(width: 4),
                  Text(
                    'الموعد: ${scheduledAt.day}/${scheduledAt.month}/${scheduledAt.year}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('اضغط لعرض التفاصيل والملاحظات',
                    style: TextStyle(color: AppColors.primary.withOpacity(0.8), fontSize: 11)),
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
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
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
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: Text(task['title'] ?? 'تفاصيل المهمة',
              style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
          backgroundColor: AppColors.card,
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
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('مهمة #${task['id']}',
                              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                          _StatusBadge(status: status),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(task['title'] ?? '',
                          style: const TextStyle(
                              color: AppColors.text,
                              fontWeight: FontWeight.bold,
                              fontSize: 18)),
                      if (task['notes'] != null && task['notes'].toString().isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(task['notes'],
                            style: const TextStyle(color: AppColors.muted, fontSize: 13)),
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
                          value: '${scheduledAt.day}/${scheduledAt.month}/${scheduledAt.year}',
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
                const Text('ملاحظات الفني',
                    style: TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.bold,
                        fontSize: 16)),
                const SizedBox(height: 12),

                if (_loadingNotes)
                  const Center(child: CircularProgressIndicator(color: AppColors.primary))
                else if (_notes.isEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: const Column(
                      children: [
                        Icon(Icons.notes_outlined, size: 40, color: AppColors.muted),
                        SizedBox(height: 8),
                        Text('لا توجد ملاحظات بعد',
                            style: TextStyle(color: AppColors.muted)),
                      ],
                    ),
                  )
                else
                  ...(_notes.map((note) => _NoteCard(note: note)).toList()),
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

  const _InfoRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.muted),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          Expanded(
            child: Text(value,
                style: const TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w500)),
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
        color: AppColors.card,
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
              Text(note['authorName'] ?? 'الفني',
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
              const Spacer(),
              if (createdAt != null)
                Text(
                  '${createdAt.day}/${createdAt.month} ${createdAt.hour}:${createdAt.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(note['content'] ?? '',
              style: const TextStyle(color: AppColors.text, fontSize: 14)),
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
                              child: Icon(Icons.play_circle_outline,
                                  color: Colors.white, size: 36),
                            ),
                          )
                        : Image.network(
                            url,
                            width: 80,
                            height: 80,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 80,
                              height: 80,
                              color: AppColors.border,
                              child: const Icon(Icons.broken_image_outlined,
                                  color: AppColors.muted),
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
                  child: Text('افتح الفيديو في المتصفح',
                      style: TextStyle(color: Colors.white)),
                ),
              )
            : InteractiveViewer(
                child: Image.network(url, fit: BoxFit.contain),
              ),
      ),
    );
  }
}
