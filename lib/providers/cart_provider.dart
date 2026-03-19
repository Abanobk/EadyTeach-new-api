import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CartItem {
  final int productId;
  final String name;
  final double price;
  final double? originalPrice;
  final String? image;
  final String? variant;
  int quantity;

  CartItem({
    required this.productId,
    required this.name,
    required this.price,
    this.originalPrice,
    this.image,
    this.variant,
    this.quantity = 1,
  });

  Map<String, dynamic> toJson() => {
        'productId': productId,
        'name': name,
        'price': price,
        'originalPrice': originalPrice,
        'image': image,
        'variant': variant,
        'quantity': quantity,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
        productId: json['productId'],
        name: json['name'],
        price: (json['price'] as num).toDouble(),
        originalPrice: json['originalPrice'] != null ? (json['originalPrice'] as num).toDouble() : null,
        image: json['image'],
        variant: json['variant'],
        quantity: json['quantity'] ?? 1,
      );
}

class CartProvider extends ChangeNotifier {
  List<CartItem> _items = [];

  List<CartItem> get items => _items;
  int get itemCount => _items.fold(0, (sum, i) => sum + i.quantity);
  double get total => _items.fold(0, (sum, i) => sum + i.price * i.quantity);

  Future<void> loadCart() async {
    final prefs = await SharedPreferences.getInstance();
    final data = prefs.getString('cart');
    if (data != null) {
      final List<dynamic> list = jsonDecode(data);
      _items = list.map((e) => CartItem.fromJson(e)).toList();
      notifyListeners();
    }
  }

  Future<void> _saveCart() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cart', jsonEncode(_items.map((e) => e.toJson()).toList()));
  }

  void addItem(CartItem item) {
    final idx = _items.indexWhere((e) => e.productId == item.productId);
    if (idx >= 0) {
      _items[idx].quantity += item.quantity;
    } else {
      _items.add(item);
    }
    _saveCart();
    notifyListeners();
  }

  void removeItem(int productId) {
    _items.removeWhere((e) => e.productId == productId);
    _saveCart();
    notifyListeners();
  }

  void updateQuantity(int productId, int qty) {
    final idx = _items.indexWhere((e) => e.productId == productId);
    if (idx >= 0) {
      if (qty <= 0) {
        _items.removeAt(idx);
      } else {
        _items[idx].quantity = qty;
      }
    }
    _saveCart();
    notifyListeners();
  }

  void incrementItem(int productId) {
    final idx = _items.indexWhere((e) => e.productId == productId);
    if (idx >= 0) {
      _items[idx].quantity++;
      _saveCart();
      notifyListeners();
    }
  }

  void decrementItem(int productId) {
    final idx = _items.indexWhere((e) => e.productId == productId);
    if (idx >= 0) {
      if (_items[idx].quantity <= 1) {
        _items.removeAt(idx);
      } else {
        _items[idx].quantity--;
      }
      _saveCart();
      notifyListeners();
    }
  }

  void clear() {
    _items = [];
    _saveCart();
    notifyListeners();
  }
}
