/// Planned opt-in Android capabilities. No accessibility control is enabled yet.
abstract interface class AndroidControl {
  Future<void> openApp(String packageName);
  Future<void> tapAt(double x, double y);
  Future<void> scroll(double dx, double dy);
}
