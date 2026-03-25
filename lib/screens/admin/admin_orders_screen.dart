import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';

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
  final Map<int, TextEditingController> _controllers = {};
  bool _open = false;
  bool _saving = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    _controllers.clear();
    super.dispose();
  }

  void _ensureControllers() {
    if (_controllers.isNotEmpty) return;
    final approvedByPid = <int, double>{};
    final a = widget.approvedItems;
    if (a != null) {
      for (final raw in a) {
        if (raw is! Map) continue;
        final pid = int.tryParse(raw['productId']?.toString() ?? '') ?? 0;
        if (pid <= 0) continue;
        final unit = double.tryParse(raw['unitPrice']?.toString() ?? '') ?? 0.0;
        approvedByPid[pid] = unit;
      }
    }
    for (final raw in widget.items) {
      if (raw is! Map) continue;
      final pid = int.tryParse(raw['productId']?.toString() ?? '') ?? 0;
      if (pid <= 0) continue;
      final unit = approvedByPid[pid] ??
          (double.tryParse(raw['unitPrice']?.toString() ?? '') ?? 0.0);
      _controllers[pid] = TextEditingController(text: unit.toStringAsFixed(2));
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
      for (final raw in widget.items) {
        if (raw is! Map) continue;
        final pid = int.tryParse(raw['productId']?.toString() ?? '') ?? 0;
        if (pid <= 0) continue;
        final qty = int.tryParse(raw['quantity']?.toString() ?? raw['qty']?.toString() ?? '') ?? 1;
        final ctrl = _controllers[pid];
        if (ctrl == null) continue;
        final unit = double.tryParse(_normalizeNumeric(ctrl.text)) ?? 0.0;
        payload.add({'productId': pid, 'quantity': qty, 'unitPrice': unit});
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
                ...widget.items.map((raw) {
                  if (raw is! Map) return const SizedBox.shrink();
                  final pid = int.tryParse(raw['productId']?.toString() ?? '') ?? 0;
                  if (pid <= 0) return const SizedBox.shrink();
                  final name = raw['name']?.toString() ?? raw['productName']?.toString() ?? 'منتج';
                  final qty = int.tryParse(raw['quantity']?.toString() ?? raw['qty']?.toString() ?? '') ?? 1;
                  final ctrl = _controllers[pid];
                  if (ctrl == null) return const SizedBox.shrink();
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
                }).toList(),
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
