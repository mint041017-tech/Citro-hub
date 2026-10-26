import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/paper.dart';
import 'g2048.dart' deferred as g2048;
import 'gbrake_web.dart' deferred as gbrake;
import 'gfeihua.dart' deferred as gfeihua;
import 'gidiom.dart' deferred as gidiom;
import 'gjump.dart' deferred as gjump;
import 'gliquid.dart' deferred as gliquid;
import 'gmemory.dart' deferred as gmemory;
import 'gnono.dart' deferred as gnono;
import 'gpeng.dart' deferred as gpeng;
import 'gsheep.dart' deferred as gsheep;
import 'gslide.dart' deferred as gslide;
import 'gsnake.dart' deferred as gsnake;
import 'gsudoku.dart' deferred as gsudoku;

Future<Widget> _loadPage(String key) async {
  switch (key) {
    case 'g2048':
      await g2048.loadLibrary();
      return g2048.Game2048Page();
    case 'gmem':
      await gmemory.loadLibrary();
      return gmemory.GameMemoryPage();
    case 'gsudoku':
      await gsudoku.loadLibrary();
      return gsudoku.GameSudokuPage();
    case 'gnono':
      await gnono.loadLibrary();
      return gnono.GameNonoPage();
    case 'gslide':
      await gslide.loadLibrary();
      return gslide.GameSlidePage();
    case 'gsnake':
      await gsnake.loadLibrary();
      return gsnake.GameSnakePage();
    case 'gsheep':
      await gsheep.loadLibrary();
      return gsheep.GameSheepPage();
    case 'gjump':
      await gjump.loadLibrary();
      return gjump.GameJumpPage();
    case 'gpeng':
      await gpeng.loadLibrary();
      return gpeng.GamePengPage();
    case 'gbrake':
      await gbrake.loadLibrary();
      return gbrake.GameBrakeWebPage();
    case 'gidiom':
      await gidiom.loadLibrary();
      return gidiom.GameIdiomPage();
    case 'gfeihua':
      await gfeihua.loadLibrary();
      return gfeihua.GameFeihuaPage();
    case 'gliquid':
      await gliquid.loadLibrary();
      return gliquid.GameLiquidPage();
    default:
      return const _MissingGame();
  }
}

Widget buildGamePage(String key) => _DeferredGamePage(gameKey: key);

class _DeferredGamePage extends StatefulWidget {
  final String gameKey;

  const _DeferredGamePage({required this.gameKey});

  @override
  State<_DeferredGamePage> createState() => _DeferredGamePageState();
}

class _DeferredGamePageState extends State<_DeferredGamePage> {
  late Future<Widget> _page = _loadPage(widget.gameKey);

  void _retry() {
    setState(() => _page = _loadPage(widget.gameKey));
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _page,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _GameLoadError(onRetry: _retry);
        }
        return snapshot.data ?? const _GameLoading();
      },
    );
  }
}

class _GameLoading extends StatelessWidget {
  const _GameLoading();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.surface,
      body: PaperBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/images/logo.webp',
                width: 92,
                height: 92,
                cacheWidth: 184,
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: 84,
                child: LinearProgressIndicator(
                  minHeight: 3,
                  color: c.accent,
                  backgroundColor: c.accent.withAlpha(34),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '正在准备游戏…',
                style: context.body(size: 12.5, color: c.inkSoft),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameLoadError extends StatelessWidget {
  final VoidCallback onRetry;

  const _GameLoadError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.surface,
      body: PaperBackground(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('🍊', style: const TextStyle(fontSize: 36)),
              const SizedBox(height: 10),
              Text('游戏加载失败', style: context.heading(size: 20)),
              const SizedBox(height: 6),
              Text(
                '检查网络后再试一次',
                style: context.body(size: 12, color: c.inkSoft),
              ),
              const SizedBox(height: 16),
              Pressable(
                onTap: onRetry,
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  decoration: BoxDecoration(
                    color: c.accent,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Center(
                    child: Text(
                      '重新加载',
                      style: context.body(
                        size: 13,
                        weight: FontWeight.w700,
                        color: const Color(0xFF2E2C22),
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
}

class _MissingGame extends StatelessWidget {
  const _MissingGame();

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Scaffold(
      backgroundColor: c.surface,
      body: PaperBackground(
        child: Center(child: Text('敬请期待', style: context.heading(size: 22))),
      ),
    );
  }
}
