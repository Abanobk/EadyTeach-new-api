import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../utils/app_theme.dart';

class ServiceRequestScreen extends StatefulWidget {
  const ServiceRequestScreen({super.key});

  @override
  State<ServiceRequestScreen> createState() => _ServiceRequestScreenState();
}

class _ServiceRequestScreenState extends State<ServiceRequestScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Map<String, dynamic> _settings = {};
  bool _loadingSettings = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final res = await ApiService.query('storeSettings.get');
      final data = res['data'] ?? res;
      if (data != null) {
        setState(() => _settings = Map<String, dynamic>.from(data));
      }
    } catch (_) {}
    setState(() => _loadingSettings = false);
  }

  String _s(String key, String fallback) =>
      (_settings[key] as String?)?.isNotEmpty == true
          ? _settings[key] as String
          : fallback;

  List<String> get _serviceTypes {
    final raw = _settings['serviceTypes'];
    if (raw is List && raw.isNotEmpty) return raw.map((e) => e.toString()).toList();
    return [
      'تركيب كاميرات مراقبة',
      'أنظمة الإضاءة الذكية',
      'أنظمة الصوت والفيديو',
      'شبكات الواي فاي',
      'أنظمة الأمان',
      'التحكم في المنزل الذكي',
      'صيانة دورية',
      'استشارة تقنية',
    ];
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tab1Label = _s('tab1Label', 'طلب صيانة');
    final tab2Label = _s('tab2Label', 'طلب تركيب');

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(
          title: const Text('طلب خدمة',
              style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold)),
          backgroundColor: AppColors.card,
          automaticallyImplyLeading: false,
          bottom: TabBar(
            controller: _tabController,
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.muted,
            tabs: [
              Tab(icon: const Icon(Icons.build_outlined), text: tab1Label),
              Tab(icon: const Icon(Icons.home_repair_service_outlined), text: tab2Label),
            ],
          ),
        ),
        body: _loadingSettings
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : TabBarView(
                controller: _tabController,
                children: [
                  _MaintenanceRequestForm(
                    serviceTypes: _serviceTypes,
                    labels: {
                      'tab1Label': _s('tab1Label', 'طلب صيانة'),
                      'tab1Description': _s('tab1Description', 'صيانة أنظمة المنزل الذكي'),
                      'tab1DeviceLabel': _s('tab1DeviceLabel', 'الجهاز / النظام'),
                      'tab1DevicePlaceholder': _s('tab1DevicePlaceholder', 'مثال: كاميرا المدخل'),
                      'tab1IssueLabel': _s('tab1IssueLabel', 'نوع المشكلة'),
                      'tab1DescLabel': _s('tab1DescLabel', 'وصف المشكلة'),
                      'tab1LocationLabel': _s('tab1LocationLabel', 'العنوان / الموقع'),
                      'tab1ButtonLabel': _s('tab1ButtonLabel', 'إرسال طلب الصيانة'),
                    },
                  ),
                  _InstallationRequestForm(
                    serviceTypes: _serviceTypes,
                    labels: {
                      'tab2Label': _s('tab2Label', 'طلب تركيب'),
                      'tab2Description': _s('tab2Description', 'تركيب أنظمة المنزل الذكي'),
                      'tab2ServiceLabel': _s('tab2ServiceLabel', 'نوع الخدمة'),
                      'tab2TitleLabel': _s('tab2TitleLabel', 'عنوان الطلب'),
                      'tab2DescLabel': _s('tab2DescLabel', 'تفاصيل الطلب'),
                      'tab2LocationLabel': _s('tab2LocationLabel', 'الموقع / العنوان'),
                      'tab2BudgetLabel': _s('tab2BudgetLabel', 'الميزانية المتوقعة'),
                      'tab2ButtonLabel': _s('tab2ButtonLabel', 'إرسال الطلب'),
                    },
                  ),
                ],
              ),
      ),
    );
  }
}

// ─── طلب صيانة ───────────────────────────────────────────────────────────────

class _MaintenanceRequestForm extends StatefulWidget {
  final List<String> serviceTypes;
  final Map<String, String> labels;
  const _MaintenanceRequestForm({required this.serviceTypes, required this.labels});

  @override
  State<_MaintenanceRequestForm> createState() => _MaintenanceRequestFormState();
}

class _MaintenanceRequestFormState extends State<_MaintenanceRequestForm> {
  final _formKey = GlobalKey<FormState>();
  final _descController = TextEditingController();
  final _locationController = TextEditingController();
  final _deviceController = TextEditingController();
  String? _selectedIssue;
  bool _loading = false;

  @override
  void dispose() {
    _descController.dispose();
    _locationController.dispose();
    _deviceController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final description = '${widget.labels['tab1DeviceLabel']}: ${_deviceController.text.trim()}\n'
          '${widget.labels['tab1IssueLabel']}: ${_selectedIssue ?? "غير محدد"}\n'
          '${widget.labels['tab1DescLabel']}: ${_descController.text.trim()}';

      await ApiService.mutate(
        'serviceRequests.submit',
        input: {
          'description': description,
          'location': _locationController.text.trim().isEmpty
              ? null
              : _locationController.text.trim(),
          'serviceType': widget.labels['tab1Label'] ?? 'صيانة',
        },
      );

      if (!mounted) return;
      _showSuccess('تم إرسال الطلب بنجاح!\nسيتواصل معك فريقنا قريباً.');
      _formKey.currentState!.reset();
      _descController.clear();
      _locationController.clear();
      _deviceController.clear();
      setState(() => _selectedIssue = null);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ: ${e.toString()}'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSuccess(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 60),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.text, fontSize: 15)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسناً', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.labels;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.build_circle_outlined, color: AppColors.primary, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l['tab1Label'] ?? 'طلب صيانة',
                            style: const TextStyle(color: AppColors.primary,
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 2),
                        Text(l['tab1Description'] ?? 'صيانة أنظمة المنزل الذكي',
                            style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            _buildLabel('${l['tab1DeviceLabel'] ?? 'الجهاز / النظام'} *'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _deviceController,
              style: const TextStyle(color: AppColors.text),
              decoration: _inputDecoration(l['tab1DevicePlaceholder'] ?? 'مثال: كاميرا المدخل'),
              validator: (v) => v == null || v.isEmpty ? 'هذا الحقل مطلوب' : null,
            ),

            const SizedBox(height: 16),

            _buildLabel('${l['tab1IssueLabel'] ?? 'نوع المشكلة'} *'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _selectedIssue,
              dropdownColor: AppColors.card,
              style: const TextStyle(color: AppColors.text),
              decoration: _inputDecoration('اختر...'),
              items: widget.serviceTypes
                  .map((issue) => DropdownMenuItem(value: issue, child: Text(issue)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedIssue = v),
              validator: (v) => v == null ? 'هذا الحقل مطلوب' : null,
            ),

            const SizedBox(height: 16),

            _buildLabel('${l['tab1DescLabel'] ?? 'وصف المشكلة'} *'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _descController,
              style: const TextStyle(color: AppColors.text),
              decoration: _inputDecoration('اشرح بالتفصيل...'),
              maxLines: 4,
              validator: (v) => v == null || v.isEmpty ? 'هذا الحقل مطلوب' : null,
            ),

            const SizedBox(height: 16),

            _buildLabel(l['tab1LocationLabel'] ?? 'العنوان / الموقع'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _locationController,
              style: const TextStyle(color: AppColors.text),
              decoration: _inputDecoration('مثال: القاهرة، مدينة نصر...'),
            ),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading
                    ? const SizedBox(height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : Text(l['tab1ButtonLabel'] ?? 'إرسال طلب الصيانة',
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) => Text(text,
      style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 14));

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.muted),
    filled: true,
    fillColor: AppColors.card,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: AppColors.primary.withOpacity(0.3)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: AppColors.primary.withOpacity(0.2)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.primary),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );
}

// ─── طلب تركيب ───────────────────────────────────────────────────────────────

class _InstallationRequestForm extends StatefulWidget {
  final List<String> serviceTypes;
  final Map<String, String> labels;
  const _InstallationRequestForm({required this.serviceTypes, required this.labels});

  @override
  State<_InstallationRequestForm> createState() => _InstallationRequestFormState();
}

class _InstallationRequestFormState extends State<_InstallationRequestForm> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _locationController = TextEditingController();
  final _budgetController = TextEditingController();
  String? _selectedService;
  bool _loading = false;

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _locationController.dispose();
    _budgetController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);

    try {
      final description = '${widget.labels['tab2ServiceLabel']}: ${_selectedService ?? "غير محدد"}\n'
          '${widget.labels['tab2TitleLabel']}: ${_titleController.text.trim()}\n'
          '${widget.labels['tab2DescLabel']}: ${_descController.text.trim()}\n'
          '${widget.labels['tab2BudgetLabel']}: ${_budgetController.text.trim().isEmpty ? "غير محدد" : _budgetController.text.trim()}';

      await ApiService.mutate(
        'serviceRequests.submit',
        input: {
          'description': description,
          'location': _locationController.text.trim().isEmpty
              ? null
              : _locationController.text.trim(),
          'serviceType': widget.labels['tab2Label'] ?? 'تركيب',
        },
      );

      if (!mounted) return;
      _showSuccess('تم إرسال الطلب بنجاح!\nسيتواصل معك فريقنا قريباً.');
      _formKey.currentState!.reset();
      _titleController.clear();
      _descController.clear();
      _locationController.clear();
      _budgetController.clear();
      setState(() => _selectedService = null);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('حدث خطأ: ${e.toString()}'), backgroundColor: AppColors.error),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSuccess(String message) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 60),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.text, fontSize: 15)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('حسناً', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = widget.labels;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.home_repair_service_outlined, color: AppColors.primary, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l['tab2Label'] ?? 'طلب تركيب',
                            style: const TextStyle(color: AppColors.primary,
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        const SizedBox(height: 2),
                        Text(l['tab2Description'] ?? 'تركيب أنظمة المنزل الذكي',
                            style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            _buildLabel('${l['tab2ServiceLabel'] ?? 'نوع الخدمة'} *'),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _selectedService,
              dropdownColor: AppColors.card,
              style: const TextStyle(color: AppColors.text),
              decoration: _inputDecoration('اختر نوع الخدمة...'),
              items: widget.serviceTypes
                  .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedService = v),
              validator: (v) => v == null ? 'هذا الحقل مطلوب' : null,
            ),

            const SizedBox(height: 16),

            _buildLabel('${l['tab2TitleLabel'] ?? 'عنوان الطلب'} *'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _titleController,
              style: const TextStyle(color: AppColors.text),
              decoration: _inputDecoration('مثال: تركيب كاميرات في المنزل'),
              validator: (v) => v == null || v.isEmpty ? 'هذا الحقل مطلوب' : null,
            ),

            const SizedBox(height: 16),

            _buildLabel('${l['tab2DescLabel'] ?? 'تفاصيل الطلب'} *'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _descController,
              style: const TextStyle(color: AppColors.text),
              decoration: _inputDecoration('اشرح متطلباتك بالتفصيل...'),
              maxLines: 4,
              validator: (v) => v == null || v.isEmpty ? 'هذا الحقل مطلوب' : null,
            ),

            const SizedBox(height: 16),

            _buildLabel(l['tab2LocationLabel'] ?? 'الموقع / العنوان'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _locationController,
              style: const TextStyle(color: AppColors.text),
              decoration: _inputDecoration('مثال: القاهرة، مدينة نصر...'),
            ),

            const SizedBox(height: 16),

            _buildLabel(l['tab2BudgetLabel'] ?? 'الميزانية المتوقعة'),
            const SizedBox(height: 6),
            TextFormField(
              controller: _budgetController,
              style: const TextStyle(color: AppColors.text),
              decoration: _inputDecoration('مثال: 5000 جنيه'),
              keyboardType: TextInputType.text,
            ),

            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: _loading
                    ? const SizedBox(height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : Text(l['tab2ButtonLabel'] ?? 'إرسال الطلب',
                        style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildLabel(String text) => Text(text,
      style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 14));

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.muted),
    filled: true,
    fillColor: AppColors.card,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: AppColors.primary.withOpacity(0.3)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: BorderSide(color: AppColors.primary.withOpacity(0.2)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.primary),
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
  );
}
