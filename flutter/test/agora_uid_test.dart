import 'package:citro/screen_share/agora_client.dart';
import 'package:flutter_test/flutter_test.dart';

/// AgoraClient.uidFor 必须和 Worker `numericUid`（src/index.ts）产出
/// 一致 —— 两端各自独立算哈希，不一致的画面就永远对不上成员。
/// 参考值由 node 直接跑 Worker 同款算法生成（见 test 生成命令）。
void main() {
  test('uidFor 与 Worker 的 numericUid 参考值一致', () {
    // node -e "…Math.imul FNV-1a…" 参考输出：
    //   guest_123456 -> 651795828
    //   citro        -> 1500029689
    //   u123         -> 97180833
    expect(AgoraClient.uidFor('guest_123456'), 651795828);
    expect(AgoraClient.uidFor('citro'), 1500029689);
    expect(AgoraClient.uidFor('u123'), 97180833);
  });

  test('uidFor 永不为 0（Agora 保留值）', () {
    for (final s in <String>['', 'a', 'guest_0', 'zzz', '中文']) {
      expect(AgoraClient.uidFor(s), isNot(0));
      expect(AgoraClient.uidFor(s), inInclusiveRange(1, 0x7ffffffe));
    }
  });

  test('uidFor 稳定且区分大小写', () {
    expect(AgoraClient.uidFor('Same'), AgoraClient.uidFor('Same'));
    expect(AgoraClient.uidFor('Same'), isNot(AgoraClient.uidFor('same')));
  });
}
