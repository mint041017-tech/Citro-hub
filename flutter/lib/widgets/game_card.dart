import 'package:flutter/material.dart';

import '../games/game_identity.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'game_emblem.dart';
import 'paper.dart';

/// 卡片自己的纸与墨：固定常量，不读主题。
///
/// 这样同一张游戏卡在亮色 / 暗色、以及任何模块皮肤下都是**像素一致**的——
/// 玩家靠颜色和图形认游戏，不靠主题。
const Color _kGamePaper = Color(0xFFFFFDF8);
const Color _kGameInk = Color(0xFF23211C);

/// 游戏卡：游戏页栅格与首页会玩位共用同一张卡。
///
/// 卡面颜色全部来自 [GameIdentity]，不读 `CitroColors.accent`。
class GameCard extends StatelessWidget {
  const GameCard({
    super.key,
    required this.identity,
    this.onTap,
    this.compact = false,
  });

  final GameIdentity identity;

  /// 传了才响应点击；不传就是一张纯展示卡（golden、占位）。
  final VoidCallback? onTap;

  /// 紧凑档：栅格列数多（平板 / 桌面）或首页小卡时用。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(15);
    final card = Container(
      decoration: BoxDecoration(
        color: _kGamePaper,
        borderRadius: radius,
        border: Border.all(color: identity.deep.withValues(alpha: .28)),
        boxShadow: [
          BoxShadow(
            color: identity.deep.withValues(alpha: .18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _cover(compact)),
          _TitleStrip(identity: identity, compact: compact),
          GameCardMeta(identity: identity, compact: compact),
        ],
      ),
    );
    if (onTap == null) return card;
    return Pressable(
      onTap: onTap,
      scale: .97,
      borderRadius: radius,
      hoverLift: 1.5,
      hoverColor: identity.soft.withValues(alpha: .35),
      child: card,
    );
  }

  Widget _cover(bool compact) {
    final ground = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        identity.soft,
        Color.lerp(identity.soft, identity.primary, .38)!,
      ],
    );
    return Container(
      margin: const EdgeInsets.all(1),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 6 : 10,
      ),
      decoration: BoxDecoration(
        gradient: ground,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(14),
          topRight: Radius.circular(14),
          bottomLeft: Radius.circular(9),
          bottomRight: Radius.circular(9),
        ),
        border: Border.all(color: identity.deep.withValues(alpha: .18)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: GameEmblem(
                  identity: identity,
                  size: compact ? 52 : 68,
                ),
              ),
            ),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: GameTagChip(identity: identity),
          ),
          // 胶带穗：手账卡的签名，每张都有。
          Positioned(
            top: -7,
            left: 9,
            child: _TapeValance(identity: identity),
          ),
        ],
      ),
    );
  }
}

/// 胶带穗：贴在封面左上的一小条。
class _TapeValance extends StatelessWidget {
  const _TapeValance({required this.identity});

  final GameIdentity identity;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -2.5 * 3.141592653589793 / 180,
      child: Container(
        width: 72,
        height: 18,
        decoration: BoxDecoration(
          color: identity.primary.withValues(alpha: .5),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(2),
            topRight: Radius.circular(3),
            bottomLeft: Radius.circular(3),
            bottomRight: Radius.circular(2),
          ),
          border: Border.all(
            color: identity.deep.withValues(alpha: .12),
            width: .8,
          ),
        ),
      ),
    );
  }
}

/// 标题条：手写标题 + 身份色小竖条。
class _TitleStrip extends StatelessWidget {
  const _TitleStrip({required this.identity, required this.compact});

  final GameIdentity identity;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: compact ? 36 : 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: _kGamePaper,
        border: Border(
          top: BorderSide(color: identity.deep.withValues(alpha: .32)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              identity.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppFonts.zcool,
                fontFamilyFallback: AppFonts.fallback,
                fontSize: compact ? 14.5 : 16.5,
                height: 1.2,
                letterSpacing: .3,
                color: _kGameInk,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 2,
            height: 20,
            decoration: BoxDecoration(
              color: identity.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ),
    );
  }
}

/// 卡面底部的成绩行：左边分类，右边本地最佳。
class GameCardMeta extends StatelessWidget {
  const GameCardMeta({super.key, required this.identity, this.compact = false});

  final GameIdentity identity;
  final bool compact;

  static const Set<String> _timeBased = {'gnono', 'gslide', 'gmem'};

  @override
  Widget build(BuildContext context) {
    final key = bestKeyOf(identity.key);
    final state = AppState.instance;
    String text;
    try {
      if (_timeBased.contains(identity.key)) {
        final best = state.localBestTime(key);
        text = best > 0 ? '最佳 ${_fmtDuration(best)}' : '未玩';
      } else {
        final best = state.localBest(key);
        text = best > 0 ? '最佳 $best' : '未玩';
      }
    } catch (_) {
      // Prefs 还没初始化（预览 / 测试）时按未玩处理。
      text = '未玩';
    }
    return Container(
      height: compact ? 18 : 20,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: _kGamePaper,
        border: Border(
          top: BorderSide(color: identity.deep.withValues(alpha: .16)),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: identity.soft,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              identity.tag,
              style: TextStyle(
                fontFamily: AppFonts.noto,
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: .4,
                color: identity.deep,
                height: 1.2,
              ),
            ),
          ),
          const Spacer(),
          Text(
            text,
            style: TextStyle(
              fontFamily: AppFonts.kalam,
              fontFamilyFallback: AppFonts.fallback,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: .2,
              color: identity.ink.withValues(alpha: .72),
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  String _fmtDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// 分类小标签：贴在封面右上角的一枚小印章。
class GameTagChip extends StatelessWidget {
  const GameTagChip({super.key, required this.identity});

  final GameIdentity identity;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
      decoration: BoxDecoration(
        color: _kGamePaper.withValues(alpha: .92),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: identity.primary.withValues(alpha: .5)),
      ),
      child: Text(
        identity.tag,
        style: TextStyle(
          fontFamily: AppFonts.noto,
          fontSize: 9.5,
          fontWeight: FontWeight.w700,
          letterSpacing: .5,
          color: identity.deep,
          height: 1.1,
        ),
      ),
    );
  }
}

/// 首页会玩位的横卡：左图右题，一行一个游戏。
class GameBannerCard extends StatelessWidget {
  const GameBannerCard({
    super.key,
    required this.identity,
    this.onTap,
    this.height = 168,
  });

  final GameIdentity identity;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final compact = height < 150;
    final radius = BorderRadius.circular(16);
    final card = Container(
      height: height,
      decoration: BoxDecoration(
        color: _kGamePaper,
        borderRadius: radius,
        border: Border.all(color: identity.deep.withValues(alpha: .28)),
        boxShadow: [
          BoxShadow(
            color: identity.deep.withValues(alpha: .18),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          _art(compact),
          Expanded(child: _meta(context, compact)),
        ],
      ),
    );
    if (onTap == null) return card;
    return Pressable(
      onTap: onTap,
      scale: .98,
      borderRadius: radius,
      hoverLift: 1.5,
      hoverColor: identity.soft.withValues(alpha: .35),
      child: card,
    );
  }

  Widget _art(bool compact) {
    return Container(
      width: compact ? 104 : 128,
      margin: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            identity.soft,
            Color.lerp(identity.soft, identity.primary, .4)!,
          ],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(15),
          bottomLeft: Radius.circular(15),
          topRight: Radius.circular(12),
          bottomRight: Radius.circular(12),
        ),
        border: Border.all(color: identity.deep.withValues(alpha: .18)),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: GameEmblem(
                  identity: identity,
                  size: compact ? 52 : 68,
                ),
              ),
            ),
          ),
          Positioned(top: 6, right: 6, child: GameTagChip(identity: identity)),
        ],
      ),
    );
  }

  Widget _meta(BuildContext context, bool compact) {
    final c = context.c;
    return Padding(
      padding: EdgeInsets.fromLTRB(compact ? 10 : 14, compact ? 8 : 12, 10, compact ? 8 : 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Spacer(),
          Text(
            identity.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: AppFonts.zcool,
              fontFamilyFallback: AppFonts.fallback,
              fontSize: compact ? 16 : 19,
              height: 1.2,
              letterSpacing: .3,
              color: _kGameInk,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '开局',
            style: context.body(size: 11, color: c.inkSoft, letterSpacing: .4),
          ),
          const Spacer(),
          GameCardMeta(identity: identity, compact: true),
        ],
      ),
    );
  }
}
