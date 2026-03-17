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
    final date = order['createdAt'] != null
        ? DateTime.fromMillisecondsSinceEpoch(order['createdAt'])
        : null;

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
