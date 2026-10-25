final _downloadPattern = RegExp(
  r'\.(exe|zip|7z|apk|msi)(\?|#|$)',
  caseSensitive: false,
);

bool isDownloadLink(String url) => _downloadPattern.hasMatch(url);

String? normalizeWebUrl(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return null;
  final uri = Uri.tryParse(value);
  if (uri == null) return null;
  if (uri.hasScheme) return uri.toString();
  return 'https://$value';
}
