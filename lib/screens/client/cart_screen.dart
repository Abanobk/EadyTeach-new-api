import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../../providers/cart_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  String _paymentMethod = 'cash';
  String? _transferProofUrl;
  bool _uploadingProof = false;
  bool _submitting = false;
  String? _shippingName;
  String? _shippingPhone;
  String? _shippingAddress;
  bool _loadingProfile = false;

  final ScrollController _itemsScrollController = ScrollController();
  int _lastItemsLen = -1;

  // Put your Instapay link here (from your message).
  static const String _instapayUrl = 'https://ipn.eg/S/abanob.mousa5861/instapay/0sN2g0';

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _itemsScrollController.dispose();
    super.dispose();
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

    // If cart sync updates items after this screen was built, ensure we show them from top.
    final currentLen = cart.items.length;
    if (_lastItemsLen != currentLen) {
      _lastItemsLen = currentLen;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_itemsScrollController.hasClients) {
          _itemsScrollController.jumpTo(0);
        }
      });
    }

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
                // Debug header to verify cart content vs rendering.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Text(
                    'DEBUG cart.items.length=${cart.items.length} | total=${cart.total.toStringAsFixed(2)} | first=${cart.items.isNotEmpty ? cart.items.first.name : "-"}',
                    style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
                // Debug: show first item outside ListView to ensure rendering isn't blocked.
                if (cart.items.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.redAccent, width: 2),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.shopping_bag_outlined, color: Colors.redAccent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'DEBUG first card: ${cart.items.first.name} (${cart.items.first.quantity}) - ${cart.items.first.price.toStringAsFixed(0)} ج.م',
                              style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.w800, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Expanded(
                  child: ListView.builder(
                    controller: _itemsScrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: cart.items.length,
                    itemBuilder: (ctx, i) {
                      final item = cart.items[i];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        height: 120, // force visible height for debugging
                        decoration: BoxDecoration(
                          // Debug-friendly styling: make items clearly visible.
                          color: AppColors.primary.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.redAccent, width: 2),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'DEBUG list card index=$i | id=${item.productId} | name=${item.name}',
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: Row(
                                children: [
                                  // Image
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: AspectRatio(
                                      aspectRatio: 1,
                                      child: item.image != null && item.image!.isNotEmpty
                                          ? Image.network(
                                              ApiService.proxyImageUrl(item.image!),
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => _imgPlaceholder(),
                                            )
                                          : _imgPlaceholder(),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          item.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: AppColors.text,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${item.price.toStringAsFixed(2)} ج.م',
                                          style: const TextStyle(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Qty controls
                                  Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.remove_circle_outline, color: AppColors.muted, size: 20),
                                        onPressed: () => cart.decrementItem(item.productId),
                                      ),
                                      Text(
                                        '${item.quantity}',
                                        style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.bold),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.add_circle_outline, color: AppColors.primary, size: 20),
                                        onPressed: () => cart.incrementItem(item.productId),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
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
                      Text(
                        'عدد المنتجات/القطع: ${cart.items.fold<int>(0, (s, i) => s + i.quantity)}',
                        style: const TextStyle(color: AppColors.text, fontWeight: FontWeight.bold, fontSize: 14),
                      ),
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
                          const SizedBox(width: 8),
                          _PaymentBtn(
                              label: 'تحويل',
                              icon: Icons.account_balance_wallet_outlined,
                              selected: _paymentMethod == 'transfer',
                              onTap: () {
                                setState(() => _paymentMethod = 'transfer');
                                // Open link + upload receipt right away for transfer.
                                _openTransferProofDialog();
                              }),
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
    // Step 1: confirm shipping/contact data after pressing order.
    final ok = await _editShippingInfo();
    if (!ok) return;

    // Step 2: validate transfer receipt if needed.
    if (_paymentMethod == 'transfer' && (_transferProofUrl == null || _transferProofUrl!.isEmpty)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('من فضلك ارفع صورة إيصال التحويل أولاً'), backgroundColor: AppColors.error),
        );
      }
      // Force user to upload receipt flow.
      await _openTransferProofDialog();
      return;
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
        if (_transferProofUrl != null && _transferProofUrl!.isNotEmpty) 'paymentProofUrl': _transferProofUrl,
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

  Future<void> _openTransferProofDialog() async {
    if (!mounted) return;
    // Open Instapay link
    try {
      final uri = Uri.parse(_instapayUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {}

    final picker = ImagePicker();
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppThemeDecorations.cardColor(context),
        title: const Text('تحويل بنكي - رفع إيصال', style: TextStyle(color: AppColors.text)),
        content: StatefulBuilder(
          builder: (ctx2, setModalState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('اضغط على InstaPay للتحويل ثم ارفع صورة الإيصال هنا.', style: TextStyle(color: AppColors.muted)),
                const SizedBox(height: 12),
                if (_transferProofUrl != null && _transferProofUrl!.isNotEmpty)
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    clipBehavior: Clip.hardEdge,
                    child: Image.network(ApiService.proxyImageUrl(_transferProofUrl!), fit: BoxFit.cover),
                  ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _uploadingProof
                      ? null
                      : () async {
                          setModalState(() => _uploadingProof = true);
                          try {
                            final xfile = await picker.pickImage(source: ImageSource.gallery, imageQuality: 80);
                            if (xfile == null) {
                              setModalState(() => _uploadingProof = false);
                              return;
                            }
                            final bytes = await xfile.readAsBytes();
                            final url = await ApiService.uploadFile(
                              xfile.path,
                              bytes: bytes,
                              filename: xfile.name,
                            );
                            setState(() => _transferProofUrl = url);
                            setModalState(() => _uploadingProof = false);
                            if (ctx.mounted) {
                              Navigator.pop(ctx, url);
                            }
                          } catch (e) {
                            setModalState(() => _uploadingProof = false);
                          }
                        },
                  icon: _uploadingProof
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.upload_file),
                  label: Text(_uploadingProof ? 'جاري الرفع...' : 'رفع صورة التحويل', style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, _transferProofUrl),
                  child: const Text('تم', style: TextStyle(color: AppColors.primary)),
                ),
              ],
            );
          },
        ),
      ),
    );

    if (result != null && result.isNotEmpty) {
      setState(() => _transferProofUrl = result);
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
