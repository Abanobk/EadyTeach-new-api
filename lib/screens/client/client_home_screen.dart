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

  @override
  void initState() {
    super.initState();
    _loadData();
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
    } catch (e) {
      setState(() => _loading = false);
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
        backgroundColor: AppColors.bg,
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
          backgroundColor: AppColors.card,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: AppColors.muted,
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
    );
  }

  Widget _buildStore(CartProvider cart) {
    return CustomScrollView(
      slivers: [
        // AppBar
        SliverAppBar(
          floating: true,
          snap: true,
          backgroundColor: AppColors.card,
          elevation: 1,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new, color: AppColors.primary, size: 20),
            onPressed: () => Navigator.pushReplacementNamed(context, '/role-select'),
          ),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Center(
                  child: Text('ET',
                      style: TextStyle(
                          color: Colors.black,
                          fontSize: 12,
                          fontWeight: FontWeight.w900)),
                ),
              ),
              const SizedBox(width: 10),
              Text(_companyName,
                  style: const TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.bold,
                      fontSize: 17)),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout, color: AppColors.muted),
              onPressed: () async {
                await context.read<AuthProvider>().logout();
                if (mounted) {
                  Navigator.pushReplacementNamed(context, '/login');
                }
              },
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(56),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                onChanged: (v) => setState(() => _search = v),
                decoration: InputDecoration(
                  hintText: 'ابحث عن منتج...',
                  prefixIcon: const Icon(Icons.search, color: AppColors.muted),
                  contentPadding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  filled: true,
                  fillColor: AppColors.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(25),
                    borderSide: BorderSide.none,
                  ),
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
                  const Text('الفئات',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.bold,
                          fontSize: 18)),
                  if (_selectedCategory != null)
                    TextButton(
                      onPressed: () => setState(() => _selectedCategory = null),
                      child: const Text('الكل',
                          style: TextStyle(color: AppColors.primary)),
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
                    height: 20,
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('المنتجات',
                      style: TextStyle(
                          color: AppColors.text,
                          fontWeight: FontWeight.bold,
                          fontSize: 18)),
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
                style: const TextStyle(
                    color: AppColors.text,
                    fontWeight: FontWeight.bold,
                    fontSize: 16),
              ),
            ),
          ),

        // Products Grid
        if (_loading)
          const SliverFillRemaining(
            child: Center(
                child: CircularProgressIndicator(color: AppColors.primary)),
          )
        else if (_filteredProducts.isEmpty)
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.inventory_2_outlined,
                      size: 64, color: AppColors.muted),
                  const SizedBox(height: 16),
                  const Text('لا توجد منتجات',
                      style: TextStyle(color: AppColors.muted, fontSize: 18)),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: _loadData,
                    icon: const Icon(Icons.refresh, color: AppColors.primary),
                    label: const Text('تحديث',
                        style: TextStyle(color: AppColors.primary)),
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (ctx, i) => _ProductCard(
                  product: _filteredProducts[i],
                  onAddToCart: (item) {
                    cart.addItem(item);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('تمت إضافة ${item.name} للسلة'),
                        backgroundColor: AppColors.success,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          ProductDetailScreen(product: _filteredProducts[i]),
                    ),
                  ),
                ),
                childCount: _filteredProducts.length,
              ),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 0.72,
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
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1a1a2e), Color(0xFF16213e), Color(0xFF0f3460)],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
      ),
      child: Stack(
        children: [
          // Background pattern
          Positioned(
            right: -30,
            top: -30,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withOpacity(0.1),
              ),
            ),
          ),
          Positioned(
            left: -20,
            bottom: -20,
            child: Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withOpacity(0.08),
              ),
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.home_outlined,
                          color: Colors.black, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _companyName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                        const Text(
                          'Smart Home Solutions',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'تصفح المنتجات',
                    style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
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

// ─── Product Card ──────────────────────────────────────────────────────────────
class _ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final Function(CartItem) onAddToCart;
  final VoidCallback onTap;

  const _ProductCard(
      {required this.product,
      required this.onAddToCart,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final price =
        double.tryParse(product['price']?.toString() ?? '0') ?? 0;
    final originalPrice =
        double.tryParse(product['originalPrice']?.toString() ?? '0') ?? 0;
    final rawImage = product['mainImageUrl'] as String?;
    final image = (rawImage != null && rawImage.isNotEmpty)
        ? ApiService.proxyImageUrl(rawImage)
        : null;
    final name = product['nameAr'] ?? product['name'] ?? '';
    final hasDiscount = originalPrice > price && originalPrice > 0;
    final stock = product['stock'] as int? ?? 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(14)),
                    child: image != null && image.isNotEmpty
                        ? Image.network(image,
                            width: double.infinity,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => _placeholder())
                        : _placeholder(),
                  ),
                  // Sale badge
                  if (hasDiscount)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '-${((1 - price / originalPrice) * 100).toStringAsFixed(0)}%',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  // Out of stock
                  if (stock <= 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'نفذ',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Info
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 12),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${price.toStringAsFixed(0)} ج.م',
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 13),
                          ),
                          if (hasDiscount)
                            Text(
                              '${originalPrice.toStringAsFixed(0)} ج.م',
                              style: const TextStyle(
                                  color: AppColors.muted,
                                  fontSize: 10,
                                  decoration: TextDecoration.lineThrough),
                            ),
                        ],
                      ),
                      GestureDetector(
                        onTap: stock > 0
                            ? () => onAddToCart(CartItem(
                                  productId: product['id'],
                                  name: name,
                                  price: price,
                                  image: image,
                                ))
                            : null,
                        child: Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            color: stock > 0
                                ? AppColors.primary
                                : AppColors.muted,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(Icons.add,
                              color: Colors.black, size: 18),
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
    );
  }

  Widget _placeholder() {
    return Container(
      color: AppColors.border,
      child: const Center(
          child:
              Icon(Icons.image_outlined, color: AppColors.muted, size: 40)),
    );
  }
}
