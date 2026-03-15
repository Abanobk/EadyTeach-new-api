import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../services/api_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_theme.dart';
import 'survey_detail_screen.dart';
import 'survey_edit_screen.dart';

class SavedSurveysScreen extends StatefulWidget {
  const SavedSurveysScreen({super.key});

  @override
  State<SavedSurveysScreen> createState() => _SavedSurveysScreenState();
}

class _SavedSurveysScreenState extends State<SavedSurveysScreen> {
  List<dynamic> _surveys = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSurveys();
  }

  Future<void> _loadSurveys() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiService.query('surveys.allSurveys');
      final list = res['data'] ?? res ?? [];
      if (list is List) {
        setState(() {
          _surveys = list;
          _loading = false;
        });
      } else {
        setState(() {
          _surveys = [];
          _loading = false;
        });
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _deleteSurvey(int id, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppThemeDecorations.cardColor(context),
          title: Text('حذف المعاينة', style: TextStyle(color: Theme.of(ctx).colorScheme.onSurface)),
          content: Text(
            'هل أنت متأكد من حذف "$name"؟\nلا يمكن التراجع عن هذا الإجراء.',
            style: TextStyle(color: Theme.of(ctx).colorScheme.onSurfaceVariant),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    try {
      await ApiService.mutate('surveys.delete', input: {'id': id});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حذف المعاينة بنجاح'), backgroundColor: Colors.green),
        );
        _loadSurveys();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل الحذف: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _openDetail(Map<String, dynamic> survey) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SurveyDetailScreen(survey: survey),
      ),
    );
    if (result == true) _loadSurveys();
  }

  void _openEdit(Map<String, dynamic> survey) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => SurveyEditScreen(survey: survey),
      ),
    );
    if (result == true) _loadSurveys();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppThemeDecorations.pageBackground(context),
        appBar: AppBar(
          backgroundColor: AppThemeDecorations.cardColor(context),
          title: Text('المعاينات الحالية', style: TextStyle(color: Theme.of(context).colorScheme.onSurface)),
          iconTheme: IconThemeData(color: Theme.of(context).colorScheme.primary),
          actions: [
            IconButton(icon: const Icon(Icons.refresh), onPressed: _loadSurveys),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: AppColors.primary));
    }

    if (_error != null) {
      final scheme = Theme.of(context).colorScheme;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: scheme.onSurfaceVariant, size: 48),
              const SizedBox(height: 12),
              Text('حدث خطأ أثناء تحميل المعاينات',
                  style: TextStyle(color: scheme.onSurface, fontSize: 16), textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton.icon(onPressed: _loadSurveys, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
            ],
          ),
        ),
      );
    }

    if (_surveys.isEmpty) {
      final scheme = Theme.of(context).colorScheme;
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.assignment_outlined, color: scheme.onSurfaceVariant.withOpacity(0.7), size: 64),
            const SizedBox(height: 16),
            Text('لا توجد معاينات محفوظة بعد', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 16)),
            const SizedBox(height: 8),
            Text('ابدأ معاينة جديدة واحفظها لتظهر هنا', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSurveys,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _surveys.length,
        itemBuilder: (context, index) {
          final survey = Map<String, dynamic>.from(_surveys[index]);
          final id = survey['id'] as int? ?? 0;
          final name = (survey['projectName'] ?? 'مشروع بدون اسم').toString();

          return Dismissible(
            key: ValueKey(id),
            direction: DismissDirection.endToStart,
            background: Container(
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: Colors.red.shade700,
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.only(left: 24),
              child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
            ),
            confirmDismiss: (_) async {
              await _deleteSurvey(id, name);
              return false;
            },
            child: _SurveyCompactCard(
              survey: survey,
              onTap: () => _openDetail(survey),
              onEdit: () => _openEdit(survey),
              onDelete: () => _deleteSurvey(id, name),
            ),
          );
        },
      ),
    );
  }
}

class _SurveyCompactCard extends StatelessWidget {
  const _SurveyCompactCard({
    required this.survey,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final Map<String, dynamic> survey;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final name = (survey['projectName'] ?? 'مشروع بدون اسم').toString();
    final lightingLines = survey['lightingLines'] ?? 0;
    final curtains = survey['curtains'] ?? 0;
    final acUnits = survey['acUnits'] ?? 0;
    final tvUnits = survey['tvUnits'] ?? 0;

    String dateStr = '';
    final createdAt = survey['createdAt'];
    if (createdAt != null) {
      try {
        final dt = DateTime.fromMillisecondsSinceEpoch(
          createdAt is int ? createdAt : int.tryParse(createdAt.toString()) ?? 0,
        );
        dateStr = DateFormat('yyyy/MM/dd', 'en').format(dt);
      } catch (_) {}
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppThemeDecorations.cardColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.assignment, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      if (dateStr.isNotEmpty) ...[
                        Icon(Icons.calendar_today, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 11),
                        const SizedBox(width: 3),
                        Text(dateStr, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11)),
                        const SizedBox(width: 10),
                      ],
                      _MiniStat(icon: Icons.lightbulb_outline, value: lightingLines, color: Colors.amber),
                      const SizedBox(width: 8),
                      _MiniStat(icon: Icons.curtains_outlined, value: curtains, color: Colors.purple),
                      const SizedBox(width: 8),
                      _MiniStat(icon: Icons.ac_unit, value: acUnits, color: Colors.cyan),
                      const SizedBox(width: 8),
                      _MiniStat(icon: Icons.tv, value: tvUnits, color: Colors.green),
                    ],
                  ),
                ],
              ),
            ),
            // Edit button
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18),
              color: AppColors.primary,
              tooltip: 'تعديل',
              onPressed: onEdit,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
            // Delete button
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 18),
              color: Colors.red.shade400,
              tooltip: 'حذف',
              onPressed: onDelete,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.icon, required this.value, required this.color});

  final IconData icon;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 13),
        const SizedBox(width: 2),
        Text('$value', style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
