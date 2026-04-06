import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:just_audio/just_audio.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';
import '../../services/api_service.dart';

class CrmLeadDetailScreen extends StatefulWidget {
  final int leadId;
  final List<dynamic> staff;
  const CrmLeadDetailScreen({super.key, required this.leadId, required this.staff});

  @override
  State<CrmLeadDetailScreen> createState() => _CrmLeadDetailScreenState();
}

class _CrmLeadDetailScreenState extends State<CrmLeadDetailScreen> {
  Map<String, dynamic> _lead = {};
  List<dynamic> _activities = [];
  bool _loading = true;
  bool _changed = false;
  bool _uploadingCallRecording = false;

  static const _stages = [
    {'key': 'new', 'label': 'جديد', 'icon': Icons.fiber_new, 'color': Colors.blue},
    {'key': 'contacted', 'label': 'تم التواصل', 'icon': Icons.phone_callback, 'color': Colors.cyan},
    {'key': 'qualified', 'label': 'مؤهل', 'icon': Icons.verified, 'color': Colors.purple},
    {'key': 'proposal', 'label': 'عرض سعر', 'icon': Icons.description, 'color': Colors.orange},
    {'key': 'negotiation', 'label': 'تفاوض', 'icon': Icons.handshake, 'color': Colors.amber},
    {'key': 'won', 'label': 'تم البيع', 'icon': Icons.emoji_events, 'color': Colors.green},
    {'key': 'lost', 'label': 'مفقود', 'icon': Icons.cancel, 'color': Colors.red},
  ];

  static const _actTypeIcons = {
    'note': Icons.note_alt, 'call': Icons.phone, 'meeting': Icons.groups,
    'email': Icons.email, 'stage_change': Icons.swap_horiz, 'assignment': Icons.person_add,
    'created': Icons.add_circle, 'follow_up': Icons.schedule, 'other': Icons.more_horiz,
    'call_recording': Icons.mic,
  };
  static const _actTypeColors = {
    'note': Colors.blue, 'call': Colors.green, 'meeting': Colors.purple,
    'email': Colors.cyan, 'stage_change': Colors.orange, 'assignment': Color(0xFFD4920A),
    'created': Colors.teal, 'follow_up': Colors.amber, 'other': Colors.grey,
    'call_recording': Colors.deepPurple,
  };
  static const _actTypeLabels = {
    'note': 'ملاحظة', 'call': 'مكالمة', 'meeting': 'اجتماع',
    'email': 'بريد', 'follow_up': 'متابعة', 'other': 'أخرى', 'stage_change': 'مرحلة',
    'assignment': 'توزيع', 'created': 'إنشاء', 'call_recording': 'تسجيل صوتي',
  };
  static const _priorityLabels = {'high': 'عالي', 'medium': 'متوسط', 'low': 'منخفض'};
  static const _priorityColors = {'high': Colors.red, 'medium': Colors.orange, 'low': Colors.green};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.query('crm.getLeadById', input: {'id': widget.leadId});
      final data = res['data'];
      if (data is Map) {
        setState(() {
          _lead = Map<String, dynamic>.from(data);
          _activities = (_lead['activities'] as List?) ?? [];
        });
      }
    } catch (_) {}
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async { Navigator.pop(context, _changed); return false; },
      child: Scaffold(
        backgroundColor: AppThemeDecorations.pageBackground(context),
        appBar: AppBar(
          backgroundColor: AppThemeDecorations.cardColor(context),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.text),
            onPressed: () => Navigator.pop(context, _changed),
          ),
          title: Text(_lead['name'] ?? 'تفاصيل الليد', style: const TextStyle(color: AppColors.text, fontSize: 16)),
          actions: [
            IconButton(icon: const Icon(Icons.edit, size: 20), color: AppColors.text, onPressed: _showEditLead),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.text),
              color: AppThemeDecorations.cardColor(context),
              onSelected: (v) {
                if (v == 'assign') _showAssignDialog();
                if (v == 'stage') _showStageDialog();
                if (v == 'delete') _deleteLead();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'assign', child: Text('توزيع على مندوب', style: TextStyle(color: AppColors.text, fontSize: 13))),
                const PopupMenuItem(value: 'stage', child: Text('تغيير المرحلة', style: TextStyle(color: AppColors.text, fontSize: 13))),
                const PopupMenuItem(value: 'delete', child: Text('حذف الليد', style: TextStyle(color: Colors.red, fontSize: 13))),
              ],
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : RefreshIndicator(
                onRefresh: _load,
                color: AppColors.primary,
                child: ListView(padding: const EdgeInsets.all(16), children: [
                  _buildInfoCard(),
                  const SizedBox(height: 12),
                  _buildPipelineProgress(),
                  const SizedBox(height: 16),
                  _buildAssigneeCard(),
                  const SizedBox(height: 16),
                  _buildCallRecordingCard(),
                  const SizedBox(height: 16),
                  _buildActivityHeader(),
                  const SizedBox(height: 8),
                  _buildTimeline(),
                ]),
              ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: AppColors.primary,
          onPressed: _showAddActivity,
          icon: const Icon(Icons.add, color: Colors.black),
          label: const Text('إضافة نشاط', style: TextStyle(color: Colors.black, fontSize: 13, fontWeight: FontWeight.bold)),
        ),
      ),
    );
  }

  Widget _buildInfoCard() {
    final stage = _lead['pipelineStage'] ?? 'new';
    final stageInfo = _stages.firstWhere((s) => s['key'] == stage, orElse: () => _stages.first);
    final priority = _lead['priority'] ?? 'medium';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppThemeDecorations.cardColor(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 50, height: 50,
            decoration: BoxDecoration(color: (stageInfo['color'] as Color).withOpacity(0.15), borderRadius: BorderRadius.circular(14)),
            child: Center(child: Text((_lead['name'] ?? 'ل')[0].toUpperCase(), style: TextStyle(color: stageInfo['color'] as Color, fontWeight: FontWeight.bold, fontSize: 22))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_lead['name'] ?? '', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 4),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: (stageInfo['color'] as Color).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(stageInfo['icon'] as IconData, color: stageInfo['color'] as Color, size: 14),
                  const SizedBox(width: 4),
                  Text(stageInfo['label'] as String, style: TextStyle(color: stageInfo['color'] as Color, fontSize: 11, fontWeight: FontWeight.bold)),
                ]),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: (_priorityColors[priority] ?? Colors.grey).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                child: Text(_priorityLabels[priority] ?? '', style: TextStyle(color: _priorityColors[priority] ?? Colors.grey, fontSize: 10, fontWeight: FontWeight.w600)),
              ),
            ]),
          ])),
        ]),
        const Divider(color: AppColors.border, height: 24),
        if ((_lead['phone'] ?? '').toString().isNotEmpty) _buildPhoneRow(),
        if ((_lead['email'] ?? '').toString().isNotEmpty) _infoRow(Icons.email, _lead['email'].toString()),
        if ((_lead['address'] ?? '').toString().isNotEmpty) _infoRow(Icons.location_on, _lead['address'].toString()),
        if ((_lead['locationUrl'] ?? '').toString().trim().isNotEmpty) _buildLocationUrlRow(),
        if (_lead['linkedClientId'] != null) _buildLinkedClientRow(),
        if ((_lead['expectedValue'] ?? 0) > 0) _infoRow(Icons.attach_money, '${(_lead['expectedValue'] as num).toStringAsFixed(0)} ج.م'),
        _infoRow(Icons.source, 'مصدر: ${_lead['source'] ?? 'يدوي'}'),
        if ((_lead['notes'] ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_lead['notes'], style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          ),
      ]),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(icon, color: AppColors.muted, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(color: AppColors.text, fontSize: 13))),
      ]),
    );
  }

  Widget _buildPhoneRow() {
    final phone = _lead['phone']?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Icon(Icons.phone, color: AppColors.muted, size: 16),
          const SizedBox(width: 8),
          Expanded(child: Text(phone, style: const TextStyle(color: AppColors.text, fontSize: 13))),
          IconButton(
            tooltip: 'اتصال وتسجيل تلقائي للمكالمة',
            icon: const Icon(Icons.call, color: Colors.green, size: 24),
            onPressed: _dialLead,
          ),
        ],
      ),
    );
  }

  Widget _buildLocationUrlRow() {
    final u = (_lead['locationUrl'] ?? '').toString().trim();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () async {
          var uri = Uri.tryParse(u);
          if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
            uri = Uri.parse('https://maps.google.com/?q=${Uri.encodeComponent(u)}');
          }
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.map_outlined, color: AppColors.primary, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                u,
                style: const TextStyle(color: AppColors.primary, fontSize: 12, decoration: TextDecoration.underline),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinkedClientRow() {
    final id = _lead['linkedClientId'];
    if (id == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.verified_user_outlined, color: Colors.teal, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'مسجّل كعميل في النظام (رقم #$id) — يمكن اختياره في المهام وقائمة العملاء',
              style: const TextStyle(color: AppColors.muted, fontSize: 12, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _dialLead() async {
    final raw = _lead['phone']?.toString().trim() ?? '';
    if (raw.isEmpty) return;
    try {
      await ApiService.mutate('crm.recordCall', input: {'leadId': widget.leadId});
      _changed = true;
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    final cleaned = raw.replaceAll(RegExp(r'[\s\-]'), '');
    final uri = Uri(scheme: 'tel', path: cleaned);
    var launched = false;
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
        launched = true;
      }
    } catch (_) {}
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            launched
                ? 'تم تسجيل المكالمة بالوقت الحالي. أضف تفاصيلها من «إضافة نشاط».'
                : 'تم تسجيل المكالمة في النظام. إذا لم يُفتح الاتصال، اتصل يدوياً ثم أضف الملاحظات من «إضافة نشاط».',
          ),
        ),
      );
    }
  }

  Widget _buildCallRecordingCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeDecorations.cardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.deepPurple.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.audio_file, color: Colors.deepPurple, size: 22),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('تسجيل مكالمة', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 14)),
              SizedBox(height: 4),
              Text(
                'ارفع ملف التسجيل من موبايل السيلز (mp3, m4a, …). يظهر في سجل النشاطات مع إمكانية التشغيل والمراجعة.',
                style: TextStyle(color: AppColors.muted, fontSize: 11, height: 1.3),
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _uploadingCallRecording ? null : _pickAndUploadCallRecording,
            icon: _uploadingCallRecording
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary))
                : const Icon(Icons.upload_file, size: 18),
            label: Text(_uploadingCallRecording ? 'جاري الرفع…' : 'اختيار ملف ورفعه'),
          ),
        ),
      ]),
    );
  }

  Future<void> _pickAndUploadCallRecording() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['m4a', 'mp3', 'aac', 'wav', 'amr', 'ogg', 'mpeg', 'mpga', '3gp'],
        withData: kIsWeb,
      );
      if (res == null || res.files.isEmpty) return;
      final f = res.files.single;
      setState(() => _uploadingCallRecording = true);
      String url;
      if (kIsWeb) {
        final bytes = f.bytes;
        if (bytes == null) throw Exception('تعذّر قراءة الملف');
        url = await ApiService.uploadFile('', bytes: bytes, filename: f.name);
      } else {
        final path = f.path;
        if (path == null || path.isEmpty) {
          final bytes = f.bytes;
          if (bytes == null) throw Exception('تعذّر قراءة الملف');
          url = await ApiService.uploadFile('', bytes: bytes, filename: f.name);
        } else {
          url = await ApiService.uploadFile(path, filename: f.name);
        }
      }

      if (!mounted) return;
      final noteCtrl = TextEditingController();
      final note = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppThemeDecorations.cardColor(context),
          title: const Text('تعليق المراقبة (اختياري)', style: TextStyle(color: AppColors.text, fontSize: 15)),
          content: TextField(
            controller: noteCtrl,
            maxLines: 3,
            style: const TextStyle(color: AppColors.text, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'ملاحظات على التسجيل…',
              hintStyle: const TextStyle(color: AppColors.muted),
              filled: true,
              fillColor: AppThemeDecorations.pageBackground(context),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('تخطّي')),
            TextButton(onPressed: () => Navigator.pop(ctx, noteCtrl.text), child: const Text('حفظ')),
          ],
        ),
      ) ?? '';

      await ApiService.mutate('crm.addActivity', input: {
        'leadId': widget.leadId,
        'type': 'call_recording',
        'title': 'تسجيل مكالمة',
        'content': note.trim(),
        'mediaUrl': url,
      });
      _changed = true;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم رفع التسجيل وربطه بهذا الليد')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingCallRecording = false);
    }
  }

  void _playRecording(String rawUrl) {
    final url = kIsWeb ? ApiService.proxyImageUrl(rawUrl) : rawUrl;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppThemeDecorations.cardColor(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => _LeadAudioPlayerSheet(url: url),
    );
  }

  Widget _buildPipelineProgress() {
    final currentStage = _lead['pipelineStage'] ?? 'new';
    final currentIdx = _stages.indexWhere((s) => s['key'] == currentStage);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: AppThemeDecorations.cardColor(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('مراحل البيع', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: List.generate(_stages.length, (i) {
            final s = _stages[i];
            final isActive = i <= currentIdx;
            final isCurrent = i == currentIdx;
            return GestureDetector(
              onTap: () => _updateStage(s['key'] as String),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Column(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: isCurrent ? (s['color'] as Color) : isActive ? (s['color'] as Color).withOpacity(0.3) : AppThemeDecorations.pageBackground(context),
                      shape: BoxShape.circle,
                      border: Border.all(color: isActive ? (s['color'] as Color) : AppColors.border, width: isCurrent ? 2 : 1),
                    ),
                    child: Icon(s['icon'] as IconData, color: isCurrent ? Colors.white : isActive ? (s['color'] as Color) : AppColors.muted, size: 16),
                  ),
                  const SizedBox(height: 4),
                  Text(s['label'] as String, style: TextStyle(color: isActive ? (s['color'] as Color) : AppColors.muted, fontSize: 9, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal)),
                ]),
                if (i < _stages.length - 1)
                  Container(width: 20, height: 2, color: isActive && i < currentIdx ? (s['color'] as Color).withOpacity(0.5) : AppColors.border, margin: const EdgeInsets.only(bottom: 16)),
              ]),
            );
          })),
        ),
      ]),
    );
  }

  Widget _buildAssigneeCard() {
    final assigneeName = (_lead['assigneeName'] as String?) ?? '';
    final hasAssignee = assigneeName.isNotEmpty;

    return GestureDetector(
      onTap: _showAssignDialog,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppThemeDecorations.cardColor(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.border)),
        child: Row(children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: hasAssignee ? AppColors.primary.withOpacity(0.15) : AppThemeDecorations.pageBackground(context),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(hasAssignee ? Icons.person : Icons.person_add, color: hasAssignee ? AppColors.primary : AppColors.muted, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('المسؤول', style: TextStyle(color: AppColors.muted, fontSize: 11)),
            Text(hasAssignee ? assigneeName : 'غير موزع - اضغط للتوزيع', style: TextStyle(color: hasAssignee ? AppColors.text : AppColors.muted, fontWeight: FontWeight.w600, fontSize: 14)),
          ])),
          const Icon(Icons.chevron_right, color: AppColors.muted, size: 20),
        ]),
      ),
    );
  }

  Widget _buildActivityHeader() {
    return Row(children: [
      const Expanded(child: Text('سجل النشاطات', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 16))),
      Text('${_activities.length} نشاط', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
    ]);
  }

  Widget _buildTimeline() {
    if (_activities.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(32),
        child: const Center(child: Column(children: [
          Icon(Icons.timeline, color: AppColors.muted, size: 48),
          SizedBox(height: 8),
          Text('لا يوجد نشاطات', style: TextStyle(color: AppColors.muted)),
        ])),
      );
    }

    return Column(children: List.generate(_activities.length, (i) {
      final a = _activities[i];
      final type = a['type'] ?? 'note';
      final isLast = i == _activities.length - 1;

      return IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 40,
          child: Column(children: [
            Container(
              width: 32, height: 32,
              decoration: BoxDecoration(
                color: (_actTypeColors[type] ?? Colors.grey).withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(_actTypeIcons[type] ?? Icons.circle, color: _actTypeColors[type] ?? Colors.grey, size: 16),
            ),
            if (!isLast) Expanded(child: Container(width: 2, color: AppColors.border.withOpacity(0.5))),
          ]),
        ),
        const SizedBox(width: 8),
        Expanded(child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppThemeDecorations.cardColor(context),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border.withOpacity(0.5)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(a['title'] ?? '', style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13))),
              if (type != 'created' && type != 'stage_change' && type != 'assignment')
                GestureDetector(
                  onTap: () => _deleteActivity(a['id']),
                  child: const Icon(Icons.close, color: AppColors.muted, size: 16),
                ),
            ]),
            if ((a['content'] ?? '').toString().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(a['content'].toString(), style: const TextStyle(color: AppColors.text, fontSize: 12)),
              ),
            if ((a['mediaUrl'] ?? '').toString().trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: () => _playRecording(a['mediaUrl'].toString()),
                  icon: const Icon(Icons.play_circle_outline, size: 20),
                  label: const Text('تشغيل التسجيل'),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.person, color: AppColors.muted, size: 12),
              const SizedBox(width: 4),
              Text(a['userName'] ?? '', style: const TextStyle(color: AppColors.muted, fontSize: 10)),
              const Spacer(),
              Text(_formatDateTime(a['createdAt']), style: const TextStyle(color: AppColors.muted, fontSize: 10)),
            ]),
          ]),
        )),
      ]));
    }));
  }

  // ─── Actions ────────────────────────────────────────────────
  void _showAddActivity() {
    final contentCtrl = TextEditingController();
    String type = 'note';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppThemeDecorations.cardColor(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.muted.withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          const Text('إضافة نشاط', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 16),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: ['note', 'call', 'meeting', 'email', 'follow_up', 'other'].map((t) => Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => setS(() => type = t),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: type == t ? (_actTypeColors[t] ?? Colors.grey).withOpacity(0.2) : AppThemeDecorations.pageBackground(context),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: type == t ? (_actTypeColors[t] ?? Colors.grey) : AppColors.border),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_actTypeIcons[t] ?? Icons.circle, color: type == t ? (_actTypeColors[t] ?? Colors.grey) : AppColors.muted, size: 16),
                    const SizedBox(width: 6),
                    Text(_actTypeLabels[t] ?? t, style: TextStyle(color: type == t ? (_actTypeColors[t] ?? Colors.grey) : AppColors.muted, fontSize: 12, fontWeight: type == t ? FontWeight.bold : FontWeight.normal)),
                  ]),
                ),
              ),
            )).toList()),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: contentCtrl,
            maxLines: 4,
            autofocus: true,
            style: const TextStyle(color: AppColors.text, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'اكتب تفاصيل النشاط...',
              hintStyle: const TextStyle(color: AppColors.muted, fontSize: 13),
              filled: true, fillColor: AppThemeDecorations.pageBackground(context),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                if (contentCtrl.text.trim().isEmpty) return;
                try {
                  await ApiService.mutate('crm.addActivity', input: {
                    'leadId': widget.leadId,
                    'type': type,
                    'title': _actTypeLabels[type] ?? type,
                    'content': contentCtrl.text.trim(),
                  });
                  if (ctx.mounted) Navigator.pop(ctx);
                  _changed = true;
                  _load();
                } catch (e) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل: $e'), backgroundColor: Colors.red));
                }
              },
              child: const Text('حفظ النشاط'),
            ),
          ),
        ]),
      )),
    );
  }

  Future<void> _deleteActivity(int id) async {
    try {
      await ApiService.mutate('crm.deleteActivity', input: {'id': id});
      _changed = true;
      _load();
    } catch (_) {}
  }

  Future<void> _updateStage(String stage) async {
    if (stage == (_lead['pipelineStage'] ?? 'new')) return;
    try {
      await ApiService.mutate('crm.updateStage', input: {'id': widget.leadId, 'stage': stage});
      _changed = true;
      _load();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل: $e'), backgroundColor: Colors.red));
    }
  }

  void _showAssignDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppThemeDecorations.cardColor(context),
        title: const Text('توزيع على مندوب', style: TextStyle(color: AppColors.text, fontSize: 16)),
        content: SizedBox(
          width: 300,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: const Icon(Icons.person_off, color: AppColors.muted),
              title: const Text('إلغاء التوزيع', style: TextStyle(color: AppColors.text, fontSize: 13)),
              onTap: () async { Navigator.pop(ctx); await _assignTo(null); },
            ),
            const Divider(color: AppColors.border),
            ...widget.staff.map((s) => ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.primary.withOpacity(0.15),
                radius: 16,
                child: Text((s['name'] ?? 'م')[0], style: const TextStyle(color: AppColors.primary, fontSize: 12)),
              ),
              title: Text(s['name'] ?? '', style: const TextStyle(color: AppColors.text, fontSize: 13)),
              subtitle: Text(s['role'] ?? '', style: const TextStyle(color: AppColors.muted, fontSize: 10)),
              trailing: _lead['assignedTo'] == s['id'] ? const Icon(Icons.check_circle, color: AppColors.primary, size: 18) : null,
              onTap: () async { Navigator.pop(ctx); await _assignTo(s['id']); },
            )),
          ]),
        ),
      ),
    );
  }

  Future<void> _assignTo(int? staffId) async {
    try {
      await ApiService.mutate('crm.assignLead', input: {'id': widget.leadId, 'assignedTo': staffId});
      _changed = true;
      _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تم التوزيع بنجاح'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل: $e'), backgroundColor: Colors.red));
    }
  }

  void _showStageDialog() {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: AppThemeDecorations.cardColor(context),
        title: const Text('تغيير المرحلة', style: TextStyle(color: AppColors.text, fontSize: 16)),
        children: _stages.map((s) => SimpleDialogOption(
          onPressed: () { Navigator.pop(ctx); _updateStage(s['key'] as String); },
          child: Row(children: [
            Icon(s['icon'] as IconData, color: s['color'] as Color, size: 20),
            const SizedBox(width: 10),
            Text(s['label'] as String, style: TextStyle(
              color: _lead['pipelineStage'] == s['key'] ? AppColors.primary : AppColors.text,
              fontWeight: _lead['pipelineStage'] == s['key'] ? FontWeight.bold : FontWeight.normal,
            )),
            if (_lead['pipelineStage'] == s['key']) ...[const Spacer(), const Icon(Icons.check, color: AppColors.primary, size: 18)],
          ]),
        )).toList(),
      ),
    );
  }

  void _showEditLead() {
    final nameCtrl = TextEditingController(text: _lead['name'] ?? '');
    final phoneCtrl = TextEditingController(text: _lead['phone'] ?? '');
    final emailCtrl = TextEditingController(text: _lead['email'] ?? '');
    final addressCtrl = TextEditingController(text: _lead['address'] ?? '');
    final locationUrlCtrl = TextEditingController(text: (_lead['locationUrl'] ?? '').toString());
    final notesCtrl = TextEditingController(text: _lead['notes'] ?? '');
    final valueCtrl = TextEditingController(text: ((_lead['expectedValue'] ?? 0) > 0) ? (_lead['expectedValue'] as num).toStringAsFixed(0) : '');
    String priority = _lead['priority'] ?? 'medium';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        backgroundColor: AppThemeDecorations.cardColor(context),
        title: const Text('تعديل بيانات الليد', style: TextStyle(color: AppColors.text, fontSize: 16)),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          _field(nameCtrl, 'الاسم', Icons.person),
          const SizedBox(height: 10),
          _field(phoneCtrl, 'الهاتف', Icons.phone),
          const SizedBox(height: 10),
          _field(emailCtrl, 'البريد', Icons.email),
          const SizedBox(height: 10),
          _field(addressCtrl, 'العنوان', Icons.location_on),
          const SizedBox(height: 10),
          _field(locationUrlCtrl, 'رابط الموقع / خرائط (اختياري)', Icons.map_outlined),
          const SizedBox(height: 10),
          _field(valueCtrl, 'القيمة المتوقعة (ج.م)', Icons.attach_money, isNumber: true),
          const SizedBox(height: 10),
          _field(notesCtrl, 'ملاحظات', Icons.note, maxLines: 2),
          const SizedBox(height: 12),
          Row(children: [
            const Text('الأولوية: ', style: TextStyle(color: AppColors.muted, fontSize: 12)),
            const SizedBox(width: 8),
            ...['low', 'medium', 'high'].map((p) => Padding(
              padding: const EdgeInsets.only(right: 6),
              child: GestureDetector(
                onTap: () => setD(() => priority = p),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: priority == p ? (_priorityColors[p] ?? Colors.grey).withOpacity(0.2) : AppThemeDecorations.pageBackground(context),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: priority == p ? (_priorityColors[p] ?? Colors.grey) : AppColors.border),
                  ),
                  child: Text(_priorityLabels[p] ?? '', style: TextStyle(color: priority == p ? _priorityColors[p] : AppColors.muted, fontSize: 11)),
                ),
              ),
            )),
          ]),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء', style: TextStyle(color: AppColors.muted))),
          ElevatedButton(
            onPressed: () async {
              try {
                await ApiService.mutate('crm.updateLead', input: {
                  'id': widget.leadId,
                  'name': nameCtrl.text.trim(),
                  'phone': phoneCtrl.text.trim(),
                  'email': emailCtrl.text.trim(),
                  'address': addressCtrl.text.trim(),
                  'locationUrl': locationUrlCtrl.text.trim(),
                  'notes': notesCtrl.text.trim(),
                  'priority': priority,
                  'expectedValue': double.tryParse(valueCtrl.text) ?? 0,
                });
                if (ctx.mounted) Navigator.pop(ctx);
                _changed = true;
                _load();
              } catch (e) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل: $e'), backgroundColor: Colors.red));
              }
            },
            child: const Text('حفظ'),
          ),
        ],
      )),
    );
  }

  Future<void> _deleteLead() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppThemeDecorations.cardColor(context),
        title: const Text('حذف الليد', style: TextStyle(color: Colors.red)),
        content: const Text('هل تريد حذف هذا الليد وكل نشاطاته؟', style: TextStyle(color: AppColors.text)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء', style: TextStyle(color: AppColors.muted))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('حذف', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await ApiService.mutate('crm.deleteLead', input: {'id': widget.leadId});
        if (mounted) Navigator.pop(context, true);
      } catch (e) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('فشل: $e'), backgroundColor: Colors.red));
      }
    }
  }

  Widget _field(TextEditingController ctrl, String hint, IconData icon, {int maxLines = 1, bool isNumber = false}) {
    return TextField(
      controller: ctrl,
      maxLines: maxLines,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      style: const TextStyle(color: AppColors.text, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint, hintStyle: const TextStyle(color: AppColors.muted, fontSize: 13),
        prefixIcon: Icon(icon, color: AppColors.muted, size: 18),
        filled: true, fillColor: AppThemeDecorations.pageBackground(context),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  String _formatDateTime(dynamic d) {
    if (d == null) return '';
    try {
      final dt = DateTime.parse(d.toString());
      return '${dt.year}/${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return d.toString();
    }
  }
}

/// مشغّل صوت بسيط لتسجيلات المكالمات المرفوعة.
class _LeadAudioPlayerSheet extends StatefulWidget {
  const _LeadAudioPlayerSheet({required this.url});
  final String url;

  @override
  State<_LeadAudioPlayerSheet> createState() => _LeadAudioPlayerSheetState();
}

class _LeadAudioPlayerSheetState extends State<_LeadAudioPlayerSheet> {
  late final AudioPlayer _player = AudioPlayer();
  bool _loading = true;
  String? _err;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _player.setUrl(widget.url);
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _err = e.toString();
        });
      }
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('تشغيل التسجيل', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 16),
            if (_loading) const CircularProgressIndicator(color: AppColors.primary),
            if (_err != null) ...[
              Text(_err!, style: const TextStyle(color: Colors.red, fontSize: 12)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () async {
                  final u = Uri.tryParse(widget.url);
                  if (u != null && await canLaunchUrl(u)) await launchUrl(u, mode: LaunchMode.externalApplication);
                },
                child: const Text('فتح الرابط خارج التطبيق'),
              ),
            ],
            if (!_loading && _err == null)
              StreamBuilder<PlayerState>(
                stream: _player.playerStateStream,
                builder: (context, snapshot) {
                  final playing = snapshot.data?.playing ?? false;
                  return IconButton(
                    iconSize: 56,
                    color: AppColors.primary,
                    icon: Icon(playing ? Icons.pause_circle : Icons.play_circle),
                    onPressed: () => playing ? _player.pause() : _player.play(),
                  );
                },
              ),
            const SizedBox(height: 8),
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('إغلاق')),
          ],
        ),
      ),
    );
  }
}
