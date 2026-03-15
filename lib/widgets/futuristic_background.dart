import 'package:flutter/material.dart';

/// خلفية مستقبلية موحدة لجميع الصفحات: زجاجية، دوائر إلكترونية، توهج أزرق/برتقالي
class FuturisticBackground extends StatelessWidget {
  const FuturisticBackground({super.key});

  static const String _assetPath = 'assets/images/bg_futuristic.png';

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          image: DecorationImage(
            image: AssetImage(_assetPath),
            fit: BoxFit.cover,
            onError: (_, __) {},
          ),
        ),
      ),
    );
  }
}
