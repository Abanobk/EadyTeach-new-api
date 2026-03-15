import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../theme/app_theme.dart';
import '../../../utils/app_theme.dart';
import '../controllers/survey_controller.dart';
import '../models/survey_models.dart';
import 'saved_surveys_screen.dart';
import 'survey_wizard_screen.dart';

/// الشاشة الرئيسية للدخول إلى نظام Smart Survey
class SurveyEntryScreen extends StatelessWidget {
  const SurveyEntryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => SurveyController(),
      child: const _SurveyEntryBody(),
    );
  }
}

class _SurveyEntryBody extends StatelessWidget {
  const _SurveyEntryBody();

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SurveyController>();
    final project = controller.project;
    final totals = controller.calculateTotals();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppThemeDecorations.pageBackground(context),
        appBar: AppBar(
          backgroundColor: AppThemeDecorations.cardColor(context),
          title: Text(
            'Smart Survey - المعاينة الذكية',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
          ),
          iconTheme: IconThemeData(color: Theme.of(context).colorScheme.primary),
        ),
        floatingActionButton: FloatingActionButton.extended(
          backgroundColor: AppColors.primary,
          onPressed: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChangeNotifierProvider.value(
                  value: controller,
                  child: const SurveyWizardScreen(),
                ),
              ),
            );
          },
          label: const Text(
            'بدء معاينة جديدة',
            style: TextStyle(color: Colors.white),
          ),
          icon: const Icon(Icons.add, color: Colors.white),
        ),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SavedSurveysScreen(),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(Icons.folder_open, color: AppColors.primary, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'المعاينات الحالية',
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.onSurface,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'عرض جميع المعاينات المحفوظة سابقاً',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.arrow_forward_ios, color: AppColors.primary, size: 18),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'ملخص سريع للمشروع الحالي',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'يمكن للمشرف أو الفني استخدام هذه الأداة لتجميع كل تفاصيل المشروع (غرف، أدوار، ستائر، تكييف، إضاءة) ثم تحويلها لاحقاً إلى عرض سعر PDF.',
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
                ),
                const SizedBox(height: 16),
                _ProjectHeaderCard(project: project),
                const SizedBox(height: 16),
                _TotalsCard(totals: totals),
                const SizedBox(height: 16),
                _FloorsList(controller: controller),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectHeaderCard extends StatelessWidget {
  const _ProjectHeaderCard({required this.project});

  final SurveyProject project;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeDecorations.cardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.home_work_outlined, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  project.name,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _projectTypeToLabel(project.type),
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  _techLabel(project),
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11),
                ),
                if (project.customerName != null || project.customerEmail != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    'العميل: ${project.customerName ?? ''}${project.customerEmail != null ? ' (${project.customerEmail})' : ''}',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _projectTypeToLabel(ProjectType type) {
    switch (type) {
      case ProjectType.apartment:
        return 'شقة سكنية';
      case ProjectType.duplex:
        return 'دوبلكس';
      case ProjectType.villa:
        return 'فيلا';
      case ProjectType.office:
        return 'مكتب إداري';
    }
  }

  static String _techLabel(SurveyProject p) {
    final bus = p.busType == BusType.wifi ? 'Wifi' : 'Zigbee';
    final sw = p.switchSystem == SwitchSystem.switchStandard ? 'Switch' : 'Mini Switch';
    return 'نظام: $bus • مفاتيح: $sw';
  }
}

class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.totals});

  final SurveyTotals totals;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppThemeDecorations.cardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'إجمالي الأجهزة التقديرية',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _totalItem(
                context,
                icon: Icons.lightbulb_outline,
                label: 'خطوط إضاءة (Magic Box)',
                value: totals.magicBoxLines,
                color: Colors.amber,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _totalItem(
                context,
                icon: Icons.curtains_outlined,
                label: 'مواتير ستائر',
                value: totals.curtainMotors,
                color: Colors.purple,
              ),
              const SizedBox(width: 12),
              _totalItem(
                context,
                icon: Icons.view_agenda_outlined,
                label: 'ضلف ستائر',
                value: totals.curtainPanels,
                color: Colors.blueGrey,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _totalItem(
                context,
                icon: Icons.settings_remote,
                label: 'وحدات تحكم IR (تكييف/تلفزيون)',
                value: totals.irControllers,
                color: Colors.green,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _totalItem(
                context,
                icon: Icons.toggle_on,
                label: 'مفاتيح 1 خط',
                value: totals.switches1Line,
                color: Colors.lightBlue,
              ),
              const SizedBox(width: 12),
              _totalItem(
                context,
                icon: Icons.toggle_on,
                label: 'مفاتيح 2 خط',
                value: totals.switches2Line,
                color: Colors.teal,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _totalItem(
                context,
                icon: Icons.toggle_on,
                label: 'مفاتيح 3 خطوط',
                value: totals.switches3Line,
                color: Colors.deepOrange,
              ),
              const SizedBox(width: 12),
              _totalItem(
                context,
                icon: Icons.toggle_on,
                label: 'مفاتيح 4 خطوط',
                value: totals.switches4Line,
                color: Colors.pink,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _totalItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required int value,
    required Color color,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
                ),
                Text(
                  '$value',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FloorsList extends StatelessWidget {
  const _FloorsList({required this.controller});

  final SurveyController controller;

  @override
  Widget build(BuildContext context) {
    final floors = controller.floors;
    if (floors.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppThemeDecorations.cardColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(
          'لا توجد أدوار أو غرف مضافة بعد.\nاضغط على زر "بدء معاينة جديدة" لإضافة الأدوار والغرف وتكوين المشروع.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13),
        ),
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'الأدوار والغرف',
          style: TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        ...floors.map(
          (f) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: AppThemeDecorations.cardColor(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: ExpansionTile(
              title: Text(
                f.name,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              subtitle: Text(
                '${f.rooms.length} غرفة',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
              ),
              children: f.rooms
                  .map(
                    (r) => ListTile(
                      title: Text(
                        r.name,
                        style: TextStyle(color: scheme.onSurface),
                      ),
                      subtitle: Text(
                        _roomSubtitle(r),
                        style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }

  String _roomSubtitle(SurveyRoom r) {
    final parts = <String>[];
    if (r.hasLighting) parts.add('إضاءة ذكية');
    if (r.hasCurtain) parts.add('ستائر ${r.curtainKind == CurtainKind.double ? 'مزدوجة' : 'مفردة'}');
    if (r.hasAcIr) parts.add('تحكم تكييف');
    if (r.hasTvIr) parts.add('تحكم تلفزيون');
    return parts.isEmpty ? 'بدون تجهيزات ذكية' : parts.join(' • ');
  }
}

