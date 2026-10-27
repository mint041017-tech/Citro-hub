import 'dart:math' as math;

import 'package:citro/games/gsheep.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('bucket lock detection matches full pairwise check', () {
    final rnd = math.Random(20261027);
    for (var round = 0; round < 120; round++) {
      final tiles = <SheepTile>[
        for (var i = 0; i < 32; i++)
          SheepTile(
            id: i,
            gx: rnd.nextInt(61) / 10,
            gy: rnd.nextInt(61) / 10,
            layer: rnd.nextInt(5),
          ),
      ];
      final geom = SheepGeom.compute(
        boardW: 340,
        boardH: 453,
        tiles: tiles,
      );
      final fast = sheepLockedIds(tiles);
      for (final tile in tiles) {
        expect(
          fast.contains(tile.id),
          geom.isLocked(tiles, tile),
          reason:
              'round=$round id=${tile.id} '
              'gx=${tile.gx} gy=${tile.gy} layer=${tile.layer}',
        );
      }
    }
  });

  test('bucket edges around half-step offsets stay conservative', () {
    final tiles = <SheepTile>[
      SheepTile(id: 0, gx: 0.4, gy: 0.4, layer: 0),
      SheepTile(id: 1, gx: 1.3, gy: 1.3, layer: 1),
      SheepTile(id: 2, gx: 2.0, gy: 2.0, layer: 0),
      SheepTile(id: 3, gx: 2.9, gy: 2.9, layer: 0),
    ];
    final geom = SheepGeom.compute(boardW: 340, boardH: 453, tiles: tiles);
    final fast = sheepLockedIds(tiles);
    for (final tile in tiles) {
      expect(fast.contains(tile.id), geom.isLocked(tiles, tile));
    }
  });
}
