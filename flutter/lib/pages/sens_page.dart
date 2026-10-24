import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../utils/navigation.dart';
import '../widgets/paper.dart';

class SensGame {
  final String code;
  final String name;
  final String engine;
  final double yaw;
  const SensGame(this.code, this.name, this.engine, this.yaw);
}

const kSensGames = [
  SensGame('CS2', 'CS2', 'Source 2', .022),
  SensGame('VAL', '无畏契约', 'Unreal Engine 4', .07),
  SensGame('APX', 'Apex 英雄', 'Source (改)', .022),
  SensGame('OW2', '守望先锋 2', '暴雪自研', .0066),
  SensGame('R6S', '彩虹六号', 'AnvilNext 2.0', .00572),
  SensGame('FN', '堡垒之夜', 'Unreal Engine 5', .5555),
  SensGame('COD', '使命召唤', 'IW 9.0', .0066),
  SensGame('EFT', '逃离塔科夫', 'Unity', .022),
  SensGame('PUB', '绝地求生', 'Unreal Engine 4', .022),
  SensGame('BF', '战地 2042', 'Frostbite 3', .0022),
  SensGame('DF', '三角洲行动', 'Unreal Engine (改)', .022),
];

class SensPage extends StatefulWidget {
  const SensPage({super.key});
  @override
  State<SensPage> createState() => _SensPageState();
}

class _SensPageState extends State<SensPage> {
  final dpi = TextEditingController(text: '800');
  final sens = TextEditingController(text: '2');
  String src = 'CS2';
  String dst = 'VAL';

  SensGame get srcGame => kSensGames.firstWhere((g) => g.code == src);
  SensGame get dstGame => kSensGames.firstWhere((g) => g.code == dst);

  double get target {
    final s = double.tryParse(sens.text.trim()) ?? 0;
    return s * srcGame.yaw / dstGame.yaw;
  }

  String get targetText {
    final v = target;
    if (v == 0) return '0';
    final s = v.toStringAsFixed(4);
    return s.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  @override
  void dispose() {
    dpi.dispose();
    sens.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final d = double.tryParse(dpi.text.trim()) ?? 0;
    final eDpi = (d * target).round();
    return Scaffold(
      body: PaperBackground(
        child: SafeArea(
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 70, 20, 40),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          '跨游戏灵敏度转换',
                          textAlign: TextAlign.center,
                          style: context.display(
                            size: 30,
                            weight: FontWeight.w700,
                            color: c.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '同一套肌肉记忆，换到哪个游戏都不迷路。',
                          textAlign: TextAlign.center,
                          style: context.body(size: 13, color: c.inkSoft),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: c.surface2,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: c.line),
                            boxShadow: CitroColors.shadows.paper(c),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                    child: _gameField(
                                      '来源游戏',
                                      src,
                                      (v) => setState(() => src = v),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 7,
                                    ),
                                    child: GestureDetector(
                                      onTap: () => setState(() {
                                        final t = src;
                                        src = dst;
                                        dst = t;
                                      }),
                                      child: Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                          color: c.hl,
                                          shape: BoxShape.circle,
                                          border: Border.all(color: c.line2),
                                        ),
                                        child: Center(
                                          child: AppIcon(
                                            strokeSvg(
                                              '<path d="M17 1l4 4-4 4"/><path d="M3 11V9a4 4 0 0 1 4-4h14"/><path d="M7 23l-4-4 4-4"/><path d="M21 13v2a4 4 0 0 1-4 4H3"/>',
                                              width: 2,
                                            ),
                                            size: 17,
                                            color: c.accentInk,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: _gameField(
                                      '目标游戏',
                                      dst,
                                      (v) => setState(() => dst = v),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(child: _numField('DPI', dpi)),
                                  const SizedBox(width: 10),
                                  Expanded(child: _numField('来源灵敏度', sens)),
                                ],
                              ),
                              const SizedBox(height: 18),
                              Container(
                                padding: const EdgeInsets.all(18),
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0x6BFFC795),
                                      Color(0x24E8964E),
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: const Color(0x57E8964E),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Text(
                                      '${dstGame.code} · 目标灵敏度',
                                      style: context.body(
                                        size: 11.5,
                                        weight: FontWeight.w600,
                                        color: c.accentInk,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      targetText,
                                      style: context.display(
                                        size: 44,
                                        weight: FontWeight.w700,
                                        color: c.ink,
                                        height: 1.05,
                                      ),
                                    ),
                                    Text(
                                      eDpi > 0 ? '$eDpi eDPI' : '— eDPI',
                                      style: context.body(
                                        size: 11,
                                        color: c.inkSoft,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Pressable(
                                      onTap: () => copyText(
                                        targetText,
                                        context: context,
                                        tip: '已复制目标灵敏度',
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: c.surface2,
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                          border: Border.all(color: c.line2),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            AppIcon(
                                              strokeSvg(
                                                AppIcons.copy,
                                                width: 2,
                                              ),
                                              size: 13,
                                              color: c.accentInk,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              '复制',
                                              style: context.body(
                                                size: 11.5,
                                                color: c.accentInk,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '换算只取决于引擎 yaw 比；DPI 视为两边共用，仅用于展示 eDPI。',
                          textAlign: TextAlign.center,
                          style: context.body(size: 10.5, color: c.inkSoft),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 16,
                top: 12,
                child: Pressable(
                  onTap: () => popOrHome(context),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: c.surface2,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.line),
                      boxShadow: CitroColors.shadows.paper(c),
                    ),
                    child: Center(
                      child: AppIcon(
                        strokeSvg(AppIcons.arrowLeft, width: 2.2),
                        size: 18,
                        color: c.ink2,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _gameField(
    String label,
    String value,
    ValueChanged<String> onChanged,
  ) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.body(
            size: 11,
            weight: FontWeight.w600,
            color: c.inkSoft,
            letterSpacing: .5,
          ),
        ),
        const SizedBox(height: 5),
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: c.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.line),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              dropdownColor: c.surface2,
              style: context.body(size: 12.5, color: c.ink),
              icon: AppIcon(
                strokeSvg(AppIcons.chevronDown, width: 2),
                size: 13,
                color: c.inkSoft,
              ),
              items: [
                for (final g in kSensGames)
                  DropdownMenuItem(
                    value: g.code,
                    child: Text(
                      '${g.code} · ${g.name}',
                      style: context.body(size: 12, color: c.ink),
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _numField(String label, TextEditingController controller) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: context.body(
            size: 11,
            weight: FontWeight.w600,
            color: c.inkSoft,
            letterSpacing: .5,
          ),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          style: context.body(size: 14, color: c.ink),
          decoration: InputDecoration(
            filled: true,
            fillColor: c.surface2,
            contentPadding: const EdgeInsets.symmetric(horizontal: 13),
            constraints: const BoxConstraints(minHeight: 44),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: c.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: c.accent),
            ),
          ),
        ),
      ],
    );
  }
}
