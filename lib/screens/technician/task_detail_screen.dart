import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:geolocator/geolocator.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';
import '../../services/api_service.dart';
import '../../widgets/task_chat_bubble.dart';
import '../../providers/auth_provider.dart';

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
  Timer? _etaTimer;

  // Finish task
  bool _finishing = false;

  // Item media uploading state
  final Map<int, bool> _mediaUploading = {};

  // GPS Tracking
  StreamSubscription<Position>? _locationSub;
  bool _gpsActive = false;
  bool _arrivedDetected = false;
  bool _sendingManualLocation = false;

  // Task Notes
  List<Map<String, dynamic>> _notes = [];
  bool _loadingNotes = false;
  bool _addingNote = false;
  final _noteCtrl = TextEditingController();
  List<String> _noteMediaUrls = [];
  List<String> _noteMediaTypes = [];
  bool _noteVisibleToClient = true;
  bool _uploadingNoteMedia = false;

  /// رسائل محادثة التقدم لكل بند (itemId → قائمة)
  Map<int, List<Map<String, dynamic>>> _itemChatByItemId = {};
  /// نصوص progress_note القديمة قبل جدول الرسائل
  Map<int, String> _legacyItemNotes = {};

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
    _etaTimer?.cancel();
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
          if (locStr.startsWith('http')) {
            final coordMatch = RegExp(r'[?&@](-?\d+\.?\d*)[,/](-?\d+\.?\d*)').firstMatch(locStr);
            if (coordMatch != null) {
              clientLat = double.tryParse(coordMatch.group(1)!);
              clientLng = double.tryParse(coordMatch.group(2)!);
            }
          } else {
            final parts = locStr.split(',');
            if (parts.length >= 2) {
              clientLat = double.tryParse(parts[0].trim());
              clientLng = double.tryParse(parts[1].trim());
            }
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
              try {
                await ApiService.mutate('technicianLocation.update', input: {
                  'taskId': id,
                  'latitude': pos.latitude,
                  'longitude': pos.longitude,
                  'arrived': true,
                });
              } catch (_) {}
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text('📍 تم اكتشاف وصولك للعميل تلقائياً! تم إشعار المسؤولين.'),
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

  Future<void> _sendManualLocationNow({int? taskId}) async {
    if (_sendingManualLocation) return;
    setState(() => _sendingManualLocation = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showSnack('خدمة الموقع غير مفعّلة', Colors.red);
        return;
      }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        _showSnack('تم رفض إذن الموقع', Colors.red);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      await ApiService.mutate('technicianLocation.update', input: {
        if (taskId != null) 'taskId': taskId,
        'latitude': pos.latitude,
        'longitude': pos.longitude,
        'accuracy': pos.accuracy,
        'source': 'manual',
      });
      _showSnack('تم تسجيل موقعك الآن ✅', Colors.green);
    } catch (e) {
      _showSnack('فشل تسجيل الموقع: $e', Colors.red);
    } finally {
      if (mounted) setState(() => _sendingManualLocation = false);
    }
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
      await _loadItemChats(idInt);
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

  void _applyItemChatData(dynamic data) {
    if (data is! Map) return;
    final by = data['byItem'];
    final leg = data['legacyByItem'];
    final Map<int, List<Map<String, dynamic>>> next = {};
    if (by is Map) {
      by.forEach((k, v) {
        final id = int.tryParse(k.toString()) ?? 0;
        if (id <= 0) return;
        if (v is List) {
          next[id] = v.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      });
    }
    final Map<int, String> legacy = {};
    if (leg is Map) {
      leg.forEach((k, v) {
        final id = int.tryParse(k.toString()) ?? 0;
        if (id <= 0) return;
        final s = v?.toString().trim() ?? '';
        if (s.isNotEmpty) legacy[id] = s;
      });
    }
    _itemChatByItemId = next;
    _legacyItemNotes = legacy;
  }

  Future<void> _loadItemChats(int taskId) async {
    if (taskId <= 0) return;
    try {
      final res = await ApiService.query('taskItemMessages.listByTask', input: {'taskId': taskId});
      if (mounted) {
        setState(() => _applyItemChatData(res['data']));
      }
    } catch (_) {}
  }

  bool _isTechnicianRole(String? role) => role == 'technician';

  bool _isTaskNoteClientVisible(dynamic v) {
    if (v == true) return true;
    if (v == 1 || v == '1') return true;
    return false;
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
      final bytes = await picked.readAsBytes();
      final url = await ApiService.uploadFile(picked.path, bytes: bytes, filename: picked.name);
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
    setState(() {
      item['isCompleted'] = newVal;
      item['progress'] = newVal ? 100 : 0;
    });
    try {
      await ApiService.mutate('tasks.updateItem', input: {
        'id': item['id'],
        'isCompleted': newVal,
        'progress': newVal ? 100 : 0,
      });
    } catch (_) {
      setState(() {
        item['isCompleted'] = !newVal;
        item['progress'] = !newVal ? 100 : 0;
      });
    }
  }

  Future<void> _updateItemProgress(Map<String, dynamic> item, int progress) async {
    final oldProgress = item['progress'] as int? ?? 0;
    final oldCompleted = item['isCompleted'] as bool? ?? false;
    setState(() {
      item['progress'] = progress;
      item['isCompleted'] = progress >= 100;
    });
    try {
      await ApiService.mutate('tasks.updateItem', input: {
        'id': item['id'],
        'progress': progress,
      });
    } catch (_) {
      setState(() {
        item['progress'] = oldProgress;
        item['isCompleted'] = oldCompleted;
      });
    }
  }

  void _showProgressEditor(Map<String, dynamic> item) {
    final currentProgress = item['progress'] as int? ?? 0;
    double sliderVal = currentProgress.toDouble();
    final noteCtrl = TextEditingController();
    final itemId = item['id'] is int ? item['id'] as int : int.tryParse(item['id'].toString()) ?? 0;
    final sheetMsgs = List<Map<String, dynamic>>.from(_itemChatByItemId[itemId] ?? []);
    final legacySheet = _legacyItemNotes[itemId] ?? '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppThemeDecorations.cardColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 20,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40, height: 4,
                      decoration: BoxDecoration(
                        color: AppColors.border,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    item['description']?.toString() ?? '',
                    style: const TextStyle(color: AppColors.text, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'محادثة التقدم (فني ↔ مشرف) — التاريخ والوقت يُسجَّلان تلقائياً',
                    style: TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppThemeDecorations.pageBackground(context),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: sheetMsgs.isEmpty && legacySheet.isEmpty
                          ? const Center(
                              child: Padding(
                                padding: EdgeInsets.all(16),
                                child: Text('لا رسائل بعد', style: TextStyle(color: AppColors.muted, fontSize: 12)),
                              ),
                            )
                          : ListView(
                              padding: const EdgeInsets.all(10),
                              shrinkWrap: true,
                              children: [
                                if (legacySheet.isNotEmpty)
                                  TaskLegacyNoteBox(
                                    title: 'سجل قديم (قبل المحادثة)',
                                    content: legacySheet,
                                  ),
                                ...sheetMsgs.map((m) {
                                  final role = m['authorRole']?.toString();
                                  final tech = _isTechnicianRole(role);
                                  return TaskChatBubble(
                                    authorName: m['authorName']?.toString().isNotEmpty == true
                                        ? m['authorName'].toString()
                                        : '—',
                                    authorRole: role,
                                    dateTimeText: formatTaskChatDateTime(m['createdAt']?.toString()),
                                    body: m['body']?.toString() ?? '',
                                    alignEnd: tech,
                                    accent: tech ? const Color(0xFF2E7D32) : const Color(0xFF1565C0),
                                  );
                                }),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      const Text('نسبة الإنجاز', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: _progressColor(sliderVal.round()).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${sliderVal.round()}%',
                          style: TextStyle(
                            color: _progressColor(sliderVal.round()),
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SliderTheme(
                    data: SliderThemeData(
                      activeTrackColor: _progressColor(sliderVal.round()),
                      inactiveTrackColor: AppColors.border,
                      thumbColor: _progressColor(sliderVal.round()),
                      overlayColor: _progressColor(sliderVal.round()).withOpacity(0.2),
                      trackHeight: 8,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                    ),
                    child: Slider(
                      value: sliderVal,
                      min: 0,
                      max: 100,
                      divisions: 20,
                      onChanged: (v) => setSheetState(() => sliderVal = v),
                    ),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [0, 25, 50, 75, 100].map((v) => GestureDetector(
                      onTap: () => setSheetState(() => sliderVal = v.toDouble()),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: sliderVal.round() == v
                              ? _progressColor(v).withOpacity(0.2)
                              : AppThemeDecorations.pageBackground(context),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: sliderVal.round() == v
                                ? _progressColor(v)
                                : AppColors.border,
                          ),
                        ),
                        child: Text(
                          '$v%',
                          style: TextStyle(
                            color: sliderVal.round() == v
                                ? _progressColor(v)
                                : AppColors.muted,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    )).toList(),
                  ),
                  const SizedBox(height: 16),
                  const Text('رسالة جديدة', style: TextStyle(color: AppColors.muted, fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  TextField(
                    controller: noteCtrl,
                    maxLines: 4,
                    style: const TextStyle(color: AppColors.text, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'اكتب تعليقاً أو رداً للمشرف/الفني… (اختياري)',
                      hintStyle: const TextStyle(color: AppColors.muted, fontSize: 12),
                      filled: true,
                      fillColor: AppThemeDecorations.pageBackground(context),
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
                        borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () async {
                        final newProgress = sliderVal.round();
                        final msg = noteCtrl.text.trim();
                        final tid = (_fullTask ?? widget.task)['id'];
                        final taskIdInt = tid is int ? tid : int.tryParse(tid.toString()) ?? 0;
                        try {
                          await ApiService.mutate('tasks.updateItem', input: {
                            'id': item['id'],
                            'progress': newProgress,
                            'isCompleted': newProgress >= 100,
                          });
                          if (msg.isNotEmpty) {
                            await ApiService.mutate('taskItemMessages.add', input: {
                              'itemId': itemId,
                              'body': msg,
                            });
                          }
                          if (!mounted) return;
                          setState(() {
                            item['progress'] = newProgress;
                            item['isCompleted'] = newProgress >= 100;
                          });
                          await _loadItemChats(taskIdInt);
                        } catch (e) {
                          if (mounted) {
                            _showSnack('فشل الحفظ: $e', Colors.red);
                          }
                          return;
                        }
                        if (ctx.mounted) Navigator.pop(ctx);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('حفظ التقدم وإرسال الرسالة', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15)),
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

  Color _progressColor(int progress) {
    if (progress >= 100) return Colors.green;
    if (progress >= 75) return const Color(0xFF2196F3);
    if (progress >= 50) return Colors.orange;
    if (progress >= 25) return const Color(0xFFF57C00);
    return Colors.red.shade400;
  }

  void _showMediaPicker(int itemId) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppThemeDecorations.cardColor(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('إرفاق ملف', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.photo_library, color: AppColors.primary),
                title: const Text('صورة من المعرض', style: TextStyle(color: AppColors.text)),
                onTap: () { Navigator.pop(ctx); _uploadItemMedia(itemId, false, ImageSource.gallery); },
              ),
              if (!kIsWeb)
                ListTile(
                  leading: const Icon(Icons.camera_alt, color: AppColors.primary),
                  title: const Text('التقاط صورة', style: TextStyle(color: AppColors.text)),
                  onTap: () { Navigator.pop(ctx); _uploadItemMedia(itemId, false, ImageSource.camera); },
                ),
              ListTile(
                leading: const Icon(Icons.videocam, color: Colors.red),
                title: const Text('فيديو من المعرض', style: TextStyle(color: AppColors.text)),
                onTap: () { Navigator.pop(ctx); _uploadItemMedia(itemId, true, ImageSource.gallery); },
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _uploadItemMedia(int itemId, bool isVideo, ImageSource source) async {
    final picker = ImagePicker();
    final XFile? picked;
    if (isVideo) {
      picked = await picker.pickVideo(source: source);
    } else {
      picked = await picker.pickImage(source: source, imageQuality: 70);
    }
    if (picked == null) return;
    setState(() => _mediaUploading[itemId] = true);
    try {
      final bytes = await picked.readAsBytes();
      final url = await ApiService.uploadFile(
        picked.path,
        bytes: bytes,
        filename: picked.name,
      );
      await ApiService.mutate('tasks.addItemMedia', input: {
        'itemId': itemId,
        'url': url,
        'type': isVideo ? 'video' : 'image',
      });
      await _loadFullTask();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في الرفع: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _mediaUploading[itemId] = false);
    }
  }

  void _confirmDeleteMedia(int itemId, int index) {
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppThemeDecorations.cardColor(context),
          title: const Text('حذف الملف', style: TextStyle(color: AppColors.text)),
          content: const Text('هل تريد حذف هذا الملف؟', style: TextStyle(color: AppColors.muted)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء', style: TextStyle(color: AppColors.muted)),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _deleteMedia(itemId, index);
              },
              child: const Text('حذف', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteMedia(int itemId, int index) async {
    try {
      await ApiService.mutate('tasks.removeItemMedia', input: {
        'itemId': itemId,
        'index': index,
      });
      await _loadFullTask();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف الملف'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في الحذف: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showImageDialog(String url) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        backgroundColor: Colors.black,
        child: InteractiveViewer(
          child: Image.network(url, fit: BoxFit.contain),
        ),
      ),
    );
  }

  Future<void> _pickTransferPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked == null) return;
    final pickedBytes = await picked.readAsBytes();
    setState(() { _uploading = true; _transferImageFile = File(picked.path); });
    try {
      final result = await ApiService.uploadFile(picked.path, bytes: pickedBytes, filename: picked.name);
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

  bool _canShowDeferTask(String status, BuildContext context) {
    if (status == 'completed' || status == 'cancelled') return false;
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      return auth.canAccessAdmin;
    } catch (_) {
      return false;
    }
  }

  DateTime? _parseTaskDateTimeLocal(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return DateTime.parse(raw).toLocal();
    } catch (_) {
      return null;
    }
  }

  void _openDeferTaskSheet(Map<String, dynamic> task) {
    final id = task['id'];
    final tid = id is int ? id : int.tryParse(id.toString()) ?? 0;
    if (tid <= 0) return;

    final fromSched = _parseTaskDateTimeLocal(task['scheduledAt']?.toString());
    final fromEst = _parseTaskDateTimeLocal(task['estimatedArrivalAt']?.toString());
    final initialDay = fromSched ?? fromEst ?? DateTime.now();
    final initialTime = fromEst != null
        ? TimeOfDay(hour: fromEst.hour, minute: fromEst.minute)
        : (fromSched != null
            ? TimeOfDay(hour: fromSched.hour, minute: fromSched.minute)
            : TimeOfDay.now());

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppThemeDecorations.cardColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _DeferTaskScheduleSheet(
        taskId: tid,
        initialDate: initialDay,
        initialTime: initialTime,
        onSuccess: () async {
          if (!mounted) return;
          await _loadFullTask();
          widget.onTaskUpdated?.call();
          _showSnack('تم ترحيل موعد المهمة وإشعار الفني', Colors.green);
        },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loadingTask) {
      return Scaffold(
        backgroundColor: AppThemeDecorations.pageBackground(context),
        appBar: AppBar(backgroundColor: AppThemeDecorations.cardColor(context), title: const Text('تفاصيل المهمة')),
        body: const Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final task = _fullTask ?? widget.task;
    final status = task['status']?.toString() ?? 'pending';
    final taskId = task['id']?.toString() ?? '';
    final taskIdInt = (() {
      final raw = (task['id']);
      if (raw is int) return raw;
      return int.tryParse(raw?.toString() ?? '');
    })();
    final title = task['title']?.toString() ?? 'مهمة';
    final customer = _customer;
    final technician = _technician;
    final scheduledAt = task['scheduledAt']?.toString();
    final estimatedArrivalAt = task['estimatedArrivalAt']?.toString();
    final amount = task['amount']?.toString();
    final collectionType = task['collectionType']?.toString();
    final notes = task['notes']?.toString();

    // Parse customer location (supports URLs and "lat,lng" format)
    double? clientLat, clientLng;
    String? locationUrl;
    final locStr = customer?['location']?.toString();
    if (locStr != null && locStr.isNotEmpty) {
      if (locStr.startsWith('http')) {
        locationUrl = locStr;
        final coordMatch = RegExp(r'[?&@](-?\d+\.?\d*)[,/](-?\d+\.?\d*)').firstMatch(locStr);
        if (coordMatch != null) {
          clientLat = double.tryParse(coordMatch.group(1)!);
          clientLng = double.tryParse(coordMatch.group(2)!);
        }
      } else {
        final parts = locStr.split(',');
        if (parts.length >= 2) {
          clientLat = double.tryParse(parts[0].trim());
          clientLng = double.tryParse(parts[1].trim());
        }
      }
    }

    // بدء حساب وقت الوصول المتوقع تلقائياً عند توفر موقع العميل
    if (clientLat != null && clientLng != null && _etaTimer == null) {
      _etaTimer = Timer(const Duration(seconds: 5), () {
        if (!mounted) return;
        _calcEta(clientLat!, clientLng!);
        _etaTimer = Timer.periodic(const Duration(minutes: 1), (_) {
          if (!mounted) return;
          _calcEta(clientLat!, clientLng!);
        });
      });
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppThemeDecorations.pageBackground(context),
        appBar: AppBar(
          backgroundColor: AppThemeDecorations.cardColor(context),
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
            if (_canShowDeferTask(status, context))
              IconButton(
                icon: const Icon(Icons.event_repeat, color: AppColors.primary),
                tooltip: 'ترحيل المهمة',
                onPressed: () => _openDeferTaskSheet(task),
              ),
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
                    Row(
                      children: [
                        Expanded(
                          child: _webBtn(
                            _sendingManualLocation ? '⏳ جاري التسجيل...' : '📍 تسجيل موقعي الآن (أوفر تايم)',
                            const Color(0xFF1565C0),
                            _sendingManualLocation ? null : () => _sendManualLocationNow(taskId: taskIdInt),
                            fullWidth: true,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    if (locationUrl != null) ...[
                      _webBtn(
                        '🗺️ فتح رابط الموقع',
                        AppColors.primary,
                        () => launchUrl(Uri.parse(locationUrl!), mode: LaunchMode.externalApplication),
                        fullWidth: true,
                      ),
                      if (clientLat != null && clientLng != null) ...[
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                            child: _webBtn(
                              '🗺️ تحديد الاتجاهات',
                              const Color(0xFF2E7D32),
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
                      ],
                    ] else if (clientLat != null && clientLng != null) ...[
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
                    ] else ...[
                      const Text('لا يوجد موقع مسجّل للعميل', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                    ],
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
                  Expanded(
                    child: _labelValue(
                      'وقت الوصول المحدد',
                      // نفضّل وقت الوصول المحدد من المسؤول، وإن لم يتوفر نستخدم تاريخ الموعد
                      _formatDateTime(estimatedArrivalAt ?? scheduledAt),
                    ),
                  ),
                ]),
                if (_canShowDeferTask(status, context)) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => _openDeferTaskSheet(task),
                      icon: const Icon(Icons.event_repeat, color: AppColors.primary, size: 20),
                      label: const Text(
                        'ترحيل المهمة (موعد جديد)',
                        style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const Text(
                    'للمشرفين والمسؤولين: عند عدم إنجاز المهمة في اليوم المحدد، حدّد تاريخاً ووقتاً جديدين للفني.',
                    style: TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
                ],
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
              ],
            ),
            const SizedBox(height: 16),

            // ── نسبة الإنجاز الكلية ─────────────────────────────────────────
            if (_items.isNotEmpty)
              Builder(builder: (_) {
                int total = 0;
                for (final item in _items) {
                  total += (item['progress'] as int? ?? ((item['isCompleted'] as bool? ?? false) ? 100 : 0));
                }
                final overall = (total / _items.length).round();
                final oColor = _progressColor(overall);
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppThemeDecorations.cardColor(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: oColor.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text('نسبة الإنجاز الكلية'.toUpperCase(),
                            style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                        const Spacer(),
                        Text('$overall%',
                            style: TextStyle(color: oColor, fontSize: 22, fontWeight: FontWeight.w900)),
                      ]),
                      const SizedBox(height: 12),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(
                          value: overall / 100.0,
                          backgroundColor: AppColors.border,
                          valueColor: AlwaysStoppedAnimation<Color>(oColor),
                          minHeight: 10,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_items.where((i) => (i['progress'] as int? ?? 0) >= 100).length} من ${_items.length} بنود مكتملة',
                        style: const TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                    ],
                  ),
                );
              }),

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
                    final progress = item['progress'] as int? ?? (done ? 100 : 0);
                    final itemId = item['id'] is int ? item['id'] as int : int.tryParse(item['id'].toString()) ?? 0;
                    final mediaUrls = item['mediaUrls'] is List ? (item['mediaUrls'] as List).cast<String>() : <String>[];
                    final mediaTypes = item['mediaTypes'] is List ? (item['mediaTypes'] as List).cast<String>() : <String>[];
                    final isUploading = _mediaUploading[itemId] == true;
                    final pColor = _progressColor(progress);
                    return GestureDetector(
                      onTap: _isCompleted ? null : () => _showProgressEditor(item),
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: done ? Colors.green.withOpacity(0.08) : AppThemeDecorations.pageBackground(context),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: done ? Colors.green.withOpacity(0.3) : AppColors.border,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
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
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: pColor.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '$progress%',
                                  style: TextStyle(color: pColor, fontWeight: FontWeight.w900, fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 6),
                              if (!_isCompleted)
                                isUploading
                                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                                    : GestureDetector(
                                        onTap: () => _showMediaPicker(itemId),
                                        child: Container(
                                          width: 28, height: 28,
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withOpacity(0.15),
                                            borderRadius: BorderRadius.circular(7),
                                          ),
                                          child: const Icon(Icons.add_a_photo, color: AppColors.primary, size: 16),
                                        ),
                                      ),
                            ]),
                            const SizedBox(height: 8),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: progress / 100.0,
                                backgroundColor: AppColors.border,
                                valueColor: AlwaysStoppedAnimation<Color>(pColor),
                                minHeight: 6,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Builder(builder: (ctx) {
                              final msgs = _itemChatByItemId[itemId] ?? [];
                              final leg = _legacyItemNotes[itemId] ??
                                  (item['progressNote']?.toString().trim().isNotEmpty == true
                                      ? item['progressNote'].toString()
                                      : '');
                              if (msgs.isEmpty && leg.isEmpty) {
                                return Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    'لا تعليقات بعد — اضغط لتحديث التقدم أو إرسال رسالة',
                                    style: TextStyle(color: AppColors.muted.withOpacity(0.9), fontSize: 11),
                                  ),
                                );
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (leg.isNotEmpty)
                                    TaskLegacyNoteBox(
                                      title: 'سجل قديم (قبل المحادثة)',
                                      content: leg,
                                    ),
                                  ...msgs.map((m) {
                                    final role = m['authorRole']?.toString();
                                    final tech = _isTechnicianRole(role);
                                    return TaskChatBubble(
                                      authorName: m['authorName']?.toString().isNotEmpty == true
                                          ? m['authorName'].toString()
                                          : '—',
                                      authorRole: role,
                                      dateTimeText: formatTaskChatDateTime(m['createdAt']?.toString()),
                                      body: m['body']?.toString() ?? '',
                                      alignEnd: tech,
                                      accent: tech ? const Color(0xFF2E7D32) : const Color(0xFF1565C0),
                                    );
                                  }),
                                ],
                              );
                            }),
                            if (!_isCompleted && progress < 100) ...[
                              const SizedBox(height: 4),
                              Text(
                                'اضغط لتحديث التقدم أو المحادثة',
                                style: TextStyle(color: AppColors.primary.withOpacity(0.6), fontSize: 10),
                              ),
                            ],
                            if (mediaUrls.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 80,
                                child: ListView.builder(
                                  scrollDirection: Axis.horizontal,
                                  itemCount: mediaUrls.length,
                                  itemBuilder: (_, i) {
                                    final url = mediaUrls[i];
                                    final isVideo = i < mediaTypes.length && mediaTypes[i] == 'video';
                                    return Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: SizedBox(
                                        width: 75, height: 75,
                                        child: Stack(
                                          clipBehavior: Clip.none,
                                          children: [
                                            GestureDetector(
                                              onTap: () {
                                                if (isVideo) {
                                                  launchUrl(Uri.parse(url));
                                                } else {
                                                  _showImageDialog(ApiService.proxyImageUrl(url));
                                                }
                                              },
                                              onLongPress: () => _confirmDeleteMedia(itemId, i),
                                              child: ClipRRect(
                                                borderRadius: BorderRadius.circular(8),
                                                child: isVideo
                                                    ? Container(
                                                        width: 75, height: 75,
                                                        color: Colors.black,
                                                        child: const Center(child: Icon(Icons.play_circle_fill, color: Colors.white, size: 30)),
                                                      )
                                                    : Image.network(
                                                        ApiService.proxyImageUrl(url),
                                                        width: 75, height: 75, fit: BoxFit.cover,
                                                        errorBuilder: (_, __, ___) => Container(
                                                          width: 75, height: 75, color: AppColors.border,
                                                          child: const Icon(Icons.broken_image, color: AppColors.muted),
                                                        ),
                                                      ),
                                              ),
                                            ),
                                            Positioned(
                                              top: -6, left: -6,
                                              child: GestureDetector(
                                                onTap: () => _confirmDeleteMedia(itemId, i),
                                                child: Container(
                                                  width: 26, height: 26,
                                                  decoration: BoxDecoration(
                                                    color: Colors.red,
                                                    shape: BoxShape.circle,
                                                    border: Border.all(color: AppThemeDecorations.cardColor(context), width: 2),
                                                  ),
                                                  child: const Icon(Icons.close, color: Colors.white, size: 16),
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
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
                        fillColor: AppThemeDecorations.pageBackground(context),
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
                            color: AppThemeDecorations.pageBackground(context),
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
                label: '📝 ملاحظات ومتابعة (شات)',
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
                      fillColor: AppThemeDecorations.pageBackground(context),
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
                  if (_loadingNotes)
                    const Center(child: CircularProgressIndicator(color: AppColors.primary))
                  else
                    Builder(builder: (innerCtx) {
                      final notesList = List<Map<String, dynamic>>.from(this._notes);
                      final team = notesList.where((n) => !_isTaskNoteClientVisible(n['isVisibleToClient'])).toList();
                      final client = notesList.where((n) => _isTaskNoteClientVisible(n['isVisibleToClient'])).toList();
                      final taskLevelNotes = notes;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '💬 محادثة الفريق (فني ↔ مشرف)',
                            style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'رسائل داخلية — لا تظهر في تطبيق العميل',
                            style: TextStyle(color: AppColors.muted, fontSize: 11),
                          ),
                          const SizedBox(height: 10),
                          if (team.isEmpty)
                            Text('لا رسائل بعد', style: TextStyle(color: AppColors.muted, fontSize: 12))
                          else
                            ...team.map((n) => _buildTaskNoteBubble(n, id, context)),
                          const SizedBox(height: 20),
                          Text(
                            '👤 ملاحظات تظهر للعميل',
                            style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 14),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'فعّل «ظاهر للعميل» عند الإضافة. تظهر هنا بالترتيب مع اسم الكاتب والتاريخ.',
                            style: TextStyle(color: AppColors.muted, fontSize: 11),
                          ),
                          const SizedBox(height: 10),
                          if (taskLevelNotes != null && taskLevelNotes.isNotEmpty)
                            TaskLegacyNoteBox(title: 'ملاحظة مع المهمة (عند الإنشاء)', content: taskLevelNotes),
                          if (client.isEmpty && (taskLevelNotes == null || taskLevelNotes.isEmpty))
                            Text('لا ملاحظات للعميل بعد', style: TextStyle(color: AppColors.muted, fontSize: 12))
                          else
                            ...client.map((n) => _buildTaskNoteBubble(n, id, context)),
                        ],
                      );
                    }),
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

  Widget _buildTaskNoteBubble(Map<String, dynamic> noteRow, int taskId, BuildContext context) {
    final noteId = noteRow['id'] is int ? noteRow['id'] as int : int.tryParse(noteRow['id'].toString()) ?? 0;
    final urls = noteRow['mediaUrls'];
    final types = noteRow['mediaTypes'];
    final mediaList = urls is List ? urls.cast<String>() : <String>[];
    final typeList = types is List ? types.cast<String>() : <String>[];
    final role = noteRow['authorRole']?.toString();
    final tech = _isTechnicianRole(role);
    final name = noteRow['authorName']?.toString().trim().isNotEmpty == true
        ? noteRow['authorName'].toString()
        : 'مستخدم';

    Widget? mediaFooter;
    if (mediaList.isNotEmpty) {
      mediaFooter = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: mediaList.asMap().entries.map((e) {
          final url = e.value;
          final isImage = typeList.length > e.key && typeList[e.key] == 'image';
          return Padding(
            padding: const EdgeInsets.only(top: 6),
            child: GestureDetector(
              onTap: () => launchUrl(Uri.parse(url)),
              child: isImage
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        ApiService.proxyImageUrl(url),
                        height: 120,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.broken_image),
                      ),
                    )
                  : Row(
                      children: [
                        const Icon(Icons.play_circle, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text('فيديو ${e.key + 1}', style: const TextStyle(color: AppColors.primary, fontSize: 12)),
                      ],
                    ),
            ),
          );
        }).toList(),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TaskChatBubble(
            authorName: name,
            authorRole: role,
            dateTimeText: formatTaskChatDateTime(noteRow['createdAt']?.toString()),
            body: noteRow['content']?.toString() ?? '',
            alignEnd: tech,
            accent: tech ? const Color(0xFF6A1B9A) : const Color(0xFF00695C),
            footer: mediaFooter,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  _isTaskNoteClientVisible(noteRow['isVisibleToClient']) ? Icons.visibility : Icons.visibility_off,
                  size: 18,
                  color: _isTaskNoteClientVisible(noteRow['isVisibleToClient']) ? Colors.green : AppColors.muted,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                onPressed: () => _deleteNote(noteId, taskId),
                tooltip: 'حذف',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({required String label, required List<Widget> children, Widget? trailing}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppThemeDecorations.cardColor(context),
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
          color: selected ? AppColors.primary : AppThemeDecorations.pageBackground(context),
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

/// نافذة ترحيل موعد المهمة (تاريخ + وقت) — للمشرفين فقط من الشاشة الأم.
class _DeferTaskScheduleSheet extends StatefulWidget {
  final int taskId;
  final DateTime initialDate;
  final TimeOfDay initialTime;
  final Future<void> Function() onSuccess;

  const _DeferTaskScheduleSheet({
    required this.taskId,
    required this.initialDate,
    required this.initialTime,
    required this.onSuccess,
  });

  @override
  State<_DeferTaskScheduleSheet> createState() => _DeferTaskScheduleSheetState();
}

class _DeferTaskScheduleSheetState extends State<_DeferTaskScheduleSheet> {
  late DateTime _day;
  late TimeOfDay _time;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _day = widget.initialDate;
    _time = widget.initialTime;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final schedIso = DateTime(_day.year, _day.month, _day.day).toIso8601String();
      final estIso = DateTime(
        _day.year,
        _day.month,
        _day.day,
        _time.hour,
        _time.minute,
      ).toIso8601String();
      await ApiService.mutate('tasks.update', input: {
        'id': widget.taskId,
        'scheduledAt': schedIso,
        'estimatedArrivalAt': estIso,
      });
      if (!mounted) return;
      Navigator.pop(context);
      await widget.onSuccess();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الترحيل: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'ترحيل المهمة',
                style: TextStyle(color: AppColors.text, fontSize: 18, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              const Text(
                'حدد تاريخاً جديداً ووقت الوصول المتوقع للفني.',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('تاريخ الزيارة', style: TextStyle(color: AppColors.text)),
                subtitle: Text(
                  '${_day.year}/${_day.month}/${_day.day}',
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                ),
                trailing: const Icon(Icons.calendar_month, color: AppColors.primary),
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _day,
                    firstDate: DateTime.now().subtract(const Duration(days: 1)),
                    lastDate: DateTime.now().add(const Duration(days: 730)),
                  );
                  if (d != null) setState(() => _day = d);
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('وقت الوصول المتوقع', style: TextStyle(color: AppColors.text)),
                subtitle: Text(
                  _time.format(context),
                  style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                ),
                trailing: const Icon(Icons.access_time, color: AppColors.primary),
                onTap: () async {
                  final t = await showTimePicker(
                    context: context,
                    initialTime: _time,
                  );
                  if (t != null) setState(() => _time = t);
                },
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Text('تأكيد الترحيل', style: TextStyle(fontWeight: FontWeight.w900)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
