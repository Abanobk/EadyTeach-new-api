/// نفس منطق المسح (survey wizard): طول فعلي بالسم → طول تجاري بالمتر للتسعير.
double curtainCommercialMetersFromCm(double lengthCm) {
  if (lengthCm <= 0) return 0;
  final lengthM = lengthCm / 100.0;
  final base = lengthM.floorToDouble();
  final frac = lengthM - base;
  if (frac == 0) {
    return lengthM;
  }
  if (frac <= 0.5) {
    return base + 0.5;
  }
  return base + 1.0;
}
