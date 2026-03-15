import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/cart_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  String _paymentMethod = 'cash';
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();

    return Scaffold(
      backgroundColor: AppThemeDecorations.pageBackground(context),
      appBar: AppBar(
        title: const Text('السلة'),
        backgroundColor: AppThemeDecorations.cardColor(context),
        automaticallyImplyLeading: false,
      ),
      body: cart.items.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.shopping_cart_outlined,
                      size: 64, color: AppColors.muted),
                  SizedBox(height: 16),
                  Text('السلة فارغة',
                      style: TextStyle(color: AppColors.muted, fontSize: 18)),
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: cart.items.length,
                    itemBuilder: (ctx, i) {
                      final item = cart.items[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppThemeDecorations.cardColor(context),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            // Image
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: item.image != null && item.image!.isNotEmpty
                                  ? Image.network(ApiService.proxyImageUrl(item.image!),
                                      width: 60,
                                      height: 60,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) =>
                                          _imgPlaceholder())
                                  : _imgPlaceholder(),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.name,
                                      style: const TextStyle(
                                          color: AppColors.text,
                                          fontWeight: FontWeight.w600)),
                                  const SizedBox(height: 4),
                                  Text(
                                      '${item.price.toStringAsFixed(2)} ج.م',
                                      style: const TextStyle(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            // Qty controls
                            Row(
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.remove_circle_outline,
                                      color: AppColors.muted, size: 20),
                                  onPressed: () =>
                                      cart.decrementItem(item.productId),
                                ),
                                Text('${item.quantity}',
                                    style: const TextStyle(
                                        color: AppColors.text,
                                        fontWeight: FontWeight.bold)),
                                IconButton(
                                  icon: const Icon(Icons.add_circle_outline,
                                      color: AppColors.primary, size: 20),
                                  onPressed: () =>
                                      cart.incrementItem(item.productId),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // Payment + Summary
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppThemeDecorations.cardColor(context),
                    border: const Border(top: BorderSide(color: AppColors.border)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('طريقة الدفع:',
                          style: TextStyle(
                              color: AppColors.text,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _PaymentBtn(
                              label: 'كاش',
                              icon: Icons.money,
                              selected: _paymentMethod == 'cash',
                              onTap: () =>
                                  setState(() => _paymentMethod = 'cash')),
                          const SizedBox(width: 8),
                          _PaymentBtn(
                              label: 'فيزا',
                              icon: Icons.credit_card,
                              selected: _paymentMethod == 'visa',
                              onTap: () =>
                                  setState(() => _paymentMethod = 'visa')),
                          const SizedBox(width: 8),
                          _PaymentBtn(
                              label: 'Apple Pay',
                              icon: Icons.apple,
                              selected: _paymentMethod == 'apple_pay',
                              onTap: () =>
                                  setState(() => _paymentMethod = 'apple_pay')),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('الإجمالي:',
                              style: TextStyle(
                                  color: AppColors.text,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16)),
                          Text('${cart.total.toStringAsFixed(2)} ج.م',
                              style: const TextStyle(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 20)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _submitting ? null : () => _placeOrder(cart),
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: _submitting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.black))
                              : Text(
                                  'إتمام الطلب — ${cart.total.toStringAsFixed(2)} ج.م',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _placeOrder(CartProvider cart) async {
    setState(() => _submitting = true);
    try {
      final items = cart.items
          .map((i) => {
                'productId': i.productId,
                'quantity': i.quantity,
                'unitPrice': i.price.toString(),
              })
          .toList();

      await ApiService.mutate('orders.create', input: {
        'items': items,
        'paymentMethod': _paymentMethod,
        'totalAmount': cart.total.toString(),
      });

      cart.clear();
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: AppThemeDecorations.cardColor(context),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.success),
                SizedBox(width: 8),
                Text('تم الطلب!',
                    style: TextStyle(color: AppColors.text)),
              ],
            ),
            content: const Text(
              'تم إرسال طلبك بنجاح. سنتواصل معك قريباً.',
              style: TextStyle(color: AppColors.muted),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('حسناً',
                    style: TextStyle(color: AppColors.primary)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في إرسال الطلب: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Widget _imgPlaceholder() {
    return Container(
      width: 60,
      height: 60,
      color: AppColors.border,
      child: const Icon(Icons.image_outlined, color: AppColors.muted),
    );
  }
}

class _PaymentBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _PaymentBtn(
      {required this.label,
      required this.icon,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : AppThemeDecorations.pageBackground(context),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected ? AppColors.primary : AppColors.border),
        ),
        child: Row(
          children: [
            Icon(icon,
                color: selected ? Colors.black : AppColors.muted, size: 16),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    color: selected ? Colors.black : AppColors.text,
                    fontWeight:
                        selected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
