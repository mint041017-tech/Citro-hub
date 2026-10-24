String? currentWebRoute() {
  final fragment = Uri.base.fragment.trim();
  return fragment.isEmpty ? null : fragment;
}
