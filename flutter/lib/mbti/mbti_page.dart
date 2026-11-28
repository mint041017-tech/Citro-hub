import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:share_plus/share_plus.dart';

import '../services/clipboard_image.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/paper.dart';
import 'ai.dart';
import 'copy.dart';
import 'models.dart';
import 'persona.dart';
import 'report.dart';
import 'scoring.dart';
import 'store.dart';

class MbtiPage extends StatefulWidget {
  const MbtiPage({super.key});

  @override
  State<MbtiPage> createState() => _MbtiPageState();
}

class _MbtiPageState extends State<MbtiPage> {
  MbtiBank? bank;
  TypeLibrary? library;
  String? loadError;

  /// intro / quiz / result
  String step = 'intro';
  MbtiMode mode = MbtiMode.full;
  final GlobalKey _shareCardKey = GlobalKey();
  bool _sharing = false;

  List<MbtiQuestion> quizQs = [];
  Map<String, int> answers = {};
  Map<String, int> itemTimingsMs = {};
  int groupIndex = 0;
  DateTime? startTime;
  DateTime? lastAnswerAt;

  MbtiRecord? record;
  String? confirmed;

  String? aiText;
  bool aiLoading = false;
  bool aiFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
    unawaited(MbtiStore.syncFromAccount(account: AppState.instance.user?.name));
  }

  Future<void> _load() async {
    try {
      final b = await MbtiBank.load();
      final l = await TypeLibrary.load();
      if (!mounted) return;
      setState(() {
        bank = b;
        library = l;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => loadError = '$e');
    }
  }

  void _start() {
    setState(() {
      mode = MbtiMode.full;
      quizQs = bank!.questionsFor(mode);
      answers = {};
      itemTimingsMs = {};
      groupIndex = 0;
      startTime = DateTime.now();
      lastAnswerAt = DateTime.now();
      confirmed = null;
      aiText = null;
      aiFailed = false;
      step = 'quiz';
    });
  }

  Future<void> _submit() async {
    final duration = DateTime.now().difference(startTime!).inSeconds;
    final timingsMs = [
      for (final q in quizQs) itemTimingsMs[q.id] ?? 0,
    ];
    final result = MbtiScoring.score(
      bank: bank!,
      mode: mode,
      answers: answers,
      durationSec: duration,
      timingsMs: timingsMs,
    );
    final id = await MbtiStore.add(result);
    if (!mounted) return;
    setState(() {
      record = MbtiStore.load().firstWhere((r) => r.id == id);
      step = 'result';
    });
    _genAi();
  }

  Future<void> _genAi() async {
    final r = record;
    if (r == null || aiLoading) return;
    setState(() {
      aiLoading = true;
      aiFailed = false;
    });
    final content = library!.byCode(confirmed ?? r.result.typeRaw)!;
    final text = await MbtiAi.insight(
      result: r.result,
      content: content,
      bank: bank!,
      typeConfirmed: confirmed,
    );
    if (!mounted) return;
    setState(() {
      aiLoading = false;
      aiText = text;
      aiFailed = text == null;
      if (text != null) {
        record = record!.copyWith(aiInsight: text);
      }
    });
    if (text != null) await MbtiStore.update(record!);
  }

  void _switchDim(String dim) {
    final r = record!;
    final meta = bank!.dimensions[dim]!;
    final code = confirmed ?? r.result.typeRaw;
    final dimIndex = ['EI', 'SN', 'TF', 'JP'].indexOf(dim);
    if (dimIndex < 0) return;
    final nextLetter = code[dimIndex] == meta.left ? meta.right : meta.left;
    final next =
        code.substring(0, dimIndex) + nextLetter + code.substring(dimIndex + 1);
    final nextConfirmed = next == r.result.typeRaw ? null : next;
    setState(() {
      confirmed = nextConfirmed;
      record = MbtiRecord(
        id: r.id,
        takenAtMs: r.takenAtMs,
        result: r.result,
        typeConfirmed: nextConfirmed,
        aiInsight: r.aiInsight,
      );
    });
    MbtiStore.update(record!);
  }

  String get effectiveCode => confirmed ?? record!.result.typeRaw;

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

  Widget _frame(Widget child, {double maxWidth = 640, VoidCallback? onClose}) {
    final c = context.c;
    return Stack(
      fit: StackFit.expand,
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 70, 20, 40),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
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

  // ---------------- 入口 ----------------

  Widget _buildIntro(CitroColors c) {
    return _frame(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '16 型测试',
            textAlign: TextAlign.center,
            style: context.display(
              size: 30,
              weight: CitroType.strong,
              color: c.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '四个维度，一张属于你的人格地图。',
            textAlign: TextAlign.center,
            style: context.body(size: CitroType.meta, color: c.inkSoft),
          ),
          const SizedBox(height: AppSpacing.x3),
          if (loadError != null)
            Text('资源加载失败：$loadError', style: context.body(color: c.danger))
          else if (bank == null || library == null)
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
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: c.accentLt,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.psychology_alt_outlined,
                          color: c.accentInk,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'MBTI 测试',
                              style: context.heading(
                                size: CitroType.title,
                                color: c.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${bank!.questionsFor(MbtiMode.full).length} 题 · 约 12 分钟',
                              style: context.body(
                                size: CitroType.caption,
                                color: c.inkSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  Text(
                    '同时测四个主维度和情绪稳定性（-A / -T），给出稳定的维度分和清晰的报告。',
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
                      CitroChip('E / I'),
                      CitroChip('S / N'),
                      CitroChip('T / F'),
                      CitroChip('J / P'),
                      CitroChip('A / T'),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.x3),
                  _primaryButton('开始测试', _start),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.x3),
            ValueListenableBuilder<int>(
              valueListenable: MbtiStore.changes,
              builder: (context, _, _) {
                final records = MbtiStore.load();
                if (records.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Text(
                          '测试档案',
                          style: context.heading(
                            size: CitroType.title,
                            color: c.ink,
                          ),
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
                                      _recordLabel(r),
                                      style: context.heading(
                                        size: CitroType.bodyLg,
                                        color: c.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      _date(r.takenAtMs),
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
                );
              },
            ),
          ],
          const SizedBox(height: AppSpacing.x3),
          Text(
            mbtiDisclaimer,
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

  void _showRecord(MbtiRecord r) {
    setState(() {
      record = r;
      confirmed = r.typeConfirmed;
      aiText = r.aiInsight;
      aiFailed = false;
      aiLoading = false;
      step = 'result';
    });
  }

  String _recordLabel(MbtiRecord r) {
    final name = library?.byCode(r.typeConfirmed ?? r.result.typeRaw)?.name;
    return '${r.displayType}${name == null ? '' : ' · $name'}';
  }

  String _date(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.year}.${two(d.month)}.${two(d.day)}';
  }

  // ---------------- 答题 ----------------

  List<List<MbtiQuestion>> get groups {
    final out = <List<MbtiQuestion>>[];
    for (var i = 0; i < quizQs.length; i += 4) {
      out.add(quizQs.sublist(i, i + 4 > quizQs.length ? quizQs.length : i + 4));
    }
    return out;
  }

  bool get currentGroupDone =>
      groups[groupIndex].every((q) => answers.containsKey(q.id));

  Future<void> _confirmQuit() async {
    if (answers.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    final c = context.c;
    final quit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
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

  Widget _buildQuiz(CitroColors c) {
    final group = groups[groupIndex];
    final answered = answers.length;
    final isLast = groupIndex == groups.length - 1;
    return _frame(
      onClose: _confirmQuit,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '第 ${groupIndex + 1}/${groups.length} 组',
            textAlign: TextAlign.center,
            style: context.heading(size: CitroType.title, color: c.ink),
          ),
          const SizedBox(height: 4),
          Text(
            '已答 $answered / ${quizQs.length} · 凭第一感觉作答，不用反复斟酌',
            textAlign: TextAlign.center,
            style: context.body(size: CitroType.small, color: c.inkSoft),
          ),
          const SizedBox(height: AppSpacing.x2),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: answered / quizQs.length,
              minHeight: 6,
              backgroundColor: c.surface2,
              valueColor: AlwaysStoppedAnimation(c.accent),
            ),
          ),
          const SizedBox(height: AppSpacing.x3),
          for (final q in group) ...[
            CitroCard(
              padding: const EdgeInsets.all(AppSpacing.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    q.text,
                    style: context.body(
                      size: CitroType.bodyLg,
                      color: c.ink,
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.x2),
                  _scaleRow(q),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Text(
                        '很不同意',
                        style: context.body(
                          size: CitroType.small,
                          color: c.inkSoft,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '很同意',
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
            const SizedBox(height: AppSpacing.x2),
          ],
          const SizedBox(height: AppSpacing.x1),
          Row(
            children: [
              if (groupIndex > 0)
                Expanded(
                  child: _ghostButton('上一组', () {
                    setState(() => groupIndex--);
                  }),
                )
              else
                const Spacer(),
              const SizedBox(width: AppSpacing.x2),
              Expanded(
                flex: 2,
                child: _primaryButton(
                  isLast ? '查看结果' : '下一组',
                  currentGroupDone
                      ? () {
                          if (isLast) {
                            _submit();
                          } else {
                            setState(() {
                              groupIndex++;
                              lastAnswerAt = DateTime.now();
                            });
                          }
                        }
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _scaleRow(MbtiQuestion q) {
    final c = context.c;
    final selected = answers[q.id];
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = ((constraints.maxWidth - 6 * 8) / 7).clamp(28.0, 44.0);
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (var a = 1; a <= 7; a++)
              Pressable(
                key: ValueKey('mbti-${q.id}-$a'),
                onTap: () => setState(() {
                  final now = DateTime.now();
                  itemTimingsMs[q.id] = now
                      .difference(lastAnswerAt ?? now)
                      .inMilliseconds;
                  lastAnswerAt = now;
                  answers[q.id] = a;
                }),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    color: selected == a ? c.accent : Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected == a ? c.accent2 : c.line2,
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$a',
                      style: context.body(
                        size: CitroType.caption,
                        weight: selected == a
                            ? CitroType.strong
                            : CitroType.regular,
                        color: selected == a ? c.onAccent : c.inkSoft,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _primaryButton(String label, VoidCallback? onTap) {
    final c = context.c;
    final enabled = onTap != null;
    return Pressable(
      onTap: onTap ?? () {},
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: enabled ? c.ink : c.surface2,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Center(
          child: Text(
            label,
            style: context.body(
              size: CitroType.body,
              weight: CitroType.medium,
              color: enabled ? c.bg : c.inkSoft,
            ),
          ),
        ),
      ),
    );
  }

  Widget _ghostButton(String label, VoidCallback onTap) {
    final c = context.c;
    return Pressable(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.line2),
        ),
        child: Center(
          child: Text(
            label,
            style: context.body(size: CitroType.body, color: c.ink2),
          ),
        ),
      ),
    );
  }

  // ---------------- 结果 ----------------

  Widget _buildResult(CitroColors c) {
    final r = record!;
    final result = r.result;
    final content = library!.byCode(effectiveCode)!;
    final displayType = '$effectiveCode${result.atSuffix}';
    final persona = buildMbtiPersona(
      result: result,
      bank: bank!,
      content: content,
      confirmed: confirmed,
    );
    return _frame(
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TypeHeaderCard(displayType: displayType, content: content),
          if (confirmed != null) ...[
            const SizedBox(height: AppSpacing.x1),
            Text(
              '作答结果为 ${result.typeRaw}，你自评确认为 $confirmed',
              textAlign: TextAlign.center,
              style: context.body(size: CitroType.small, color: c.stamp),
            ),
          ],
          if (result.quality.hasWarning ||
              (result.audit != null && result.audit!.warnings.isNotEmpty)) ...[
            const SizedBox(height: AppSpacing.x2),
            CitroCard(
              padding: const EdgeInsets.all(AppSpacing.x2),
              child: Text(
                result.audit != null && result.audit!.warnings.isNotEmpty
                    ? '效度审计提示（${result.audit!.validityStatus}）：${result.audit!.warnings.join('；')}，结果可能不够准，建议找个安静的时间认真重测一次。'
                    : '${[if (result.quality.fastFinish) '本次作答较快', if (result.quality.straightLine) '选项分布比较单一', if (result.quality.inconsistentPairs >= 2) '部分回答前后不太一致'].join('，')}，结果可能不够准，建议找个安静的时间认真重测一次。',
                style: context.body(
                  size: CitroType.caption,
                  color: c.stamp,
                  height: 1.6,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.x2),
          ResultPersonaCard(
            result: result,
            bank: bank!,
            content: content,
            confirmed: confirmed,
          ),
          const SizedBox(height: AppSpacing.x2),
          CitroCard(
            padding: const EdgeInsets.all(AppSpacing.x3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final dim in ['EI', 'SN', 'TF', 'JP', 'AT'])
                  if (result.scores[dim] != null) ...[
                    DimBar(
                      score: result.scores[dim]!,
                      meta: bank!.dimensions[dim]!,
                    ),
                    const SizedBox(height: AppSpacing.x2),
                  ],
                Text(
                  mbtiDimCopy['EI']!.myth,
                  style: context.body(
                    size: CitroType.small,
                    color: c.inkSoft,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
          _auditCard(c, result),
          const SizedBox(height: AppSpacing.x2),
          _calibrationCard(c),
          const SizedBox(height: AppSpacing.x2),
          _aiCard(c),
          const SizedBox(height: AppSpacing.x2),
          TypeReportSections(content: content),
          const SizedBox(height: AppSpacing.x3),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: RepaintBoundary(
                key: _shareCardKey,
                child: MbtiShareCard(
                  result: result,
                  content: content,
                  persona: persona,
                  displayType: displayType,
                  bank: bank!,
                  confirmed: confirmed,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.x3),
          Row(
            children: [
              Expanded(
                child: _primaryButton(
                  _sharing ? '生成中…' : '分享结果',
                  _sharing ? null : _shareResult,
                ),
              ),
              const SizedBox(width: AppSpacing.x2),
              Expanded(
                child: _ghostButton('再测一次', () {
                  setState(() => step = 'intro');
                }),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x2),
          Text(
            mbtiDisclaimer,
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

  Widget _auditCard(CitroColors c, MbtiResult result) {
    final audit = result.audit;
    final status = audit?.validityStatus ??
        (result.quality.hasWarning ? '需留意' : '可靠');
    final warn = audit?.validityWarn ?? result.quality.hasWarning;
    final pairCount = bank == null
        ? 4
        : bank!.questionsFor(result.mode).where((q) => q.pair != null).length ~/
            2;
    return CitroCard(
      padding: const EdgeInsets.all(AppSpacing.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                warn ? Icons.verified_user_outlined : Icons.verified_user_rounded,
                size: 18,
                color: warn ? c.danger : c.accentInk,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '测量效度审计',
                  style: context.heading(size: CitroType.title, color: c.ink),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: warn ? c.dangerSoft : c.accentLt,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status,
                  style: context.body(
                    size: CitroType.small,
                    weight: CitroType.strong,
                    color: warn ? c.danger : c.accentInk,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'CURRAN PROTOCOL · 作答效度审计',
            style: context.body(
              size: CitroType.micro,
              color: c.inkSoft,
              letterSpacing: .8,
            ),
          ),
          const SizedBox(height: AppSpacing.x1),
          if (audit == null) ...[
            _auditRow(
              c,
              '题对一致性冲突',
              '同维度镜像题对矛盾数（≥2 预警）',
              '${result.quality.inconsistentPairs} 对',
              result.quality.inconsistentPairs >= 2,
            ),
            _auditRow(
              c,
              '直线连续作答',
              '连续同选或单一选项占比过高',
              result.quality.straightLine ? '存在异常' : '正常',
              result.quality.straightLine,
            ),
            _auditRow(
              c,
              '整卷作答耗时',
              '平均每题低于 1.5s 提示未充分阅读',
              result.quality.fastFinish ? '过快' : '正常',
              result.quality.fastFinish,
              last: true,
            ),
          ] else ...[
            _auditRow(
              c,
              '题对镜像一致性',
              '$pairCount 组跨距配对题极性一致度',
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
              '正反题对冲结构已自动抵消其影响',
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
        ],
      ),
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
      padding: const EdgeInsets.symmetric(vertical: 11),
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

  Widget _calibrationCard(CitroColors c) {
    final r = record!;
    return CitroCard(
      padding: const EdgeInsets.all(AppSpacing.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '最后一步：确认一下像不像你',
            style: context.heading(size: CitroType.title, color: c.ink),
          ),
          const SizedBox(height: 4),
          Text(
            '贴线的维度最容易测歪，看看哪边的描述更像你，点按钮即可改判，报告会跟着变。',
            style: context.body(
              size: CitroType.small,
              color: c.inkSoft,
              height: 1.6,
            ),
          ),
          const SizedBox(height: AppSpacing.x2),
          for (final dim in ['EI', 'SN', 'TF', 'JP']) ...[
            _calibrationRow(dim, r),
            if (dim != 'JP') const SizedBox(height: AppSpacing.x2),
          ],
        ],
      ),
    );
  }

  Widget _calibrationRow(String dim, MbtiRecord r) {
    final c = context.c;
    final meta = bank!.dimensions[dim]!;
    final copy = mbtiDimCopy[dim]!;
    final code = effectiveCode;
    final dimIndex = ['EI', 'SN', 'TF', 'JP'].indexOf(dim);
    final letter = code[dimIndex];
    final isLeft = letter == meta.left;
    final center = r.result.scores[dim]!.band == DimBand.center;
    final otherLetter = isLeft ? meta.right : meta.left;
    final otherName = isLeft ? meta.rightName : meta.leftName;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.x2),
      decoration: BoxDecoration(
        color: center ? c.tintYellow : c.surface2,
        borderRadius: BorderRadius.circular(CitroColors.radii.inner),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                '${copy.title}：$letter · ${isLeft ? meta.leftName : meta.rightName}',
                style: context.heading(
                  size: CitroType.label,
                  color: c.accentInk,
                ),
              ),
              if (center) ...[
                const SizedBox(width: 6),
                Text(
                  '贴线',
                  style: context.body(size: CitroType.small, color: c.stamp),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isLeft ? copy.leftDesc : copy.rightDesc,
            style: context.body(
              size: CitroType.caption,
              color: c.ink2,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Pressable(
              onTap: () => _switchDim(dim),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: c.surface,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: c.line2),
                ),
                child: Text(
                  '不太像，我更偏 $otherLetter · $otherName',
                  style: context.body(
                    size: CitroType.small,
                    color: c.accentInk,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _aiCard(CitroColors c) {
    return CitroCard(
      padding: const EdgeInsets.all(AppSpacing.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 18, color: c.accentInk),
              const SizedBox(width: 6),
              Text(
                'CiCi 个性化解读',
                style: context.heading(size: CitroType.title, color: c.ink),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.x2),
          if (aiLoading)
            Text('正在结合你的维度分生成解读…', style: context.body(color: c.inkSoft))
          else if (aiText != null)
            Text(
              aiText!,
              style: context.body(
                size: CitroType.body,
                color: c.ink2,
                height: 1.8,
              ),
            )
          else ...[
            Text(
              aiFailed ? '生成失败，检查网络后可以重试。' : '暂未生成解读。',
              style: context.body(size: CitroType.caption, color: c.inkSoft),
            ),
            const SizedBox(height: AppSpacing.x1),
            Align(
              alignment: Alignment.centerLeft,
              child: _ghostButton('生成 AI 解读', _genAi),
            ),
          ],
          if (aiText != null) ...[
            const SizedBox(height: AppSpacing.x1),
            Align(
              alignment: Alignment.centerLeft,
              child: Pressable(
                onTap: _genAi,
                borderRadius: BorderRadius.circular(999),
                child: Text(
                  '按当前确认类型重新生成',
                  style: context.body(
                    size: CitroType.small,
                    color: c.accentInk,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _shareResult() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final target = _shareCardKey.currentContext;
      if (target == null) throw StateError('share card not ready');
      await Scrollable.ensureVisible(
        target,
        alignment: 0.08,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 160));
      final boundary =
          _shareCardKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('share card not ready');
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('capture failed');
      final bytes = data.buffer.asUint8List();

      final r = record!;
      final content = library!.byCode(effectiveCode)!;
      final dimLines = <String>[];
      for (final dim in ['EI', 'SN', 'TF', 'JP']) {
        final s = r.result.scores[dim]!;
        final meta = bank!.dimensions[dim]!;
        dimLines.add(
          '${meta.leftName} ${s.pctLeft}% / ${meta.rightName} ${s.pctRight}%',
        );
      }
      final text = mbtiShareText(
        type: '$effectiveCode${r.result.atSuffix}',
        name: content.name,
        tagline: content.tagline,
        dimLines: dimLines,
      );
      final fileName = 'Citro-MBTI-$effectiveCode.png';
      final file = XFile.fromData(bytes, mimeType: 'image/png', name: fileName);
      final shareBox = target.findRenderObject();
      final shareOrigin = shareBox is RenderBox && shareBox.hasSize
          ? shareBox.localToGlobal(Offset.zero) & shareBox.size
          : null;
      try {
        await Share.shareXFiles(
          [file],
          text: text,
          fileNameOverrides: [fileName],
          sharePositionOrigin: shareOrigin,
        );
      } catch (_) {
        if (kIsWeb && await copyImageToClipboard(bytes)) {
          if (mounted) AppToast.show(context, '分享图已复制到剪贴板');
          return;
        }
        rethrow;
      }
      if (mounted) AppToast.show(context, '分享卡片已生成');
    } catch (_) {
      if (mounted) AppToast.show(context, '分享失败，请检查网络或稍后再试');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }
}
