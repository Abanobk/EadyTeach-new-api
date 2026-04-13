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
  bool _openedInstapayThisSession = false;
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
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    final cart = context.watch<CartProvider>();
    final itemCount = cart.items.fold<int>(0, (s, i) => s + i.quantity);

    if (_lastItemsLen != cart.items.length) {
      _lastItemsLen = cart.items.length;
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
        automaticallyImplyLeading: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 16,
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: AppThemeDecorations.glassCard(context, radius: 16),
              child: const Icon(Icons.shopping_bag_rounded, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('السلة', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  Text(
                    'مراجعة الطلب قبل الإتمام',
                    style: theme.textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: cart.items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(28),
                  decoration: AppThemeDecorations.loginStyleCard(context, 28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 88,
                        height: 88,
                        decoration: BoxDecoration(
                          gradient: AppThemeDecorations.primaryButtonGradient,
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: const Icon(Icons.shopping_cart_checkout_rounded, color: Colors.white, size: 40),
                      ),
                      const SizedBox(height: 20),
                      Text('السلة فارغة حالياً', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 10),
                      Text(
                        'ابدأ بإضافة المنتجات التي تعجبك لتظهر هنا داخل تجربة شراء أكثر ترتيبًا وأناقة.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: c.onSurfaceVariant, height: 1.6),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    controller: _itemsScrollController,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(28),
                            gradient: const LinearGradient(
                              begin: Alignment.topRight,
                              end: Alignment.bottomLeft,
                              colors: [Color(0xFF0F172A), Color(0xFF17345F), Color(0xFFF59E0B)],
                            ),
                            boxShadow: theme.brightness == Brightness.dark
                                ? []
                                : [
                                    BoxShadow(
                                      color: const Color(0xFF0F172A).withOpacity(0.12),
                                      blurRadius: 30,
                                      spreadRadius: -10,
                                      offset: const Offset(0, 20),
                                    ),
                                  ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: const Text(
                                  'ملخص سريع',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                                ),
                              ),
                              const SizedBox(height: 18),
                              const Text(
                                'تجربة طلب أكثر وضوحًا وأناقة',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 24, height: 1.2),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'راجع منتجاتك، اختر طريقة الدفع المناسبة، ثم أكمل الطلب في واجهة مرتبة وسهلة.',
                                style: TextStyle(color: Colors.white.withOpacity(0.84), height: 1.6),
                              ),
                              const SizedBox(height: 18),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  _CartSummaryPill(icon: Icons.inventory_2_rounded, label: '$itemCount قطعة'),
                                  _CartSummaryPill(icon: Icons.sell_rounded, label: '${cart.items.length} منتج'),
                                  _CartSummaryPill(icon: Icons.payments_rounded, label: '${cart.total.toStringAsFixed(2)} ج.م'),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text('العناصر المضافة', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Text(
                          'تم ترتيب البطاقات بشكل أوضح لتسهيل مراجعة السعر والكمية والخصم.',
                          style: theme.textTheme.bodyMedium?.copyWith(color: c.onSurfaceVariant),
                        ),
                        const SizedBox(height: 14),
                        ...List.generate(cart.items.length, (idx) {
                          final item = cart.items[idx];
                          final hasOriginal = item.originalPrice != null && item.originalPrice! > item.price;
                          final lineTotal = item.price * item.quantity;

                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(14),
                            decoration: AppThemeDecorations.loginStyleCard(context, 24),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 92,
                                  height: 92,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(22),
                                    border: Border.all(color: c.outline.withOpacity(0.45)),
                                  ),
                                  clipBehavior: Clip.hardEdge,
                                  child: item.image != null && item.image!.isNotEmpty
                                      ? Image.network(
                                          ApiService.proxyImageUrl(item.image!),
                                          fit: BoxFit.cover,
                                          errorBuilder: (_, __, ___) => _imgPlaceholder(context),
                                        )
                                      : _imgPlaceholder(context),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, height: 1.35),
                                      ),
                                      if (item.variant != null && item.variant!.trim().isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: c.secondary.withOpacity(0.12),
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                          child: Text(
                                            item.variant!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(color: c.secondary, fontWeight: FontWeight.w700, fontSize: 11),
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 10),
                                      _CartLine(label: 'سعر القطعة', value: '${item.price.toStringAsFixed(2)} ج.م', emphasize: true),
                                      if (hasOriginal)
                                        _CartLine(
                                          label: 'قبل الخصم',
                                          value: '${item.originalPrice!.toStringAsFixed(2)} ج.م',
                                          struck: true,
                                        ),
                                      _CartLine(label: 'الإجمالي', value: '${lineTotal.toStringAsFixed(2)} ج.م'),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  width: 56,
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                  decoration: BoxDecoration(
                                    color: c.surfaceContainerHighest.withOpacity(0.55),
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  child: Column(
                                    children: [
                                      IconButton(
                                        icon: const Icon(Icons.add_circle_rounded, color: AppColors.primary, size: 24),
                                        onPressed: () => cart.incrementItem(item.productId),
                                      ),
                                      Text(
                                        '${item.quantity}',
                                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.remove_circle_rounded, color: c.onSurfaceVariant, size: 24),
                                        onPressed: () => cart.decrementItem(item.productId),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  padding: const EdgeInsets.all(18),
                  decoration: AppThemeDecorations.loginStyleCard(context, 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text('ملخص الدفع', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                          ),
                          if (_paymentMethod == 'transfer' && _transferProofUrl != null && _transferProofUrl!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFDCFCE7),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: const Text(
                                'الإيصال مرفوع',
                                style: TextStyle(color: Color(0xFF166534), fontWeight: FontWeight.w700, fontSize: 11),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _loadingProfile
                            ? 'جاري تحميل بيانات التوصيل...' : 'الاسم: ${_shippingName?.isNotEmpty == true ? _shippingName : 'لم يتم إدخاله بعد'}',
                        style: theme.textTheme.bodyMedium?.copyWith(color: c.onSurfaceVariant),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          _PaymentBtn(
                            label: 'كاش',
                            icon: Icons.money_rounded,
                            selected: _paymentMethod == 'cash',
                            onTap: () => setState(() => _paymentMethod = 'cash'),
                          ),
                          _PaymentBtn(
                            label: 'فيزا',
                            icon: Icons.credit_card_rounded,
                            selected: _paymentMethod == 'visa',
                            onTap: () => setState(() => _paymentMethod = 'visa'),
                          ),
                          _PaymentBtn(
                            label: 'Apple Pay',
                            icon: Icons.apple_rounded,
                            selected: _paymentMethod == 'apple_pay',
                            onTap: () => setState(() => _paymentMethod = 'apple_pay'),
                          ),
                          _PaymentBtn(
                            label: 'تحويل',
                            icon: Icons.account_balance_wallet_rounded,
                            selected: _paymentMethod == 'transfer',
                            onTap: () {
                              setState(() => _paymentMethod = 'transfer');
                              _openTransferProofDialog();
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: c.surfaceContainerHighest.withOpacity(0.42),
                          borderRadius: BorderRadius.circular(22),
                        ),
                        child: Column(
                          children: [
                            _CartLine(label: 'عدد القطع', value: '$itemCount'),
                            const SizedBox(height: 10),
                            _CartLine(label: 'عدد المنتجات', value: '${cart.items.length}'),
                            const SizedBox(height: 10),
                            _CartLine(label: 'طريقة الدفع', value: _paymentMethod == 'cash' ? 'كاش عند الاستلام' : _paymentMethod == 'visa' ? 'بطاقة' : _paymentMethod == 'apple_pay' ? 'Apple Pay' : 'تحويل بنكي'),
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 14),
                              child: Divider(height: 1),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('الإجمالي النهائي', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                                Text(
                                  '${cart.total.toStringAsFixed(2)} ج.م',
                                  style: theme.textTheme.titleLarge?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w900),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _submitting ? null : () => _placeOrder(cart),
                          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
                          child: _submitting
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                                )
                              : Text(
                                  'إتمام الطلب — ${cart.total.toStringAsFixed(2)} ج.م',
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
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
                if (i.name.isNotEmpty) 'name': i.name,
                if (i.variant != null && i.variant!.trim().isNotEmpty)
                  'variant': i.variant!.trim(),
                if (i.configuration != null && i.configuration!.isNotEmpty)
                  'configuration': i.configuration,
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
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        final uri = Uri.parse(_instapayUrl);
                        if (await canLaunchUrl(uri)) {
                          await launchUrl(uri, mode: LaunchMode.externalApplication);
                          _openedInstapayThisSession = true;
                        }
                      } catch (_) {}
                    },
                    icon: const Icon(Icons.open_in_new, color: AppColors.primary),
                    label: const Text('فتح InstaPay', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 10),
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
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('فشل رفع صورة التحويل: $e'), backgroundColor: AppColors.error),
                              );
                            }
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

  Widget _imgPlaceholder(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [c.surfaceContainerHighest, c.surface],
        ),
      ),
      child: Center(
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.55),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.image_outlined, color: c.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _CartSummaryPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _CartSummaryPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _CartLine extends StatelessWidget {
  final String label;
  final String value;
  final bool emphasize;
  final bool struck;

  const _CartLine({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.struck = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: theme.textTheme.bodySmall?.copyWith(color: c.onSurfaceVariant)),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: emphasize ? AppColors.primary : c.onSurface,
            fontWeight: emphasize ? FontWeight.w800 : FontWeight.w700,
            decoration: struck ? TextDecoration.lineThrough : TextDecoration.none,
          ),
        ),
      ],
    );
  }
}

class _PaymentBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _PaymentBtn({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: selected ? AppThemeDecorations.primaryButtonGradient : null,
            color: selected ? null : c.surfaceContainerHighest.withOpacity(0.45),
            border: Border.all(
              color: selected ? Colors.transparent : c.outline.withOpacity(0.45),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: selected ? Colors.white : c.onSurfaceVariant, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : c.onSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
