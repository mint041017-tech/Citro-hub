import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/paper.dart';
import 'models.dart';
import 'scoring.dart';
import 'store.dart';

class KeiPage extends StatefulWidget {
  const KeiPage({super.key});

  @override
  State<KeiPage> createState() => _KeiPageState();
}

class _KeiPageState extends State<KeiPage> {
  KeiBank? bank;
  String? loadError;
  String step = 'intro';
  List<KeiRecord> records = KeiStore.load();
  KeiRecord? record;
  int idx = 0;
  int resultTab = 0;
  List<int?> answers = [];
  List<int> timings = [];
  DateTime? startTime;
  DateTime? questionAt;
  Timer? advanceTimer;

  @override
  void initState() {
    super.initState();
    KeiStore.changes.addListener(_reloadRecords);
    unawaited(KeiStore.syncFromAccount(account: AppState.instance.user?.name));
    unawaited(_load());
  }

  @override
  void dispose() {
    advanceTimer?.cancel();
    KeiStore.changes.removeListener(_reloadRecords);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final b = await KeiBank.load();
      if (!mounted) return;
      setState(() {
        bank = b;
        answers = List<int?>.filled(b.questions.length, null);
        timings = List<int>.filled(b.questions.length, 0);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loadError = '$e');
    }
  }

  void _reloadRecords() {
    if (!mounted) return;
    setState(() => records = KeiStore.load());
  }

  void _start() {
    final b = bank;
    if (b == null) return;
    advanceTimer?.cancel();
    setState(() {
      idx = 0;
      answers = List<int?>.filled(b.questions.length, null);
      timings = List<int>.filled(b.questions.length, 0);
      startTime = DateTime.now();
      questionAt = DateTime.now();
      record = null;
      resultTab = 0;
      step = 'quiz';
    });
  }

  Future<void> _pick(int value) async {
    if (bank == null || idx >= bank!.questions.length) return;
    advanceTimer?.cancel();
    final now = DateTime.now();
    setState(() {
      answers[idx] = value;
      timings[idx] = now.difference(questionAt ?? now).inMilliseconds;
    });
    if (idx == bank!.questions.length - 1) {
      await Future<void>.delayed(const Duration(milliseconds: 160));
      if (!mounted) return;
      await _submit();
      return;
    }
    advanceTimer = Timer(const Duration(milliseconds: 170), () {
      if (!mounted) return;
      setState(() {
        idx++;
        questionAt = DateTime.now();
      });
    });
  }

  void _prev() {
    if (idx == 0) return;
    advanceTimer?.cancel();
    setState(() {
      idx--;
      questionAt = DateTime.now();
    });
  }

  Future<void> _submit() async {
    final b = bank;
    if (b == null || answers.any((a) => a == null)) return;
    final result = KeiScoring.analyze(
      bank: b,
      answers: answers.map((e) => e!).toList(),
      timings: List<int>.of(timings),
    );
    final id = await KeiStore.add(result);
    if (!mounted) return;
    KeiRecord? saved;
    for (final item in KeiStore.load()) {
      if (item.id == id) saved = item;
    }
    setState(() {
      records = KeiStore.load();
      record = saved;
      resultTab = 0;
      step = 'result';
    });
  }

  Future<void> _confirmQuit() async {
    if (step != 'quiz' || answers.every((a) => a == null)) {
      Navigator.of(context).pop();
      return;
    }
    final c = context.c;
    final quit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.sheet,
        title: Text('退出测试？', style: context.heading(color: c.ink)),
        content: Text('本次作答不会保存。', style: context.body(color: c.ink2)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('继续作答', style: context.body(color: c.accentInk)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('退出', style: context.body(color: c.danger)),
          ),
        ],
      ),
    );
    if (quit == true && mounted) Navigator.of(context).pop();
  }

  void _showRecord(KeiRecord r) {
    setState(() {
      record = r;
      resultTab = 0;
      step = 'result';
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      body: CitroBackground(
        child: SafeArea(
          child: switch (step) {
            'quiz' => _buildQuiz(c),
            'result' => _buildResult(c),
            _ => _buildIntro(c),
          },
        ),
      ),
    );
  }

  Widget _frame(Widget child, {VoidCallback? onClose}) {
    final c = context.c;
    return Stack(
      fit: StackFit.expand,
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 70, 20, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: child,
            ),
          ),
        ),
        Positioned(
          top: 8,
          left: 8,
          child: IconButton(
            icon: Icon(Icons.close_rounded, color: c.ink),
            onPressed: onClose ?? () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }

  Widget _buildIntro(CitroColors c) {
    return _frame(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '十二系亲密关系',
            textAlign: TextAlign.center,
            style: context.display(
              size: 30,
              weight: CitroType.strong,
              color: c.ink,
              letterSpacing: -.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '四十题，看见你在关系里的默认姿态。',
            textAlign: TextAlign.center,
            style: context.body(size: CitroType.meta, color: c.inkSoft),
          ),
          const SizedBox(height: AppSpacing.x3),
          if (loadError != null)
            Text('资源加载失败：$loadError', style: context.body(color: c.danger))
          else if (bank == null)
            const Center(child: CircularProgressIndicator())
          else ...[
            CitroCard(
              padding: const EdgeInsets.all(AppSpacing.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: c.tintPink,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.favorite_border_rounded,
                          size: 23,
                          color: c.accentInk,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'TWELVE KEI · 十二系图谱',
                          style: context.heading(
                            size: CitroType.title,
                            color: c.ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  Text(
                    '五个正交维度、40 道正反对称题，计算 12 个原型的后验占比与稳定率。',
                    style: context.body(
                      size: CitroType.caption,
                      color: c.inkSoft,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: const [
                      CitroChip('40 题'),
                      CitroChip('5 个维度'),
                      CitroChip('12 系原型'),
                      CitroChip('约 8 分钟'),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  CitroButton(label: '开始测试', expanded: true, onPressed: _start),
                ],
              ),
            ),
            if (records.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.x3),
              Row(
                children: [
                  Text(
                    '测试档案',
                    style: context.heading(size: CitroType.title, color: c.ink),
                  ),
                  const Spacer(),
                  Text(
                    '${records.length} 次 · 云端同步',
                    style: context.body(
                      size: CitroType.small,
                      color: c.inkSoft,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.x1),
              for (final r in records.take(5))
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: CitroCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    onTap: () => _showRecord(r),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                r.result.typeName,
                                style: context.heading(
                                  size: CitroType.bodyLg,
                                  color: c.ink,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_date(r.takenAtMs)} · 稳定率 ${r.result.stabilityPct}%',
                                style: context.body(
                                  size: CitroType.small,
                                  color: c.inkSoft,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: c.inkSoft,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ],
          const SizedBox(height: AppSpacing.x3),
          Text(
            '本测评参照成人依恋量表和人际环状模型构建，“十二系”仅用于自我觉察，不构成临床诊断或终身标签。',
            style: context.body(
              size: CitroType.small,
              color: c.inkSoft,
              height: 1.7,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuiz(CitroColors c) {
    final b = bank!;
    final q = b.questions[idx];
    final selected = answers[idx];
    final progress = (idx + (selected == null ? 0 : 1)) / b.questions.length;
    return _frame(
      onClose: _confirmQuit,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '第 ${idx + 1} / ${b.questions.length} 题',
            textAlign: TextAlign.center,
            style: context.heading(size: CitroType.title, color: c.ink),
          ),
          const SizedBox(height: 4),
          Text(
            '凭第一感觉选择，不用反复斟酌',
            textAlign: TextAlign.center,
            style: context.body(size: CitroType.small, color: c.inkSoft),
          ),
          const SizedBox(height: AppSpacing.x2),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: c.surface2,
              valueColor: AlwaysStoppedAnimation(c.accent),
            ),
          ),
          const SizedBox(height: AppSpacing.x3),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: CitroCard(
              key: ValueKey(idx),
              padding: const EdgeInsets.all(AppSpacing.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    q.text,
                    style: context.body(
                      size: CitroType.bodyLg,
                      color: c.ink,
                      height: 1.65,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x4),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final size = ((constraints.maxWidth - 6 * 8) / 7).clamp(
                        30.0,
                        46.0,
                      );
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          for (var v = -3; v <= 3; v++)
                            _optionButton(c, v, size, selected == v),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '不像我',
                        style: context.body(
                          size: CitroType.small,
                          color: c.inkSoft,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '很像我',
                        style: context.body(
                          size: CitroType.small,
                          color: c.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.x3),
          Row(
            children: [
              Expanded(
                child: CitroButton(
                  label: '上一题',
                  style: CitroButtonStyle.outline,
                  onPressed: idx == 0 ? null : _prev,
                ),
              ),
              const SizedBox(width: AppSpacing.x2),
              Expanded(
                flex: 2,
                child: Text(
                  selected == null ? '请选择最符合你的程度' : '已记录，继续下一题',
                  textAlign: TextAlign.center,
                  style: context.body(size: CitroType.small, color: c.inkSoft),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _optionButton(CitroColors c, int value, double size, bool selected) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${value + 4} 级',
      child: Pressable(
        key: ValueKey('kei-option-${idx}-$value'),
        onTap: () => _pick(value),
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: selected ? c.accent : c.surface2,
            shape: BoxShape.circle,
            border: Border.all(color: selected ? c.accent : c.line),
            boxShadow: selected ? CitroColors.shadows.glow(c) : null,
          ),
          child: Center(
            child: Text(
              '${value + 4}',
              style: context.body(
                size: CitroType.caption,
                weight: selected ? CitroType.strong : CitroType.medium,
                color: selected ? c.onAccent : c.ink2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResult(CitroColors c) {
    final r = record;
    if (r == null) return _buildIntro(c);
    final proto = bank?.byId(r.result.typeId);
    final accent = _hex(proto?.accent ?? '#7A6857');
    final protoVec = proto == null
        ? r.result.vec
        : KeiScoring.normalizedVec(proto);
    return _frame(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CitroCard(
            padding: const EdgeInsets.all(AppSpacing.x3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 560;
                    final info = _reportHeroInfo(c, r, proto, accent);
                    final radar = SizedBox(
                      width: 210,
                      height: 210,
                      child: CustomPaint(
                        painter: _KeiRadarPainter(
                          user: r.result.vec,
                          proto: protoVec,
                          labels: [for (final d in r.result.dimensions) d.name],
                          accent: accent,
                          ink: c.inkSoft,
                          line: c.line,
                        ),
                      ),
                    );
                    if (!wide) {
                      return Column(
                        children: [
                          info,
                          const SizedBox(height: AppSpacing.x2),
                          radar,
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: info),
                        const SizedBox(width: AppSpacing.x2),
                        radar,
                      ],
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.x2),
                _telemetry(c, r),
                if (r.result.audit != null &&
                    r.result.audit!.warnings.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.x2),
                  Text(
                    '效度审计提示：${r.result.audit!.warnings.join('；')}。',
                    style: context.body(
                      size: CitroType.small,
                      color: c.stamp,
                      height: 1.55,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.x3),
          _resultTabs(c),
          const SizedBox(height: AppSpacing.x2),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: KeyedSubtree(
              key: ValueKey('kei-result-tab-$resultTab'),
              child: switch (resultTab) {
                1 => _metricsPane(c, r, proto),
                2 => _dynamicsPane(c, r, accent),
                _ => _profilePane(c, r, proto, accent),
              },
            ),
          ),
          const SizedBox(height: AppSpacing.x3),
          CitroButton(label: '再测一次', expanded: true, onPressed: _start),
          const SizedBox(height: AppSpacing.x1),
          CitroButton(
            label: '返回测试中心',
            style: CitroButtonStyle.outline,
            expanded: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(height: AppSpacing.x3),
          Text(
            '结果反映当前关系脚本，不等同于临床诊断，也不是终身标签。',
            textAlign: TextAlign.center,
            style: context.body(size: CitroType.small, color: c.inkSoft),
          ),
        ],
      ),
    );
  }

  Widget _reportHeroInfo(
    CitroColors c,
    KeiRecord r,
    KeiPrototype? proto,
    Color accent,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${r.result.profileMode} · ${_date(r.takenAtMs)}',
          style: context.body(
            size: CitroType.small,
            weight: CitroType.strong,
            color: c.inkSoft,
            letterSpacing: .5,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          r.result.typeName,
          style: context.display(
            size: 38,
            weight: CitroType.strong,
            color: accent,
            letterSpacing: -1.2,
          ),
        ),
        if (proto != null) ...[
          Text(
            proto.en.toUpperCase(),
            style: context.body(
              size: CitroType.small,
              color: c.inkSoft,
              letterSpacing: 1.8,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            proto.tagline,
            style: context.body(
              size: CitroType.body,
              color: c.ink2,
              height: 1.65,
            ),
          ),
        ],
      ],
    );
  }

  Widget _telemetry(CitroColors c, KeiRecord r) {
    final audit = r.result.audit;
    final items = <(String, String, bool)>[
      ('依恋象限', r.result.attachment, false),
      ('主型稳定率', '${r.result.stabilityPct}%', false),
      ('轮廓集中度', '${r.result.sharpness} / 100', false),
      ('作答效度审计', audit?.validityStatus ?? '—', audit?.validityWarn ?? false),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620 ? 4 : 2;
        const gap = 12.0;
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: 12,
          children: [
            for (final item in items)
              SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.$1,
                      style: context.body(
                        size: CitroType.micro,
                        color: c.inkSoft,
                        letterSpacing: .5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.heading(
                        size: CitroType.bodyLg,
                        color: item.$3 ? c.danger : c.ink,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _resultTabs(CitroColors c) {
    const labels = ['画像与占比', '五维与效度', '关系动力学'];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(CitroColors.radii.card),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => resultTab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 38,
                  decoration: BoxDecoration(
                    color: resultTab == i ? c.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(
                      CitroColors.radii.inner,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      labels[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.body(
                        size: CitroType.caption,
                        weight: resultTab == i
                            ? CitroType.strong
                            : CitroType.medium,
                        color: resultTab == i ? c.ink : c.inkSoft,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _profilePane(
    CitroColors c,
    KeiRecord r,
    KeiPrototype? proto,
    Color accent,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (r.result.synthesis.isNotEmpty)
          _contentSection(c, '主辅动力学解读', r.result.synthesis),
        _sectionTitle(c, '十二系等半径投影分布'),
        const SizedBox(height: AppSpacing.x1),
        CitroCard(
          padding: const EdgeInsets.all(AppSpacing.x3),
          child: Column(
            children: [
              for (final t in r.result.ranked)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _pctBar(
                    c,
                    t.name,
                    t.pct,
                    t.id == r.result.typeId ? accent : c.inkSoft,
                  ),
                ),
              if (r.result.driftName != null)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '误差模拟中另有 ${r.result.driftPct}% 概率向「${r.result.driftName}」偏移。',
                    style: context.body(
                      size: CitroType.small,
                      color: c.inkSoft,
                      height: 1.55,
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (proto != null) ...[
          const SizedBox(height: AppSpacing.x2),
          _contentSection(c, '内在机制', proto.mechanism),
          _contentSection(c, '关系表现', proto.behavior),
          _contentSection(c, '盲点提醒', proto.blindspot, accent: true),
        ],
      ],
    );
  }

  Widget _metricsPane(CitroColors c, KeiRecord r, KeiPrototype? proto) {
    final accent = _hex(proto?.accent ?? '#7A6857');
    final audit = r.result.audit;
    final d1 = r.result.dimensions[0];
    final d2 = r.result.dimensions[1];

    final attachColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '成人依恋平面',
                style: context.heading(size: CitroType.bodyLg, color: c.ink),
              ),
            ),
            Text(
              'X1 × X2',
              style: context.body(
                size: CitroType.micro,
                color: c.inkSoft,
                letterSpacing: .8,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        CitroCard(
          padding: const EdgeInsets.all(AppSpacing.x2),
          child: Column(
            children: [
              AspectRatio(
                aspectRatio: 310 / 274,
                child: CustomPaint(
                  painter: _AttachmentPlanePainter(
                    x1: d1.mean,
                    x2: d2.mean,
                    se1: d1.se,
                    se2: d2.se,
                    accent: accent,
                    ink: c.ink,
                    inkSoft: c.inkSoft,
                    line: c.line,
                    danger: c.danger,
                    safe: c.dark
                        ? const Color(0xFF86D6B2)
                        : const Color(0xFF2F755A),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '(${d1.mean.toStringAsFixed(2)}, ${d2.mean.toStringAsFixed(2)}) · 虚线椭圆为 95% 置信误差域',
                textAlign: TextAlign.center,
                style: context.body(size: CitroType.micro, color: c.inkSoft),
              ),
            ],
          ),
        ),
      ],
    );

    final auditColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '测量效度审计',
                style: context.heading(size: CitroType.bodyLg, color: c.ink),
              ),
            ),
            Text(
              'CURRAN PROTOCOL',
              style: context.body(
                size: CitroType.micro,
                color: c.inkSoft,
                letterSpacing: .8,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        CitroCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: audit == null
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(
                    '该记录生成于旧版本，未包含效度审计数据。',
                    style: context.body(
                      size: CitroType.small,
                      color: c.inkSoft,
                      height: 1.6,
                    ),
                  ),
                )
              : Column(
                  children: [
                    _auditRow(
                      c,
                      '反义镜像一致性',
                      '5 组跨距反义题极性一致度',
                      '${audit.antonymScore} / 100',
                      audit.antonymScore < 62,
                    ),
                    _auditRow(
                      c,
                      'Longstring 连续同选',
                      'Curran 粗心作答指标（≥8 预警）',
                      '${audit.longstring} 题',
                      audit.longstring >= 8,
                    ),
                    _auditRow(
                      c,
                      '默认赞同偏差 (ARS)',
                      '对称题项结构已自动抵消其影响',
                      '${audit.ars > 0 ? '+' : ''}${audit.ars.toStringAsFixed(2)}',
                      false,
                    ),
                    _auditRow(
                      c,
                      '极端作答率 (ERS)',
                      '选择端点 1 分或 7 分的比例',
                      '${audit.ersPct}%',
                      false,
                    ),
                    _auditRow(
                      c,
                      '中位单题耗时',
                      '低于 1.2s 提示未充分阅读',
                      '${audit.medianSec}s',
                      audit.medianSec < 1.2,
                      last: true,
                    ),
                  ],
                ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(c, '五维潜变量与 95% 置信区间'),
        const SizedBox(height: AppSpacing.x1),
        CitroCard(
          padding: const EdgeInsets.all(AppSpacing.x3),
          child: Column(
            children: [
              for (final d in r.result.dimensions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    children: [
                      _dimensionBar(c, d, accent),
                      const SizedBox(height: 3),
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          '95% CI ${d.ciLow.toStringAsFixed(2)} ~ ${d.ciHigh.toStringAsFixed(2)}',
                          style: context.body(
                            size: CitroType.micro,
                            color: c.inkSoft,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.x3),
        LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < 700) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  attachColumn,
                  const SizedBox(height: AppSpacing.x2),
                  auditColumn,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: attachColumn),
                const SizedBox(width: AppSpacing.x2),
                Expanded(child: auditColumn),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _auditRow(
    CitroColors c,
    String title,
    String subtitle,
    String value,
    bool warn, {
    bool last = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: last
            ? null
            : Border(bottom: BorderSide(color: c.line.withValues(alpha: .6))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.body(
                    size: CitroType.caption,
                    weight: CitroType.medium,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: context.body(size: CitroType.micro, color: c.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            value,
            style: context.body(
              size: CitroType.caption,
              weight: warn ? CitroType.strong : CitroType.medium,
              color: warn ? c.danger : c.ink,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dynamicsPane(CitroColors c, KeiRecord r, Color accent) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionTitle(c, '低摩擦协同组合'),
        const SizedBox(height: AppSpacing.x1),
        _compatGroup(c, '实测向量动态方程推导 · TOP 3', r.result.compatBest, accent),
        const SizedBox(height: AppSpacing.x2),
        _sectionTitle(c, '高张力磨合组合'),
        const SizedBox(height: AppSpacing.x1),
        _compatGroup(c, '结构性摩擦预警 · TOP 2', r.result.compatHard, c.danger),
      ],
    );
  }

  Widget _compatGroup(
    CitroColors c,
    String title,
    List<KeiCompat> items,
    Color color,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: context.body(
            size: CitroType.caption,
            weight: CitroType.strong,
            color: color,
          ),
        ),
        const SizedBox(height: 6),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: CitroCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.name,
                          style: context.heading(
                            size: CitroType.body,
                            color: c.ink,
                          ),
                        ),
                      ),
                      Text(
                        '${item.total}',
                        style: context.heading(
                          size: CitroType.title,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.sub.entries
                        .map((e) => '${e.key} ${e.value}')
                        .join(' · '),
                    style: context.body(
                      size: CitroType.micro,
                      color: c.inkSoft,
                    ),
                  ),
                  if (item.note.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      item.note,
                      style: context.body(
                        size: CitroType.small,
                        color: c.ink2,
                        height: 1.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _sectionTitle(CitroColors c, String text) {
    return Text(
      text,
      style: context.heading(size: CitroType.title, color: c.ink),
    );
  }

  Widget _pctBar(CitroColors c, String label, double pct, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: context.body(
                  size: CitroType.caption,
                  weight: CitroType.medium,
                  color: c.ink,
                ),
              ),
            ),
            Text(
              _pctText(pct),
              style: context.body(size: CitroType.small, color: c.inkSoft),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Stack(
            children: [
              Container(height: 6, color: c.surface2),
              FractionallySizedBox(
                widthFactor: (pct / 100).clamp(0.02, 1.0),
                child: Container(height: 6, color: color),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dimensionBar(CitroColors c, KeiDimensionScore d, Color accent) {
    final v = ((d.mean + 1) / 2).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                d.name,
                style: context.body(
                  size: CitroType.caption,
                  weight: CitroType.medium,
                  color: c.ink,
                ),
              ),
            ),
            Text(
              d.mean.toStringAsFixed(2),
              style: context.body(size: CitroType.small, color: c.inkSoft),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: Stack(
            children: [
              Container(height: 6, color: c.surface2),
              FractionallySizedBox(
                widthFactor: v,
                alignment: Alignment.centerLeft,
                child: Container(height: 6, color: accent),
              ),
            ],
          ),
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            Text(
              d.low,
              style: context.body(size: CitroType.micro, color: c.inkSoft),
            ),
            const Spacer(),
            Text(
              d.high,
              style: context.body(size: CitroType.micro, color: c.inkSoft),
            ),
          ],
        ),
      ],
    );
  }

  Widget _contentSection(
    CitroColors c,
    String title,
    String body, {
    bool accent = false,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.x2),
      child: CitroCard(
        padding: const EdgeInsets.all(AppSpacing.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: context.heading(
                size: CitroType.bodyLg,
                color: accent ? c.accentInk : c.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              body,
              style: context.body(
                size: CitroType.caption,
                color: c.ink2,
                height: 1.7,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _hex(String value) {
    final hex = value.replaceAll('#', '');
    return Color(int.parse('FF$hex', radix: 16));
  }

  String _pctText(double value) => value == value.roundToDouble()
      ? '${value.round()}%'
      : '${value.toStringAsFixed(1)}%';

  String _date(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}.${two(d.month)}.${two(d.day)}';
  }
}

class _KeiRadarPainter extends CustomPainter {
  _KeiRadarPainter({
    required this.user,
    required this.proto,
    required this.labels,
    required this.accent,
    required this.ink,
    required this.line,
  });

  final List<double> user;
  final List<double> proto;
  final List<String> labels;
  final Color accent;
  final Color ink;
  final Color line;

  @override
  void paint(Canvas canvas, Size size) {
    final n = math.min(user.length, labels.length);
    if (n < 3) return;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 26;
    if (radius <= 0) return;

    Offset pointAt(int i, double value) {
      final angle = -math.pi / 2 + 2 * math.pi * i / n;
      final r = radius * ((value + 1) / 2).clamp(0.0, 1.0);
      return center + Offset(math.cos(angle) * r, math.sin(angle) * r);
    }

    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .8
      ..color = line.withValues(alpha: .55);
    for (final scale in [.5, 1.0]) {
      final path = Path();
      for (var i = 0; i < n; i++) {
        final angle = -math.pi / 2 + 2 * math.pi * i / n;
        final p =
            center +
            Offset(
              math.cos(angle) * radius * scale,
              math.sin(angle) * radius * scale,
            );
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      canvas.drawPath(path, ring);
    }

    final spoke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7
      ..color = line.withValues(alpha: .45);
    for (var i = 0; i < n; i++) {
      final angle = -math.pi / 2 + 2 * math.pi * i / n;
      canvas.drawLine(
        center,
        center + Offset(math.cos(angle) * radius, math.sin(angle) * radius),
        spoke,
      );
    }

    Path polygon(List<double> values, {double shrink = 1.0}) {
      final path = Path();
      for (var i = 0; i < n; i++) {
        final angle = -math.pi / 2 + 2 * math.pi * i / n;
        final r = radius * ((values[i] + 1) / 2).clamp(0.0, 1.0) * shrink;
        final p = center + Offset(math.cos(angle) * r, math.sin(angle) * r);
        i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
      }
      path.close();
      return path;
    }

    final protoPath = polygon(proto);
    final protoStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = accent.withValues(alpha: .45);
    _drawDashed(canvas, protoPath, protoStroke);

    final userPath = polygon(user);
    canvas.drawPath(
      userPath,
      Paint()
        ..style = PaintingStyle.fill
        ..color = accent.withValues(alpha: .16),
    );
    canvas.drawPath(
      userPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = accent,
    );

    final dot = Paint()..color = accent;
    for (var i = 0; i < n; i++) {
      canvas.drawCircle(pointAt(i, user[i]), 2.6, dot);
    }

    for (var i = 0; i < n; i++) {
      final angle = -math.pi / 2 + 2 * math.pi * i / n;
      final anchor =
          center +
          Offset(
            math.cos(angle) * (radius + 12),
            math.sin(angle) * (radius + 12),
          );
      final tp = TextPainter(
        text: TextSpan(
          text: labels[i],
          style: TextStyle(
            fontSize: 10,
            height: 1.2,
            color: ink,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout(maxWidth: 60);
      final cos = math.cos(angle);
      final x = cos > .25
          ? anchor.dx
          : cos < -.25
          ? anchor.dx - tp.width
          : anchor.dx - tp.width / 2;
      final y = anchor.dy - tp.height / 2;
      tp.paint(
        canvas,
        Offset(
          x.clamp(2.0, math.max(2.0, size.width - tp.width - 2)),
          y.clamp(2.0, math.max(2.0, size.height - tp.height - 2)),
        ),
      );
    }
  }

  void _drawDashed(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + 4, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance = next + 3;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _KeiRadarPainter old) {
    return old.accent != accent ||
        old.ink != ink ||
        old.line != line ||
        !_sameList(old.user, user) ||
        !_sameList(old.proto, proto) ||
        !_sameList(old.labels, labels);
  }

  bool _sameList(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

class _AttachmentPlanePainter extends CustomPainter {
  _AttachmentPlanePainter({
    required this.x1,
    required this.x2,
    required this.se1,
    required this.se2,
    required this.accent,
    required this.ink,
    required this.inkSoft,
    required this.line,
    required this.danger,
    required this.safe,
  });

  final double x1;
  final double x2;
  final double se1;
  final double se2;
  final Color accent;
  final Color ink;
  final Color inkSoft;
  final Color line;
  final Color danger;
  final Color safe;

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 26.0;
    final rect = Rect.fromLTWH(
      pad,
      pad,
      size.width - pad * 2,
      size.height - pad * 2,
    );
    if (rect.width <= 0 || rect.height <= 0) return;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(12)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = line,
    );

    final dash = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = line.withValues(alpha: .8);
    _dashedLine(
      canvas,
      Offset(rect.left, rect.center.dy),
      Offset(rect.right, rect.center.dy),
      dash,
    );
    _dashedLine(
      canvas,
      Offset(rect.center.dx, rect.top),
      Offset(rect.center.dx, rect.bottom),
      dash,
    );

    final cx = rect.center.dx + x1.clamp(-1.0, 1.0) * (rect.width / 2);
    final cy = rect.center.dy - x2.clamp(-1.0, 1.0) * (rect.height / 2);
    final rx = math.min(rect.width / 2, 1.96 * se1 * (rect.width / 2));
    final ry = math.min(rect.height / 2, 1.96 * se2 * (rect.height / 2));

    final ellipse = Rect.fromCenter(
      center: Offset(cx, cy),
      width: math.max(2, rx * 2),
      height: math.max(2, ry * 2),
    );
    final ellipsePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = accent.withValues(alpha: .85);
    canvas.drawOval(ellipse, Paint()..color = accent.withValues(alpha: .12));
    _dashedOval(canvas, ellipse, ellipsePaint);

    canvas.drawCircle(Offset(cx, cy), 4.8, Paint()..color = ink);
    canvas.drawCircle(
      Offset(cx, cy),
      4.8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = const Color(0xFFFFFFFF),
    );

    _label(canvas, '疏离回避', Offset(rect.left + 8, rect.top + 6), inkSoft);
    _label(
      canvas,
      '恐惧回避',
      Offset(rect.right - 8, rect.top + 6),
      danger,
      alignRight: true,
    );
    _label(canvas, '安全型', Offset(rect.left + 8, rect.bottom - 20), safe);
    _label(
      canvas,
      '焦虑痴迷',
      Offset(rect.right - 8, rect.bottom - 20),
      inkSoft,
      alignRight: true,
    );

    _label(
      canvas,
      'HIGH AVOIDANCE (+X2)',
      Offset(rect.center.dx, rect.top - 18),
      inkSoft,
      alignCenter: true,
      small: true,
    );
    _label(
      canvas,
      'LOW AVOIDANCE (−X2)',
      Offset(rect.center.dx, rect.bottom + 5),
      inkSoft,
      alignCenter: true,
      small: true,
    );
    _label(
      canvas,
      '−X1',
      Offset(rect.left - 8, rect.center.dy - 6),
      inkSoft,
      alignRight: true,
      small: true,
    );
    _label(
      canvas,
      '+X1',
      Offset(rect.right + 8, rect.center.dy - 6),
      inkSoft,
      small: true,
    );
  }

  void _dashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 3.0;
    const gap = 3.0;
    final total = (b - a).distance;
    if (total <= 0) return;
    final dir = (b - a) / total;
    var t = 0.0;
    while (t < total) {
      final end = math.min(t + dash, total);
      canvas.drawLine(a + dir * t, a + dir * end, paint);
      t = end + gap;
    }
  }

  void _dashedOval(Canvas canvas, Rect rect, Paint paint) {
    const segments = 48;
    for (var i = 0; i < segments; i += 2) {
      final start = (i / segments) * math.pi * 2;
      final end = ((i + 1) / segments) * math.pi * 2;
      canvas.drawArc(rect, start, end - start, false, paint);
    }
  }

  void _label(
    Canvas canvas,
    String text,
    Offset offset,
    Color color, {
    bool alignRight = false,
    bool alignCenter = false,
    bool small = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: small ? 7.5 : 9.5,
          height: 1.2,
          color: color,
          letterSpacing: small ? .4 : 0,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final dx = alignRight
        ? offset.dx - tp.width
        : alignCenter
        ? offset.dx - tp.width / 2
        : offset.dx;
    tp.paint(canvas, Offset(dx, offset.dy));
  }

  @override
  bool shouldRepaint(covariant _AttachmentPlanePainter old) {
    return old.x1 != x1 ||
        old.x2 != x2 ||
        old.se1 != se1 ||
        old.se2 != se2 ||
        old.accent != accent ||
        old.ink != ink ||
        old.inkSoft != inkSoft ||
        old.line != line ||
        old.danger != danger ||
        old.safe != safe;
  }
}
