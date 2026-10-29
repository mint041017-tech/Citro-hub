import 'package:flutter/material.dart';

class SoundSpec {
  final String id;
  final String name;
  final String category;
  final String description;
  final IconData icon;
  final bool synthesized;
  const SoundSpec(
    this.id,
    this.name,
    this.category,
    this.description,
    this.icon, {
    this.synthesized = false,
  });
}

const sounds = <SoundSpec>[
  SoundSpec('rain', '雨幕远雷', '雨声', '真实雨声，伴有雷声起伏', Icons.water_drop_outlined),
  SoundSpec('rain_soft', '伞下雨声', '雨声', '雨滴落在伞面的持续声响', Icons.umbrella_outlined),
  SoundSpec(
    'rain_roof',
    '车顶落雨',
    '雨声',
    '坐在车里，听雨滴打在车顶',
    Icons.directions_car_outlined,
  ),
  SoundSpec('forest', '林间鸟鸣', '森林', '鸟鸣与虫声，偶有远处车声', Icons.forest_outlined),
  SoundSpec('crickets', '田野蟋蟀', '森林', '田野里，一只蟋蟀的鸣唱', Icons.grass_outlined),
  SoundSpec('cicadas', '林野蝉鸣', '森林', '多只蝉鸣交织的自然底色', Icons.park_outlined),
  SoundSpec('frogs', '池畔蛙鸣', '森林', '池畔群蛙，伴着背景水声', Icons.water_outlined),
  SoundSpec('leaves', '风吹灌木', '森林', '乡间灌木丛里，风在穿行', Icons.eco_outlined),
  SoundSpec('stream', '潺潺溪流', '水流', '让思绪，跟着水流走', Icons.waves_outlined),
  SoundSpec('river', '河道流水', '水流', '河道里持续流动的水声', Icons.water_outlined),
  SoundSpec('waterfall', '山间瀑布', '水流', '山间小瀑布，绵密而厚实', Icons.waves_outlined),
  SoundSpec('ocean', '海浪与海鸟', '水流', '浪拍岸边，鸟鸣掠过', Icons.beach_access_outlined),
  SoundSpec('wind', '草野之风', '森林', '有风经过高草的午后', Icons.air_outlined),
  SoundSpec('chimes', '风铃清音', '风铃', '棚内实录，清亮的铃音', Icons.wind_power_outlined),
  SoundSpec(
    'underwater',
    '水下静域',
    '水下',
    '低沉而柔和的合成氛围',
    Icons.bubble_chart_outlined,
    synthesized: true,
  ),
  SoundSpec(
    'bubbles',
    '近水气泡',
    '水下',
    '吸管吹出的真实水泡，近水细节',
    Icons.bubble_chart_outlined,
  ),
  SoundSpec('cafe', '街角咖啡馆', '城市', '含交谈声的咖啡馆氛围', Icons.local_cafe_outlined),
  SoundSpec('train', '列车车厢', '城市', '列车行进中的稳定环境声', Icons.train_outlined),
  SoundSpec('traffic', '桥上车流', '城市', '桥上俯瞰的巴黎环城车流', Icons.traffic_outlined),
  SoundSpec(
    'fire',
    '枝火轻响',
    '篝火',
    '户外枝火，间有清脆爆裂声',
    Icons.local_fire_department_outlined,
  ),
  SoundSpec(
    'fireplace',
    '壁炉薪火',
    '篝火',
    '木柴燃烧，比枝火更柔一些',
    Icons.fireplace_outlined,
  ),
  SoundSpec('fan', '电扇低鸣', '城市', '电扇稳定转动的持续低鸣', Icons.air_outlined),
  SoundSpec('clock', '机械钟滴答', '城市', '不紧不慢地走过每一秒', Icons.timer_outlined),
  SoundSpec('keyboard', '键盘慢敲', '城市', '慢速打字，陪你把事做完', Icons.keyboard_outlined),
  SoundSpec(
    'laundry',
    '洗衣机滚筒',
    '城市',
    '烘干模式中段的平稳转动',
    Icons.local_laundry_service_outlined,
  ),
  SoundSpec(
    'white',
    '白噪声',
    '噪声',
    '均匀、明亮的声音底色',
    Icons.graphic_eq_outlined,
    synthesized: true,
  ),
  SoundSpec(
    'pink',
    '粉红噪声',
    '噪声',
    '更柔和的宽频声音',
    Icons.blur_on_outlined,
    synthesized: true,
  ),
  SoundSpec(
    'brown',
    '棕色噪声',
    '噪声',
    '温厚、低沉，少一点锐利',
    Icons.grain_outlined,
    synthesized: true,
  ),
];

class SceneSpec {
  final String title;
  final String subtitle;
  final IconData icon;
  final int minutes;
  final int fadeSeconds;
  final Map<String, int> tracks;
  final Color tint;
  const SceneSpec(
    this.title,
    this.subtitle,
    this.icon,
    this.minutes,
    this.tracks,
    this.tint, {
    this.fadeSeconds = 30,
  });
}

const scenes = <SceneSpec>[
  SceneSpec('专注一页', '留给认真做事的你', Icons.menu_book_outlined, 60, {
    'rain_soft': 60,
    'pink': 20,
    'cafe': 15,
  }, Color(0xffe6e9df)),
  SceneSpec('午后小憩', '休息，也是一件正事', Icons.wb_cloudy_outlined, 30, {
    'forest': 45,
    'stream': 30,
  }, Color(0xffeee9df)),
  SceneSpec(
    '慢慢入夜',
    '平稳低频，不含雷声',
    Icons.nightlight_outlined,
    60,
    {'rain_soft': 55, 'brown': 20, 'underwater': 15},
    Color(0xffe3e7ec),
    fadeSeconds: 60,
  ),
  SceneSpec('放松片刻', '把呼吸还给自己', Icons.spa_outlined, 10, {
    'ocean': 40,
    'chimes': 10,
  }, Color(0xffe8eadf)),
];

const categoryOrder = [
  '全部',
  '雨声',
  '森林',
  '水流',
  '风铃',
  '水下',
  '城市',
  '篝火',
  '噪声',
  '本地',
];

String clockText(num seconds) {
  final n = seconds.ceil().clamp(0, 43200);
  final hours = n ~/ 3600;
  final minutes = (n % 3600) ~/ 60;
  final rest = n % 60;
  return hours > 0
      ? '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}'
      : '${minutes.toString().padLeft(2, '0')}:${rest.toString().padLeft(2, '0')}';
}

String endClockText(num seconds) {
  final now = DateTime.now();
  final end = now.add(Duration(seconds: seconds.ceil()));
  final hm =
      '${end.hour.toString().padLeft(2, '0')}:${end.minute.toString().padLeft(2, '0')}';
  final sameDay =
      end.year == now.year && end.month == now.month && end.day == now.day;
  return sameDay ? hm : '明天 $hm';
}

String sizeText(num bytes) => bytes >= 1048576
    ? '${(bytes / 1048576).toStringAsFixed(1)} MB'
    : '${(bytes / 1024).toStringAsFixed(0)} KB';

List<Map<String, dynamic>> validTracks(dynamic value) {
  if (value is! List) return [];
  final seen = <String>{};
  return value
      .whereType<Map>()
      .where(
        (m) =>
            m['id'] is String &&
            m['volume'] is num &&
            seen.add(m['id'] as String),
      )
      .take(6)
      .map(
        (m) => <String, dynamic>{
          'id': m['id'],
          'volume': (m['volume'] as num).clamp(0, 100).round(),
        },
      )
      .toList();
}
