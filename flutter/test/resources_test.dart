import 'package:citro/data/resources.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('mods and self-hosted tools use the current OBS links', () {
    for (final mod in kMods) {
      expect(mod.url, startsWith('https://obs.chimu-claw.xyz/MOD/'));
    }
    for (final tool in kTools) {
      final urls = [
        if (tool.url != null) tool.url!,
        for (final version in tool.versions) version.url,
      ];
      for (final url in urls) {
        expect(
          url,
          isNot(contains('123pan.cn')),
          reason: '${tool.name} still points at the retired 123pan link',
        );
        if (url.contains('obs.chimu-claw.xyz') ||
            url.contains('myhuaweicloud.com')) {
          expect(url, startsWith('https://'));
        }
      }
    }
  });

  test('client drivers use the listed download hosts', () {
    for (final driver in kDriversClient) {
      expect(
        driver.url,
        anyOf(
          startsWith('https://obs.chimu-claw.xyz/'),
          startsWith('https://citro.obs.cn-south-1.myhuaweicloud.com/'),
        ),
      );
    }
  });
}
