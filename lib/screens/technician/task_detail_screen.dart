import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import '../../utils/app_theme.dart';
import '../../services/api_service.dart';

// ══════════════════════════════════════════════════════════════════════════════
// شاشة تفاصيل المهمة - مطابقة للويب
// ══════════════════════════════════════════════════════════════════════════════
class TaskDetailScreen extends StatefulWidget {
  final Map<String, dynamic> task;
  final VoidCallback? onTaskUpdated;
  const TaskDetailScreen({super.key, required this.task, this.onTaskUpdated});

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  Map<String, dynamic>? _fullTask;
  List<Map<String, dynamic>> _items = [];
  bool _loadingTask = true;

  // Collection state
  String? _collectionMode; // 'cash' | 'transfer' | null
  final _cashAmountCtrl = TextEditingController();
  bool _cashConfirmed = false;
  String? _transferImageUrl;
  bool _uploading = false;
  File? _transferImageFile;

  // ETA
  int? _etaMinutes;
  bool _etaLoading = false;

  // Finish task
  bool _finishing = false;

  // Item media uploading state
  final Map<int, bool> _mediaUploading = {};

  // GPS Tracking
  StreamSubscription<Position>? _locationSub;
  bool _gpsActive = false;
  bool _arrivedDetected = false;

  // Task Notes
  List<Map<String, dynamic>> _notes = [];
  bool _loadingNotes = false;
  bool _addingNote = false;
  final _noteCtrl = TextEditingController();
  List<String> _noteMediaUrls = [];
  List<String> _noteMediaTypes = [];
  bool _noteVisibleToClient = true;
  bool _uploadingNoteMedia = false;

  @override
  void initState() {
    super.initState();
    _loadFullTask();
    _startGpsTracking();
  }

  @override
  void dispose() {
    _cashAmountCtrl.dispose();
    _noteCtrl.dispose();
    _locationSub?.cancel();
    super.dispose();
  }

  // ── GPS Tracking ──────────────────────────────────────────────────────────
  Future<void> _startGpsTracking() async {
    final task = widget.task;
    final status = task['status']?.toString() ?? '';
    if (status == 'completed' || status == 'cancelled') return;
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) return;
      setState(() => _gpsActive = true);
      _locationSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 20),
      ).listen((Position pos) async {
        if (!mounted) return;
        final taskId = widget.task['id'];
        if (taskId == null) return;
        final id = taskId is int ? taskId : int.tryParse(taskId.toString());
        if (id == null) return;
        final customer = _customer;
        double? clientLat, clientLng;
        final locStr = customer?['location']?.toString();
        if (locStr != null && locStr.isNotEmpty) {
          final parts = locStr.split(',');
          if (parts.length >= 2) {
            clientLat = double.tryParse(parts[0].trim());
            clientLng = double.tryParse(parts[1].trim());
          }
        }
        try {
          await ApiService.mutate('technicianLocation.update', input: {
            'taskId': id,
            'latitude': pos.latitude,
            'longitude': pos.longitude,
            'accuracy': pos.accuracy,
            if (clientLat != null) 'customerLat': clientLat,
            if (clientLng != null) 'customerLng': clientLng,
          });
          if (!_arrivedDetected && clientLat != null && clientLng != null) {
            final dist = Geolocator.distanceBetween(pos.latitude, pos.longitude, clientLat, clientLng);
            if (dist < 100) {
              setState(() => _arrivedDetected = true);
              _locationSub?.cancel();
              setState(() => _gpsActive = false);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('📍 تم اكتشاف وصولك للعميل تلقائياً! تم إشعار العميل.'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 4),
                ));
                await _loadFullTask();
              }
            }
          }
        } catch (_) {}
      });
    } catch (_) {}
  }

  // ── Data Loading ─────────────────────────────────────────────────────────

  Future<void> _loadFullTask() async {
    setState(() => _loadingTask = true);
    try {
      final taskId = widget.task['id'];
      if (taskId == null) {
        setState(() { _fullTask = widget.task; _loadingTask = false; });
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

      for (final key in widget.task.keys) {
        if (!fullTask.containsKey(key) || fullTask[key] == null) {
          fullTask[key] = widget.task[key];
        }
      }

      List<Map<String, dynamic>> items = [];
      if (rawItems is List) {
        items = rawItems.map<Map<String, dynamic>>((item) => Map<String, dynamic>.from(item as Map)).toList();
      }

      setState(() {
        _fullTask = fullTask;
        _items = items;
        _loadingTask = false;
      });
      // تحميل الملاحظات
      final idInt = id is int ? id : int.tryParse(id.toString()) ?? 0;
      await _loadNotes(idInt);
    } catch (e) {
      setState(() {
        _fullTask = Map<String, dynamic>.from(widget.task);
        _loadingTask = false;
      });
    }
  }

  Future<void> _loadNotes(int taskId) async {
    setState(() => _loadingNotes = true);
    try {
      final res = await ApiService.query('taskNotes.list', input: {'taskId': taskId});
      final raw = res['data'];
      if (raw is List) {
        setState(() {
          _notes = raw.map<Map<String, dynamic>>((n) => Map<String, dynamic>.from(n as Map)).toList();
        });
      }
    } catch (_) {}
    setState(() => _loadingNotes = false);
  }

  Future<void> _pickNoteMedia({bool isVideo = false}) async {
    final picker = ImagePicker();
    XFile? picked;
    if (isVideo) {
      picked = await picker.pickVideo(source: ImageSource.gallery);
    } else {
      picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
    }
    if (picked == null) return;
    setState(() => _uploadingNoteMedia = true);
    try {
      final url = await ApiService.uploadFile(picked.path);
      setState(() {
        _noteMediaUrls.add(url);
        _noteMediaTypes.add(isVideo ? 'video' : 'image');
        _uploadingNoteMedia = false;
      });
    } catch (_) {
      setState(() => _uploadingNoteMedia = false);
      _showSnack('فشل رفع الملف', Colors.red);
    }
  }

  Future<void> _submitNote(int taskId) async {
    if (_noteCtrl.text.trim().isEmpty) return;
    setState(() => _addingNote = true);
    try {
      await ApiService.mutate('taskNotes.create', input: {
        'taskId': taskId,
        'content': _noteCtrl.text.trim(),
        'mediaUrls': _noteMediaUrls,
        'mediaTypes': _noteMediaTypes,
        'isVisibleToClient': _noteVisibleToClient,
      });
      _noteCtrl.clear();
      setState(() {
        _noteMediaUrls = [];
        _noteMediaTypes = [];
        _addingNote = false;
      });
      await _loadNotes(taskId);
      _showSnack('✅ تم إضافة الملاحظة', Colors.green);
    } catch (e) {
      setState(() => _addingNote = false);
      _showSnack('فشل إضافة الملاحظة', Colors.red);
    }
  }

  Future<void> _deleteNote(int noteId, int taskId) async {
    try {
      await ApiService.mutate('taskNotes.delete', input: {'id': noteId});
      await _loadNotes(taskId);
    } catch (_) {
      _showSnack('فشل حذف الملاحظة', Colors.red);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  Map<String, dynamic>? get _customer {
    final t = _fullTask ?? widget.task;
    final c = t['customer'];
    if (c is Map) return Map<String, dynamic>.from(c);
    // fallback from flat fields
    final name = t['customerName']?.toString();
    final phone = t['customerPhone']?.toString();
    final address = t['customerAddress']?.toString();
    final location = t['customerLocation']?.toString();
    if (name != null || phone != null) {
      return {'name': name, 'phone': phone, 'address': address, 'location': location};
    }
    return null;
  }

  Map<String, dynamic>? get _technician {
    final t = _fullTask ?? widget.task;
    final tech = t['technician'];
    if (tech is Map) return Map<String, dynamic>.from(tech);
    final name = t['technicianName']?.toString();
    if (name != null) return {'name': name};
    return null;
  }

  String _formatDateTime(String? dt) {
    if (dt == null) return '—';
    try {
      final parsed = DateTime.parse(dt).toLocal();
      final days = ['الأحد', 'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت'];
      final months = ['يناير', 'فبراير', 'مارس', 'إبريل', 'مايو', 'يونيو', 'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'];
      final day = days[parsed.weekday % 7];
      final month = months[parsed.month - 1];
      final hour = parsed.hour > 12 ? parsed.hour - 12 : (parsed.hour == 0 ? 12 : parsed.hour);
      final ampm = parsed.hour >= 12 ? 'م' : 'ص';
      final min = parsed.minute.toString().padLeft(2, '0');
      return '$day، ${parsed.day} $month ${parsed.year} – $hour:$min $ampm';
    } catch (_) { return dt; }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'pending': return 'قيد الانتظار';
      case 'assigned': return 'مخصصة';
      case 'in_progress': return 'قيد التنفيذ';
      case 'completed': return '✓ مكتملة';
      case 'cancelled': return 'ملغية';
      default: return s;
    }
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'pending': return Colors.orange;
      case 'assigned': return Colors.blue;
      case 'in_progress': return AppColors.primary;
      case 'completed': return Colors.green;
      case 'cancelled': return Colors.red;
      default: return AppColors.muted;
    }
  }

  bool get _isCompleted => (_fullTask ?? widget.task)['status'] == 'completed';

  bool get _canFinish {
    if (_isCompleted) return false;
    if (_collectionMode == 'cash') return _cashConfirmed;
    if (_collectionMode == 'transfer') return _transferImageUrl != null && _transferImageUrl!.isNotEmpty;
    return false;
  }

  bool get _allItemsDone => _items.isNotEmpty && _items.every((i) => i['isCompleted'] == true);

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _openWhatsApp(String phone) async {
    final cleaned = phone.replaceAll(RegExp(r'[^\d]'), '');
    final intl = cleaned.startsWith('0') ? '2$cleaned' : cleaned;
    final uri = Uri.parse('https://wa.me/$intl');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _callPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _openDirections(double lat, double lng) async {
    final uri = Uri.parse('https://www.google.com/maps/dir/?api=1&destination=$lat,$lng');
    if (await canLaunchUrl(uri)) await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _calcEta(double destLat, double destLng) async {
    setState(() { _etaLoading = true; _etaMinutes = null; });
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnack('خدمة الموقع غير مفعّلة', Colors.red);
        setState(() => _etaLoading = false);
        return;
      }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _showSnack('تم رفض إذن الموقع', Colors.red);
        setState(() => _etaLoading = false);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      final distM = Geolocator.distanceBetween(pos.latitude, pos.longitude, destLat, destLng);
      final mins = (distM / 1000 / 30 * 60).round();
      setState(() { _etaMinutes = mins; _etaLoading = false; });
    } catch (_) {
      _showSnack('تعذّر حساب وقت الوصول', Colors.red);
      setState(() => _etaLoading = false);
    }
  }

  Future<void> _toggleItem(Map<String, dynamic> item) async {
    final newVal = !(item['isCompleted'] as bool? ?? false);
    setState(() => item['isCompleted'] = newVal);
    try {
      await ApiService.mutate('tasks.updateItem', input: {'id': item['id'], 'isCompleted': newVal});
    } catch (_) {
      setState(() => item['isCompleted'] = !newVal);
    }
  }

  Future<void> _pickTransferPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked == null) return;
    setState(() { _uploading = true; _transferImageFile = File(picked.path); });
    try {
      // Upload to server
      final result = await ApiService.uploadFile(picked.path);
      setState(() {
        _transferImageUrl = result;
        _uploading = false;
      });
    } catch (_) {
      // Fallback: use local file path as placeholder
      setState(() {
        _transferImageUrl = picked.path;
        _uploading = false;
      });
    }
  }

  Future<void> _finishTask() async {
    final task = _fullTask ?? widget.task;
    final taskId = task['id'];
    if (taskId == null) return;
    final id = taskId is int ? taskId : int.tryParse(taskId.toString()) ?? taskId;

    setState(() => _finishing = true);
    try {
      final input = <String, dynamic>{
        'id': id,
        'status': 'completed',
        'collectionStatus': 'collected',
        'completedAt': DateTime.now().toUtc().toIso8601String(),
      };
      if (_collectionMode == 'transfer' && _transferImageUrl != null) {
        input['collectionImageUrl'] = _transferImageUrl;
      }
      await ApiService.mutate('tasks.update', input: input);
      _showSnack('تم إنهاء المهمة بنجاح! ✅', Colors.green);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      _showSnack('خطأ: $e', Colors.red);
    }
    setState(() => _finishing = false);
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: color),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loadingTask) {
      return Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(backgroundColor: AppColors.card, title: const Text('تفاصيل المهمة')),
        body: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final task = _fullTask ?? widget.task;
    final status = task['status']?.toString() ?? 'pending';
    final taskId = task['id']?.toString() ?? '';
    final title = task['title']?.toString() ?? 'مهمة';
    final customer = _customer;
    final technician = _technician;
    final scheduledAt = task['scheduledAt']?.toString();
    final amount = task['amount']?.toString();
    final collectionType = task['collectionType']?.toString();
    final notes = task['notes']?.toString();

    // Parse customer location
    double? clientLat, clientLng;
    final locStr = customer?['location']?.toString();
    if (locStr != null && locStr.isNotEmpty) {
      final parts = locStr.split(',');
      if (parts.length >= 2) {
        clientLat = double.tryParse(parts[0].trim());
        clientLng = double.tryParse(parts[1].trim());
      }
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          backgroundColor: AppColors.card,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.primary, size: 18),
            onPressed: () => Navigator.pop(context),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('TASK #$taskId',
                  style: const TextStyle(color: AppColors.primary, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.bold)),
              Text(title,
                  style: const TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.w900)),
            ],
          ),
          actions: [
            Container(
              margin: const EdgeInsets.only(left: 16, right: 4),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: _statusColor(status).withOpacity(0.15),
                borderRadius: BorderRadius.circular(50),
                border: Border.all(color: _statusColor(status).withOpacity(0.4)),
              ),
              child: Text(_statusLabel(status),
                  style: TextStyle(color: _statusColor(status), fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          children: [

            // ── بيانات العميل ──────────────────────────────────────────────
            if (customer != null) ...[
              _sectionCard(
                label: 'بيانات العميل',
                children: [
                  // الاسم
                  Row(children: [
                    Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          (customer['name'] ?? '؟').toString().isNotEmpty
                              ? (customer['name'] ?? '؟').toString()[0].toUpperCase()
                              : '؟',
                          style: const TextStyle(color: AppColors.primary, fontSize: 18, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(customer['name'] ?? '—',
                          style: const TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.bold)),
                      const Text('عميل', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    ]),
                  ]),

                  // رقم الهاتف + أزرار
                  if (customer['phone'] != null) ...[
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('رقم الهاتف', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                        const SizedBox(height: 2),
                        Text(customer['phone'], style: const TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.bold)),
                      ])),
                      _webBtn('📞 اتصال', const Color(0xFF4A90D9), () => _callPhone(customer['phone'])),
                      const SizedBox(width: 8),
                      _webBtn('💬 واتساب', const Color(0xFF25D366), () => _openWhatsApp(customer['phone'])),
                    ]),
                  ],

                  // العنوان
                  if (customer['address'] != null && customer['address'].toString().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _labelValue('العنوان', customer['address'].toString()),
                  ],

                  // الموقع الجغرافي
                  ...[
                    const SizedBox(height: 16),
                    const Text('الموقع الجغرافي', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                    const SizedBox(height: 6),
                    if (clientLat != null && clientLng != null) ...[
                      Text(
                        '${clientLat.toStringAsFixed(5)}, ${clientLng.toStringAsFixed(5)}',
                        style: const TextStyle(color: AppColors.text, fontSize: 13, fontFamily: 'monospace'),
                      ),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(
                          child: _webBtn(
                            '🗺️ تحديد الاتجاهات',
                            AppColors.primary,
                            () => _openDirections(clientLat!, clientLng!),
                            fullWidth: true,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _webBtn(
                            _etaLoading ? '⏳ جاري الحساب...' : '⏱️ وقت الوصول المتوقع',
                            const Color(0xFF9B59B6),
                            _etaLoading ? null : () => _calcEta(clientLat!, clientLng!),
                            fullWidth: true,
                          ),
                        ),
                      ]),
                      if (_etaMinutes != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF9B59B6).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF9B59B6).withOpacity(0.4)),
                          ),
                          child: Text(
                            '⏱️ وقت الوصول المتوقع: ${_etaMinutes! < 60 ? '${_etaMinutes!} دقيقة' : '${_etaMinutes! ~/ 60} ساعة ${_etaMinutes! % 60} دقيقة'}',
                            style: const TextStyle(color: Color(0xFF9B59B6), fontWeight: FontWeight.bold, fontSize: 13),
                          ),
                        ),
                      ],
                    ] else ...[
                      const Text('لا يوجد موقع مسجّل للعميل', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                    ],
                  ],
                ],
              ),
              const SizedBox(height: 16),
            ],

            // ── تفاصيل المهمة ──────────────────────────────────────────────
            _sectionCard(
              label: 'تفاصيل المهمة',
              children: [
                // Grid: الفني + الموعد + المبلغ + طريقة الدفع
                Row(children: [
                  Expanded(child: _labelValue('الفني المعيّن', technician?['name'] ?? '—')),
                  Expanded(child: _labelValue('وقت الوصول المحدد', _formatDateTime(scheduledAt))),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('المبلغ المطلوب', style: TextStyle(color: AppColors.muted, fontSize: 11)),
                    const SizedBox(height: 2),
                    Text(
                      '${amount ?? '—'} ج.م',
                      style: const TextStyle(color: AppColors.primary, fontSize: 20, fontWeight: FontWeight.w900),
                    ),
                  ])),
                  Expanded(child: _labelValue(
                    'طريقة التحصيل',
                    collectionType == 'cash' ? '💵 نقدي' : collectionType == 'transfer' ? '🏦 تحويل' : '—',
                  )),
                ]),
                if (notes != null && notes.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _labelValue('ملاحظات', notes),
                ],
              ],
            ),
            const SizedBox(height: 16),

            // ── بنود المهمة ────────────────────────────────────────────────
            _sectionCard(
              label: 'بنود المهمة',
              trailing: _allItemsDone && _items.isNotEmpty
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(50),
                      ),
                      child: const Text('✓ جميع البنود مكتملة',
                          style: TextStyle(color: Colors.green, fontSize: 11, fontWeight: FontWeight.bold)),
                    )
                  : null,
              children: [
                if (_items.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('لا توجد بنود', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                    ),
                  )
                else
                  ..._items.map((item) {
                    final done = item['isCompleted'] as bool? ?? false;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: done ? Colors.green.withOpacity(0.08) : AppColors.bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: done ? Colors.green.withOpacity(0.3) : AppColors.border,
                        ),
                      ),
                      child: Row(children: [
                        GestureDetector(
                          onTap: _isCompleted ? null : () => _toggleItem(item),
                          child: Container(
                            width: 24, height: 24,
                            decoration: BoxDecoration(
                              color: done ? Colors.green : Colors.transparent,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                color: done ? Colors.green : AppColors.border,
                                width: 2,
                              ),
                            ),
                            child: done
                                ? const Icon(Icons.check, color: Colors.white, size: 14)
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            item['description']?.toString() ?? '',
                            style: TextStyle(
                              color: done ? Colors.green : AppColors.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              decoration: done ? TextDecoration.lineThrough : null,
                            ),
                          ),
                        ),
                      ]),
                    );
                  }),
              ],
            ),
            const SizedBox(height: 16),

            // ── التحصيل ────────────────────────────────────────────────────
            if (!_isCompleted) ...[
              _sectionCard(
                label: 'التحصيل',
                children: [
                  // أزرار اختيار طريقة الدفع
                  Row(children: [
                    Expanded(child: _collectionModeBtn('💵 نقدي', 'cash')),
                    const SizedBox(width: 12),
                    Expanded(child: _collectionModeBtn('🏦 تحويل', 'transfer')),
                  ]),

                  // نقدي
                  if (_collectionMode == 'cash' && !_cashConfirmed) ...[
                    const SizedBox(height: 16),
                    const Text('المبلغ المحصّل', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _cashAmountCtrl,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.right,
                      style: const TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        hintText: amount ?? '0',
                        hintStyle: const TextStyle(color: AppColors.muted),
                        filled: true,
                        fillColor: AppColors.bg,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
                        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          if (_cashAmountCtrl.text.trim().isEmpty) {
                            _showSnack('أدخل المبلغ أولاً', Colors.red);
                            return;
                          }
                          setState(() => _cashConfirmed = true);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text('✓ تأكيد التحصيل', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
                      ),
                    ),
                  ],

                  if (_collectionMode == 'cash' && _cashConfirmed) ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '✓ تم تأكيد تحصيل ${_cashAmountCtrl.text} ج.م نقداً',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ],

                  // تحويل
                  if (_collectionMode == 'transfer') ...[
                    const SizedBox(height: 16),
                    const Text('يجب رفع صورة إثبات التحويل قبل إنهاء المهمة',
                        style: TextStyle(color: AppColors.muted, fontSize: 13)),
                    const SizedBox(height: 12),
                    if (_transferImageUrl == null) ...[
                      GestureDetector(
                        onTap: _uploading ? null : _pickTransferPhoto,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 20),
                          decoration: BoxDecoration(
                            color: AppColors.bg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border, width: 2, style: BorderStyle.solid),
                          ),
                          child: Column(children: [
                            Icon(_uploading ? Icons.hourglass_empty : Icons.camera_alt_outlined,
                                color: AppColors.muted, size: 28),
                            const SizedBox(height: 6),
                            Text(_uploading ? '⏳ جاري الرفع...' : '📷 رفع صورة التحويل',
                                style: const TextStyle(color: AppColors.muted, fontWeight: FontWeight.bold)),
                          ]),
                        ),
                      ),
                    ] else ...[
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: _transferImageFile != null
                            ? Image.file(_transferImageFile!, height: 180, width: double.infinity, fit: BoxFit.cover)
                            : Container(height: 100, color: AppColors.border,
                                child: const Center(child: Icon(Icons.image, color: AppColors.muted))),
                      ),
                      const SizedBox(height: 8),
                      const Center(
                        child: Text('✓ تم رفع صورة التحويل',
                            style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () => setState(() { _transferImageUrl = null; _transferImageFile = null; }),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.muted,
                            side: const BorderSide(color: AppColors.border),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                          child: const Text('تغيير الصورة'),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
              const SizedBox(height: 16),
            ],

            // ── زر إنهاء المهمة ────────────────────────────────────────────
            if (!_isCompleted && _canFinish) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _finishing ? null : _finishTask,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _finishing
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : const Text('✅ إنهاء المهمة', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // ── بانر المهمة المكتملة ────────────────────────────────────────
            if (_isCompleted) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 20),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Column(children: [
                  const Text('✅ تم إنهاء هذه المهمة بنجاح',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.green, fontSize: 17, fontWeight: FontWeight.w900)),
                  if (((_fullTask ?? widget.task)['completedAt']) != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      _formatDateTime((_fullTask ?? widget.task)['completedAt']?.toString()),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.green.withOpacity(0.7), fontSize: 12),
                    ),
                  ],
                ]),
              ),
              const SizedBox(height: 24),
            ],

            // ── قسم الملاحظات ─────────────────────────────────────────────────────
            Builder(builder: (ctx) {
              final taskId = (_fullTask ?? widget.task)['id'];
              final id = taskId is int ? taskId : int.tryParse(taskId.toString()) ?? 0;
              return _sectionCard(
                label: '📝 ملاحظات الفني',
                children: [
                  // إضافة ملاحظة جديدة
                  TextField(
                    controller: _noteCtrl,
                    maxLines: 3,
                    style: const TextStyle(color: AppColors.text),
                    decoration: InputDecoration(
                      hintText: 'اكتب ملاحظة...',
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
                    ),
                  ),
                  const SizedBox(height: 8),
                  // ميديا مرفوعة
                  if (_noteMediaUrls.isNotEmpty) ...
                    _noteMediaUrls.asMap().entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(children: [
                        Icon(_noteMediaTypes[e.key] == 'video' ? Icons.videocam : Icons.image,
                            color: AppColors.primary, size: 16),
                        const SizedBox(width: 6),
                        Expanded(child: Text('ملف ${e.key + 1}',
                            style: const TextStyle(color: AppColors.text, fontSize: 12))),
                        GestureDetector(
                          onTap: () => setState(() {
                            _noteMediaUrls.removeAt(e.key);
                            _noteMediaTypes.removeAt(e.key);
                          }),
                          child: const Icon(Icons.close, color: Colors.red, size: 16),
                        ),
                      ]),
                    )).toList(),
                  // أزرار الوسائط والإرسال
                  Row(children: [
                    IconButton(
                      icon: const Icon(Icons.image, color: AppColors.primary),
                      tooltip: 'إضافة صورة',
                      onPressed: _uploadingNoteMedia ? null : () => _pickNoteMedia(isVideo: false),
                    ),
                    IconButton(
                      icon: const Icon(Icons.videocam, color: AppColors.primary),
                      tooltip: 'إضافة فيديو',
                      onPressed: _uploadingNoteMedia ? null : () => _pickNoteMedia(isVideo: true),
                    ),
                    Row(children: [
                      Switch(
                        value: _noteVisibleToClient,
                        onChanged: (v) => setState(() => _noteVisibleToClient = v),
                        activeColor: AppColors.primary,
                      ),
                      Text('ظاهر للعميل',
                          style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                    ]),
                    const Spacer(),
                    if (_uploadingNoteMedia)
                      const SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                    else
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                        onPressed: _addingNote ? null : () => _submitNote(id),
                        child: _addingNote
                            ? const SizedBox(width: 16, height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Text('إضافة', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                      ),
                  ]),
                  const Divider(color: AppColors.border),
                  // عرض الملاحظات
                  if (_loadingNotes)
                    const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  else if (_notes.isEmpty)
                    const Text('لا توجد ملاحظات بعد',
                        style: TextStyle(color: AppColors.muted, fontSize: 13))
                  else
                    ..._notes.map((note) {
                      final noteId = note['id'] is int ? note['id'] as int : int.tryParse(note['id'].toString()) ?? 0;
                      final urls = note['mediaUrls'];
                      final types = note['mediaTypes'];
                      final mediaList = urls is List ? urls.cast<String>() : <String>[];
                      final typeList = types is List ? types.cast<String>() : <String>[];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.bg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(
                              note['content']?.toString() ?? '',
                              style: const TextStyle(color: AppColors.text, fontSize: 13),
                            )),
                            if (note['isVisibleToClient'] == true)
                              const Icon(Icons.visibility, color: Colors.green, size: 14)
                            else
                              const Icon(Icons.visibility_off, color: AppColors.muted, size: 14),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: () => _deleteNote(noteId, id),
                              child: const Icon(Icons.delete_outline, color: Colors.red, size: 16),
                            ),
                          ]),
                          if (mediaList.isNotEmpty) ...
                            mediaList.asMap().entries.map((e) => Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: GestureDetector(
                                onTap: () => launchUrl(Uri.parse(e.value)),
                                child: typeList.length > e.key && typeList[e.key] == 'image'
                                    ? ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.network(e.value, height: 120, fit: BoxFit.cover,
                                            errorBuilder: (_, __, ___) => const Icon(Icons.broken_image)))
                                    : Row(children: [
                                        const Icon(Icons.play_circle, color: AppColors.primary),
                                        const SizedBox(width: 6),
                                        Text('فيديو ${e.key + 1}',
                                            style: const TextStyle(color: AppColors.primary, fontSize: 12)),
                                      ]),
                              ),
                            )).toList(),
                          const SizedBox(height: 4),
                          Text(
                            note['createdAt']?.toString().substring(0, 16) ?? '',
                            style: const TextStyle(color: AppColors.muted, fontSize: 10),
                          ),
                        ]),
                      );
                    }).toList(),
                ],
              );
            }),
            const SizedBox(height: 32),

          ],
        ),
      ),
    );
  }

  // ── UI Helpers ────────────────────────────────────────────────────────────

  Widget _sectionCard({required String label, required List<Widget> children, Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(label.toUpperCase(),
              style: const TextStyle(
                  color: AppColors.primary, fontSize: 11,
                  fontWeight: FontWeight.bold, letterSpacing: 1.5)),
          if (trailing != null) ...[const Spacer(), trailing],
        ]),
        const SizedBox(height: 16),
        ...children,
      ]),
    );
  }

  Widget _labelValue(String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 11)),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(color: AppColors.text, fontSize: 14, fontWeight: FontWeight.bold)),
    ]);
  }

  Widget _webBtn(String label, Color color, VoidCallback? onTap, {bool fullWidth = false}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: fullWidth ? double.infinity : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: color.withOpacity(0.15),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Center(
          child: Text(label,
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _collectionModeBtn(String label, String mode) {
    final selected = _collectionMode == mode;
    return GestureDetector(
      onTap: () => setState(() {
        _collectionMode = mode;
        _cashConfirmed = false;
        _cashAmountCtrl.clear();
        _transferImageUrl = null;
        _transferImageFile = null;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppColors.bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.border,
            width: selected ? 2 : 1,
          ),
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                  color: selected ? Colors.black : AppColors.muted,
                  fontWeight: FontWeight.bold,
                  fontSize: 14)),
        ),
      ),
    );
  }
}
