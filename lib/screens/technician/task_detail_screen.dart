import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import '../../utils/app_theme.dart';
import '../../services/api_service.dart';

class TaskDetailScreen extends StatefulWidget {
  final Map<String, dynamic> task;
  const TaskDetailScreen({super.key, required this.task});

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  Map<String, dynamic>? _fullTask;
  List<Map<String, dynamic>> _items = [];
  bool _loadingTask = true;
  bool _isCompleting = false;
  File? _transferPhoto;
  String? _estimatedArrival;
  bool _loadingETA = false;

  @override
  void initState() {
    super.initState();
    _loadFullTask();
  }

  Future<void> _loadFullTask() async {
    setState(() => _loadingTask = true);
    try {
      final taskId = widget.task['id'];
      if (taskId == null) {
        setState(() {
          _fullTask = widget.task;
          _loadingTask = false;
        });
        return;
      }
      final id = taskId is int ? taskId : int.tryParse(taskId.toString()) ?? taskId;

      final taskRes = await ApiService.query('tasks.byId', input: {'id': id});
      final itemsRes = await ApiService.query('tasks.items', input: {'taskId': id});

      final rawTask = taskRes['data'];
      final rawItems = itemsRes['data'];

      Map<String, dynamic> fullTask = rawTask is Map
          ? Map<String, dynamic>.from(rawTask)
          : Map<String, dynamic>.from(widget.task);

      // Merge list-level fields (customerName, customerPhone, etc.) if not present
      for (final key in widget.task.keys) {
        if (!fullTask.containsKey(key) || fullTask[key] == null) {
          fullTask[key] = widget.task[key];
        }
      }

      List<Map<String, dynamic>> items = [];
      if (rawItems is List) {
        items = rawItems
            .map<Map<String, dynamic>>((item) => Map<String, dynamic>.from(item as Map))
            .toList();
      }

      setState(() {
        _fullTask = fullTask;
        _items = items;
        _loadingTask = false;
      });
    } catch (e) {
      setState(() {
        _fullTask = Map<String, dynamic>.from(widget.task);
        _loadingTask = false;
      });
    }
  }

  // ── Data helpers ──────────────────────────────────────────────────────────

  String? _getCustomerName() {
    final t = _fullTask ?? widget.task;
    final c = t['customer'];
    if (c is Map) return c['name']?.toString();
    return t['customerName']?.toString();
  }

  String? _getCustomerPhone() {
    final t = _fullTask ?? widget.task;
    final c = t['customer'];
    if (c is Map) return c['phone']?.toString();
    return t['customerPhone']?.toString();
  }

  String? _getCustomerAddress() {
    final t = _fullTask ?? widget.task;
    final c = t['customer'];
    if (c is Map) return c['address']?.toString();
    return t['customerAddress']?.toString();
  }

  String? _getCustomerLocation() {
    final t = _fullTask ?? widget.task;
    final c = t['customer'];
    if (c is Map) return c['location']?.toString();
    return t['customerLocation']?.toString();
  }

  String? _getTechnicianName() {
    final t = _fullTask ?? widget.task;
    final tech = t['technician'];
    if (tech is Map) return tech['name']?.toString();
    return t['technicianName']?.toString();
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '—';
    try {
      final dt = DateTime.parse(dateStr).toLocal();
      return DateFormat('EEEE، d MMMM yyyy – hh:mm a', 'ar').format(dt);
    } catch (_) {
      return dateStr;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending': return Colors.orange;
      case 'assigned': return Colors.blue;
      case 'in_progress': return Colors.purple;
      case 'completed': return Colors.green;
      case 'cancelled': return Colors.red;
      default: return AppColors.muted;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending': return 'قيد الانتظار';
      case 'assigned': return 'تم التعيين';
      case 'in_progress': return 'جاري';
      case 'completed': return 'مكتمل';
      case 'cancelled': return 'ملغي';
      default: return status;
    }
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _callPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openWhatsApp(String phone) async {
    final cleaned = phone.replaceAll(RegExp(r'[^\d]'), '');
    final intl = cleaned.startsWith('0') ? '2$cleaned' : cleaned;
    final uri = Uri.parse('https://wa.me/$intl');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _openDirections(String location) async {
    final parts = location.split(',');
    if (parts.length < 2) return;
    final lat = parts[0].trim();
    final lng = parts[1].trim();
    final uri = Uri.parse('https://maps.google.com/maps?daddr=$lat,$lng');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _calculateETA(String customerLocation) async {
    setState(() {
      _loadingETA = true;
      _estimatedArrival = null;
    });
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _loadingETA = false;
          _estimatedArrival = 'خدمة الموقع غير مفعّلة';
        });
        return;
      }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever ||
          permission == LocationPermission.denied) {
        setState(() {
          _loadingETA = false;
          _estimatedArrival = 'تم رفض إذن الموقع';
        });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      final parts = customerLocation.split(',');
      final destLat = double.tryParse(parts[0].trim()) ?? 0;
      final destLng = double.tryParse(parts[1].trim()) ?? 0;

      final distanceMeters = Geolocator.distanceBetween(
          pos.latitude, pos.longitude, destLat, destLng);
      final distanceKm = distanceMeters / 1000;
      final minutes = (distanceKm / 30 * 60).round();
      final arrival = DateTime.now().add(Duration(minutes: minutes));
      final formatted = DateFormat('hh:mm a', 'ar').format(arrival);
      setState(() {
        _loadingETA = false;
        _estimatedArrival =
            '~$minutes دقيقة (${distanceKm.toStringAsFixed(1)} كم) — وصول: $formatted';
      });
    } catch (e) {
      setState(() {
        _loadingETA = false;
        _estimatedArrival = 'تعذّر حساب الوقت';
      });
    }
  }

  Future<void> _toggleItem(Map<String, dynamic> item) async {
    final newVal = !(item['isCompleted'] as bool? ?? false);
    setState(() => item['isCompleted'] = newVal);
    try {
      await ApiService.mutate('tasks.updateItem',
          input: {'id': item['id'], 'isCompleted': newVal});
    } catch (_) {
      setState(() => item['isCompleted'] = !newVal);
    }
  }

  Future<void> _pickTransferPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked != null) setState(() => _transferPhoto = File(picked.path));
  }

  Future<void> _completeTask() async {
    final task = _fullTask ?? widget.task;
    final taskId = task['id'];
    if (taskId == null) return;
    final id = taskId is int ? taskId : int.tryParse(taskId.toString()) ?? taskId;

    setState(() => _isCompleting = true);
    try {
      await ApiService.mutate('tasks.update', input: {
        'id': id,
        'status': 'completed',
        'completedAt': DateTime.now().toUtc().toIso8601String(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تم إنهاء المهمة بنجاح ✅'),
              backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e'), backgroundColor: Colors.red),
        );
      }
    }
    setState(() => _isCompleting = false);
  }

  Future<void> _notifyArrival() async {
    final task = _fullTask ?? widget.task;
    final taskId = task['id'];
    if (taskId == null) return;
    final id = taskId is int ? taskId : int.tryParse(taskId.toString()) ?? taskId;
    try {
      await ApiService.mutate('tasks.notifyArrival', input: {'taskId': id});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('تم إرسال إشعار الوصول ✅'),
              backgroundColor: Colors.green),
        );
      }
    } catch (_) {}
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loadingTask) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
            backgroundColor: AppColors.card,
            title: const Text('تفاصيل المهمة')),
        body: const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final task = _fullTask ?? widget.task;
    final status = task['status']?.toString() ?? 'pending';
    final taskId = task['id']?.toString() ?? '';
    final title = task['title']?.toString() ?? 'مهمة';
    final customerName = _getCustomerName();
    final customerPhone = _getCustomerPhone();
    final customerAddress = _getCustomerAddress();
    final customerLocation = _getCustomerLocation();
    final technicianName = _getTechnicianName();
    final scheduledAt = task['scheduledAt']?.toString();
    final amount = task['amount']?.toString();
    final collectionType = task['collectionType']?.toString();
    final notes = task['notes']?.toString();
    final hasCustomer = customerName != null || customerPhone != null || customerAddress != null;

    return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.card,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TASK #$taskId',
                  style: const TextStyle(
                      color: AppColors.primary, fontSize: 11, letterSpacing: 1)),
              Text(title,
                  style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ],
          ),
          actions: [
            Container(
              margin: const EdgeInsets.only(left: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _statusColor(status).withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _statusColor(status).withOpacity(0.4)),
              ),
              child: Text(_statusLabel(status),
                  style: TextStyle(
                      color: _statusColor(status),
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── بيانات العميل ─────────────────────────────────────────────
            if (hasCustomer) ...[
              _sectionTitle('بيانات العميل', Icons.person_outline),
              _card([
                if (customerName != null)
                  _infoRow(Icons.person, customerName, sub: 'عميل'),
                if (customerPhone != null) ...[
                  _divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    child: Row(children: [
                      const Icon(Icons.phone, color: AppColors.muted, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('رقم الهاتف',
                              style: TextStyle(color: AppColors.muted, fontSize: 11)),
                          Text(customerPhone,
                              style: const TextStyle(
                                  color: AppColors.text,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600)),
                        ]),
                      ),
                      _actionBtn('واتساب', Icons.chat, const Color(0xFF25D366),
                          () => _openWhatsApp(customerPhone)),
                      const SizedBox(width: 8),
                      _actionBtn('اتصال', Icons.phone, Colors.blue,
                          () => _callPhone(customerPhone)),
                    ]),
                  ),
                ],
                if (customerAddress != null) ...[
                  _divider(),
                  _infoRow(Icons.location_on_outlined, customerAddress, label: 'العنوان'),
                ],
                if (customerLocation != null && customerLocation.isNotEmpty) ...[
                  _divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        const Icon(Icons.map_outlined, color: AppColors.muted, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            const Text('الموقع الجغرافي',
                                style: TextStyle(color: AppColors.muted, fontSize: 11)),
                            Text(customerLocation,
                                style: const TextStyle(color: AppColors.text, fontSize: 13)),
                          ]),
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: _locationBtn(
                            'تحديد الاتجاهات',
                            Icons.navigation,
                            AppColors.primary,
                            () => _openDirections(customerLocation),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _locationBtn(
                            'وقت الوصول',
                            Icons.access_time,
                            Colors.purple,
                            _loadingETA ? null : () => _calculateETA(customerLocation),
                            loading: _loadingETA,
                          ),
                        ),
                      ]),
                      if (_estimatedArrival != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.purple.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.purple.withOpacity(0.3)),
                          ),
                          child: Row(children: [
                            const Icon(Icons.schedule, color: Colors.purple, size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_estimatedArrival!,
                                  style: const TextStyle(color: Colors.purple, fontSize: 13)),
                            ),
                          ]),
                        ),
                      ],
                    ]),
                  ),
                ],
              ]),
              const SizedBox(height: 16),
            ],

            // ── تفاصيل المهمة ─────────────────────────────────────────────
            _sectionTitle('تفاصيل المهمة', Icons.assignment_outlined),
            _card([
              if (technicianName != null)
                _infoRow(Icons.engineering_outlined, technicianName, label: 'الفني المعين'),
              if (scheduledAt != null) ...[
                _divider(),
                _infoRow(Icons.calendar_today_outlined, _formatDate(scheduledAt),
                    label: 'وقت الوصول المحدد'),
              ],
              if (amount != null && amount.isNotEmpty) ...[
                _divider(),
                _infoRow(Icons.attach_money, 'ج.م $amount',
                    label: 'المبلغ المطلوب', valueColor: AppColors.primary),
              ],
              if (collectionType != null) ...[
                _divider(),
                _infoRow(
                  collectionType == 'cash' ? Icons.money : Icons.account_balance,
                  collectionType == 'cash' ? 'نقدي 💵' : 'تحويل 🏦',
                  label: 'طريقة التحصيل',
                ),
              ],
              if (notes != null && notes.isNotEmpty) ...[
                _divider(),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Row(children: [
                      Icon(Icons.notes, color: AppColors.muted, size: 18),
                      SizedBox(width: 8),
                      Text('ملاحظات',
                          style: TextStyle(color: AppColors.muted, fontSize: 11)),
                    ]),
                    const SizedBox(height: 6),
                    Text(notes, style: const TextStyle(color: AppColors.text, fontSize: 14)),
                  ]),
                ),
              ],
            ]),
            const SizedBox(height: 16),

            // ── بنود المهمة ───────────────────────────────────────────────
            if (_items.isNotEmpty) ...[
              _sectionTitle('بنود المهمة', Icons.checklist_outlined),
              _card([
                ..._items.asMap().entries.map((entry) {
                  final i = entry.key;
                  final item = entry.value;
                  final done = item['isCompleted'] as bool? ?? false;
                  return Column(children: [
                    if (i > 0) _divider(),
                    InkWell(
                      onTap: () => _toggleItem(item),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
                        child: Row(children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: done ? AppColors.primary : Colors.transparent,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: done ? AppColors.primary : AppColors.border,
                                width: 1.5,
                              ),
                            ),
                            child: done
                                ? const Icon(Icons.check, color: Colors.black, size: 14)
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              item['description']?.toString() ?? '',
                              style: TextStyle(
                                color: done ? AppColors.muted : AppColors.text,
                                fontSize: 14,
                                decoration: done ? TextDecoration.lineThrough : null,
                              ),
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ]);
                }),
              ]),
              const SizedBox(height: 16),
            ],

            // ── التحصيل ───────────────────────────────────────────────────
            if (status != 'completed' && status != 'cancelled') ...[
              _sectionTitle('التحصيل', Icons.payments_outlined),
              _card([
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(children: [
                    Expanded(
                      child: _paymentTypeCard('نقدي', '💵', collectionType == 'cash'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _paymentTypeCard('تحويل', '🏦', collectionType == 'transfer'),
                    ),
                  ]),
                ),
                if (collectionType == 'transfer') ...[
                  _divider(),
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('صورة إيصال التحويل',
                          style: TextStyle(color: AppColors.muted, fontSize: 12)),
                      const SizedBox(height: 8),
                      GestureDetector(
                        onTap: _pickTransferPhoto,
                        child: Container(
                          height: 100,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: AppColors.bg,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: _transferPhoto != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.file(_transferPhoto!, fit: BoxFit.cover))
                              : const Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.cloud_upload_outlined,
                                        color: AppColors.muted, size: 28),
                                    SizedBox(height: 4),
                                    Text('اضغط لرفع الصورة',
                                        style: TextStyle(
                                            color: AppColors.muted, fontSize: 12)),
                                  ],
                                ),
                        ),
                      ),
                    ]),
                  ),
                ],
              ]),
              const SizedBox(height: 16),
            ],

            // ── أزرار الإجراءات ───────────────────────────────────────────
            if (status != 'completed' && status != 'cancelled') ...[
              if (status == 'assigned' || status == 'in_progress') ...[
                OutlinedButton.icon(
                  onPressed: _notifyArrival,
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('إرسال إشعار الوصول'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange,
                    side: const BorderSide(color: Colors.orange),
                    minimumSize: const Size(double.infinity, 48),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              ElevatedButton.icon(
                onPressed: _isCompleting ? null : _completeTask,
                icon: _isCompleting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.check_circle_outline),
                label: Text(_isCompleting ? 'جاري الإنهاء...' : 'إنهاء المهمة ✓'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }

  // ── UI Helpers ────────────────────────────────────────────────────────────

  Widget _sectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(icon, color: AppColors.primary, size: 18),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                color: AppColors.primary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5)),
      ]),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(children: children),
      ),
    );
  }

  Widget _divider() => const Divider(color: AppColors.border, height: 1);

  Widget _infoRow(IconData icon, String value,
      {String? label, String? sub, Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
      child: Row(children: [
        Icon(icon, color: AppColors.muted, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (label != null)
              Text(label,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11)),
            Text(value,
                style: TextStyle(
                    color: valueColor ?? AppColors.text,
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
            if (sub != null)
              Text(sub,
                  style: const TextStyle(color: AppColors.muted, fontSize: 11)),
          ]),
        ),
      ]),
    );
  }

  Widget _actionBtn(String label, IconData icon, Color color, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 15),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 12, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  Widget _locationBtn(String label, IconData icon, Color color, VoidCallback? onTap,
      {bool loading = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          loading
              ? SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: color))
              : Icon(icon, color: color, size: 16),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  color: color, fontSize: 13, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }

  Widget _paymentTypeCard(String label, String emoji, bool selected) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: selected ? AppColors.primary.withOpacity(0.15) : AppColors.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? AppColors.primary : AppColors.border,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Column(children: [
        Text(emoji, style: const TextStyle(fontSize: 22)),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(
                color: selected ? AppColors.primary : AppColors.muted,
                fontWeight: FontWeight.bold)),
      ]),
    );
  }
}
