import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';

class AdminTechnicianTrackingScreen extends StatefulWidget {
  const AdminTechnicianTrackingScreen({super.key});

  @override
  State<AdminTechnicianTrackingScreen> createState() => _AdminTechnicianTrackingScreenState();
}

class _AdminTechnicianTrackingScreenState extends State<AdminTechnicianTrackingScreen> {
  bool _loadingLatest = true;
  bool _loadingTrack = false;

  List<Map<String, dynamic>> _latest = [];
  int? _selectedTechId;
  String? _selectedTechName;

  DateTime _day = DateTime.now();
  Map<String, dynamic>? _track;
  bool _settingManual = false;
  bool _requestingNow = false;

  @override
  void initState() {
    super.initState();
    _loadLatest();
  }

  Future<void> _loadLatest() async {
    setState(() => _loadingLatest = true);
    try {
      final res = await ApiService.query('technicianLocation.latest', input: {'sinceHours': 24});
      final raw = res['data'];
      final rows = raw is List ? raw : <dynamic>[];
      final parsed = rows.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
      parsed.sort((a, b) => (b['createdAt'] ?? '').toString().compareTo((a['createdAt'] ?? '').toString()));
      if (!mounted) return;
      setState(() {
        _latest = parsed;
        _loadingLatest = false;
      });
      if (_selectedTechId == null && _latest.isNotEmpty) {
        final first = _latest.first;
        _selectTech(first['technicianId'], first['technicianName']);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingLatest = false);
    }
  }

  Future<void> _openTechPicker() async {
    // Always allow picking technicians even when no location points exist.
    List<Map<String, dynamic>> techs = [];
    try {
      final res = await ApiService.query('technicianLocation.technicians');
      final raw = res['data'];
      final rows = (raw is Map && raw['rows'] is List) ? (raw['rows'] as List) : const [];
      techs = rows.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {}
    if (techs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('لا يوجد فنيين في النظام أو لا توجد صلاحيات'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    final picked = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
        decoration: BoxDecoration(
          color: AppThemeDecorations.cardColor(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
        ),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(width: 42, height: 4, decoration: BoxDecoration(color: AppColors.border, borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 10),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    Icon(Icons.people_outline, color: AppColors.primary),
                    SizedBox(width: 8),
                    Text('اختر فني', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w900, fontSize: 16)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: techs.length,
                  itemBuilder: (_, i) {
                    final r = techs[i];
                    final name = (r['name'] ?? 'فني').toString();
                    final id = r['id'];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: AppColors.primary.withOpacity(0.2),
                        child: Text(name.isNotEmpty ? name.substring(0, 1) : 'ف', style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                      ),
                      title: Text(name, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w800)),
                      subtitle: Text((r['phone'] ?? r['email'] ?? '').toString(), style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                      trailing: Text('#$id', style: const TextStyle(color: AppColors.muted)),
                      onTap: () => Navigator.pop(ctx, r),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    _selectTech(picked['id'], picked['name']);
  }

  void _selectTech(dynamic id, dynamic name) {
    final tid = id is int ? id : int.tryParse(id.toString());
    if (tid == null || tid <= 0) return;
    setState(() {
      _selectedTechId = tid;
      _selectedTechName = (name ?? '').toString();
      _track = null;
    });
    _loadTrack();
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      builder: (c, child) => Theme(
        data: ThemeData.dark().copyWith(
          colorScheme: const ColorScheme.dark(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() => _day = picked);
    _loadTrack();
  }

  String _dayStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadTrack() async {
    final techId = _selectedTechId;
    if (techId == null) return;
    setState(() => _loadingTrack = true);
    try {
      final res = await ApiService.query('technicianLocation.track', input: {
        'technicianId': techId,
        'date': _dayStr(_day),
        'fromHour': 9,
        'toHour': 19,
        'intervalMin': 30,
      });
      if (!mounted) return;
      setState(() {
        _track = res['data'] is Map ? Map<String, dynamic>.from(res['data']) : null;
        _loadingTrack = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingTrack = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('فشل تحميل مسار الفني (تأكد من صلاحيات الأدمن ومن نشر تحديث السيرفر)'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Map<String, double>? _parseLatLngFromText(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    // Accept "lat,lng"
    if (s.contains(',')) {
      final parts = s.split(',');
      if (parts.length >= 2) {
        final lat = double.tryParse(parts[0].trim());
        final lng = double.tryParse(parts[1].trim());
        if (lat != null && lng != null) return {'lat': lat, 'lng': lng};
      }
    }
    // Accept Google Maps URL with "...@lat,lng" or "?q=lat,lng"
    final re = RegExp(r'(@|\bq=)(-?\d+\.?\d*),\s*(-?\d+\.?\d*)');
    final m = re.firstMatch(s);
    if (m != null) {
      final lat = double.tryParse(m.group(2) ?? '');
      final lng = double.tryParse(m.group(3) ?? '');
      if (lat != null && lng != null) return {'lat': lat, 'lng': lng};
    }
    return null;
  }

  Future<void> _openManualSetDialog() async {
    final techId = _selectedTechId;
    if (techId == null) return;

    final ctrl = TextEditingController();
    final noteCtrl = TextEditingController(text: 'overtime');
    final accCtrl = TextEditingController(text: '30');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppThemeDecorations.cardColor(context),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.edit_location_alt, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'تحديد موقع يدوي للفني',
                        style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 16),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  _selectedTechName?.isNotEmpty == true ? 'الفني: $_selectedTechName' : 'الفني: #$techId',
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: ctrl,
                  style: const TextStyle(color: AppColors.text),
                  decoration: InputDecoration(
                    labelText: 'Lat,Lng أو لينك Google Maps',
                    labelStyle: const TextStyle(color: AppColors.muted),
                    filled: true,
                    fillColor: AppThemeDecorations.pageBackground(context),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: accCtrl,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(color: AppColors.text),
                        decoration: InputDecoration(
                          labelText: 'Accuracy (m)',
                          labelStyle: const TextStyle(color: AppColors.muted),
                          filled: true,
                          fillColor: AppThemeDecorations.pageBackground(context),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: noteCtrl,
                        style: const TextStyle(color: AppColors.text),
                        decoration: InputDecoration(
                          labelText: 'ملاحظة قصيرة',
                          labelStyle: const TextStyle(color: AppColors.muted),
                          filled: true,
                          fillColor: AppThemeDecorations.pageBackground(context),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ElevatedButton(
                  onPressed: _settingManual
                      ? null
                      : () async {
                          final parsed = _parseLatLngFromText(ctrl.text);
                          if (parsed == null) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('اكتب Lat,Lng صحيح أو الصق رابط خرائط'), backgroundColor: Colors.red),
                              );
                            }
                            return;
                          }
                          setState(() => _settingManual = true);
                          try {
                            final acc = double.tryParse(accCtrl.text.trim());
                            await ApiService.mutate('technicianLocation.adminSet', input: {
                              'technicianId': techId,
                              'latitude': parsed['lat'],
                              'longitude': parsed['lng'],
                              if (acc != null) 'accuracy': acc,
                              'note': noteCtrl.text.trim(),
                            });
                            if (mounted) Navigator.pop(ctx);
                            await _loadLatest();
                            await _loadTrack();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('تم تسجيل الموقع يدويًا ✅'), backgroundColor: Colors.green),
                              );
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('فشل: $e'), backgroundColor: Colors.red),
                              );
                            }
                          } finally {
                            if (mounted) setState(() => _settingManual = false);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(_settingManual ? 'جاري الحفظ...' : 'حفظ الموقع'),
                ),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _requestTechnicianLocationNow() async {
    final techId = _selectedTechId;
    if (techId == null || _requestingNow) return;
    setState(() => _requestingNow = true);
    try {
      await ApiService.mutate('technicianLocation.requestNow', input: {'technicianId': techId});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال طلب لوكيشن للفني الآن…'), backgroundColor: Colors.green),
        );
      }
      // Give device a moment to respond then refresh.
      Future.delayed(const Duration(seconds: 6), () async {
        if (!mounted) return;
        await _loadLatest();
        await _loadTrack();
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل إرسال الطلب: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _requestingNow = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppThemeDecorations.pageBackground(context),
        appBar: AppBar(
          backgroundColor: AppThemeDecorations.cardColor(context),
          title: const Text('تحركات الفنيين', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
          iconTheme: const IconThemeData(color: AppColors.text),
          actions: [
            IconButton(
              tooltip: 'تحديث',
              icon: const Icon(Icons.refresh, color: AppColors.primary),
              onPressed: _loadLatest,
            ),
          ],
        ),
        body: _loadingLatest
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : Column(
                children: [
                  _topBar(),
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(flex: 2, child: _techniciansList()),
                        Expanded(flex: 3, child: _trackPanel()),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _topBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppThemeDecorations.cardColor(context),
        border: Border(bottom: BorderSide(color: AppColors.border.withOpacity(0.7))),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_searching, color: AppColors.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedTechName?.isNotEmpty == true ? 'الفني: $_selectedTechName' : 'اختر فني',
                    style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _openTechPicker,
                  icon: const Icon(Icons.person_search, size: 18, color: AppColors.primary),
                  label: const Text('اختر', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppColors.primary),
                    backgroundColor: AppColors.primary.withOpacity(0.06),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          OutlinedButton.icon(
            onPressed: _pickDay,
            icon: const Icon(Icons.calendar_month, size: 18, color: AppColors.primary),
            label: Text(
              _dayStr(_day),
              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: AppColors.primary),
              backgroundColor: AppColors.primary.withOpacity(0.06),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            onPressed: (_selectedTechId == null || _requestingNow) ? null : _requestTechnicianLocationNow,
            icon: Icon(_requestingNow ? Icons.hourglass_top : Icons.my_location, size: 18),
            label: Text(_requestingNow ? 'جاري الطلب…' : 'اطلب موقع الآن', style: const TextStyle(fontWeight: FontWeight.w800)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.lightBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _techniciansList() {
    if (_latest.isEmpty) {
      return Center(
        child: Text(
          'لا توجد نقاط مواقع مسجلة خلال آخر 24 ساعة',
          style: TextStyle(color: AppColors.muted.withOpacity(0.9)),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: _latest.length,
      itemBuilder: (ctx, i) {
        final r = _latest[i];
        final id = r['technicianId'];
        final name = (r['technicianName'] ?? 'فني').toString();
        final createdAt = (r['createdAt'] ?? '').toString();
        final lat = r['latitude'];
        final lng = r['longitude'];
        final selected = _selectedTechId != null && _selectedTechId.toString() == id.toString();

        return GestureDetector(
          onTap: () => _selectTech(id, name),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: selected ? AppColors.primary.withOpacity(0.12) : AppThemeDecorations.cardColor(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? AppColors.primary.withOpacity(0.6) : AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 16,
                      backgroundColor: AppColors.primary.withOpacity(0.2),
                      child: Text(
                        name.isNotEmpty ? name.substring(0, 1) : 'ف',
                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w800),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text('آخر ظهور: $createdAt', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                const SizedBox(height: 6),
                Text('Lat/Lng: $lat, $lng', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _trackPanel() {
    if (_selectedTechId == null) {
      return Center(child: Text('اختر فني لعرض المسار', style: TextStyle(color: AppColors.muted.withOpacity(0.9))));
    }

    if (_loadingTrack) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    final t = _track;
    final pointsRaw = (t?['points'] is List) ? (t!['points'] as List) : const [];
    final points = pointsRaw.map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map)).toList();
    final rawCount = t?['rawCount'];

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Container(
        decoration: BoxDecoration(
          color: AppThemeDecorations.cardColor(context),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
              child: Row(
                children: [
                  const Icon(Icons.timeline, color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'مسار اليوم (كل 30 دقيقة) — نقاط: ${points.length} (خام: ${rawCount ?? '—'})',
                      style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w800),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'تحديث المسار',
                    icon: const Icon(Icons.refresh, color: AppColors.primary),
                    onPressed: _loadTrack,
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: points.isEmpty
                  ? Center(child: Text('لا توجد نقاط في هذا اليوم', style: TextStyle(color: AppColors.muted.withOpacity(0.9))))
                  : ListView.builder(
                      padding: const EdgeInsets.all(12),
                      itemCount: points.length,
                      itemBuilder: (ctx, i) {
                        final p = points[i];
                        final createdAt = (p['createdAt'] ?? '').toString();
                        final lat = p['latitude'];
                        final lng = p['longitude'];
                        final taskId = p['taskId'];
                        final isArrived = p['isArrived'] == true;
                        final url = 'https://www.google.com/maps?q=$lat,$lng';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppThemeDecorations.pageBackground(context),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: isArrived ? Colors.green.withOpacity(0.2) : AppColors.primary.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  isArrived ? Icons.flag : Icons.place,
                                  color: isArrived ? Colors.green : AppColors.primary,
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(createdAt, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700)),
                                    const SizedBox(height: 4),
                                    Text('Lat/Lng: $lat, $lng', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                                    if (taskId != null) ...[
                                      const SizedBox(height: 2),
                                      Text('Task: #$taskId', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                                    ],
                                  ],
                                ),
                              ),
                              TextButton(
                                onPressed: () async {
                                  final uri = Uri.parse(url);
                                  if (await canLaunchUrl(uri)) {
                                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                                  }
                                },
                                child: const Text('فتح', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

