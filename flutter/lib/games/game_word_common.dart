import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/paper.dart';
import 'game_identity.dart';
import 'game_ui.dart';

// ---------------------------------------------------------------------------
// 飞花令 / 成语接龙共用的平台无关部分：输入区、链表面板、规则行、结算面板、
// 提示胶囊、发送按钮，以及回合推进里与玩法规则无关的小状态持有方。
//
// 各局的校验规则、计分明细、文案、数据源与 AI 调用仍留在各自页面文件，
// 通过参数或窄接口注入这里的共享 widget / 纯函数。
// ---------------------------------------------------------------------------

/// 对句 / 接龙的计分倍率：每 2 句倍率 +2，下限 1。
int wordMultiplier(int count) => math.max(1, (count ~/ 2) * 2);

/// 回车提交前的候选词守卫：输入法组合态未结束、或还没选好中文时不放行。
bool wordEnterGuardPasses(TextEditingController input) {
  if (input.value.composing.isValid) return false;
  if (!RegExp(r'[\u4e00-\u9fa5]').hasMatch(input.text)) return false;
  return true;
}

/// 反向链表滚到最新一条（偏移 0）；列表短于视口时 maxScrollExtent 为 0，
/// offset 天然停在 0。
void scrollWordChainLatest(ScrollController scroll) {
  Future.delayed(const Duration(milliseconds: 80), () {
    if (!scroll.hasClients) return;
    if (scroll.position.pixels <= 0) return;
    scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  });
}

/// 顶部 2.2s 自动消失的提示浮层持有方：两局共用同一套 toast 时序。
class WordToast {
  WordToast({required this.setState, required this.isMounted});

  final void Function(VoidCallback) setState;
  final bool Function() isMounted;

  String fb = '';
  Timer? _timer;

  void show(String msg) {
    _timer?.cancel();
    if (!isMounted()) return;
    setState(() => fb = msg);
    _timer = Timer(const Duration(milliseconds: 2200), () {
      if (isMounted()) setState(() => fb = '');
    });
  }

  /// 重开 / 结算时清掉残留提示，并取消尚未触发的自动消失定时器。
  void clear() {
    _timer?.cancel();
    fb = '';
  }

  void dispose() {
    _timer?.cancel();
  }
}

/// 每回合倒计时：两局共用同一套 1s 节拍与超时回调，总时长由各自传入。
class WordCountdown {
  WordCountdown({
    required this.total,
    required this.isMounted,
    required this.isRunning,
    required this.onTick,
    required this.onTimeout,
  });

  final int total;
  final bool Function() isMounted;
  final bool Function() isRunning;
  final void Function(int left) onTick;
  final VoidCallback onTimeout;

  int left = 0;
  Timer? _timer;

  void start() {
    _timer?.cancel();
    left = total;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!isMounted() || !isRunning()) return;
      left--;
      onTick(left);
      if (left <= 0) onTimeout();
    });
  }

  void cancel() => _timer?.cancel();

  void dispose() => _timer?.cancel();
}

// ---------------------------------------------------------------------------
// 共用纯视觉小件
// ---------------------------------------------------------------------------

/// 规则文案的一段：[em] 为 true 时用身份主色强调，否则走正文墨色。
///
/// 只传纯文本与标记，强调色由 [WordRulesList] 在自己解析出的身份上生成，
/// 避免调用方在身份作用域建立之前预先求值颜色。
class WordSeg {
  const WordSeg(this.text, {this.em = false});

  final String text;
  final bool em;
}

/// 规则行里的强调文字样式。
TextStyle _wordEmStyle(GameIdentity id) => TextStyle(
      color: id.primaryInk,
      fontWeight: FontWeight.w700,
      letterSpacing: 0,
    );

/// 规则列表：序号印章字 + 一行富文本，条目文案由各局传入。
class WordRulesList extends StatelessWidget {
  const WordRulesList({super.key, required this.texts});

  /// 每条规则的文案片段（强调段由本列表按身份上色）。
  final List<List<WordSeg>> texts;

  static const _ord = ['壹', '贰', '叁', '肆'];

  @override
  Widget build(BuildContext context) {
    final id = GameIdentityScope.of(context);
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < texts.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          WordRuleRow(
            id: id,
            ord: _ord[i],
            span: TextSpan(
              style: context.body(size: CitroType.body, color: c.ink2),
              children: [
                for (final seg in texts[i])
                  TextSpan(text: seg.text, style: seg.em ? _wordEmStyle(id) : null),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// 单条规则：左侧序号印章字，右侧富文本。
class WordRuleRow extends StatelessWidget {
  const WordRuleRow({
    super.key,
    required this.id,
    required this.ord,
    required this.span,
  });

  final GameIdentity id;
  final String ord;
  final TextSpan span;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          margin: const EdgeInsets.only(top: 2),
          decoration: BoxDecoration(
            color: id.soft,
            borderRadius: BorderRadius.circular(CitroColors.radii.xs),
          ),
          alignment: Alignment.center,
          child: OrdinalGlyph(ord, color: id.primaryInk),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text.rich(span)),
      ],
    );
  }
}

/// 链表区顶部的错误 / AI 判定提示胶囊。
class WordFbChip extends StatelessWidget {
  const WordFbChip({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final id = GameIdentityScope.of(context);
    final c = context.c;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(CitroColors.radii.chip),
        border: Border.all(color: id.primary.withAlpha(90)),
        boxShadow: CitroColors.shadows.card(c),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.clip,
        style: context.body(
          size: CitroType.meta,
          weight: CitroType.strong,
          color: id.ink,
        ),
      ),
    );
  }
}

/// 反向链表面板：最新一条从底部「长」出来，顶部叠提示胶囊。
class WordChainPanel extends StatelessWidget {
  const WordChainPanel({
    super.key,
    this.scrollController,
    required this.itemCount,
    required this.itemBuilder,
    required this.fb,
  });

  final ScrollController? scrollController;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final String fb;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Stack(
        children: [
          Positioned.fill(
            child: ListView.builder(
              controller: scrollController,
              // 反向列表：最新一条从底部「长」出来，短链时条目贴在输入区上方，
              // 键盘弹出被顶掉的只是上面的旧条目，最新条始终可见。
              reverse: true,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              itemCount: itemCount,
              itemBuilder: itemBuilder,
            ),
          ),
          if (fb.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              top: 6,
              child: Center(child: WordFbChip(text: fb)),
            ),
        ],
      ),
    );
  }
}

/// 链表条目外壳：左侧身份色条 + 角色标签 + 出处 / 备注，正文由各局传入
/// （令字高亮 / 尾字高亮的规则不同）。
class WordChainRow extends StatelessWidget {
  const WordChainRow({
    super.key,
    required this.bar,
    required this.tagText,
    required this.meta,
    required this.body,
    this.showMeta = true,
  });

  final Color bar;
  final String tagText;
  final String meta;
  final TextSpan body;
  final bool showMeta;

  @override
  Widget build(BuildContext context) {
    final id = GameIdentityScope.of(context);
    final c = context.c;
    return Container(
      decoration: BoxDecoration(
        color: id.soft,
        borderRadius: BorderRadius.circular(CitroColors.radii.inner),
        border: Border.all(color: id.deep.withAlpha(70)),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: bar),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: bar,
                            borderRadius:
                                BorderRadius.circular(CitroColors.radii.chip),
                          ),
                          child: Text(
                            tagText,
                            style: context.body(
                              size: CitroType.micro,
                              weight: CitroType.strong,
                              color: id.onPrimary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (showMeta)
                          Expanded(
                            child: Text(
                              meta,
                              textAlign: TextAlign.right,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: context.body(
                                  size: CitroType.small, color: c.inkSoft),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text.rich(body),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 输入行：48 高输入框 + 同高发送按钮。候选词 / 成语的占位文案与长度上限
/// 由各局传入。
class WordInputRow extends StatelessWidget {
  const WordInputRow({
    super.key,
    this.controller,
    this.focusNode,
    required this.enabled,
    required this.hintText,
    required this.maxLength,
    this.onEnter,
  });

  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool enabled;
  final String hintText;
  final int maxLength;
  final VoidCallback? onEnter;

  @override
  Widget build(BuildContext context) {
    final id = GameIdentityScope.of(context);
    final c = context.c;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 48,
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                enabled: enabled,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onEnter?.call(),
                maxLength: maxLength,
                style: context.body(size: CitroType.bodyLg, color: c.ink),
                decoration: InputDecoration(
                  isDense: true,
                  counterText: '',
                  hintText: hintText,
                  hintStyle:
                      context.body(size: CitroType.body, color: c.inkSoft),
                  filled: true,
                  fillColor: id.soft.withAlpha(90),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  // 去掉身份红描边：输入区只用中性描边，聚焦时换主题青瓷。
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(CitroColors.radii.field),
                    borderSide: BorderSide(color: c.line2),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(CitroColors.radii.field),
                    borderSide: BorderSide(color: c.line2),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(CitroColors.radii.field),
                    borderSide: BorderSide(color: c.accent, width: 1.5),
                  ),
                  disabledBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(CitroColors.radii.field),
                    borderSide: BorderSide(color: c.line2),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 发送按钮：键盘弹出时也能直接点，不必依赖键盘右下角的回车。
          WordSendButton(
            enabled: enabled,
            onTap: () => onEnter?.call(),
          ),
        ],
      ),
    );
  }
}

/// 输入区右侧的发送按钮（48 高，和输入框同高）。
class WordSendButton extends StatelessWidget {
  const WordSendButton({super.key, required this.onTap, this.enabled = true});

  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final id = GameIdentityScope.of(context);
    return Pressable(
      onTap: enabled ? onTap : null,
      hoverLift: 0,
      hoverShadow: false,
      borderRadius: BorderRadius.circular(CitroColors.radii.button),
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? id.primary : id.soft,
          borderRadius: BorderRadius.circular(CitroColors.radii.button),
        ),
        child: AppIcon(
          strokeSvg(AppIcons.arrowRight, width: 2.2),
          size: 18,
          color: enabled ? id.onPrimary : c.inkSoft,
        ),
      ),
    );
  }
}

/// 结算面板里的单个统计块。
class WordStatBlock extends StatelessWidget {
  const WordStatBlock({
    super.key,
    required this.label,
    required this.value,
    this.accent = false,
  });

  final String label;
  final String value;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final id = GameIdentityScope.of(context);
    final c = context.c;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: context.body(size: CitroType.small, color: c.inkSoft)),
        const SizedBox(height: 3),
        Text(
          value,
          style: context.hand(
            size: CitroType.heading,
            weight: CitroType.strong,
            color: accent ? id.primaryInk : id.ink,
          ),
        ),
      ],
    );
  }
}

/// 结算统计项（文案 / 数值 / 是否主色强调由各局传入）。
class WordStat {
  const WordStat({required this.label, required this.value, this.accent = false});

  final String label;
  final String value;
  final bool accent;
}

/// 结算面板：标题 + 副文案 + 一行统计块 + 再来一局。
class WordResultPanel extends StatelessWidget {
  const WordResultPanel({
    super.key,
    required this.endTitle,
    required this.endSub,
    required this.won,
    required this.stats,
    required this.onAgain,
  });

  final String endTitle;
  final String endSub;
  final bool won;
  final List<WordStat> stats;
  final VoidCallback? onAgain;

  @override
  Widget build(BuildContext context) {
    final id = GameIdentityScope.of(context);
    final c = context.c;
    final titleColor = won ? id.primaryInk : id.deep;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              endTitle,
              textAlign: TextAlign.center,
              style: context.heading(size: CitroType.heading, color: titleColor),
            ),
            const SizedBox(height: 8),
            Text(
              endSub,
              textAlign: TextAlign.center,
              style: context.body(size: CitroType.meta, color: c.ink2),
            ),
            const SizedBox(height: 18),
            // 窄屏（横屏 / 小窗）改成 Wrap，统计块自动换行不挤爆。
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 20,
              runSpacing: 12,
              children: [
                for (final s in stats)
                  WordStatBlock(
                      label: s.label, value: s.value, accent: s.accent),
              ],
            ),
            const SizedBox(height: 20),
            GameActionButton(
              label: '再来一局',
              primary: true,
              expand: true,
              onTap: onAgain,
            ),
          ],
        ),
      ),
    );
  }
}

/// 菜单面板：标题 + 副文案 + 规则列表 + AI 说明行。
class WordMenuShell extends StatelessWidget {
  const WordMenuShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.rules,
    required this.aiLine,
  });

  final String title;
  final String subtitle;
  final List<List<WordSeg>> rules;
  final String aiLine;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: context.heading(size: CitroType.heading, color: c.ink),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: context.body(size: CitroType.meta, color: c.ink2),
            ),
            const SizedBox(height: 18),
            WordRulesList(texts: rules),
            const SizedBox(height: 16),
            Text(
              aiLine,
              textAlign: TextAlign.center,
              style: context.body(size: CitroType.small, color: c.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}

/// 棋盘舞台壳：LayoutBuilder 约束 + 卡片底 + 圆角裁剪，按阶段切换
/// 菜单 / 对局 / 结算三态。
class WordBoardShell extends StatelessWidget {
  const WordBoardShell({
    super.key,
    required this.colors,
    required this.phaseIndex,
    required this.menu,
    required this.playing,
    required this.result,
  });

  final CitroColors colors;

  /// 0 = menu, 1 = playing, 2 = result。
  final int phaseIndex;
  final Widget menu;
  final Widget playing;
  final Widget result;

  @override
  Widget build(BuildContext context) {
    final c = colors;
    return LayoutBuilder(
      builder: (context, constraints) {
        final w =
            constraints.maxWidth.isFinite ? constraints.maxWidth : 360.0;
        // 键盘弹出时压缩棋盘：棋盘是固定高（滚动区无界），不压的话
        // 输入行会被顶到首屏之外。
        final kb = MediaQuery.viewInsetsOf(context).bottom;
        final h = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : math.max(
                220.0,
                math.min(600.0, math.max(420.0, w * 1.5)) - kb,
              );
        final id = GameIdentityScope.of(context);
        return SizedBox(
          width: w,
          height: h,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(CitroColors.radii.card),
              border: Border.all(color: id.primary.withAlpha(46)),
              boxShadow: CitroColors.shadows.card(c),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(CitroColors.radii.card),
              child: phaseIndex == 0
                  ? menu
                  : (phaseIndex == 1 ? playing : result),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 壹 / 贰 / 叁 / 肆 序数印章字
//
// App 内置的 zcool-app.ttf 是子集字体，没有这四个字（web 端用的是全量
// ZCOOL KuaiLe，页面靠它渲染）。这里把 devtools/fonts-src/ZCOOLKuaiLe.ttf
// 里四个字的字形轮廓（纯直线轮廓）内嵌成路径，按 web 的字号与基线绘制：
// ZCOOL KuaiLe upm=1000 / hhea ascent=880 / descent=-120 / advance=920。
// 这样不新增字体资源也能与参考图逐像素一致。
// ---------------------------------------------------------------------------

class OrdinalGlyph extends StatelessWidget {
  const OrdinalGlyph(this.ord, {super.key, this.fontSize = 12, this.color});

  final String ord;
  final double fontSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final resolved = color ?? context.c.ink;
    return SizedBox(
      width: fontSize * 0.92,
      height: fontSize,
      child: CustomPaint(
        painter: _OrdinalGlyphPainter(ord, fontSize, resolved),
      ),
    );
  }
}

class _OrdinalGlyphPainter extends CustomPainter {
  _OrdinalGlyphPainter(this.ord, this.fontSize, this.color);

  final String ord;
  final double fontSize;
  final Color color;

  static const Map<String, String> _glyphs = {
    '壹': 'M468,648L468,630L701,636L703,541L197,530L194,623L374,627L374,649L71,655L72,748L374,743L374,778L468,778L468,742L806,737L804,642ZM714,316L751,422L156,420L159,317L66,313L61,465L107,513L817,517L862,455L803,286ZM213,407L686,411L687,317L213,313ZM203,121L189,250L237,301L663,301L711,248L696,138L652,98L633,97L620,56L822,65L826,-30L62,-60L58,33L273,42L260,80L253,80ZM293,176L608,190L609,207L289,207ZM370,46L520,52L533,93L357,85Z',
    '贰': 'M829,-69L674,85L660,108L568,602L25,610L26,705L550,697L534,783L626,801L645,696L729,695L690,760L771,808L841,693L875,693L874,598L663,601L750,141L895,-3ZM468,466L69,480L73,573L471,560ZM495,348L81,350L81,445L495,443ZM514,90L423,112L449,226L381,227L309,119L530,31L495,-57L255,39L169,-90L90,-38L268,230L156,233L165,106L70,100L59,280L108,330L510,318L555,260Z',
    '叁': 'M744,393L857,249L783,190L687,313L685,234L282,254L284,287L131,126L62,191L267,407L95,412L98,506L354,498L405,552L235,537L195,615L322,771L396,711L338,641L649,667L627,724L715,759L795,554L707,519L684,576L476,558L511,526L481,495L857,484L855,390ZM338,344L675,329L623,397L394,403ZM272,191L653,200L656,106L273,97ZM201,42L817,90L825,-4L207,-51Z',
    '肆': 'M826,469L826,389L781,341L675,336L674,286L820,291L824,196L670,191L669,145L876,155L880,60L665,50L662,-53L567,-51L570,45L449,40L445,135L574,141L575,188L485,185L482,280L579,283L580,331L465,325L460,420L584,425L586,484L422,494L427,587L589,577L591,630L456,640L464,734L594,724L596,776L691,772L689,717L781,711L825,664L825,564L880,561L875,466ZM41,260L94,266L61,680L107,730L364,734L365,639L159,637L164,573L355,587L362,494L171,478L176,417L399,446L411,352L184,322L188,276L420,302L430,209L223,185L170,57L311,78L290,135L379,167L450,-24L362,-56L345,-11L102,-49L51,16L115,173L51,166ZM686,623L684,572L731,569L731,620ZM732,475L680,478L679,429L732,432Z',
  };

  @override
  void paint(Canvas canvas, Size size) {
    final data = _glyphs[ord];
    if (data == null) return;
    final scale = fontSize / 1000;
    canvas.save();
    canvas.translate(0, fontSize * 0.88);
    canvas.scale(scale, -scale);
    canvas.drawPath(
      _parse(data),
      Paint()
        ..color = color
        ..isAntiAlias = true
        ..style = PaintingStyle.fill,
    );
    canvas.restore();
  }

  static Path _parse(String data) {
    final path = Path();
    var cmd = 'M';
    var i = 0;
    while (i < data.length) {
      final ch = data[i];
      final code = data.codeUnitAt(i);
      if (ch == 'Z') {
        path.close();
        i++;
        continue;
      }
      if (code >= 65 && code <= 90) {
        cmd = ch;
        i++;
        continue;
      }
      final xEnd = _numEnd(data, i);
      final x = double.parse(data.substring(i, xEnd));
      i = xEnd;
      if (i < data.length && data[i] == ',') i++;
      final yEnd = _numEnd(data, i);
      final y = double.parse(data.substring(i, yEnd));
      i = yEnd;
      if (cmd == 'M') {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path;
  }

  static int _numEnd(String data, int start) {
    var i = start;
    while (i < data.length) {
      final c = data.codeUnitAt(i);
      final isDigit = c >= 48 && c <= 57;
      if (!isDigit && data[i] != '-' && data[i] != '.') break;
      i++;
    }
    return i;
  }

  @override
  bool shouldRepaint(covariant _OrdinalGlyphPainter old) =>
      old.ord != ord || old.fontSize != fontSize || old.color != color;
}
