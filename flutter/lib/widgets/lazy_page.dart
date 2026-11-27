import 'package:flutter/material.dart';

/// 延迟加载页面的壳。
///
/// `deferred import` 的页面第一次被打开时，先 await `loadLibrary()` 把代码分片
/// 下回来，再换成真正的页面。下载期间给一个和全站同色的过渡页，避免白屏。
///
/// 只给「非首屏」的页面用：首页 / 计划 / 游戏 / 社区 / 资源库这几个 Tab
/// 仍然静态编译在主包里，切 Tab 时才不会有等待。
class CitroLazyPage extends StatefulWidget {
  /// 真正页面的加载器：内部 await 分片的 loadLibrary()，再返回页面实例。
  final Future<Widget> Function() load;

  const CitroLazyPage({super.key, required this.load});

  @override
  State<CitroLazyPage> createState() => _CitroLazyPageState();
}

class _CitroLazyPageState extends State<CitroLazyPage> {
  late Future<Widget> _future = widget.load();

  void _retry() {
    setState(() => _future = widget.load());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _LazyError(onRetry: _retry);
        }
        final page = snapshot.data;
        if (page == null) return const _LazyLoading();
        return page;
      },
    );
  }
}

class _LazyLoading extends StatelessWidget {
  const _LazyLoading();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: Center(
        child: SizedBox(
          width: 84,
          child: LinearProgressIndicator(
            minHeight: 3,
            // 跟随背景派生的强调色（secondary = accent），不用近黑的 primary。
            color: scheme.secondary,
            backgroundColor: scheme.secondaryContainer,
          ),
        ),
      ),
    );
  }
}

class _LazyError extends StatelessWidget {
  final VoidCallback onRetry;

  const _LazyError({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('页面加载失败', style: TextStyle(color: scheme.onSurface)),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: const Text('重新加载')),
          ],
        ),
      ),
    );
  }
}
