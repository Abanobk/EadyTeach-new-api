import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';

Map<String, dynamic>? _asStrKeyMap(dynamic v) {
  if (v == null) return null;
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return Map<String, dynamic>.from(v);
  return null;
}

/// عرض بيانات مسار الستائر (للإدارة — للقراءة فقط).
List<String> _curtainConfigLines(Map<String, dynamic> cfg) {
  final lines = <String>[];
  final cm = cfg['curtainLengthCm'];
  if (cm != null) {
    lines.add('المقاس الفعلي (العميل): ${cm is num ? cm.toStringAsFixed(0) : cm.toString()} سم');
  }
  final comm = cfg['curtainCommercialM'];
  if (comm != null) {
    lines.add('المقاس التقريبي التجاري: ${comm is num ? (comm as num).toStringAsFixed(1) : comm.toString()} م');
  }
  final dir = cfg['direction']?.toString();
  if (dir != null && dir.isNotEmpty) {
    final dirAr = switch (dir) {
      'left' => 'يسار',
      'right' => 'يمين',
      'center' => 'منتصف',
      _ => dir,
    };
    lines.add('الاتجاه: $dirAr');
  }
  final wheel = cfg['wheel']?.toString();
  if (wheel != null && wheel.isNotEmpty) {
    lines.add(wheel == 'wave' ? 'العجلة: Wave (ويفي)' : 'العجلة: عادي');
  }
  final motor = cfg['motorId']?.toString();
  if (motor != null && motor.isNotEmpty && motor != 'none') {
    lines.add('المحرك: $motor');
  }
  final notes = cfg['notes']?.toString();
  if (notes != null && notes.trim().isNotEmpty) {
    lines.add('ملاحظات العميل: $notes');
  }
  return lines;
}

class AdminOrdersScreen extends StatefulWidget {
  const AdminOrdersScreen({super.key});

  @override
  State<AdminOrdersScreen> createState() => _AdminOrdersScreenState();
}

class _AdminOrdersScreenState extends State<AdminOrdersScreen> {
  List<dynamic> _orders = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() => _loading = true);
    try {
      final res = await ApiService.query('admin.getAllOrders');
      setState(() {
        _orders = res['data'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _updateStatus(dynamic orderId, String status) async {
    try {
      await ApiService.mutate('admin.updateOrderStatus', input: {
        'orderId': orderId,
        'status': status,
      });
      await _loadOrders();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('تم تحديث حالة الطلب'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeDecorations.pageBackground(context),
      appBar: AppBar(
        title: const Text('إدارة الطلبات'),
        backgroundColor: AppThemeDecorations.cardColor(context),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh, color: AppColors.muted),
            onPressed: _loadOrders,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _orders.isEmpty
              ? const Center(
                  child: Text('لا توجد طلبات',
                      style: TextStyle(color: AppColors.muted)))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _orders.length,
                  itemBuilder: (ctx, i) => _AdminOrderCard(
                    order: _orders[i],
                    onUpdateStatus: _updateStatus,
                  ),
                ),
    );
  }
}

class _AdminOrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  final Function(dynamic, String) onUpdateStatus;

  const _AdminOrderCard(
      {required this.order, required this.onUpdateStatus});

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String? ?? 'pending';
    final total =
        double.tryParse(order['totalAmount']?.toString() ?? '0') ?? 0;
    final approvedItems = (order['approvedItems'] is List) ? (order['approvedItems'] as List) : null;
    final paymentMethod = order['paymentMethod']?.toString();
    final paymentProofUrl = order['paymentProofUrl']?.toString();
    final date = order['createdAt'] != null
        ? DateTime.fromMillisecondsSinceEpoch(order['createdAt'])
        : null;
    final items = (order['items'] is List) ? (order['items'] as List) : const [];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppThemeDecorations.cardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        title: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('طلب #${order['id']}',
                      style: const TextStyle(
                          color: AppColors.text,
                          fontWeight: FontWeight.bold,
                          fontSize: 14)),
                  if (order['customerName'] != null)
                    Text(order['customerName'],
                        style: const TextStyle(
                            color: AppColors.muted, fontSize: 12)),
                ],
              ),
            ),
            _StatusBadge(status: status),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${total.toStringAsFixed(2)} ج.م',
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
              if (date != null)
                Text('${date.day}/${date.month}/${date.year}',
                    style: const TextStyle(
                        color: AppColors.muted, fontSize: 11)),
            ],
          ),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(color: AppColors.border),
                if (items.isNotEmpty) ...[
                  const Text(
                    'بنود الطلب وبيانات القياس',
                    style: TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'للعرض فقط — يمكن تعديل سعر الوحدة من «تعديل أسعار الطلب المسبق» عند حالة طلب مسبق.',
                    style: TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
                  const SizedBox(height: 10),
                  ...List.generate(items.length, (i) {
                    final raw = items[i];
                    if (raw is! Map) return const SizedBox.shrink();
                    final m = Map<String, dynamic>.from(raw);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _AdminOrderLineCard(
                        line: m,
                        lineIndex: i,
                        approvedItems: approvedItems,
                      ),
                    );
                  }),
                  const SizedBox(height: 4),
                ],
                if (paymentMethod == 'transfer') ...[
                  const Text('إثبات التحويل:', style: TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 8),
                  if (paymentProofUrl != null && paymentProofUrl.trim().isNotEmpty)
                    GestureDetector(
                      onTap: () async {
                        try {
                          // ignore: use_build_context_synchronously
                          await showDialog(
                            context: context,
                            builder: (_) => Dialog(
                              backgroundColor: AppThemeDecorations.cardColor(context),
                              child: Padding(
                                padding: const EdgeInsets.all(12),
                                child: Image.network(
                                  ApiService.proxyImageUrl(paymentProofUrl),
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => const Center(
                                      child: Icon(Icons.broken_image, color: AppColors.muted, size: 40)),
                                ),
                              ),
                            ),
                          );
                        } catch (_) {}
                      },
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        clipBehavior: Clip.hardEdge,
                        child: Image.network(
                          ApiService.proxyImageUrl(paymentProofUrl),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(
                              child: Icon(Icons.broken_image, color: AppColors.muted, size: 28)),
                        ),
                      ),
                    )
                  else
                    const Text('لم يتم رفع إيصال بعد', style: TextStyle(color: AppColors.muted)),
                  const SizedBox(height: 12),
                ],
                if (status == 'preorder') ...[
                  _AdminOrderPricingEditor(
                    orderId: order['id'],
                    items: items,
                    approvedItems: approvedItems,
                    onSaved: () => onUpdateStatus(order['id'], status), // just refresh via parent flow
                  ),
                  const SizedBox(height: 12),
                ],
                // Customer details
                if (order['customerPhone'] != null)
                  _DetailRow(
                      icon: Icons.phone_outlined,
                      label: 'الهاتف',
                      value: order['customerPhone']),
                if (order['customerAddress'] != null)
                  _DetailRow(
                      icon: Icons.location_on_outlined,
                      label: 'العنوان',
                      value: order['customerAddress']),
                const SizedBox(height: 12),
                const Text('تغيير الحالة:',
                    style: TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 13)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    'pending',
                    'confirmed',
                    'processing',
                    'delivered',
                    'cancelled',
                    'preorder',
                  ]
                      .map((s) => _StatusChip(
                            statusKey: s,
                            selected: status == s,
                            onTap: () =>
                                onUpdateStatus(order['id'], s),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminOrderLineCard extends StatelessWidget {
  final Map<String, dynamic> line;
  final int lineIndex;
  final List? approvedItems;

  const _AdminOrderLineCard({
    required this.line,
    required this.lineIndex,
    required this.approvedItems,
  });

  @override
  Widget build(BuildContext context) {
    final pid = line['productId'];
    final name = (line['name'] ?? line['productName'] ?? 'منتج #$pid').toString();
    final qty = int.tryParse(line['quantity']?.toString() ?? line['qty']?.toString() ?? '') ?? 1;
    final unitRequested =
        double.tryParse(line['unitPrice']?.toString() ?? line['price']?.toString() ?? '') ?? 0.0;
    double? unitApproved;
    final a = approvedItems;
    if (a != null && lineIndex < a.length && a[lineIndex] is Map) {
      final am = _asStrKeyMap(a[lineIndex]);
      final rawU = am?['unitPrice']?.toString();
      if (rawU != null && rawU.trim().isNotEmpty) {
        unitApproved = double.tryParse(rawU.replaceAll('،', '.'));
      }
    }
    final variant = line['variant']?.toString();
    final cfg = _asStrKeyMap(line['configuration']);
    final curtainLines = (cfg != null &&
            (cfg['pricingMode']?.toString() == 'curtain_per_meter' ||
                cfg['curtainLengthCm'] != null ||
                cfg['curtainCommercialM'] != null))
        ? _curtainConfigLines(cfg)
        : <String>[];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppThemeDecorations.pageBackground(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text('الكمية: $qty', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          if (variant != null && variant.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'ملخص المواصفات: $variant',
                style: const TextStyle(color: AppColors.text, fontSize: 12),
              ),
            ),
          if (curtainLines.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text('تفاصيل مسار / ستائر:', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 12)),
            const SizedBox(height: 4),
            ...curtainLines.map(
              (t) => Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('• $t', style: const TextStyle(color: AppColors.text, fontSize: 11, height: 1.25)),
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            unitApproved != null
                ? 'سعر الوحدة (طلب العميل): ${unitRequested.toStringAsFixed(2)} ج.م  ←  بعد الموافقة: ${unitApproved.toStringAsFixed(2)} ج.م'
                : 'سعر الوحدة في الطلب: ${unitRequested.toStringAsFixed(2)} ج.م',
            style: const TextStyle(color: AppColors.muted, fontSize: 11),
          ),
          Text(
            'إجمالي السطر: ${((unitApproved ?? unitRequested) * qty).toStringAsFixed(2)} ج.م',
            style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _AdminOrderPricingEditor extends StatefulWidget {
  final dynamic orderId;
  final List items;
  final List? approvedItems;
  final VoidCallback onSaved;

  const _AdminOrderPricingEditor({
    required this.orderId,
    required this.items,
    required this.approvedItems,
    required this.onSaved,
  });

  @override
  State<_AdminOrderPricingEditor> createState() => _AdminOrderPricingEditorState();
}

class _AdminOrderPricingEditorState extends State<_AdminOrderPricingEditor> {
  final List<TextEditingController> _controllers = [];
  bool _open = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    _controllers.clear();
    super.dispose();
  }

  void _ensureControllers() {
    if (_controllers.isNotEmpty) return;
    final a = widget.approvedItems;
    for (var i = 0; i < widget.items.length; i++) {
      var unit = 0.0;
      final raw = widget.items[i];
      if (raw is Map) {
        final pid = int.tryParse(raw['productId']?.toString() ?? '') ?? 0;
        if (pid > 0) {
          unit = double.tryParse(raw['unitPrice']?.toString() ?? '') ?? 0.0;
          if (a != null && i < a.length && a[i] is Map) {
            final am = _asStrKeyMap(a[i]);
            final rawU = am?['unitPrice']?.toString();
            if (rawU != null && rawU.trim().isNotEmpty) {
              final au = double.tryParse(rawU.replaceAll('،', '.'));
              if (au != null) unit = au;
            }
          }
        }
      }
      _controllers.add(TextEditingController(text: unit.toStringAsFixed(2)));
    }
  }

  String _normalizeNumeric(String s) {
    const arabicIndic = {
      '٠': '0',
      '١': '1',
      '٢': '2',
      '٣': '3',
      '٤': '4',
      '٥': '5',
      '٦': '6',
      '٧': '7',
      '٨': '8',
      '٩': '9',
    };
    var x = s.trim().replaceAll('،', '.').replaceAll(',', '.');
    x = x.split('').map((ch) => arabicIndic[ch] ?? ch).join();
    x = x.replaceAll(RegExp(r'[^0-9\.\-]'), '');
    return x;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      _ensureControllers();
      final payload = <Map<String, dynamic>>[];
      for (var i = 0; i < widget.items.length; i++) {
        final raw = widget.items[i];
        if (raw is! Map) continue;
        final pid = int.tryParse(raw['productId']?.toString() ?? '') ?? 0;
        if (pid <= 0) continue;
        final qty = int.tryParse(raw['quantity']?.toString() ?? raw['qty']?.toString() ?? '') ?? 1;
        if (i >= _controllers.length) continue;
        final ctrl = _controllers[i];
        final unit = double.tryParse(_normalizeNumeric(ctrl.text)) ?? 0.0;
        payload.add({
          'lineIndex': i,
          'productId': pid,
          'quantity': qty,
          'unitPrice': unit,
        });
      }

      await ApiService.mutate('admin.updateOrderPricing', input: {
        'orderId': widget.orderId,
        'items': payload,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم حفظ أسعار الطلب المسبق'), backgroundColor: AppColors.success),
        );
      }
      widget.onSaved();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ في حفظ الأسعار: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _open = !_open;
              });
              if (_open) _ensureControllers();
            },
            icon: const Icon(Icons.edit),
            label: Text(_open ? 'إخفاء تعديل الأسعار' : 'تعديل أسعار الطلب المسبق'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
        if (_open) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppThemeDecorations.cardColor(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                ...List.generate(widget.items.length, (i) {
                  final raw = widget.items[i];
                  if (raw is! Map) return const SizedBox.shrink();
                  final pid = int.tryParse(raw['productId']?.toString() ?? '') ?? 0;
                  if (pid <= 0) return const SizedBox.shrink();
                  final name = raw['name']?.toString() ?? raw['productName']?.toString() ?? 'منتج';
                  final qty = int.tryParse(raw['quantity']?.toString() ?? raw['qty']?.toString() ?? '') ?? 1;
                  if (i >= _controllers.length) return const SizedBox.shrink();
                  final ctrl = _controllers[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w600, fontSize: 13)),
                              Text('الكمية: $qty', style: const TextStyle(color: AppColors.muted, fontSize: 12)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: 130,
                          child: TextField(
                            controller: ctrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textDirection: TextDirection.ltr,
                            decoration: const InputDecoration(
                              labelText: 'سعر الوحدة',
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: Text(_saving ? 'جاري الحفظ...' : 'حفظ الأسعار'),
                  ),
                ),
              ],
            ),
          ),
        ]
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow(
      {required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, color: AppColors.muted, size: 16),
          const SizedBox(width: 8),
          Text('$label: ',
              style: const TextStyle(color: AppColors.muted, fontSize: 12)),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    color: AppColors.text, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String statusKey;
  final bool selected;
  final VoidCallback onTap;

  const _StatusChip(
      {required this.statusKey,
      required this.selected,
      required this.onTap});

  String get label {
    switch (statusKey) {
      case 'pending':
        return 'انتظار';
      case 'confirmed':
        return 'مؤكد';
      case 'processing':
        return 'جاري';
      case 'delivered':
        return 'مُسلَّم';
      case 'cancelled':
        return 'ملغي';
      default:
        return statusKey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppThemeDecorations.pageBackground(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : AppColors.text,
            fontSize: 12,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case 'pending':
        color = const Color(0xFFD4920A);
        label = 'انتظار';
        break;
      case 'preorder':
        color = const Color(0xFF6A1B9A);
        label = 'طلب مسبق';
        break;
      case 'confirmed':
        color = const Color(0xFF2E7D32);
        label = 'مؤكد';
        break;
      case 'processing':
        color = const Color(0xFF1565C0);
        label = 'جاري';
        break;
      case 'delivered':
        color = AppColors.success;
        label = 'مُسلَّم';
        break;
      case 'cancelled':
        color = AppColors.error;
        label = 'ملغي';
        break;
      default:
        color = AppColors.muted;
        label = status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }
}
