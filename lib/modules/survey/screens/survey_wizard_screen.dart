import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../services/api_service.dart';
import '../../../theme/app_theme.dart';
import '../../../utils/app_theme.dart';
import '../controllers/survey_controller.dart';
import '../models/survey_models.dart';
import 'widgets/sensor_row.dart';

/// معالج خطوة بخطوة لإعداد المشروع (Smart Survey Wizard)
class SurveyWizardScreen extends StatefulWidget {
  const SurveyWizardScreen({super.key});

  @override
  State<SurveyWizardScreen> createState() => _SurveyWizardScreenState();
}

class _SurveyWizardScreenState extends State<SurveyWizardScreen> {
  int _step = 0;
  bool _saving = false;

  final _projectNameCtrl = TextEditingController();
  final _customerNameCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  ProjectType _projectType = ProjectType.apartment;
  BusType _busType = BusType.wifi;
  SwitchSystem _switchSystem = SwitchSystem.switchStandard;
  // العملاء
  List<dynamic> _customers = [];
  bool _loadingCustomers = false;
  bool _customersLoadAttempted = false;
  Map<String, dynamic>? _selectedCustomer;

  final _floorNameCtrl = TextEditingController();

  final _roomNameCtrl = TextEditingController();
  RoomType _roomType = RoomType.bedroom;
  // إعدادات علب الـ Magic Box لكل غرفة (قائمة من العناصر)
  // القيمة المخزنة تمثل نوع العلبة:
  // 1..4  => عدد الخطوط (1–4)
  // 101   => ستارة خط واحد (يُحسب كخط واحد)
  // 102   => ستارة خطين (يُحسب كخطين)
  final List<int> _magicBoxTypes = [1];
  bool _roomHasLighting = true;
  bool _roomHasCurtain = false;
  CurtainKind _roomCurtainKind = CurtainKind.single;
  CurtainShape _roomCurtainShape = CurtainShape.straight;
  CurtainDirection _roomCurtainDirection = CurtainDirection.center;
  // IR devices (counts)
  final _acCountCtrl = TextEditingController();
  final _tvCountCtrl = TextEditingController();
  // Sensors
  bool _sensorMotion = false;
  final _motionQtyCtrl = TextEditingController();
  bool _sensorWater = false;
  final _waterQtyCtrl = TextEditingController();
  bool _sensorGas = false;
  final _gasQtyCtrl = TextEditingController();
  bool _sensorTemp = false;
  final _tempQtyCtrl = TextEditingController();
  bool _sensorValve = false;
  final _valveQtyCtrl = TextEditingController();
  final _roomNotesCtrl = TextEditingController();
  final _curtainLengthCtrl = TextEditingController();

  SurveyFloor? _selectedFloor;

  @override
  void dispose() {
    _projectNameCtrl.dispose();
    _customerNameCtrl.dispose();
    _notesCtrl.dispose();
    _floorNameCtrl.dispose();
    _roomNameCtrl.dispose();
    _acCountCtrl.dispose();
    _tvCountCtrl.dispose();
    _motionQtyCtrl.dispose();
    _waterQtyCtrl.dispose();
    _gasQtyCtrl.dispose();
    _tempQtyCtrl.dispose();
    _valveQtyCtrl.dispose();
    _roomNotesCtrl.dispose();
    _curtainLengthCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<SurveyController>();
    final totals = controller.calculateTotals();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppThemeDecorations.pageBackground(context),
        appBar: AppBar(
          backgroundColor: AppThemeDecorations.cardColor(context),
          title: const Text(
            'إعداد المعاينة - Smart Survey',
            style: TextStyle(color: AppColors.text),
          ),
          iconTheme: const IconThemeData(color: AppColors.primary),
        ),
        bottomNavigationBar: _buildBottomBar(controller),
        body: SafeArea(
          child: Stepper(
            type: StepperType.horizontal,
            currentStep: _step,
            controlsBuilder: (_, __) => const SizedBox.shrink(),
            steps: [
              Step(
                title: const Text('المشروع', style: TextStyle(fontSize: 11)),
                isActive: _step == 0,
                content: _buildProjectStep(controller),
              ),
              Step(
                title: const Text('الأدوار', style: TextStyle(fontSize: 11)),
                isActive: _step == 1,
                content: _buildFloorsStep(controller),
              ),
              Step(
                title: const Text('الغرف', style: TextStyle(fontSize: 11)),
                isActive: _step == 2,
                content: _buildRoomsStep(controller),
              ),
              Step(
                title: const Text('الملخص', style: TextStyle(fontSize: 11)),
                isActive: _step == 3,
                content: _buildSummaryStep(controller, totals),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(SurveyController controller) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppThemeDecorations.cardColor(context),
        border: const Border(
          top: BorderSide(color: AppColors.border),
        ),
      ),
      child: Row(
        children: [
          if (_step > 0)
            TextButton.icon(
              onPressed: () => setState(() => _step -= 1),
              icon: const Icon(Icons.arrow_back_ios, size: 14, color: AppColors.muted),
              label: const Text('السابق', style: TextStyle(color: AppColors.muted)),
            ),
          const Spacer(),
          if (_step < 3)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                if (_step == 0) {
                  _saveProjectMeta(controller);
                  // في حالة الشقة: لا نسأل عن الأدوار، ننشئ دور افتراضي ونقفز مباشرة إلى الغرف
                  if (_projectType == ProjectType.apartment) {
                    if (controller.floors.isEmpty) {
                      controller.addFloor('الدور الرئيسي');
                    }
                    setState(() => _step = 2);
                    return;
                  }
                }
                if (_step == 1 && controller.floors.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('من فضلك أضف على الأقل دوراً واحداً')),
                  );
                  return;
                }
                setState(() => _step += 1);
              },
              icon: const Icon(Icons.arrow_forward_ios, size: 14),
              label: const Text('التالي'),
            )
          else
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              onPressed: _saving ? null : _finishSurvey,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(_saving ? 'جاري الحفظ...' : 'إنهاء المعاينة'),
            ),
        ],
      ),
    );
  }

  Widget _buildProjectStep(SurveyController controller) {
    final project = controller.project;
    _projectNameCtrl.text = project.name;
    _projectType = project.type;
    _busType = project.busType;
    _switchSystem = project.switchSystem;

    // تحميل العملاء مرة واحدة
    if (!_customersLoadAttempted && !_loadingCustomers) {
      _loadCustomers();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'بيانات المشروع الأساسية',
          style: TextStyle(
            color: AppColors.text,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _projectNameCtrl,
          decoration: const InputDecoration(
            labelText: 'اسم المشروع',
            hintText: 'مثال: شقة العميل / فيلا التجمع',
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<ProjectType>(
          value: _projectType,
          decoration: const InputDecoration(labelText: 'نوع المشروع'),
          items: const [
            DropdownMenuItem(
              value: ProjectType.apartment,
              child: Text('شقة سكنية'),
            ),
            DropdownMenuItem(
              value: ProjectType.duplex,
              child: Text('دوبلكس'),
            ),
            DropdownMenuItem(
              value: ProjectType.villa,
              child: Text('فيلا'),
            ),
            DropdownMenuItem(
              value: ProjectType.office,
              child: Text('مكتب إداري'),
            ),
          ],
          onChanged: (v) => setState(() => _projectType = v ?? _projectType),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<BusType>(
          value: _busType,
          decoration: const InputDecoration(labelText: 'نظام الاتصال (Wifi / Zigbee)'),
          items: const [
            DropdownMenuItem(
              value: BusType.wifi,
              child: Text('Wifi'),
            ),
            DropdownMenuItem(
              value: BusType.zigbee,
              child: Text('Zigbee'),
            ),
          ],
          onChanged: (v) => setState(() => _busType = v ?? _busType),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<SwitchSystem>(
          value: _switchSystem,
          decoration: const InputDecoration(labelText: 'نوع المفاتيح (Switch / Mini Switch)'),
          items: const [
            DropdownMenuItem(
              value: SwitchSystem.switchStandard,
              child: Text('Switch'),
            ),
            DropdownMenuItem(
              value: SwitchSystem.miniSwitch,
              child: Text('Mini Switch'),
            ),
          ],
          onChanged: (v) => setState(() => _switchSystem = v ?? _switchSystem),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _customerNameCtrl,
          decoration: const InputDecoration(
            labelText: 'اسم العميل (اختياري)',
          ),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<Map<String, dynamic>>(
          value: _selectedCustomer,
          decoration: InputDecoration(
            labelText: 'اختر عميل من القائمة (اختياري)',
            helperText: _loadingCustomers
                ? 'جاري تحميل العملاء...'
                : (_customersLoadAttempted && _customers.isEmpty)
                    ? 'لم يتم العثور على عملاء'
                    : null,
            helperStyle: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
          items: _customers.map(
            (c) => DropdownMenuItem<Map<String, dynamic>>(
              value: c,
              child: Text(
                '${c['name'] ?? 'عميل بدون اسم'}',
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ).toList(),
          onChanged: _loadingCustomers
              ? null
              : (v) {
                  setState(() {
                    _selectedCustomer = v;
                    if (v != null && _customerNameCtrl.text.isEmpty) {
                      _customerNameCtrl.text = (v['name'] ?? '').toString();
                    }
                  });
                },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _notesCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'ملاحظات عامة حول المشروع (اختياري)',
          ),
        ),
      ],
    );
  }

  Widget _buildFloorsStep(SurveyController controller) {
    final floors = controller.floors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'إضافة الأدوار (طابق أرضي، أول، ثاني... إلخ)',
          style: TextStyle(
            color: AppColors.text,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _floorNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'اسم الدور',
                  hintText: 'مثال: أرضي، أول علوي...',
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                controller.addFloor(_floorNameCtrl.text.trim());
                _floorNameCtrl.clear();
              },
              child: const Text('إضافة'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (floors.isEmpty)
          const Text(
            'لم يتم إضافة أي دور بعد.',
            style: TextStyle(color: AppColors.muted),
          )
        else
          Column(
            children: floors
                .map(
                  (f) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      f.name,
                      style: const TextStyle(color: AppColors.text),
                    ),
                    subtitle: Text(
                      '${f.rooms.length} غرفة',
                      style: const TextStyle(color: AppColors.muted, fontSize: 12),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                      onPressed: () => controller.removeFloor(f),
                    ),
                  ),
                )
                .toList(),
          ),
      ],
    );
  }

  Widget _buildRoomsStep(SurveyController controller) {
    final floors = controller.floors;
    if (floors.isEmpty) {
      return const Text(
        'من فضلك أضف على الأقل دوراً واحداً أولاً في الخطوة السابقة.',
        style: TextStyle(color: AppColors.muted),
      );
    }

    if (_selectedFloor == null || !floors.contains(_selectedFloor)) {
      _selectedFloor = floors.first;
    }
    final selectedFloor = _selectedFloor!;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'إضافة غرف لكل دور',
            style: TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: AppThemeDecorations.cardColor(context),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<SurveyFloor>(
                    value: selectedFloor,
                    decoration: const InputDecoration(labelText: 'اختر الدور الذي ستضيف عليه الغرفة'),
                    items: floors
                        .map(
                          (f) => DropdownMenuItem(
                            value: f,
                            child: Text(f.name),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _selectedFloor = v);
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'سيتم إضافة الغرفة على الدور: ${selectedFloor.name}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _roomNameCtrl,
                    decoration: const InputDecoration(
                      labelText: 'اسم الغرفة (اختياري، سيتم التسمية تلقائياً لو تركته فارغاً)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<RoomType>(
                    value: _roomType,
                    decoration: const InputDecoration(labelText: 'نوع الغرفة'),
                    items: const [
                      DropdownMenuItem(value: RoomType.bedroom, child: Text('غرفة نوم')),
                      DropdownMenuItem(value: RoomType.masterBedroom, child: Text('ماستر')),
                      DropdownMenuItem(value: RoomType.kidsRoom, child: Text('أطفال')),
                      DropdownMenuItem(value: RoomType.reception, child: Text('ريسيبشن')),
                      DropdownMenuItem(value: RoomType.livingRoom, child: Text('معيشة')),
                      DropdownMenuItem(value: RoomType.hall, child: Text('طرقة')),
                      DropdownMenuItem(value: RoomType.kitchen, child: Text('مطبخ')),
                      DropdownMenuItem(value: RoomType.bathroom, child: Text('حمام')),
                      DropdownMenuItem(value: RoomType.outdoor, child: Text('خارجي / حديقة')),
                    ],
                    onChanged: (v) => setState(() => _roomType = v ?? _roomType),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Lighting section
          Card(
            color: AppThemeDecorations.cardColor(context),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ExpansionTile(
              initiallyExpanded: true,
              leading: const Icon(Icons.lightbulb_outline, color: AppColors.primary),
              title: const Text(
                'Lighting Control',
                style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                SwitchListTile(
                  title: const Text('إضاءة ذكية (Magic Box)'),
                  value: _roomHasLighting,
                  onChanged: (v) => setState(() => _roomHasLighting = v),
                ),
                if (_roomHasLighting) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'علب Magic Box في هذه الغرفة',
                    style: TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Column(
                    children: [
                      for (int i = 0; i < _magicBoxTypes.length; i++)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              const Text(
                                'علبة Magic',
                                style: TextStyle(color: AppColors.text, fontSize: 13),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButtonFormField<int>(
                                  value: _magicBoxTypes[i],
                                  decoration: const InputDecoration(
                                    labelText: 'اختيار نوع العلبة',
                                  ),
                                  items: const [
                                    DropdownMenuItem(value: 1, child: Text('خط واحد')),
                                    DropdownMenuItem(value: 2, child: Text('خطين')),
                                    DropdownMenuItem(value: 3, child: Text('3 خطوط')),
                                    DropdownMenuItem(value: 4, child: Text('4 خطوط')),
                                    DropdownMenuItem(value: 101, child: Text('ستارة خط واحد')),
                                    DropdownMenuItem(value: 102, child: Text('ستارة ٢ خط')),
                                  ],
                                  onChanged: (v) {
                                    if (v == null) return;
                                    setState(() {
                                      _magicBoxTypes[i] = v;
                                    });
                                  },
                                ),
                              ),
                              if (_magicBoxTypes.length > 1)
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline, color: Colors.redAccent),
                                  onPressed: () {
                                    setState(() {
                                      _magicBoxTypes.removeAt(i);
                                    });
                                  },
                                ),
                            ],
                          ),
                        ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() {
                              _magicBoxTypes.add(1);
                            });
                          },
                          icon: const Icon(Icons.add_circle_outline),
                          label: const Text('إضافة علبة Magic أخرى'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          // IR Devices section
          Card(
            color: AppThemeDecorations.cardColor(context),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.settings_remote, color: AppColors.primary),
                      SizedBox(width: 8),
                      Text(
                        'IR Devices',
                        style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'يتم احتساب وحدة IR واحدة للغرفة عند وجود تكييف أو تلفزيون.',
                    style: TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _acCountCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'AC Count',
                            hintText: 'عدد وحدات التكييف',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _tvCountCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'TV Count',
                            hintText: 'عدد الشاشات',
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Curtains section
          Card(
            color: AppThemeDecorations.cardColor(context),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ExpansionTile(
              leading: const Icon(Icons.curtains, color: AppColors.primary),
              title: const Text(
                'Curtains',
                style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600),
              ),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                SwitchListTile(
                  title: const Text('ستائر كهرباء'),
                  value: _roomHasCurtain,
                  onChanged: (v) => setState(() => _roomHasCurtain = v),
                ),
                if (_roomHasCurtain) ...[
                  DropdownButtonFormField<CurtainKind>(
                    value: _roomCurtainKind,
                    decoration: const InputDecoration(labelText: 'عدد الضلف'),
                    items: const [
                      DropdownMenuItem(value: CurtainKind.single, child: Text('ستارة واحدة')),
                      DropdownMenuItem(value: CurtainKind.double, child: Text('ستارتين')),
                    ],
                    onChanged: (v) => setState(() => _roomCurtainKind = v ?? _roomCurtainKind),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'اتجاه فتح الستارة',
                    style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('يسار'),
                        selected: _roomCurtainDirection == CurtainDirection.left,
                        onSelected: (_) => setState(() => _roomCurtainDirection = CurtainDirection.left),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('منتصف'),
                        selected: _roomCurtainDirection == CurtainDirection.center,
                        onSelected: (_) => setState(() => _roomCurtainDirection = CurtainDirection.center),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('يمين'),
                        selected: _roomCurtainDirection == CurtainDirection.right,
                        onSelected: (_) => setState(() => _roomCurtainDirection = CurtainDirection.right),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Wheel (مسار الستارة)',
                    style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      ChoiceChip(
                        label: const Text('Normal'),
                        selected: _roomCurtainShape == CurtainShape.straight,
                        onSelected: (_) => setState(() => _roomCurtainShape = CurtainShape.straight),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text('Wave'),
                        selected: _roomCurtainShape == CurtainShape.wave,
                        onSelected: (_) => setState(() => _roomCurtainShape = CurtainShape.wave),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _curtainLengthCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'طول الستارة بالسنتيمتر',
                      hintText: 'مثال: 260',
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Sensors section
          Card(
            color: AppThemeDecorations.cardColor(context),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.sensors, color: AppColors.primary),
                      SizedBox(width: 8),
                      Text(
                        'Sensors',
                        style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SensorRow(
                    label: 'Motion Sensor',
                    selected: _sensorMotion,
                    onChanged: (v) {
                      setState(() {
                        _sensorMotion = v;
                        if (_sensorMotion && _motionQtyCtrl.text.isEmpty) {
                          _motionQtyCtrl.text = '1';
                        }
                        if (!_sensorMotion) _motionQtyCtrl.clear();
                      });
                    },
                    controller: _motionQtyCtrl,
                  ),
                  SensorRow(
                    label: 'Water Leak Sensor',
                    selected: _sensorWater,
                    onChanged: (v) {
                      setState(() {
                        _sensorWater = v;
                        if (_sensorWater && _waterQtyCtrl.text.isEmpty) {
                          _waterQtyCtrl.text = '1';
                        }
                        if (!_sensorWater) _waterQtyCtrl.clear();
                      });
                    },
                    controller: _waterQtyCtrl,
                  ),
                  SensorRow(
                    label: 'Gas Sensor',
                    selected: _sensorGas,
                    onChanged: (v) {
                      setState(() {
                        _sensorGas = v;
                        if (_sensorGas && _gasQtyCtrl.text.isEmpty) {
                          _gasQtyCtrl.text = '1';
                        }
                        if (!_sensorGas) _gasQtyCtrl.clear();
                      });
                    },
                    controller: _gasQtyCtrl,
                  ),
                  SensorRow(
                    label: 'Temperature Sensor',
                    selected: _sensorTemp,
                    onChanged: (v) {
                      setState(() {
                        _sensorTemp = v;
                        if (_sensorTemp && _tempQtyCtrl.text.isEmpty) {
                          _tempQtyCtrl.text = '1';
                        }
                        if (!_sensorTemp) _tempQtyCtrl.clear();
                      });
                    },
                    controller: _tempQtyCtrl,
                  ),
                  SensorRow(
                    label: 'Smart Valve',
                    selected: _sensorValve,
                    onChanged: (v) {
                      setState(() {
                        _sensorValve = v;
                        if (_sensorValve && _valveQtyCtrl.text.isEmpty) {
                          _valveQtyCtrl.text = '1';
                        }
                        if (!_sensorValve) _valveQtyCtrl.clear();
                      });
                    },
                    controller: _valveQtyCtrl,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Notes + Add button
          Card(
            color: AppThemeDecorations.cardColor(context),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: _roomNotesCtrl,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظات الغرفة (اختياري)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        int magicBoxesCount = 0;
                        int magicLinesManual = 0;
                        int switches1 = 0;
                        int switches2 = 0;
                        int switches3 = 0;
                        int switches4 = 0;
                        int curtainSw1 = 0;
                        int curtainSw2 = 0;
                        if (_roomHasLighting) {
                          magicBoxesCount = _magicBoxTypes.length;
                          for (final t in _magicBoxTypes) {
                            switch (t) {
                              case 1:
                              case 2:
                              case 3:
                              case 4:
                                magicLinesManual += t;
                                if (t == 1) switches1++;
                                if (t == 2) switches2++;
                                if (t == 3) switches3++;
                                if (t == 4) switches4++;
                                break;
                              case 101: // ستارة خط واحد
                                magicLinesManual += 1;
                                switches1++;
                                curtainSw1++;
                                break;
                              case 102: // ستارة خطين
                                magicLinesManual += 2;
                                switches2++;
                                curtainSw2++;
                                break;
                            }
                          }
                        }
                        final curtainLengthParsed =
                            double.tryParse(_curtainLengthCtrl.text.replaceAll(',', '.'));
                        final curtainLengthCm =
                            (curtainLengthParsed != null && curtainLengthParsed > 0) ? curtainLengthParsed : null;
                        double? curtainLengthApproxM;
                        if (curtainLengthCm != null) {
                          final lengthM = curtainLengthCm / 100.0;
                          final base = lengthM.floorToDouble();
                          final frac = lengthM - base;
                          if (frac == 0) {
                            curtainLengthApproxM = lengthM;
                          } else if (frac <= 0.5) {
                            curtainLengthApproxM = base + 0.5;
                          } else {
                            curtainLengthApproxM = base + 1.0;
                          }
                        }
                        final acCount = int.tryParse(_acCountCtrl.text.trim()) ?? 0;
                        final tvCount = int.tryParse(_tvCountCtrl.text.trim()) ?? 0;
                        final hasAcIr = acCount > 0;
                        final hasTvIr = tvCount > 0;

                        int parseSensorQty(bool selected, TextEditingController c) {
                          if (!selected) return 0;
                          final v = int.tryParse(c.text.trim());
                          return (v != null && v > 0) ? v : 1;
                        }

                        final motionQty = parseSensorQty(_sensorMotion, _motionQtyCtrl);
                        final waterQty = parseSensorQty(_sensorWater, _waterQtyCtrl);
                        final gasQty = parseSensorQty(_sensorGas, _gasQtyCtrl);
                        final tempQty = parseSensorQty(_sensorTemp, _tempQtyCtrl);
                        final valveQty = parseSensorQty(_sensorValve, _valveQtyCtrl);

                        controller.addRoom(
                          floor: selectedFloor,
                          name: _roomNameCtrl.text.trim(),
                          type: _roomType,
                          area: null,
                          hasLighting: _roomHasLighting,
                          hasCurtain: _roomHasCurtain,
                          curtainKind: _roomHasCurtain ? _roomCurtainKind : null,
                          curtainShape: _roomHasCurtain ? _roomCurtainShape : null,
                          curtainDirection: _roomHasCurtain ? _roomCurtainDirection : null,
                          hasAcIr: hasAcIr,
                          hasTvIr: hasTvIr,
                          magicBoxesCount: magicBoxesCount,
                          linesPerBox: 0,
                          magicLinesManual: magicLinesManual,
                          curtainLengthCm: curtainLengthCm,
                          curtainLengthApproxM: curtainLengthApproxM,
                          switches1Line: switches1,
                          switches2Line: switches2,
                          switches3Line: switches3,
                          switches4Line: switches4,
                          acUnits: acCount,
                          tvUnits: tvCount,
                          motionSensors: motionQty,
                          waterLeakSensors: waterQty,
                          gasSensors: gasQty,
                          temperatureSensors: tempQty,
                          smartValves: valveQty,
                          curtainSwitch1Ch: curtainSw1,
                          curtainSwitch2Ch: curtainSw2,
                          notes: _roomNotesCtrl.text.trim().isEmpty ? null : _roomNotesCtrl.text.trim(),
                        );
                        _roomNameCtrl.clear();
                        _roomNotesCtrl.clear();
                        _curtainLengthCtrl.clear();
                        _acCountCtrl.clear();
                        _tvCountCtrl.clear();
                        _motionQtyCtrl.clear();
                        _waterQtyCtrl.clear();
                        _gasQtyCtrl.clear();
                        _tempQtyCtrl.clear();
                        _valveQtyCtrl.clear();
                        _sensorMotion = false;
                        _sensorWater = false;
                        _sensorGas = false;
                        _sensorTemp = false;
                        _sensorValve = false;
                        _magicBoxTypes
                          ..clear()
                          ..add(1);
                        setState(() {});
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('إضافة الغرفة'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 8),
          const Text(
            'الغرف المضافة على هذا الدور:',
            style: TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if (selectedFloor.rooms.isEmpty)
            const Text(
              'لم يتم إضافة غرف بعد.',
              style: TextStyle(color: AppColors.muted),
            )
          else
            Column(
              children: selectedFloor.rooms
                  .map(
                    (r) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        r.name,
                        style: const TextStyle(color: AppColors.text),
                      ),
                      subtitle: Text(
                        _roomSummary(r),
                        style: const TextStyle(color: AppColors.muted, fontSize: 12),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                        onPressed: () => controller.removeRoom(selectedFloor, r),
                      ),
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryStep(SurveyController controller, SurveyTotals totals) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ملخص عام للمشروع',
          style: TextStyle(
            color: AppColors.text,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'هذه البيانات يمكن ربطها لاحقاً بباك إند PHP لعمل تسعير تلقائي وربطها بنظام عروض الأسعار الحالي ثم إنتاج ملف PDF.',
          style: const TextStyle(color: AppColors.muted, fontSize: 12),
        ),
        const SizedBox(height: 16),
        _buildTotalsView(totals),
        const SizedBox(height: 16),
        _buildCurtainDetails(controller),
        const SizedBox(height: 16),
        const Text(
          'الأدوار والغرف',
          style: TextStyle(
            color: AppColors.text,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        ...controller.floors.map(
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
                style: const TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              subtitle: Text(
                '${f.rooms.length} غرفة',
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
              children: f.rooms
                  .map(
                    (r) => ListTile(
                      title: Text(
                        r.name,
                        style: const TextStyle(color: AppColors.text),
                      ),
                      subtitle: Text(
                        _roomSummary(r),
                        style: const TextStyle(color: AppColors.muted, fontSize: 12),
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

  /// عرض تفاصيل طول كل ستارة (فعلي + تقريبي) لكل غرفة على حدة
  Widget _buildCurtainDetails(SurveyController controller) {
    final items = <Widget>[];

    for (final floor in controller.floors) {
      for (final room in floor.rooms) {
        if (!room.hasCurtain || room.curtainKind == null || room.curtainLengthCm == null) {
          continue;
        }
        final curtainsInRoom =
            room.curtainKind == CurtainKind.double ? 2 : 1;
        final lengthCm = room.curtainLengthCm!;
        final lengthApproxM = room.curtainLengthApproxM;

        items.add(
          ListTile(
            dense: true,
            leading: const Icon(Icons.curtains, color: AppColors.primary),
            title: Text(
              room.name,
              style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'عدد الستائر في الغرفة: $curtainsInRoom',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
                Text(
                  'الطول الفعلي لكل ستارة: ${lengthCm.toStringAsFixed(0)} سم',
                  style: const TextStyle(color: AppColors.muted, fontSize: 11),
                ),
                if (lengthApproxM != null)
                  Text(
                    'الطول التجاري لكل ستارة: ${lengthApproxM.toStringAsFixed(1)} م',
                    style: const TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
              ],
            ),
          ),
        );
      }
    }

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

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
          const Text(
            'تفاصيل أطوال الستائر (للتصنيع)',
            style: TextStyle(
              color: AppColors.text,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'القائمة التالية توضح طول كل ستارة في كل غرفة (الطول الفعلي + التجاري) ليُستخدم في أمر التصنيع.',
            style: TextStyle(color: AppColors.muted, fontSize: 11),
          ),
          const SizedBox(height: 8),
          ...items,
        ],
      ),
    );
  }

  Widget _buildTotalsView(SurveyTotals totals) {
    return Column(
      children: [
        // Section 1: Lighting Summary
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppThemeDecorations.cardColor(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Lighting Summary',
                style: TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _totalsItem(
                    icon: Icons.lightbulb_outline,
                    label: 'إجمالي خطوط الإضاءة',
                    value: totals.magicBoxLines,
                    color: Colors.amber,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _totalsItem(
                    icon: Icons.toggle_on,
                    label: 'Single Switch (1 Line)',
                    value: totals.switches1Line,
                    color: Colors.lightBlue,
                  ),
                  const SizedBox(width: 12),
                  _totalsItem(
                    icon: Icons.toggle_on,
                    label: 'Double Switch (2 Lines)',
                    value: totals.switches2Line,
                    color: Colors.teal,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _totalsItem(
                    icon: Icons.toggle_on,
                    label: 'Triple Switch (3 Lines)',
                    value: totals.switches3Line,
                    color: Colors.deepOrange,
                  ),
                  const SizedBox(width: 12),
                  _totalsItem(
                    icon: Icons.toggle_on,
                    label: '4-Line Switch',
                    value: totals.switches4Line,
                    color: Colors.pink,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _totalsItem(
                    icon: Icons.curtains,
                    label: 'Curtain Switch 1CH',
                    value: totals.curtainSwitch1Ch,
                    color: Colors.indigo,
                  ),
                  const SizedBox(width: 12),
                  _totalsItem(
                    icon: Icons.curtains,
                    label: 'Curtain Switch 2CH',
                    value: totals.curtainSwitch2Ch,
                    color: Colors.indigoAccent,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Section 2: IR Controllers
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppThemeDecorations.cardColor(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'IR Controllers',
                style: TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _totalsItem(
                    icon: Icons.settings_remote,
                    label: 'Total IR Devices (Rooms with AC/TV)',
                    value: totals.irControllers,
                    color: Colors.green,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Section 3: Curtain System
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppThemeDecorations.cardColor(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Curtain System',
                style: TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _totalsItem(
                    icon: Icons.curtains_outlined,
                    label: 'Total Curtains',
                    value: totals.totalCurtains,
                    color: Colors.purple,
                  ),
                  const SizedBox(width: 12),
                  _totalsItem(
                    icon: Icons.curtains_closed,
                    label: 'Total Curtain Motors',
                    value: totals.curtainMotors,
                    color: Colors.deepPurple,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.indigo.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.straighten, color: Colors.indigo, size: 18),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'إجمالي الطول التجاري للستائر',
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                totals.curtainMeters.toStringAsFixed(1),
                                style: const TextStyle(
                                  color: AppColors.text,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: Colors.blueGrey.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.straighten, color: Colors.blueGrey, size: 18),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Total Curtain Length (actual, cm)',
                                style: TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 11,
                                ),
                              ),
                              Text(
                                totals.curtainCmActual.toStringAsFixed(0),
                                style: const TextStyle(
                                  color: AppColors.text,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Section 4: Sensors
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppThemeDecorations.cardColor(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sensors',
                style: TextStyle(
                  color: AppColors.text,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _totalsItem(
                    icon: Icons.sensors,
                    label: 'Motion Sensors',
                    value: totals.motionSensors,
                    color: Colors.lightBlue,
                  ),
                  const SizedBox(width: 12),
                  _totalsItem(
                    icon: Icons.water_damage_outlined,
                    label: 'Water Leak Sensors',
                    value: totals.waterLeakSensors,
                    color: Colors.cyan,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _totalsItem(
                    icon: Icons.local_fire_department_outlined,
                    label: 'Gas Sensors',
                    value: totals.gasSensors,
                    color: Colors.redAccent,
                  ),
                  const SizedBox(width: 12),
                  _totalsItem(
                    icon: Icons.thermostat,
                    label: 'Temperature Sensors',
                    value: totals.temperatureSensors,
                    color: Colors.orange,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _totalsItem(
                    icon: Icons.settings_input_component,
                    label: 'Smart Valves',
                    value: totals.smartValves,
                    color: Colors.green,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _totalsItem({
    required IconData icon,
    required String label,
    required int value,
    required Color color,
  }) {
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
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                  ),
                ),
                Text(
                  '$value',
                  style: const TextStyle(
                    color: AppColors.text,
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

  Future<void> _finishSurvey() async {
    final controller = context.read<SurveyController>();
    _saveProjectMeta(controller);

    final project = controller.project;
    final totals = controller.calculateTotals();

    int acUnitsTotal = 0;
    int tvUnitsTotal = 0;
    for (final floor in project.floors) {
      for (final room in floor.rooms) {
        acUnitsTotal += room.acUnits;
        tvUnitsTotal += room.tvUnits;
      }
    }

    final floorsJson = project.floors.map((f) {
      return {
        'id': f.id,
        'name': f.name,
        'index': f.index,
        'rooms': f.rooms.map((r) => _roomToJson(r)).toList(),
      };
    }).toList();

    final roomsJson = <Map<String, dynamic>>[];
    for (final floor in project.floors) {
      for (final room in floor.rooms) {
        roomsJson.add(_roomToJson(room)..['floorName'] = floor.name);
      }
    }

    final payload = {
      'projectName': project.name,
      'clientId': project.customerId,
      'clientEmail': project.customerEmail,
      'floors': floorsJson,
      'rooms': roomsJson,
      'lightingLines': totals.magicBoxLines,
      'switchGroups': {
        'switches1Line': totals.switches1Line,
        'switches2Line': totals.switches2Line,
        'switches3Line': totals.switches3Line,
        'switches4Line': totals.switches4Line,
      },
      'acUnits': acUnitsTotal,
      'tvUnits': tvUnitsTotal,
      'curtains': totals.totalCurtains,
      'curtainMeters': totals.curtainMeters,
      'sensors': {
        'motion': totals.motionSensors,
        'waterLeak': totals.waterLeakSensors,
        'gas': totals.gasSensors,
        'temperature': totals.temperatureSensors,
        'smartValves': totals.smartValves,
      },
      'notes': project.notes,
    };

    setState(() => _saving = true);
    try {
      await ApiService.mutate('surveys.create', input: payload);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم حفظ المعاينة بنجاح'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Map<String, dynamic> _roomToJson(SurveyRoom r) {
    return {
      'id': r.id,
      'name': r.name,
      'type': r.type.name,
      'floorIndex': r.floorIndex,
      'area': r.area,
      'hasLighting': r.hasLighting,
      'hasCurtain': r.hasCurtain,
      'curtainKind': r.curtainKind?.name,
      'curtainShape': r.curtainShape?.name,
      'curtainDirection': r.curtainDirection?.name,
      'hasAcIr': r.hasAcIr,
      'hasTvIr': r.hasTvIr,
      'magicBoxesCount': r.magicBoxesCount,
      'linesPerBox': r.linesPerBox,
      'magicLinesManual': r.magicLinesManual,
      'curtainLengthCm': r.curtainLengthCm,
      'curtainLengthApproxM': r.curtainLengthApproxM,
      'switches1Line': r.switches1Line,
      'switches2Line': r.switches2Line,
      'switches3Line': r.switches3Line,
      'switches4Line': r.switches4Line,
      'acUnits': r.acUnits,
      'tvUnits': r.tvUnits,
      'motionSensors': r.motionSensors,
      'waterLeakSensors': r.waterLeakSensors,
      'gasSensors': r.gasSensors,
      'temperatureSensors': r.temperatureSensors,
      'smartValves': r.smartValves,
      'curtainSwitch1Ch': r.curtainSwitch1Ch,
      'curtainSwitch2Ch': r.curtainSwitch2Ch,
      'notes': r.notes,
    };
  }

  void _saveProjectMeta(SurveyController controller) {
    controller.setProjectMeta(
      name: _projectNameCtrl.text.trim().isEmpty ? 'مشروع بدون اسم' : _projectNameCtrl.text.trim(),
      type: _projectType,
      customerName: _customerNameCtrl.text.trim().isEmpty ? null : _customerNameCtrl.text.trim(),
      customerEmail: _selectedCustomer?['email']?.toString(),
      customerId: _selectedCustomer != null && _selectedCustomer!['id'] is int
          ? _selectedCustomer!['id'] as int
          : null,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      busType: _busType,
      switchSystem: _switchSystem,
    );
  }

  Future<void> _loadCustomers() async {
    setState(() => _loadingCustomers = true);
    try {
      final res = await ApiService.query('clients.allUsers');
      final list = res['data'] ?? res ?? [];
      if (list is List) {
        setState(() {
          _customers = list;
          _loadingCustomers = false;
          _customersLoadAttempted = true;
        });
      } else {
        setState(() {
          _loadingCustomers = false;
          _customersLoadAttempted = true;
        });
      }
    } catch (_) {
      setState(() {
        _loadingCustomers = false;
        _customersLoadAttempted = true;
      });
    }
  }

  String _roomSummary(SurveyRoom r) {
    final parts = <String>[];
    // لم نعد نستخدم مساحة الغرفة في هذا الإصدار
    if (r.hasLighting) {
      if (r.magicLinesManual > 0 && r.magicBoxesCount > 0) {
        parts.add('إضاءة: ${r.magicBoxesCount} علبة Magic (إجمالي ${r.magicLinesManual} خط)');
      } else if (r.magicBoxesCount > 0 && r.linesPerBox > 0) {
        parts.add('إضاءة: ${r.magicBoxesCount} Magic Box × ${r.linesPerBox} خط');
      } else {
        parts.add('إضاءة ذكية (تقدير تلقائي)');
      }
    }
    if (r.hasCurtain) {
      parts.add(
        'ستائر ${r.curtainKind == CurtainKind.double ? 'مزدوجة' : 'مفردة'}',
      );
      if (r.curtainLengthCm != null) {
        parts.add('طول فعلي ≈ ${r.curtainLengthCm!.toStringAsFixed(0)} سم');
      }
      if (r.curtainLengthApproxM != null) {
        parts.add('طول للتسعير ≈ ${r.curtainLengthApproxM!.toStringAsFixed(1)} م');
      }
      if (r.curtainDirection != null) {
        final dirLabel = () {
          switch (r.curtainDirection!) {
            case CurtainDirection.left:
              return 'يسار';
            case CurtainDirection.center:
              return 'منتصف';
            case CurtainDirection.right:
              return 'يمين';
          }
        }();
        parts.add('اتجاه: $dirLabel');
      }
    }
    if (r.hasAcIr) parts.add('تحكم تكييف');
    if (r.hasTvIr) parts.add('تحكم تلفزيون');
    return parts.isEmpty ? 'بدون تجهيزات ذكية' : parts.join(' • ');
  }
}

