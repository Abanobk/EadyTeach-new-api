import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../services/api_service.dart';
import '../../utils/app_theme.dart';
import 'product_detail_screen.dart';
import 'cart_screen.dart';
import 'orders_screen.dart';
import 'profile_screen.dart';
import 'my_tasks_screen.dart';
import 'service_request_screen.dart';
import 'client_quotations_screen.dart';

// ألوان الفئات (مثل stacksmarket)
const List<Color> _catColors = [
  Color(0xFFE74C3C), // أحمر - Security Cam
  Color(0xFFF39C12), // برتقالي - Smart Lighting
  Color(0xFF27AE60), // أخضر - Smart Lock
  Color(0xFF2980B9), // أزرق - Smart Remote
  Color(0xFF8E44AD), // بنفسجي - Touch Screen
  Color(0xFF16A085), // تركواز - Voice Assistant
  Color(0xFFE67E22), // برتقالي داكن - Sale
  Color(0xFF2C3E50), // كحلي - Sensor
  Color(0xFF7F8C8D), // رمادي - HUBS
  Color(0xFFD35400), // بني - Security
];

class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  int _selectedIndex = 0;
  List<dynamic> _products = [];
  List<dynamic> _categories = [];
  Map<String, dynamic>? _storeSettings;
  String? _selectedCategory;
  bool _loading = true;
  String _search = '';
  bool _didSyncConfirmedPreorders = false;
  int? _pendingOpenProductId;
  bool _didAttemptPendingProductOpen = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pendingOpenProductId != null) return;
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      final pid = int.tryParse(args['productId']?.toString() ?? '');
      if (pid != null && pid > 0) {
        _pendingOpenProductId = pid;
      }
    }
  }

  Map<int, Map<String, dynamic>> _productsById() {
    final map = <int, Map<String, dynamic>>{};
    for (final p in _products) {
      if (p is! Map) continue;
      final id = int.tryParse(p['id']?.toString() ?? '') ??
          int.tryParse(p['productId']?.toString() ?? '');
      if (id == null || id <= 0) continue;
      map[id] = Map<String, dynamic>.from(p);
    }
    return map;
  }

  String? _pickProductImageUrl(Map<String, dynamic>? p) {
    if (p == null) return null;
    final direct = (p['imageUrl'] ?? p['mainImageUrl'] ?? p['main_image_url'] ?? p['image'] ?? p['image_url'])?.toString();
    if (direct != null && direct.trim().isNotEmpty) return direct.trim();
    final imgs = p['images'];
    if (imgs is List && imgs.isNotEmpty) {
      final first = imgs.first?.toString();
      if (first != null && first.trim().isNotEmpty) return first.trim();
    }
    return null;
  }

  Future<void> _syncConfirmedPreordersToCartIfNeeded() async {
    if (_didSyncConfirmedPreorders) return;
    _didSyncConfirmedPreorders = true;
    try {
      final res = await ApiService.query('orders.getPendingCartSync');
      final data = res['data'];
      if (data is! List || data.isEmpty) return;

      final cart = context.read<CartProvider>();
      await cart.loadCart();

      final byId = _productsById();
      for (final row in data) {
        if (row is! Map) continue;
        final items = row['items'];
        if (items is! List) continue;
        for (final it in items) {
          if (it is! Map) continue;
          final pid = int.tryParse(it['productId']?.toString() ?? '') ?? 0;
          if (pid <= 0) continue;
          final qty = int.tryParse(it['quantity']?.toString() ?? '') ?? 1;
          final unit = double.tryParse(it['unitPrice']?.toString() ?? '') ?? 0.0;

          final p = byId[pid];
          final name = (p?['nameAr'] ?? p?['name'] ?? 'منتج').toString();
          final image = _pickProductImageUrl(p);
          cart.addItem(CartItem(productId: pid, name: name, image: image, price: unit, quantity: qty));
        }
        final orderId = row['orderId'];
        await ApiService.mutate('orders.markCartSynced', input: {'orderId': orderId});
      }
    } catch (_) {
      // ignore - sync is best-effort
    }
  }

  Future<void> _loadData() async {
    setState(() => _loading = true);
    try {
      final productsRes = await ApiService.query('products.list');
      final categoriesRes = await ApiService.query('categories.list');
      final settingsRes = await ApiService.query('storeSettings.get');
      setState(() {
        final rawSettings = settingsRes['data'] ?? settingsRes;
        if (rawSettings is Map) {
          _storeSettings = Map<String, dynamic>.from(rawSettings);
        }
        final raw = productsRes['data'] ?? productsRes;
        if (raw is List) {
          _products = raw;
        } else if (raw is Map && raw.containsKey('items')) {
          _products = raw['items'] ?? [];
        } else {
          _products = [];
        }
        final rawCats = categoriesRes['data'] ?? categoriesRes;
        if (rawCats is List) {
          _categories = rawCats;
        } else {
          _categories = [];
        }
        _loading = false;
      });
      // After products are loaded, sync any confirmed preorder orders into cart (with images).
      await _syncConfirmedPreordersToCartIfNeeded();
      await _openPendingProductIfNeeded();
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _openPendingProductIfNeeded() async {
    if (!mounted || _didAttemptPendingProductOpen) return;
    final pid = _pendingOpenProductId;
    if (pid == null || pid <= 0) return;
    _didAttemptPendingProductOpen = true;

    Map<String, dynamic>? product;
    for (final raw in _products) {
      if (raw is! Map) continue;
      final id = int.tryParse(raw['id']?.toString() ?? raw['productId']?.toString() ?? '');
      if (id == pid) {
        product = Map<String, dynamic>.from(raw);
        break;
      }
    }

    if (product == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر العثور على المنتج المطلوب')), 
        );
      }
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ProductDetailScreen(product: product!)),
      );
      _pendingOpenProductId = null;
    });
  }

  String get _companyName =>
      _storeSettings?['companyNameAr'] ?? _storeSettings?['companyName'] ?? 'Easy Tech';
  String get _bannerTitle => _storeSettings?['bannerTitleAr'] ?? _storeSettings?['bannerTitle'] ?? '';
  String get _bannerImageUrl => _storeSettings?['bannerImageUrl'] ?? '';
  bool get _showBanner => _storeSettings?['showBanner'] != false;
  bool get _showCategories => _storeSettings?['showCategories'] != false;

  List<dynamic> get _filteredProducts {
    return _products.where((p) {
      final matchSearch = _search.isEmpty ||
          (p['name'] ?? '').toLowerCase().contains(_search.toLowerCase()) ||
          (p['nameAr'] ?? '').contains(_search);
      if (_selectedCategory == null) return matchSearch;
      final catId = p['categoryId']?.toString();
      final catIds = (p['categoryIds'] as List?)?.map((e) => e.toString()).toList() ?? [];
      return matchSearch && (catId == _selectedCategory || catIds.contains(_selectedCategory));
    }).toList();
  }

  List<dynamic> get _featuredProducts =>
      _products.where((p) => p['isFeatured'] == true).take(6).toList();

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartProvider>();
    final auth = context.watch<AuthProvider>();
    final canViewQuotations = auth.hasPermission('quotations.view');

    final screens = <Widget>[
      _buildStore(cart),
      const ServiceRequestScreen(),
      const MyTasksScreen(),
      const CartScreen(),
      const ClientOrdersScreen(),
      if (canViewQuotations) const ClientQuotationsScreen(),
      const ClientProfileScreen(),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        // خلي الخلفية تعتمد على الثيم (فاتح/غامق)
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: screens[_selectedIndex],
          ),
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (i) => setState(() => _selectedIndex = i),
          type: BottomNavigationBarType.fixed,
          backgroundColor: Theme.of(context).colorScheme.surface,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: Theme.of(context).colorScheme.onSurfaceVariant,
          selectedFontSize: 11,
          unselectedFontSize: 10,
          items: [
            const BottomNavigationBarItem(
              icon: Icon(Icons.store_outlined),
              activeIcon: Icon(Icons.store),
              label: 'المتجر',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.miscellaneous_services_outlined),
              activeIcon: Icon(Icons.miscellaneous_services),
              label: 'طلب خدمة',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.assignment_outlined),
              activeIcon: Icon(Icons.assignment),
              label: 'مهامي',
            ),
            BottomNavigationBarItem(
              icon: Badge(
                label: Text('${cart.itemCount}'),
                isLabelVisible: cart.itemCount > 0,
                child: const Icon(Icons.shopping_cart_outlined),
              ),
              activeIcon: Badge(
                label: Text('${cart.itemCount}'),
                isLabelVisible: cart.itemCount > 0,
                child: const Icon(Icons.shopping_cart),
              ),
              label: 'السلة',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.receipt_long_outlined),
              activeIcon: Icon(Icons.receipt_long),
              label: 'طلباتي',
            ),
            if (canViewQuotations)
              const BottomNavigationBarItem(
                icon: Icon(Icons.request_quote_outlined),
                activeIcon: Icon(Icons.request_quote),
                label: 'عروض الأسعار',
              ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: 'بياناتي',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStore(CartProvider cart) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final featuredCount = _featuredProducts.length;

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverAppBar(
          floating: true,
          snap: true,
          pinned: true,
          backgroundColor: theme.scaffoldBackgroundColor.withOpacity(0.96),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leadingWidth: 72,
          leading: Padding(
            padding: const EdgeInsets.only(right: 16, top: 8, bottom: 8),
            child: Container(
              decoration: AppThemeDecorations.glassCard(context, radius: 18),
              child: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.primary, size: 20),
                onPressed: () {
                  final auth = context.read<AuthProvider>();
                  if (auth.canAccessAdmin) {
                    Navigator.pushReplacementNamed(context, '/role-select');
                    return;
                  }
                  Navigator.maybePop(context);
                },
              ),
            ),
          ),
          titleSpacing: 0,
          title: Row(
            children: [
              const EtLogo(size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _companyName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      'واجهة متجر أكثر ترتيبًا ووضوحًا',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Container(
                margin: const EdgeInsets.only(left: 8),
                decoration: AppThemeDecorations.glassCard(context, radius: 18),
                child: IconButton(
                  tooltip: 'Smart Home',
                  icon: const Icon(Icons.home_work_rounded, color: AppColors.primary),
                  onPressed: () => Navigator.of(context).pushNamed('/smart-home'),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
              child: Container(
                decoration: AppThemeDecorations.glassCard(context, radius: 18),
                child: IconButton(
                  icon: Icon(Icons.logout_rounded, color: colorScheme.onSurfaceVariant),
                  onPressed: () async {
                    await context.read<AuthProvider>().logout();
                    if (mounted) {
                      Navigator.pushReplacementNamed(context, '/login');
                    }
                  },
                ),
              ),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(84),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
              child: Container(
                decoration: AppThemeDecorations.loginStyleCard(context, 24),
                child: TextField(
                  onChanged: (v) => setState(() => _search = v),
                  decoration: InputDecoration(
                    hintText: 'ابحث عن منتج أو خدمة أو فئة...',
                    prefixIcon: Icon(Icons.search_rounded, color: colorScheme.secondary),
                    suffixIcon: _search.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () => setState(() => _search = ''),
                            icon: Icon(Icons.close_rounded, color: colorScheme.onSurfaceVariant),
                          ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: colorScheme.outline.withOpacity(0.5)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide(color: colorScheme.secondary, width: 1.4),
                    ),
                    filled: true,
                    fillColor: theme.brightness == Brightness.dark
                        ? colorScheme.surface.withOpacity(0.8)
                        : Colors.white.withOpacity(0.88),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (_showBanner)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _buildBanner(),
            ),
          ),
        if (_showCategories && _categories.isNotEmpty && _search.isEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: _StoreSectionHeader(
                title: 'الفئات',
                subtitle: 'تصنيف أسرع للمنتجات والخدمات حسب احتياجك',
                actionLabel: _selectedCategory != null ? 'عرض الكل' : null,
                onAction: _selectedCategory != null ? () => setState(() => _selectedCategory = null) : null,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 132,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: _categories.length,
                itemBuilder: (ctx, i) {
                  final cat = _categories[i];
                  final color = _catColors[i % _catColors.length];
                  final isSelected = _selectedCategory == cat['id'].toString();
                  final catImgRaw = cat['imageUrl'] as String?;
                  return _CategoryCard(
                    name: cat['nameAr'] ?? cat['name'] ?? '',
                    imageUrl: (catImgRaw != null && catImgRaw.isNotEmpty) ? ApiService.proxyImageUrl(catImgRaw) : null,
                    color: color,
                    isSelected: isSelected,
                    onTap: () => setState(() {
                      _selectedCategory = isSelected ? null : cat['id'].toString();
                    }),
                  );
                },
              ),
            ),
          ),
        ],
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
            child: _StoreSectionHeader(
              title: _search.isNotEmpty
                  ? 'نتائج البحث'
                  : _selectedCategory != null
                      ? 'المنتجات المختارة'
                      : 'المنتجات',
              subtitle: _search.isNotEmpty
                  ? 'تم العثور على ${_filteredProducts.length} نتيجة مطابقة'
                  : 'عرض مرتب وواضح مع بطاقات أحدث وتجربة شراء أسرع',
              actionLabel: _search.isEmpty && _selectedCategory == null && featuredCount > 0 ? '$featuredCount مميز' : null,
            ),
          ),
        ),
        if (_loading)
          const SliverFillRemaining(
            child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
          )
        else if (_filteredProducts.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 24),
                padding: const EdgeInsets.all(28),
                decoration: AppThemeDecorations.loginStyleCard(context, 28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 74,
                      height: 74,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: const Icon(Icons.inventory_2_outlined, size: 36, color: AppColors.primary),
                    ),
                    const SizedBox(height: 18),
                    Text('لا توجد منتجات مطابقة', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      'جرّب تعديل البحث أو تحديث البيانات لإظهار أحدث المنتجات داخل المتجر.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      onPressed: _loadData,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('تحديث البيانات'),
                    ),
                  ],
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _ProductCard(
                  product: _filteredProducts[i],
                  onAddToCart: (item) {
                    cart.addItem(item);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('تمت إضافة ${item.name} إلى السلة'),
                        backgroundColor: AppColors.success,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ProductDetailScreen(product: _filteredProducts[i]),
                    ),
                  ),
                ),
                childCount: _filteredProducts.length,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 0.66,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBanner() {
    final theme = Theme.of(context);
    final c = theme.colorScheme;

    return Container(
      height: 220,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        boxShadow: theme.brightness == Brightness.dark
            ? []
            : [
                BoxShadow(
                  color: const Color(0xFF0F172A).withOpacity(0.12),
                  blurRadius: 34,
                  spreadRadius: -10,
                  offset: const Offset(0, 24),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_bannerImageUrl.isNotEmpty)
              Image.network(
                _bannerImageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildDefaultBanner(),
              )
            else
              _buildDefaultBanner(),
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                  colors: [
                    const Color(0xFF0B1120).withOpacity(0.20),
                    const Color(0xFF0F172A).withOpacity(0.58),
                    const Color(0xFF111827).withOpacity(0.92),
                  ],
                ),
              ),
            ),
            Positioned(
              top: -36,
              left: -28,
              child: Container(
                width: 150,
                height: 150,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withOpacity(0.08),
                ),
              ),
            ),
            Positioned(
              bottom: -52,
              right: -18,
              child: Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withOpacity(0.14),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: const Text(
                      'تجربة متجر مطورة',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _bannerTitle.isNotEmpty ? _bannerTitle : 'حلول متكاملة للمنزل الذكي بتجربة أكثر فخامة',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'تصميم أحدث، بحث أسرع، وبطاقات أوضح تساعدك على الوصول للمنتج المناسب واتخاذ القرار بثقة.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.82),
                      fontSize: 14,
                      height: 1.6,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _SectionStatChip(label: _companyName, icon: Icons.storefront_rounded),
                      _SectionStatChip(label: '${_categories.length} فئة', icon: Icons.dashboard_customize_rounded),
                      _SectionStatChip(label: '${_products.length} منتج', icon: Icons.inventory_2_rounded),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultBanner() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF10213A), Color(0xFF17345F), Color(0xFFF59E0B)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
    );
  }
}

class _StoreSectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _StoreSectionHeader({
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 10,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: AppThemeDecorations.primaryButtonGradient,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: theme.textTheme.bodyMedium?.copyWith(color: c.onSurfaceVariant, height: 1.55),
              ),
            ],
          ),
        ),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            child: Text(
              actionLabel!,
              style: TextStyle(color: c.secondary, fontWeight: FontWeight.w700),
            ),
          ),
      ],
    );
  }
}

class _SectionStatChip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _SectionStatChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.white),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

// ─── Category Card (مثل stacksmarket) ─────────────────────────────────────────
class _CategoryCard extends StatelessWidget {
  final String name;
  final String? imageUrl;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _CategoryCard({
    required this.name,
    this.imageUrl,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(24),
          onTap: onTap,
          child: Ink(
            width: 112,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              gradient: LinearGradient(
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
                colors: [
                  color.withOpacity(isSelected ? 0.95 : 0.84),
                  color.withOpacity(isSelected ? 0.70 : 0.62),
                ],
              ),
              border: Border.all(
                color: isSelected ? Colors.white.withOpacity(0.95) : Colors.white.withOpacity(0.16),
                width: isSelected ? 2 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: color.withOpacity(0.28),
                  blurRadius: isSelected ? 18 : 12,
                  spreadRadius: -4,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: imageUrl != null && imageUrl!.isNotEmpty
                        ? Image.network(
                            imageUrl!,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _defaultIcon(),
                          )
                        : _defaultIcon(),
                  ),
                ),
                const Spacer(),
                Text(
                  name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isSelected ? 'مفعّلة الآن' : 'اضغط للتصفية',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.82),
                          fontSize: 10.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      isSelected ? Icons.check_circle_rounded : Icons.arrow_forward_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _defaultIcon() {
    return Container(
      color: Colors.white.withOpacity(0.14),
      child: const Icon(Icons.category_rounded, color: Colors.white, size: 26),
    );
  }
}

// ─── Product Card ──────────────────────────────────────────────────────────────
class _ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final Function(CartItem) onAddToCart;
  final VoidCallback onTap;

  const _ProductCard({
    required this.product,
    required this.onAddToCart,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = theme.colorScheme;
    final price = double.tryParse(product['price']?.toString() ?? '0') ?? 0;
    final originalPrice = double.tryParse(product['originalPrice']?.toString() ?? '0') ?? 0;
    final discountPercent = double.tryParse(product['discountPercent']?.toString() ?? '0') ?? 0;
    final rawImage = product['mainImageUrl'] as String?;
    final image = (rawImage != null && rawImage.isNotEmpty) ? ApiService.proxyImageUrl(rawImage) : null;
    final name = product['nameAr'] ?? product['name'] ?? '';
    final hasDiscount = (discountPercent > 0 && price > 0) || (originalPrice > price && originalPrice > 0);
    final stock = int.tryParse(product['stock']?.toString() ?? '') ?? 0;
    final category = (product['categoryNameAr'] ?? product['categoryName'] ?? 'منتج ذكي').toString();
    final effectiveDiscount = discountPercent > 0 && price > 0
        ? discountPercent.toStringAsFixed(0)
        : (originalPrice > 0 && price > 0)
            ? ((1 - price / originalPrice) * 100).toStringAsFixed(0)
            : '0';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: c.outline.withOpacity(0.55)),
            boxShadow: theme.brightness == Brightness.dark
                ? []
                : [
                    BoxShadow(
                      color: const Color(0xFF0F172A).withOpacity(0.08),
                      blurRadius: 22,
                      spreadRadius: -8,
                      offset: const Offset(0, 16),
                    ),
                  ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 1,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                        child: image != null && image.isNotEmpty
                            ? Image.network(
                                image,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => _placeholder(context),
                              )
                            : _placeholder(context),
                      ),
                    ),
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withOpacity(0.04),
                              Colors.black.withOpacity(0.22),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 12,
                      right: 12,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.88),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                    if (hasDiscount)
                      Positioned(
                        top: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFDC2626),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            '-$effectiveDiscount%',
                            style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800),
                          ),
                        ),
                      ),
                    if (stock <= 0)
                      Positioned(
                        bottom: 12,
                        left: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFF111827).withOpacity(0.88),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'غير متوفر',
                            style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(
                              color: c.onSurface,
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              height: 1.35,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _ProductMetaPill(
                            icon: Icons.verified_rounded,
                            label: stock > 0 ? 'جاهز للطلب' : 'نفد المخزون',
                            foreground: stock > 0 ? const Color(0xFF166534) : c.onSurfaceVariant,
                            background: stock > 0 ? const Color(0xFFDCFCE7) : c.surfaceContainerHighest,
                          ),
                          const SizedBox(width: 8),
                          _ProductMetaPill(
                            icon: Icons.local_shipping_rounded,
                            label: 'توصيل مرن',
                            foreground: c.secondary,
                            background: c.secondary.withOpacity(0.12),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (hasDiscount)
                                  Text(
                                    '${originalPrice.toStringAsFixed(0)} ج.م',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: c.onSurfaceVariant,
                                      decoration: TextDecoration.lineThrough,
                                      fontSize: 11,
                                    ),
                                  ),
                                Text(
                                  '${price.toStringAsFixed(0)} ج.م',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          InkWell(
                            onTap: stock > 0
                                ? () => onAddToCart(CartItem(
                                      productId: product['id'],
                                      name: name,
                                      price: price,
                                      originalPrice: hasDiscount ? originalPrice : null,
                                      image: image,
                                    ))
                                : null,
                            borderRadius: BorderRadius.circular(18),
                            child: Ink(
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                gradient: stock > 0 ? AppThemeDecorations.primaryButtonGradient : null,
                                color: stock > 0 ? null : c.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: Icon(
                                stock > 0 ? Icons.add_shopping_cart_rounded : Icons.remove_shopping_cart_rounded,
                                color: stock > 0 ? Colors.white : c.onSurfaceVariant,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    final c = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            c.surfaceContainerHighest,
            c.surface,
          ],
        ),
      ),
      child: Center(
        child: Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.55),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(Icons.image_outlined, color: c.onSurfaceVariant, size: 30),
        ),
      ),
    );
  }
}

class _ProductMetaPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;

  const _ProductMetaPill({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: foreground),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(color: foreground, fontSize: 10.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}
