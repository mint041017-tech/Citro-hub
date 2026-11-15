import 'package:citro/services/refresh_rate.dart';
import 'package:flutter_test/flutter_test.dart';

// 说明：曾有一版按「滚动空闲自动释放」重构过 RefreshRate，但实现没有
// 合入，测试却先提交了，导致整个套件红着。这里按当前实际 API（纯
// acquire/release 租约计数）重写，行为对齐 lib/services/refresh_rate.dart。
void main() {
  setUp(() {
    // 租约计数是静态的，跨用例先归零。
    RefreshRate.resetForTest();
  });

  test('acquire 后 release 一次即归零', () async {
    RefreshRate.acquire();
    expect(RefreshRate.debugLeases, 1);
    RefreshRate.release();
    expect(RefreshRate.debugLeases, 0);
    // 让 _set 的异步体跑完，避免用例间残留未完成的 Future。
    await Future<void>.delayed(Duration.zero);
  });

  test('多层租约不叠加：两层要 release 两次才释放', () async {
    RefreshRate.acquire();
    RefreshRate.acquire();
    expect(RefreshRate.debugLeases, 2);
    RefreshRate.release();
    expect(RefreshRate.debugLeases, 1);
    RefreshRate.release();
    expect(RefreshRate.debugLeases, 0);
    await Future<void>.delayed(Duration.zero);
  });

  test('零租约时 release 是安全的空操作', () async {
    expect(RefreshRate.debugLeases, 0);
    RefreshRate.release();
    expect(RefreshRate.debugLeases, 0);
    await Future<void>.delayed(Duration.zero);
  });
}
