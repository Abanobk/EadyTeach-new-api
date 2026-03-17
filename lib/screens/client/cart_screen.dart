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
  String? _shippingName;
  String? _shippingPhone;
  String? _shippingAddress;
  bool _loadingProfile = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _loadingProfile = true);
    try {
      final res = await ApiService.query('users.getProfile');
      final data = res['data'] ?? res;
      setState(() {
        _shippingName = data['name'] as String?;
        _shippingPhone = data['phone'] as String?;
        _shippingAddress = data['address'] as String?;
        _loadingProfile = false;
      });
    } catch (_) {
      setState(() => _loadingProfile = false);
    }
  }

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
                      const Text('بيانات التوصيل:',
                          style: TextStyle(
                              color: AppColors.text,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppThemeDecorations.pageBackground(context),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: _loadingProfile
                            ? const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.primary),
                                  ),
                                  SizedBox(width: 8),
                                  Text('جاري تحميل بياناتك...',
                                      style: TextStyle(
                                          color: AppColors.muted,
                                          fontSize: 13)),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _shippingName?.isNotEmpty == true
                                        ? _shippingName!
                                        : 'الاسم: غير مُدخل',
                                    style: const TextStyle(
                                        color: AppColors.text, fontSize: 13),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _shippingPhone?.isNotEmpty == true
                                        ? 'الهاتف: $_shippingPhone'
                                        : 'الهاتف: غير مُدخل',
                                    style: const TextStyle(
                                        color: AppColors.text, fontSize: 13),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _shippingAddress?.isNotEmpty == true
                                        ? 'العنوان: $_shippingAddress'
                                        : 'العنوان: غير مُدخل',
                                    style: const TextStyle(
                                        color: AppColors.text, fontSize: 13),
                                  ),
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: TextButton.icon(
                                      onPressed: _submitting
                                          ? null
                                          : () => _editShippingInfo(),
                                      icon: const Icon(Icons.edit_location_alt,
                                          size: 18),
                                      label: Text(
                                        _shippingAddress?.isNotEmpty == true
                                            ? 'تعديل بيانات التوصيل'
                                            : 'إضافة بيانات التوصيل',
                                        style: const TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                      ),
                      const SizedBox(height: 16),
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
                          onPressed:
                              _submitting ? null : () => _placeOrder(cart),
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
    // تأكد من وجود بيانات التوصيل (خاصة العنوان)
    final hasAddress =
        _shippingAddress != null && _shippingAddress!.trim().isNotEmpty;
    if (!hasAddress) {
      final ok = await _editShippingInfo();
      if (!ok) return;
    }

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
        if (_shippingAddress != null && _shippingAddress!.isNotEmpty)
          'shippingAddress': _shippingAddress,
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

  Future<bool> _editShippingInfo() async {
    final nameCtrl = TextEditingController(text: _shippingName ?? '');
    final phoneCtrl = TextEditingController(text: _shippingPhone ?? '');
    final addressCtrl = TextEditingController(text: _shippingAddress ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: AppThemeDecorations.cardColor(context),
          title: const Text('بيانات التوصيل',
              style: TextStyle(color: AppColors.text)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'الاسم الكامل',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'رقم الهاتف',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: addressCtrl,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'عنوان التوصيل',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      // حفظ في البروفايل حتى تُستخدم لاحقاً
      try {
        await ApiService.mutate('users.updateProfile', input: {
          'name': nameCtrl.text.trim(),
          'phone': phoneCtrl.text.trim(),
          'address': addressCtrl.text.trim(),
        });
      } catch (_) {
        // نتجاهل الخطأ هنا، المهم نحدّث الطلب الحالي
      }

      setState(() {
        _shippingName = nameCtrl.text.trim();
        _shippingPhone = phoneCtrl.text.trim();
        _shippingAddress = addressCtrl.text.trim();
      });
      return true;
    }
    return false;
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
