import 'package:citro/utils/links.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('only file downloads bypass the in-app browser', () {
    expect(isDownloadLink('https://obs.example.com/Mod/REPO.zip'), isTrue);
    expect(isDownloadLink('https://obs.example.com/tool.exe?v=2'), isTrue);
    expect(isDownloadLink('https://obs.example.com/app.apk#top'), isTrue);
    expect(isDownloadLink('https://hub.example.com/home'), isFalse);
    expect(isDownloadLink('https://www.bing.com/search?q=citro'), isFalse);
  });

  test('bare hosts are normalized to https', () {
    expect(
      normalizeWebUrl('hub.example.com/home'),
      'https://hub.example.com/home',
    );
    expect(normalizeWebUrl(' https://example.com/a '), 'https://example.com/a');
    expect(normalizeWebUrl(''), isNull);
  });
}
