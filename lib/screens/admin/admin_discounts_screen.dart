import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';
import '../../providers/auth_provider.dart';

class AdminDiscountsScreen extends StatefulWidget {
  const AdminDiscountsScreen({super.key});

  @override
  State<AdminDiscountsScreen> createState() => _AdminDiscountsScreenState();
}

class _AdminDiscountsScreenState extends State<AdminDiscountsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  bool _loading = true;
  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _dealers = [];
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _products = [];

  String _targetType = 'dealer'; // dealer | client
  int? _selectedTargetId;

  List<Map<String, dynamic>> _categoryRules = [];
  List<Map<String, dynamic>> _productRules = [];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadLookups();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLookups() async {
    setState(() => _loading = true);
    try {
      final res = await Future.wait([
        ApiService.query('clients.allUsers', input: {}),
        ApiService.query('products.getCategories', input: {}),
        ApiService.query('products.listAdmin', input: {}),
      ]);

      final users =
          (res[0]['data'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
      _categories =
          (res[1]['data'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();
      _products =
          (res[2]['data'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)).toList();

      _clients = users
          .where((u) => (u['role'] == 'user' || u['role'] == 'client'))
          .map((u) => u)
          .toList();
      _dealers =
          users.where((u) => (u['role'] == 'dealer' || u['role'] == 'reseller')).toList();

      _loading = false;
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل البيانات: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _loadRules() async {
    if (_selectedTargetId == null) return;
    setState(() => _loading = true);
    try {
      final res = await Future.wait([
        ApiService.query('discounts.listRules', input: {
          'targetType': _targetType,
          'targetId': _selectedTargetId,
          'scopeType': 'category',
        }),
        ApiService.query('discounts.listRules', input: {
          'targetType': _targetType,
          'targetId': _selectedTargetId,
          'scopeType': 'product',
        }),
      ]);
      _categoryRules = (res[0]['data'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      _productRules = (res[1]['data'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في تحميل قواعد الخصم: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _currentTargets =>
      _targetType == 'dealer' ? _dealers : _clients;

  String _targetLabel(Map<String, dynamic> u) {
    final name = (u['name'] ?? '').toString();
    final email = (u['email'] ?? '').toString();
    final phone = (u['phone'] ?? '').toString();
    if (name.isNotEmpty) return name;
    if (email.isNotEmpty) return email;
    if (phone.isNotEmpty) return phone;
    return 'مستخدم ${u['id']}';
  }

  String _categoryName(int? id) {
    if (id == null) return '-';
    final c = _categories.firstWhere(
      (e) => e['id'] == id,
      orElse: () => {},
    );
    if (c.isEmpty) return '-';
    return (c['nameAr'] ?? c['name'] ?? '').toString();
  }

  String _productName(int? id) {
    if (id == null) return '-';
    final p = _products.firstWhere(
      (e) => e['id'] == id,
      orElse: () => {},
    );
    if (p.isEmpty) return '-';
    return (p['nameAr'] ?? p['name'] ?? '').toString();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppThemeDecorations.pageBackground(context),
        appBar: AppBar(
          backgroundColor: AppThemeDecorations.cardColor(context),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.text),
            onPressed: () => Navigator.maybePop(context),
          ),
          title: const Text(
            'إدارة خصومات التجار / العملاء',
            style: TextStyle(color: AppColors.text, fontWeight: FontWeight.bold),
          ),
          iconTheme: const IconThemeData(color: AppColors.text),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, color: AppColors.muted),
              onPressed: () async {
                await _loadLookups();
                await _loadRules();
              },
            ),
          ],
          bottom: TabBar(
            controller: _tabCtrl,
            indicatorColor: AppColors.primary,
            tabs: const [
              Tab(text: 'خصم على الفئات'),
              Tab(text: 'خصم على المنتجات'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : Column(
                children: [
                  _buildTargetSelector(),
                  const Divider(height: 1, color: AppColors.border),
                  Expanded(
                    child: TabBarView(
                      controller: _tabCtrl,
                      children: [
                        _buildCategoryRules(),
                        _buildProductRules(),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildTargetSelector() {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      color: AppThemeDecorations.cardColor(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'اختر نوع المستفيد:',
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ChoiceChip(
                label: const Text('تاجر'),
                selected: _targetType == 'dealer',
                onSelected: (v) {
                  if (!v) return;
                  setState(() {
                    _targetType = 'dealer';
                    _selectedTargetId = null;
                    _categoryRules = [];
                    _productRules = [];
                  });
                },
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('عميل'),
                selected: _targetType == 'client',
                onSelected: (v) {
                  if (!v) return;
                  setState(() {
                    _targetType = 'client';
                    _selectedTargetId = null;
                    _categoryRules = [];
                    _productRules = [];
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'اختر التاجر / العميل:',
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: AppThemeDecorations.pageBackground(context),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int?>(
                isExpanded: true,
                value: _selectedTargetId,
                hint: const Text(
                  'اختر مستخدماً',
                  style: TextStyle(color: AppColors.muted),
                ),
                items: _currentTargets
                    .map(
                      (u) => DropdownMenuItem<int?>(
                        value: u['id'] as int?,
                        child: Text(
                          _targetLabel(u),
                          style: const TextStyle(color: AppColors.text),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) async {
                  setState(() {
                    _selectedTargetId = v;
                    _categoryRules = [];
                    _productRules = [];
                  });
                  await _loadRules();
                },
              ),
            ),
          ),
          if (_selectedTargetId != null) ...[
            const SizedBox(height: 8),
            Text(
              'سيتم تطبيق قواعد الخصم على كل الأسعار التي يراها هذا المستخدم في المتجر.',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCategoryRules() {
    if (_selectedTargetId == null) {
      return const Center(
        child: Text(
          'اختر أولاً التاجر أو العميل لعرض خصومات الفئات.',
          style: TextStyle(color: AppColors.muted),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'خصومات الفئات',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showRuleDialog(scopeType: 'category'),
                icon: const Icon(Icons.add),
                label: const Text('إضافة خصم'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _categoryRules.isEmpty
                ? const Center(
                    child: Text('لا توجد خصومات مسجلة على الفئات بعد.',
                        style: TextStyle(color: AppColors.muted)),
                  )
                : ListView.separated(
                    itemBuilder: (_, i) {
                      final r = _categoryRules[i];
                      final pct = (r['discountPercent'] as num).toDouble();
                      final amt = (r['discountAmount'] as num).toDouble();
                      final minStock = (r['minStock'] as num).toInt();
                      final active = r['isActive'] == true;
                      final label = pct > 0
                          ? '${pct.toStringAsFixed(0)}%'
                          : '${amt.toStringAsFixed(0)} ج.م';
                      return ListTile(
                        tileColor: AppThemeDecorations.cardColor(context),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: const BorderSide(color: AppColors.border),
                        ),
                        title: Text(
                          _categoryName(r['categoryId'] as int?),
                          style: const TextStyle(
                            color: AppColors.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              'الخصم: $label',
                              style: const TextStyle(color: AppColors.muted, fontSize: 12),
                            ),
                            if (minStock > 0)
                              Text(
                                'شرط المخزون: من $minStock فأكثر',
                                style:
                                    const TextStyle(color: AppColors.muted, fontSize: 11),
                              ),
                            if ((r['note'] ?? '').toString().isNotEmpty)
                              Text(
                                r['note'],
                                style:
                                    const TextStyle(color: AppColors.muted, fontSize: 11),
                              ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: active,
                              onChanged: (v) async {
                                await _saveRule(
                                  data: {...r, 'isActive': v},
                                  scopeType: 'category',
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit, color: AppColors.primary),
                              onPressed: () =>
                                  _showRuleDialog(scopeType: 'category', existing: r),
                            ),
                            IconButton(
                              icon:
                                  const Icon(Icons.delete_outline, color: AppColors.error),
                              onPressed: () => _confirmDeleteRule(r),
                            ),
                          ],
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemCount: _categoryRules.length,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductRules() {
    if (_selectedTargetId == null) {
      return const Center(
        child: Text(
          'اختر أولاً التاجر أو العميل لعرض خصومات المنتجات.',
          style: TextStyle(color: AppColors.muted),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'خصومات المنتجات',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showRuleDialog(scopeType: 'product'),
                icon: const Icon(Icons.add),
                label: const Text('إضافة خصم'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _productRules.isEmpty
                ? const Center(
                    child: Text('لا توجد خصومات مسجلة على المنتجات بعد.',
                        style: TextStyle(color: AppColors.muted)),
                  )
                : ListView.separated(
                    itemBuilder: (_, i) {
                      final r = _productRules[i];
                      final pct = (r['discountPercent'] as num).toDouble();
                      final amt = (r['discountAmount'] as num).toDouble();
                      final minStock = (r['minStock'] as num).toInt();
                      final active = r['isActive'] == true;
                      final label = pct > 0
                          ? '${pct.toStringAsFixed(0)}%'
                          : '${amt.toStringAsFixed(0)} ج.م';
                      return ListTile(
                        tileColor: AppThemeDecorations.cardColor(context),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: const BorderSide(color: AppColors.border),
                        ),
                        title: Text(
                          _productName(r['productId'] as int?),
                          style: const TextStyle(
                            color: AppColors.text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              'الخصم: $label',
                              style: const TextStyle(color: AppColors.muted, fontSize: 12),
                            ),
                            if (minStock > 0)
                              Text(
                                'شرط المخزون: من $minStock فأكثر',
                                style:
                                    const TextStyle(color: AppColors.muted, fontSize: 11),
                              ),
                            if ((r['note'] ?? '').toString().isNotEmpty)
                              Text(
                                r['note'],
                                style:
                                    const TextStyle(color: AppColors.muted, fontSize: 11),
                              ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Switch(
                              value: active,
                              onChanged: (v) async {
                                await _saveRule(
                                  data: {...r, 'isActive': v},
                                  scopeType: 'product',
                                );
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit, color: AppColors.primary),
                              onPressed: () =>
                                  _showRuleDialog(scopeType: 'product', existing: r),
                            ),
                            IconButton(
                              icon:
                                  const Icon(Icons.delete_outline, color: AppColors.error),
                              onPressed: () => _confirmDeleteRule(r),
                            ),
                          ],
                        ),
                      );
                    },
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemCount: _productRules.length,
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _showRuleDialog({
    required String scopeType, // category | product
    Map<String, dynamic>? existing,
  }) async {
    if (_selectedTargetId == null) return;
    final isEdit = existing != null;
    int? categoryId = existing?['categoryId'] as int?;
    int? productId = existing?['productId'] as int?;
    double pct =
        (existing?['discountPercent'] as num?)?.toDouble() ?? 0;
    double amt =
        (existing?['discountAmount'] as num?)?.toDouble() ?? 0;
    int minStock = (existing?['minStock'] as num?)?.toInt() ?? 0;
    bool isActive = existing?['isActive'] == true;
    final noteCtrl = TextEditingController(text: existing?['note']?.toString() ?? '');

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppThemeDecorations.cardColor(context),
        title: Text(
          isEdit ? 'تعديل خصم' : 'إضافة خصم جديد',
          style: const TextStyle(color: AppColors.text),
        ),
        content: StatefulBuilder(
          builder: (ctx, setState) => SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (scopeType == 'category') ...[
                    const Text('الفئة', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int?>(
                      value: categoryId,
                      decoration: _inputDec(),
                      dropdownColor: AppThemeDecorations.cardColor(context),
                      items: _categories
                          .map(
                            (c) => DropdownMenuItem<int?>(
                              value: c['id'] as int?,
                              child: Text(
                                (c['nameAr'] ?? c['name'] ?? '').toString(),
                                style: const TextStyle(color: AppColors.text),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => categoryId = v),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'اختياري: منتج محدد (لو اخترته يبقى التنفيذ للمنتج)',
                      style: TextStyle(color: AppColors.muted, fontSize: 13),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int?>(
                      value: productId,
                      decoration: _inputDec(hint: 'لا شيء'),
                      dropdownColor: AppThemeDecorations.cardColor(context),
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('- لا شيء', style: TextStyle(color: AppColors.muted)),
                        ),
                        ..._products.map(
                          (p) => DropdownMenuItem<int?>(
                            value: p['id'] as int?,
                            child: Text(
                              (p['nameAr'] ?? p['name'] ?? '').toString(),
                              style: const TextStyle(color: AppColors.text),
                            ),
                          ),
                        ),
                      ],
                      onChanged: (v) => setState(() => productId = v),
                    ),
                  ] else ...[
                    const Text('المنتج', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<int?>(
                      value: productId,
                      decoration: _inputDec(),
                      dropdownColor: AppThemeDecorations.cardColor(context),
                      items: _products
                          .map(
                            (p) => DropdownMenuItem<int?>(
                              value: p['id'] as int?,
                              child: Text(
                                (p['nameAr'] ?? p['name'] ?? '').toString(),
                                style: const TextStyle(color: AppColors.text),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => productId = v),
                    ),
                  ],
                  const SizedBox(height: 16),
                  const Text('نسبة الخصم (%)', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  const SizedBox(height: 4),
                  TextFormField(
                    initialValue: pct > 0 ? pct.toStringAsFixed(0) : '',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: AppColors.text),
                    decoration: _inputDec(hint: 'اتركها فارغة لاستخدام مبلغ ثابت'),
                    onChanged: (v) =>
                        pct = double.tryParse(v.replaceAll(',', '.')) ?? 0,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'مبلغ خصم ثابت (ج.م) – يُستخدم إذا كانت النسبة فارغة أو 0',
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  TextFormField(
                    initialValue: amt > 0 ? amt.toStringAsFixed(0) : '',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(color: AppColors.text),
                    decoration: _inputDec(hint: 'مثال: 100'),
                    onChanged: (v) =>
                        amt = double.tryParse(v.replaceAll(',', '.')) ?? 0,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'شرط المخزون لتفعيل الخصم (الحد الأدنى للكمية في المخزون)',
                    style: TextStyle(color: AppColors.muted, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  TextFormField(
                    initialValue: minStock > 0 ? '$minStock' : '',
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: AppColors.text),
                    decoration: _inputDec(hint: 'اتركه فارغًا لإلغاء الشرط'),
                    onChanged: (v) => minStock = int.tryParse(v) ?? 0,
                  ),
                  const SizedBox(height: 12),
                  const Text('ملاحظة (اختياري)', style: TextStyle(color: AppColors.muted, fontSize: 13)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: noteCtrl,
                    maxLines: 2,
                    style: const TextStyle(color: AppColors.text),
                    decoration: _inputDec(hint: 'مثال: خصم خاص للتاجر الفلاني'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Switch(
                        value: isActive,
                        onChanged: (v) => setState(() => isActive = v),
                      ),
                      const Text('مُفعل', style: TextStyle(color: AppColors.text)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (scopeType == 'category' && categoryId == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('برجاء اختيار فئة'),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }
              if (scopeType == 'product' && productId == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('برجاء اختيار منتج'),
                    backgroundColor: AppColors.error,
                  ),
                );
                return;
              }

              final finalScopeType = scopeType == 'category'
                  ? (productId != null ? 'product' : 'category')
                  : scopeType;

              await _saveRule(
                data: {
                  if (existing != null) 'id': existing['id'],
                  'targetType': _targetType,
                  'targetId': _selectedTargetId,
                  'scopeType': finalScopeType,
                  if (finalScopeType == 'category') 'categoryId': categoryId,
                  if (finalScopeType == 'product') 'productId': productId,
                  'discountPercent': pct,
                  'discountAmount': pct > 0 ? 0 : amt,
                  'minStock': minStock,
                  'isActive': isActive,
                  'note': noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
                },
                scopeType: finalScopeType,
              );
              if (context.mounted) Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.black,
            ),
            child: Text(isEdit ? 'حفظ' : 'إضافة'),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDec({String hint = ''}) => InputDecoration(
        hintText: hint,
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
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      );

  Future<void> _saveRule({
    required Map<String, dynamic> data,
    required String scopeType,
  }) async {
    try {
      await ApiService.mutate('discounts.saveRule', input: data);
      await _loadRules();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حفظ قاعدة الخصم بنجاح'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في حفظ قاعدة الخصم: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }

  Future<void> _confirmDeleteRule(Map<String, dynamic> r) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppThemeDecorations.cardColor(context),
        title: const Text('حذف قاعدة خصم', style: TextStyle(color: AppColors.text)),
        content: const Text(
          'هل أنت متأكد من حذف هذه القاعدة؟',
          style: TextStyle(color: AppColors.muted),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('حذف', style: TextStyle(color: AppColors.error)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiService.mutate('discounts.deleteRule', input: {'id': r['id']});
      await _loadRules();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('تم حذف قاعدة الخصم'),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في حذف القاعدة: $e'),
          backgroundColor: AppColors.error,
        ),
      );
    }
  }
}

