import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../services/api_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_theme.dart';
import 'survey_edit_screen.dart';

class SurveyDetailScreen extends StatefulWidget {
  const SurveyDetailScreen({super.key, required this.survey});

  final Map<String, dynamic> survey;

  @override
  State<SurveyDetailScreen> createState() => _SurveyDetailScreenState();
}

class _SurveyDetailScreenState extends State<SurveyDetailScreen> {
  late Map<String, dynamic> survey;

  @override
  void initState() {
    super.initState();
    survey = Map<String, dynamic>.from(widget.survey);
  }

  Future<void> _deleteSurvey() async {
    final name = (survey['projectName'] ?? '').toString();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppThemeDecorations.cardColor(context),
          title: const Text('حذف المعاينة', style: TextStyle(color: AppColors.text)),
          content: Text(
            'هل أنت متأكد من حذف "$name"؟\nلا يمكن التراجع عن هذا الإجراء.',
            style: const TextStyle(color: AppColors.muted),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await ApiService.mutate('surveys.delete', input: {'id': survey['id']});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف المعاينة بنجاح'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الحذف: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _editSurvey() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => SurveyEditScreen(survey: survey)),
    );
    if (result == true && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (survey['projectName'] ?? 'مشروع بدون اسم').toString();
    final clientEmail = survey['clientEmail']?.toString() ?? '';
    final notes = survey['notes']?.toString() ?? '';
    final lightingLines = survey['lightingLines'] ?? 0;
    final curtains = survey['curtains'] ?? 0;
    final acUnits = survey['acUnits'] ?? 0;
    final tvUnits = survey['tvUnits'] ?? 0;
    final curtainMeters = (survey['curtainMeters'] ?? 0).toDouble();

    final switchGroups = survey['switchGroups'];
    final sensors = survey['sensors'];
    final floors = survey['floors'];
    final rooms = survey['rooms'];

    String dateStr = '';
    final createdAt = survey['createdAt'];
    if (createdAt != null) {
      try {
        final dt = DateTime.fromMillisecondsSinceEpoch(
          createdAt is int ? createdAt : int.tryParse(createdAt.toString()) ?? 0,
        );
        dateStr = DateFormat('yyyy/MM/dd – hh:mm a', 'en').format(dt);
      } catch (_) {}
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppThemeDecorations.pageBackground(context),
        appBar: AppBar(
          backgroundColor: AppThemeDecorations.cardColor(context),
          title: Text(name, style: const TextStyle(color: AppColors.text, fontSize: 16)),
          iconTheme: const IconThemeData(color: AppColors.primary),
          actions: [
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              color: AppColors.primary,
              tooltip: 'تعديل',
              onPressed: _editSurvey,
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline),
              color: Colors.red.shade400,
              tooltip: 'حذف',
              onPressed: _deleteSurvey,
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Project info
              _Section(
                title: 'بيانات المشروع',
                icon: Icons.home_work_outlined,
                children: [
                  _DetailRow(label: 'اسم المشروع', value: name),
                  if (clientEmail.isNotEmpty)
                    _DetailRow(label: 'إيميل العميل', value: clientEmail),
                  if (dateStr.isNotEmpty)
                    _DetailRow(label: 'تاريخ الإنشاء', value: dateStr),
                  if (notes.isNotEmpty)
                    _DetailRow(label: 'ملاحظات', value: notes),
                ],
              ),
              const SizedBox(height: 12),

              // Lighting summary
              _Section(
                title: 'Lighting Summary',
                icon: Icons.lightbulb_outline,
                children: [
                  _DetailRow(label: 'إجمالي خطوط الإضاءة', value: '$lightingLines'),
                  if (switchGroups is Map) ...[
                    _DetailRow(label: 'مفاتيح 1 خط', value: '${switchGroups['switches1Line'] ?? 0}'),
                    _DetailRow(label: 'مفاتيح 2 خط', value: '${switchGroups['switches2Line'] ?? 0}'),
                    _DetailRow(label: 'مفاتيح 3 خطوط', value: '${switchGroups['switches3Line'] ?? 0}'),
                    _DetailRow(label: 'مفاتيح 4 خطوط', value: '${switchGroups['switches4Line'] ?? 0}'),
                  ],
                ],
              ),
              const SizedBox(height: 12),

              // IR Controllers
              _Section(
                title: 'IR Controllers',
                icon: Icons.settings_remote,
                children: [
                  _DetailRow(label: 'وحدات تكييف', value: '$acUnits'),
                  _DetailRow(label: 'وحدات شاشات', value: '$tvUnits'),
                ],
              ),
              const SizedBox(height: 12),

              // Curtains
              _Section(
                title: 'Curtain System',
                icon: Icons.curtains_outlined,
                children: [
                  _DetailRow(label: 'عدد الستائر', value: '$curtains'),
                  _DetailRow(label: 'إجمالي الأمتار', value: '${curtainMeters.toStringAsFixed(1)} م'),
                ],
              ),
              const SizedBox(height: 12),

              // Sensors
              if (sensors is Map)
                _Section(
                  title: 'Sensors',
                  icon: Icons.sensors,
                  children: [
                    if ((sensors['motion'] ?? 0) > 0)
                      _DetailRow(label: 'Motion Sensor', value: '${sensors['motion']}'),
                    if ((sensors['waterLeak'] ?? 0) > 0)
                      _DetailRow(label: 'Water Leak Sensor', value: '${sensors['waterLeak']}'),
                    if ((sensors['gas'] ?? 0) > 0)
                      _DetailRow(label: 'Gas Sensor', value: '${sensors['gas']}'),
                    if ((sensors['temperature'] ?? 0) > 0)
                      _DetailRow(label: 'Temperature Sensor', value: '${sensors['temperature']}'),
                    if ((sensors['smartValves'] ?? 0) > 0)
                      _DetailRow(label: 'Smart Valve', value: '${sensors['smartValves']}'),
                  ],
                ),
              if (sensors is Map) const SizedBox(height: 12),

              // Floors & Rooms
              if (floors is List && (floors as List).isNotEmpty)
                _Section(
                  title: 'الأدوار والغرف',
                  icon: Icons.layers,
                  children: [
                    for (final floor in floors as List)
                      _FloorTile(floor: floor),
                  ],
                )
              else if (rooms is List && (rooms as List).isNotEmpty)
                _Section(
                  title: 'الغرف',
                  icon: Icons.meeting_room,
                  children: [
                    for (final room in rooms as List)
                      _RoomTile(room: room),
                  ],
                ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.children});

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: AppThemeDecorations.cardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
            child: Row(
              children: [
                Icon(icon, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 14)),
              ],
            ),
          ),
          const Divider(color: AppColors.border, height: 1),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: AppColors.text, fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _FloorTile extends StatelessWidget {
  const _FloorTile({required this.floor});

  final dynamic floor;

  @override
  Widget build(BuildContext context) {
    final floorName = (floor['name'] ?? 'دور').toString();
    final floorRooms = floor['rooms'];

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppThemeDecorations.pageBackground(context),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border.withOpacity(0.5)),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        title: Text(floorName, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Text(
          floorRooms is List ? '${floorRooms.length} غرفة' : '',
          style: const TextStyle(color: AppColors.muted, fontSize: 11),
        ),
        children: [
          if (floorRooms is List)
            for (final room in floorRooms)
              _RoomTile(room: room),
        ],
      ),
    );
  }
}

class _RoomTile extends StatelessWidget {
  const _RoomTile({required this.room});

  final dynamic room;

  @override
  Widget build(BuildContext context) {
    final roomName = (room['name'] ?? 'غرفة').toString();
    final parts = <String>[];

    if (room['hasLighting'] == true) {
      final boxes = room['magicBoxesCount'] ?? 0;
      final lines = room['magicLinesManual'] ?? 0;
      if (boxes > 0 && lines > 0) {
        parts.add('إضاءة: $boxes علبة ($lines خط)');
      } else {
        parts.add('إضاءة ذكية');
      }
    }
    if (room['hasCurtain'] == true) {
      final kind = room['curtainKind']?.toString() ?? '';
      parts.add('ستائر ${kind == 'double' ? 'مزدوجة' : 'مفردة'}');
      final lengthCm = room['curtainLengthCm'];
      if (lengthCm != null) parts.add('طول: ${(lengthCm as num).toStringAsFixed(0)} سم');
    }
    if (room['hasAcIr'] == true) parts.add('تكييف: ${room['acUnits'] ?? 1}');
    if (room['hasTvIr'] == true) parts.add('شاشات: ${room['tvUnits'] ?? 1}');

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: const Icon(Icons.meeting_room_outlined, color: AppColors.primary, size: 18),
      title: Text(roomName, style: const TextStyle(color: AppColors.text, fontSize: 13)),
      subtitle: parts.isNotEmpty
          ? Text(parts.join(' • '), style: const TextStyle(color: AppColors.muted, fontSize: 11))
          : null,
    );
  }
}
