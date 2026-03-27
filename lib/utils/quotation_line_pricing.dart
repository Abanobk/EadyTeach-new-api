import 'dart:convert' show jsonDecode;

/// يفكّ `configuration` من بند العرض (Map أو JSON نصي).
Map<String, dynamic>? parseQuotationItemConfiguration(dynamic raw) {
  if (raw == null) return null;
  if (raw is Map) return Map<String, dynamic>.from(raw);
  if (raw is String && raw.trim().isNotEmpty) {
    try {
      final d = jsonDecode(raw);
      if (d is Map) return Map<String, dynamic>.from(d);
    } catch (_) {}
  }
  return null;
}

/// عروض قديمة: السيرفر كان يخزن سعر شراء التاجر في `unitPrice` بينما `officialUnitPrice` هو سعر العرض للعميل.
bool quotationPdfItemLooksLikeDealerPriceInClientSlot(Map<String, dynamic> item) {
  final up = double.tryParse(item['unitPrice']?.toString() ?? '0') ?? 0;
  final official = double.tryParse(item['officialUnitPrice']?.toString() ?? '0') ?? 0;
  final dealer = double.tryParse(item['dealerUnitPrice']?.toString() ?? '0') ?? 0;
  if (official <= 0 || dealer <= 0) return false;
  if (official <= up + 0.01) return false;
  return (up - dealer).abs() < 0.02;
}

double quotationPdfClientUnitPriceForItem(Map<String, dynamic> item) {
  final up = double.tryParse(item['unitPrice']?.toString() ?? '0') ?? 0;
  if (quotationPdfItemLooksLikeDealerPriceInClientSlot(item)) {
    final official = double.tryParse(item['officialUnitPrice']?.toString() ?? '0') ?? 0;
    if (official > 0) return official;
  }
  return up;
}

/// إجمالي الأمتار التجارية للبند: متر تجاري لمسار واحد × عدد المسارات (الكمية).
double? quotationCurtainCommercialMetersForLine(Map<String, dynamic> item) {
  final cfg = parseQuotationItemConfiguration(item['configuration']);
  if (cfg == null || cfg['pricingMode']?.toString() != 'curtain_per_meter') return null;
  final commRaw = cfg['curtainCommercialM'];
  double? comm;
  if (commRaw is num) {
    comm = commRaw.toDouble();
  } else {
    comm = double.tryParse(commRaw?.toString() ?? '');
  }
  if (comm == null || comm <= 0) return null;
  final qty = int.tryParse(item['qty']?.toString() ?? item['quantity']?.toString() ?? '1') ?? 1;
  return comm * qty;
}

/// إجمالي سطر البيع للعميل: للمسار بالمتر = سعر/م × إجمالي أمتار تجارية؛ غير ذلك = سعر الوحدة × الكمية.
double quotationPdfClientLineAmount(Map<String, dynamic> item) {
  final unit = quotationPdfClientUnitPriceForItem(item);
  final qty = int.tryParse(item['qty']?.toString() ?? item['quantity']?.toString() ?? '1') ?? 1;
  final meters = quotationCurtainCommercialMetersForLine(item);
  if (meters != null) return unit * meters;
  return unit * qty;
}
