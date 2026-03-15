import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/cart_provider.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
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
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _errorMessage = null;
    });
    try {
      final productsRes = await ApiService.query('products.list');
      final categoriesRes = await ApiService.query('categories.list');
      final settingsRes = await ApiService.query('storeSettings.get');
      if (!mounted) return;
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
        _errorMessage = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _errorMessage = e is Exception ? e.toString().replaceFirst('Exception: ', '') : e.toString();
      });
    }
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

    final screens = [
      _buildStore(cart),
      const ServiceRequestScreen(),
      const MyTasksScreen(),
      const CartScreen(),
      const ClientOrdersScreen(),
      const ClientQuotationsScreen(),
      const ClientProfileScreen(),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: Container(
          decoration: AppThemeDecorations.gradientBackground(context),
          child: screens[_selectedIndex],
        ),
        floatingActionButton: _selectedIndex == 0
            ? Padding(
                padding: const EdgeInsets.only(bottom: 72, right: 20),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => setState(() => _selectedIndex = 1),
                    borderRadius: BorderRadius.circular(16),
                    child: Ink(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: AppThemeDecorations.primaryButtonGradient,
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.4),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.miscellaneous_services, color: Colors.white, size: 22),
                            SizedBox(width: 10),
                            Text(
                              'طلب خدمة',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              )
            : null,
        floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
        bottomNavigationBar: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withOpacity(0.95),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Theme.of(context).colorScheme.outline),
              ),
              child: BottomNavigationBar(
                currentIndex: _selectedIndex,
                onTap: (i) => setState(() => _selectedIndex = i),
                type: BottomNavigationBarType.fixed,
                backgroundColor: Colors.transparent,
                elevation: 0,
                selectedItemColor: Theme.of(context).colorScheme.primary,
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
              ),
            ),
      ),
    );
  }

  Widget _buildStore(CartProvider cart) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(
          floating: true,
          snap: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_ios_new, color: Theme.of(context).colorScheme.primary, size: 20),
            onPressed: () => Navigator.pushReplacementNamed(context, '/role-select'),
          ),
          title: Row(
            children: [
              ThemeToggleLogo(size: 38),
              const SizedBox(width: 10),
              Text(
                _companyName,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: Icon(Icons.logout, color: Theme.of(context).colorScheme.onSurfaceVariant),
              onPressed: () async {
                await context.read<AuthProvider>().logout();
                if (mounted) Navigator.pushReplacementNamed(context, '/login');
              },
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                onChanged: (v) => setState(() => _search = v),
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
                decoration: appThemeInputDecoration(
                  context,
                  hintText: 'ابحث عن منتج...',
                  prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
            ),
          ),
        ),

        // Banner (مثل stacksmarket)
        if (_showBanner)
          SliverToBoxAdapter(
            child: _buildBanner(),
          ),

        // Categories Grid (مثل stacksmarket - شبكة ملونة)
        if (_showCategories && _categories.isNotEmpty && _search.isEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'الفئات',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                  if (_selectedCategory != null)
                    TextButton(
                      onPressed: () => setState(() => _selectedCategory = null),
                      child: Text('الكل', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 120,
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
                      _selectedCategory =
                          isSelected ? null : cat['id'].toString();
                    }),
                  );
                },
              ),
            ),
          ),
        ],

        // Popular Products title
        if (_search.isEmpty && _selectedCategory == null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'المنتجات',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
              child: Text(
                _search.isNotEmpty
                    ? 'نتائج البحث (${_filteredProducts.length})'
                    : 'المنتجات (${_filteredProducts.length})',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ),
          ),

        // Products Grid
        if (_loading)
          SliverFillRemaining(
            child: Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary)),
          )
        else if (_errorMessage != null)
          SliverFillRemaining(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.cloud_off, size: 64, color: Theme.of(context).colorScheme.error),
                    const SizedBox(height: 16),
                    Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontSize: 16),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _loadData,
                      icon: const Icon(Icons.refresh),
                      label: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            ),
          )
        else if (_filteredProducts.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.inventory_2_outlined, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(height: 16),
                  Text('لا توجد منتجات', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 18)),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _loadData,
                    icon: Icon(Icons.refresh, color: Theme.of(context).colorScheme.primary),
                    label: Text('تحديث', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _ProductShowcaseCard(
                  product: _filteredProducts[i],
                  onAddToCart: (item) {
                    cart.addItem(item);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('تمت إضافة ${item.name} للسلة'),
                        backgroundColor: AppThemeColors.success,
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
                childAspectRatio: 0.62,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildBanner() {
    if (_bannerImageUrl.isNotEmpty) {
      return Container(
        margin: const EdgeInsets.fromLTRB(0, 0, 0, 0),
        height: 180,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              _bannerImageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildDefaultBanner(),
            ),
            // Gradient overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.black.withOpacity(0.5),
                    Colors.transparent,
                  ],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
              ),
            ),
            if (_bannerTitle.isNotEmpty)
              Positioned(
                bottom: 16,
                right: 16,
                child: Text(
                  _bannerTitle,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    shadows: [Shadow(color: Colors.black, blurRadius: 4)],
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return _buildDefaultBanner();
  }

  Widget _buildDefaultBanner() {
    return Container(
      height: 180,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: AppThemeDecorations.loginStyleCard(context, 24),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.home_rounded, color: Theme.of(context).colorScheme.primary, size: 26),
                ),
                const SizedBox(width: 14),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_companyName, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w800, fontSize: 20)),
                    Text('Smart Home Solutions', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                gradient: AppThemeDecorations.primaryButtonGradient,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text('تصفح المنتجات', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ],
        ),
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 90,
        margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? color : color.withOpacity(0.85),
          borderRadius: BorderRadius.circular(14),
          border: isSelected
              ? Border.all(color: Colors.white, width: 2.5)
              : null,
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.4),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // صورة الفئة أو أيقونة افتراضية
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: imageUrl != null && imageUrl!.isNotEmpty
                  ? Image.network(
                      imageUrl!,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _defaultIcon(),
                    )
                  : _defaultIcon(),
            ),
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                name,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _defaultIcon() {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Icon(Icons.category_outlined, color: Colors.white, size: 26),
    );
  }
}

// ─── Product Showcase Card (Glassmorphism, 20px, large image) ─────────────────
class _ProductShowcaseCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final Function(CartItem) onAddToCart;
  final VoidCallback onTap;

  const _ProductShowcaseCard({
    required this.product,
    required this.onAddToCart,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final price = double.tryParse(product['price']?.toString() ?? '0') ?? 0;
    final originalPrice = double.tryParse(product['originalPrice']?.toString() ?? '0') ?? 0;
    final rawImage = product['mainImageUrl'] as String?;
    final image = (rawImage != null && rawImage.isNotEmpty) ? ApiService.proxyImageUrl(rawImage) : null;
    final name = product['nameAr'] ?? product['name'] ?? '';
    final hasDiscount = originalPrice > price && originalPrice > 0;
    final stock = product['stock'] as int? ?? 0;

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.95),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Theme.of(context).colorScheme.outline),
              boxShadow: [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                  spreadRadius: -2,
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 3,
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                        child: image != null && image.isNotEmpty
                            ? Image.network(image, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _placeholder(context))
                            : _placeholder(context),
                      ),
                      if (hasDiscount)
                        Positioned(
                          top: 10,
                          left: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary, borderRadius: BorderRadius.circular(8)),
                            child: Text('-${((1 - price / originalPrice) * 100).toStringAsFixed(0)}%', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
                          ),
                        ),
                      if (stock <= 0)
                        Positioned(
                          top: 10,
                          right: 10,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                            decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(8)),
                            child: const Text('نفذ', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700)),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.w600, fontSize: 13), maxLines: 2, overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${price.toStringAsFixed(0)} ج.م', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w700, fontSize: 14)),
                              if (hasDiscount) Text('${originalPrice.toStringAsFixed(0)} ج.م', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 10, decoration: TextDecoration.lineThrough)),
                            ],
                          ),
                          GestureDetector(
                            onTap: stock > 0 ? () => onAddToCart(CartItem(productId: product['id'], name: name, price: price, image: image)) : null,
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: stock > 0 ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurfaceVariant,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.add, color: Colors.white, size: 20),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _placeholder(BuildContext context) {
    return Container(
      color: const Color(0xFFE0E4E8),
      child: Center(child: Icon(Icons.image_outlined, color: Theme.of(context).colorScheme.onSurfaceVariant, size: 44)),
    );
  }
}
