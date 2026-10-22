/// Счётчики libbox возвращают байты в секунду; интерфейс показывает биты.
String trafficSpeed(int bytesPerSecond) {
  final bits = bytesPerSecond.clamp(0, 1 << 62) * 8;
  if (bits >= 1000000000) {
    return '${(bits / 1000000000).toStringAsFixed(1)} Гбит/с';
  }
  if (bits >= 1000000) return '${(bits / 1000000).toStringAsFixed(1)} Мбит/с';
  return '${(bits / 1000).round()} кбит/с';
}
