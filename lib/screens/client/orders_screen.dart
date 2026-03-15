import 'package:flutter/material.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';

class ClientOrdersScreen extends StatefulWidget {
  const ClientOrdersScreen({super.key});

  @override
  State<ClientOrdersScreen> createState() => _ClientOrdersScreenState();
}

class _ClientOrdersScreenState extends State<ClientOrdersScreen> {
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
      final res = await ApiService.query('orders.getMyOrders');
      setState(() {
        _orders = res['data'] ?? [];
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppThemeDecorations.pageBackground(context),
      appBar: AppBar(
        title: const Text('طلباتي'),
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
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.receipt_long_outlined,
                          size: 64, color: AppColors.muted),
                      SizedBox(height: 16),
                      Text('لا توجد طلبات بعد',
                          style: TextStyle(color: AppColors.muted, fontSize: 18)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _orders.length,
                  itemBuilder: (ctx, i) {
                    final order = _orders[i];
                    return _OrderCard(order: order);
                  },
                ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final Map<String, dynamic> order;
  const _OrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final status = order['status'] as String? ?? 'pending';
    final total = double.tryParse(order['totalAmount']?.toString() ?? '0') ?? 0;
    final date = order['createdAt'] != null
        ? DateTime.fromMillisecondsSinceEpoch(order['createdAt'])
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppThemeDecorations.cardColor(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('طلب #${order['id']}',
                  style: const TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.bold,
                      fontSize: 15)),
              _StatusBadge(status: status),
            ],
          ),
          const SizedBox(height: 8),
          if (date != null)
            Text(
              '${date.day}/${date.month}/${date.year}',
              style: const TextStyle(color: AppColors.muted, fontSize: 12),
            ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${total.toStringAsFixed(2)} ج.م',
                style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
              Text(
                _paymentLabel(order['paymentMethod'] as String? ?? ''),
                style: const TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _paymentLabel(String method) {
    switch (method) {
      case 'cash':
        return 'كاش';
      case 'visa':
        return 'فيزا';
      case 'apple_pay':
        return 'Apple Pay';
      default:
        return method;
    }
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
        label = 'قيد الانتظار';
        break;
      case 'confirmed':
        color = const Color(0xFF2E7D32);
        label = 'مؤكد';
        break;
      case 'processing':
        color = const Color(0xFF1565C0);
        label = 'جاري التنفيذ';
        break;
      case 'delivered':
        color = AppColors.success;
        label = 'تم التسليم';
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}
