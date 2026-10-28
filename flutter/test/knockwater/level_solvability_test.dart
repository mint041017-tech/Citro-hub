import 'package:flutter_test/flutter_test.dart';
import 'package:citro/games/knockwater/engine.dart';
import 'package:citro/games/knockwater/levels.dart';

import '../../tool/knockwater/canonical_solutions.dart';
import '../../tool/knockwater/solver.dart';

void main() {
  test('关卡总数与七章分布', () {
    expect(kLevels, hasLength(78));
    expect(kLevels.where((level) => level.chapter == '第一章 · 初纹'), hasLength(8));
    expect(
      kLevels.where((level) => level.chapter == '第二章 · 回声'),
      hasLength(12),
    );
    expect(
      kLevels.where((level) => level.chapter == '第三章 · 双生'),
      hasLength(12),
    );
    expect(
      kLevels.where((level) => level.chapter == '第四章 · 暗流'),
      hasLength(12),
    );
    expect(
      kLevels.where((level) => level.chapter == '第五章 · 浅滩'),
      hasLength(12),
    );
    expect(
      kLevels.where((level) => level.chapter == '第六章 · 合鸣'),
      hasLength(16),
    );
    expect(
      kLevels.where((level) => level.chapter == '第七章 · 涡潮'),
      hasLength(6),
    );
  });

  test('关卡名称不重复', () {
    final names = kLevels.map((level) => level.name).toSet();
    expect(names, hasLength(kLevels.length));
  });

  test('canonical 与关卡数一致；普通关 3 条、第七章 1 条', () {
    expect(kCanonicalSolutions, hasLength(kLevels.length));
    for (var i = 0; i < kLevels.length; i++) {
      final expected = kLevels[i].chapter == '第七章 · 涡潮' ? 1 : 3;
      expect(
        kCanonicalSolutions[i],
        hasLength(expected),
        reason: '第 ${i + 1} 关',
      );
    }
  });

  test('第七章每关唯一通路：仅最后一步推瓣，重叩失效（含最快步频）', () {
    final indices = <int>[
      for (var i = 0; i < kLevels.length; i++)
        if (kLevels[i].chapter == '第七章 · 涡潮') i,
    ];
    expect(indices, hasLength(6));
    const mouth = <int>[8, 10];
    for (final i in indices) {
      final level = kLevels[i];
      final canonical = kCanonicalSolutions[i].single.split(' ');
      final engine = Engine.fromLevel(level);
      expect(level.allowHeavy, isFalse, reason: '第 ${i + 1} 关应禁用重叩');
      expect(
        engine.startCharge(),
        isFalse,
        reason: '第 ${i + 1} 关仍可重叩',
      );
      expect(
        canonical,
        hasLength(level.charges),
        reason: '第 ${i + 1} 关必须用满铃息走完整条长道',
      );

      // 只有一条从水铃到湾心东侧推瓣位的简单通路。
      final probe = Engine.fromLevel(level);
      final visited = <String>{'${level.bellX},${level.bellY}'};
      final paths = <String>[];
      void dfs(int x, int y, List<String> path) {
        if (x == mouth[0] && y == mouth[1] && path.isNotEmpty) {
          paths.add(path.join(' '));
          return;
        }
        if (path.length >= level.charges) return;
        for (final entry in kDirs.entries) {
          final nx = x + entry.value[0];
          final ny = y + entry.value[1];
          if (nx < 0 || nx >= kCols || ny < 0 || ny >= kRows) continue;
          final key = '$nx,$ny';
          if (visited.contains(key)) continue;
          if (!probe.canWalkCell(nx, ny)) continue;
          visited.add(key);
          path.add(entry.key);
          dfs(nx, ny, path);
          path.removeLast();
          visited.remove(key);
        }
      }

      dfs(level.bellX, level.bellY, <String>[]);
      expect(
        paths,
        hasLength(1),
        reason: '第 ${i + 1} 关存在多条可走通路：$paths',
      );
      expect(
        paths.single.split(' '),
        canonical,
        reason: '第 ${i + 1} 关可走通路与 canonical 不一致',
      );

      // 长道前任何一步都不能提前把花瓣推进湾心。
      // 0.13s 是移动动画结束后的最快连步，必须同样只有最后一步获胜。
      for (var k = 1; k < canonical.length; k++) {
        final prefix = canonical.take(k).toList();
        for (final beat in <double>[0.13, 0.62, 0.9]) {
          expect(
            replaySolution(level, prefix, beat),
            isNull,
            reason: '第 ${i + 1} 关第 $k 步提前获胜（${beat}s）',
          );
        }
      }
      expect(
        replaySolution(level, canonical, 0.13),
        isNotNull,
        reason: '第 ${i + 1} 关最快步频无法完成',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 8)));

  for (var i = 0; i < kLevels.length; i++) {
    test('第 ${i + 1} 关 ${kLevels[i].name} 有效解双节奏通过', () {
      expect(kCanonicalSolutions.length, kLevels.length);
      final solutions = kCanonicalSolutions[i];
      final expected = kLevels[i].chapter == '第七章 · 涡潮' ? 1 : 3;
      expect(
        solutions,
        hasLength(expected),
        reason: '第 ${i + 1} 关需要恰好 $expected 条解',
      );
      final distinct = <String>{};
      for (final encoded in solutions) {
        final moves = encoded.split(' ');
        expect(
          replaySolution(kLevels[i], moves, 0.62),
          isNotNull,
          reason: '0.62s 节奏失败：$encoded',
        );
        expect(
          replaySolution(kLevels[i], moves, 0.9),
          isNotNull,
          reason: '0.9s 节奏失败：$encoded',
        );
        final eff62 = effectiveMoves(kLevels[i], moves, 0.62);
        final eff90 = effectiveMoves(kLevels[i], moves, 0.9);
        expect(eff62, isNotEmpty, reason: '0.62s 无有效动作：$encoded');
        expect(eff90, isNotEmpty, reason: '0.9s 无有效动作：$encoded');
        distinct.add(eff62.join(' '));
      }
      expect(
        distinct,
        hasLength(expected),
        reason: '第 ${i + 1} 关存在重复有效解',
      );
    });
  }
}
