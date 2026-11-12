import 'package:citro/services/refresh_rate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(RefreshRate.endInteractionNow);

  test('滚动结束后空闲计时自动释放高刷租约', () async {
    RefreshRate.onScrollActivity();
    expect(RefreshRate.isHolding, isTrue);

    // 空闲阈值 900ms，留 200ms 余量。
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(RefreshRate.isHolding, isFalse);
  });

  test('转场脉冲可被退后台立即收回', () {
    RefreshRate.pulse();
    expect(RefreshRate.isHolding, isTrue);

    RefreshRate.endInteractionNow();
    expect(RefreshRate.isHolding, isFalse);
  });

  test('连续滚动不会叠加租约', () async {
    for (var i = 0; i < 5; i++) {
      RefreshRate.onScrollActivity();
    }
    expect(RefreshRate.isHolding, isTrue);

    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(RefreshRate.isHolding, isFalse);
  });
}