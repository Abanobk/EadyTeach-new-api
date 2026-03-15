import 'package:flutter/material.dart';

import '../../../services/api_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_theme.dart';

class SurveyEditScreen extends StatefulWidget {
  const SurveyEditScreen({super.key, required this.survey});

  final Map<String, dynamic> survey;

  @override
  State<SurveyEditScreen> createState() => _SurveyEditScreenState();
}

class _SurveyEditScreenState extends State<SurveyEditScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  late final TextEditingController _projectNameCtrl;
  late final TextEditingController _clientEmailCtrl;
  late final TextEditingController _lightingLinesCtrl;
  late final TextEditingController _acUnitsCtrl;
  late final TextEditingController _tvUnitsCtrl;
  late final TextEditingController _curtainsCtrl;
  late final TextEditingController _curtainMetersCtrl;
  late final TextEditingController _notesCtrl;

  // Switch groups
  late final TextEditingController _sw1Ctrl;
  late final TextEditingController _sw2Ctrl;
  late final TextEditingController _sw3Ctrl;
  late final TextEditingController _sw4Ctrl;

  // Sensors
  late final TextEditingController _motionCtrl;
  late final TextEditingController _waterLeakCtrl;
  late final TextEditingController _gasCtrl;
  late final TextEditingController _tempCtrl;
  late final TextEditingController _smartValvesCtrl;

  @override
  void initState() {
    super.initState();
    final s = widget.survey;
    _projectNameCtrl = TextEditingController(text: s['projectName']?.toString() ?? '');
    _clientEmailCtrl = TextEditingController(text: s['clientEmail']?.toString() ?? '');
    _lightingLinesCtrl = TextEditingController(text: '${s['lightingLines'] ?? 0}');
    _acUnitsCtrl = TextEditingController(text: '${s['acUnits'] ?? 0}');
    _tvUnitsCtrl = TextEditingController(text: '${s['tvUnits'] ?? 0}');
    _curtainsCtrl = TextEditingController(text: '${s['curtains'] ?? 0}');
    _curtainMetersCtrl = TextEditingController(text: '${(s['curtainMeters'] ?? 0.0)}');
    _notesCtrl = TextEditingController(text: s['notes']?.toString() ?? '');

    final sw = s['switchGroups'] is Map ? s['switchGroups'] as Map : {};
    _sw1Ctrl = TextEditingController(text: '${sw['switches1Line'] ?? 0}');
    _sw2Ctrl = TextEditingController(text: '${sw['switches2Line'] ?? 0}');
    _sw3Ctrl = TextEditingController(text: '${sw['switches3Line'] ?? 0}');
    _sw4Ctrl = TextEditingController(text: '${sw['switches4Line'] ?? 0}');

    final sn = s['sensors'] is Map ? s['sensors'] as Map : {};
    _motionCtrl = TextEditingController(text: '${sn['motion'] ?? 0}');
    _waterLeakCtrl = TextEditingController(text: '${sn['waterLeak'] ?? 0}');
    _gasCtrl = TextEditingController(text: '${sn['gas'] ?? 0}');
    _tempCtrl = TextEditingController(text: '${sn['temperature'] ?? 0}');
    _smartValvesCtrl = TextEditingController(text: '${sn['smartValves'] ?? 0}');
  }

  @override
  void dispose() {
    _projectNameCtrl.dispose();
    _clientEmailCtrl.dispose();
    _lightingLinesCtrl.dispose();
    _acUnitsCtrl.dispose();
    _tvUnitsCtrl.dispose();
    _curtainsCtrl.dispose();
    _curtainMetersCtrl.dispose();
    _notesCtrl.dispose();
    _sw1Ctrl.dispose();
    _sw2Ctrl.dispose();
    _sw3Ctrl.dispose();
    _sw4Ctrl.dispose();
    _motionCtrl.dispose();
    _waterLeakCtrl.dispose();
    _gasCtrl.dispose();
    _tempCtrl.dispose();
    _smartValvesCtrl.dispose();
    super.dispose();
  }

  int _int(TextEditingController c) => int.tryParse(c.text) ?? 0;
  double _double(TextEditingController c) => double.tryParse(c.text) ?? 0.0;

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      final payload = {
        'id': widget.survey['id'],
        'projectName': _projectNameCtrl.text.trim(),
        'clientId': widget.survey['clientId'],
        'clientEmail': _clientEmailCtrl.text.trim().isNotEmpty ? _clientEmailCtrl.text.trim() : null,
        'floors': widget.survey['floors'],
        'rooms': widget.survey['rooms'],
        'lightingLines': _int(_lightingLinesCtrl),
        'switchGroups': {
          'switches1Line': _int(_sw1Ctrl),
          'switches2Line': _int(_sw2Ctrl),
          'switches3Line': _int(_sw3Ctrl),
          'switches4Line': _int(_sw4Ctrl),
        },
        'acUnits': _int(_acUnitsCtrl),
        'tvUnits': _int(_tvUnitsCtrl),
        'curtains': _int(_curtainsCtrl),
        'curtainMeters': _double(_curtainMetersCtrl),
        'sensors': {
          'motion': _int(_motionCtrl),
          'waterLeak': _int(_waterLeakCtrl),
          'gas': _int(_gasCtrl),
          'temperature': _int(_tempCtrl),
          'smartValves': _int(_smartValvesCtrl),
        },
        'notes': _notesCtrl.text.trim().isNotEmpty ? _notesCtrl.text.trim() : null,
      };

      await ApiService.mutate('surveys.update', input: payload);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تحديث المعاينة بنجاح'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل التحديث: $e'), backgroundColor: Colors.red),
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
      child: Scaffold(
        backgroundColor: AppThemeDecorations.pageBackground(context),
        appBar: AppBar(
          backgroundColor: AppThemeDecorations.cardColor(context),
          title: const Text('تعديل المعاينة', style: TextStyle(color: AppColors.text, fontSize: 16)),
          iconTheme: const IconThemeData(color: AppColors.primary),
          actions: [
            _saving
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(
                    icon: const Icon(Icons.check),
                    color: Colors.green,
                    tooltip: 'حفظ',
                    onPressed: _save,
                  ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionCard(
                  title: 'بيانات المشروع',
                  icon: Icons.home_work_outlined,
                  children: [
                    _field('اسم المشروع', _projectNameCtrl, required: true),
                    _field('إيميل العميل', _clientEmailCtrl),
                  ],
                ),
                const SizedBox(height: 12),

                _SectionCard(
                  title: 'الإضاءة',
                  icon: Icons.lightbulb_outline,
                  children: [
                    _numField('إجمالي خطوط الإضاءة', _lightingLinesCtrl),
                    _numField('مفاتيح 1 خط', _sw1Ctrl),
                    _numField('مفاتيح 2 خط', _sw2Ctrl),
                    _numField('مفاتيح 3 خطوط', _sw3Ctrl),
                    _numField('مفاتيح 4 خطوط', _sw4Ctrl),
                  ],
                ),
                const SizedBox(height: 12),

                _SectionCard(
                  title: 'IR Controllers',
                  icon: Icons.settings_remote,
                  children: [
                    _numField('وحدات تكييف', _acUnitsCtrl),
                    _numField('وحدات شاشات', _tvUnitsCtrl),
                  ],
                ),
                const SizedBox(height: 12),

                _SectionCard(
                  title: 'الستائر',
                  icon: Icons.curtains_outlined,
                  children: [
                    _numField('عدد الستائر', _curtainsCtrl),
                    _numField('إجمالي الأمتار', _curtainMetersCtrl, decimal: true),
                  ],
                ),
                const SizedBox(height: 12),

                _SectionCard(
                  title: 'Sensors',
                  icon: Icons.sensors,
                  children: [
                    _numField('Motion Sensor', _motionCtrl),
                    _numField('Water Leak Sensor', _waterLeakCtrl),
                    _numField('Gas Sensor', _gasCtrl),
                    _numField('Temperature Sensor', _tempCtrl),
                    _numField('Smart Valve', _smartValvesCtrl),
                  ],
                ),
                const SizedBox(height: 12),

                _SectionCard(
                  title: 'ملاحظات',
                  icon: Icons.notes,
                  children: [
                    TextFormField(
                      controller: _notesCtrl,
                      maxLines: 3,
                      style: const TextStyle(color: AppColors.text, fontSize: 14),
                      decoration: _inputDecor('ملاحظات إضافية'),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save),
                    label: Text(_saving ? 'جاري الحفظ...' : 'حفظ التعديلات'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        style: const TextStyle(color: AppColors.text, fontSize: 14),
        decoration: _inputDecor(label),
        validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'مطلوب' : null : null,
      ),
    );
  }

  Widget _numField(String label, TextEditingController ctrl, {bool decimal = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: ctrl,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        style: const TextStyle(color: AppColors.text, fontSize: 14),
        decoration: _inputDecor(label),
      ),
    );
  }

  InputDecoration _inputDecor(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: AppColors.muted, fontSize: 13),
      filled: true,
      fillColor: AppThemeDecorations.pageBackground(context),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.primary)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.icon, required this.children});

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
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
            child: Column(children: children),
          ),
        ],
      ),
    );
  }
}
