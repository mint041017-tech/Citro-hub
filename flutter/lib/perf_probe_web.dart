class PerfProbe {
  static const bool enabled = false;

  static void start() {}
  static void homeReady(void Function(int) switchTab) {}
  static void beginFrameCollection() {}
  static void endFrameCollection(String label) {}
}
