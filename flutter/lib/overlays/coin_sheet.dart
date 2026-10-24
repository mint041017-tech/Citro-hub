import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';

Future<void> showCoinSheet(BuildContext context) async {
  await showCitroDialog(context, builder: (_) => const _CoinDialog());
}

enum _CoinOutcome { front, back, edge }

class _CoinDialog extends StatefulWidget {
  const _CoinDialog();

  @override
  State<_CoinDialog> createState() => _CoinDialogState();
}

class _CoinDialogState extends State<_CoinDialog>
    with TickerProviderStateMixin {
  static const _turn = math.pi * 2;
  static const _tossCurve = Cubic(.32, .08, .24, 1);

  final _random = math.Random();
  late final AnimationController _toss;
  late final AnimationController _wobble;
  late final Animation<double> _lift;
  late final Animation<double> _tilt;
  Timer? _introTimer;

  bool _busy = false;
  _CoinOutcome? _result;
  double _rotation = 0;
  double _startRotation = 0;
  double _endRotation = 0;

  @override
  void initState() {
    super.initState();
    _toss = AnimationController(vsync: this);
    _wobble = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
    );
    const weights = <double>[9, 21, 18, 20, 18, 7, 3.5, 3.5];
    _lift = TweenSequence<double>([
      _frame(0, -56, weights[0]),
      _frame(-56, -138, weights[1]),
      _frame(-138, -152, weights[2]),
      _frame(-152, -88, weights[3]),
      _frame(-88, -14, weights[4]),
      _frame(-14, 0, weights[5]),
      _frame(0, -7, weights[6]),
      _frame(-7, 0, weights[7]),
    ]).animate(_toss);
    _tilt = TweenSequence<double>([
      _frame(0, -16, weights[0]),
      _frame(-16, -11, weights[1]),
      _frame(-11, 7, weights[2]),
      _frame(7, -6, weights[3]),
      _frame(-6, 4, weights[4]),
      _frame(4, 0, weights[5]),
      _frame(0, 0, weights[6] + weights[7]),
    ]).animate(_toss);
    _introTimer = Timer(const Duration(milliseconds: 400), _flip);
  }

  TweenSequenceItem<double> _frame(double begin, double end, double weight) =>
      TweenSequenceItem(
        tween: Tween(begin: begin, end: end),
        weight: weight,
      );

  _CoinOutcome _pickOutcome() {
    final roll = _random.nextDouble();
    if (roll < .49) return _CoinOutcome.front;
    if (roll < .98) return _CoinOutcome.back;
    return _CoinOutcome.edge;
  }

  Future<void> _flip() async {
    if (_busy || !mounted) return;
    _introTimer?.cancel();
    final outcome = _pickOutcome();
    final target = switch (outcome) {
      _CoinOutcome.front => 0.0,
      _CoinOutcome.back => math.pi,
      _CoinOutcome.edge => math.pi / 2,
    };
    final spins = 7 + _random.nextInt(4);
    final current = _rotation % _turn;
    final adjustment = (target - current + _turn) % _turn;
    setState(() {
      _busy = true;
      _result = null;
      _startRotation = _rotation;
      _endRotation = _rotation + spins * _turn + adjustment;
    });
    _toss.duration = Duration(
      milliseconds: outcome == _CoinOutcome.edge ? 2500 : 2200,
    );
    HapticFeedback.lightImpact();
    await _toss.forward(from: 0);
    if (!mounted) return;
    _rotation = _endRotation;
    if (outcome == _CoinOutcome.edge) {
      await _wobble.forward(from: 0);
      if (!mounted) return;
    }
    HapticFeedback.selectionClick();
    setState(() {
      _result = outcome;
      _busy = false;
    });
  }

  @override
  void dispose() {
    _introTimer?.cancel();
    _toss.dispose();
    _wobble.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final copy = _resultCopy(_result);
    return PaperDialog(
      maxWidth: 376,
      tapeColor: c.tape3,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '抛硬币',
            textAlign: TextAlign.center,
            style: context.heading(size: 25, color: c.ink),
          ),
          const SizedBox(height: 4),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Text(
              copy.$2,
              key: ValueKey(copy.$2),
              textAlign: TextAlign.center,
              style: context.body(size: 12, color: c.inkSoft),
            ),
          ),
          SizedBox(
            height: 286,
            child: AnimatedBuilder(
              animation: Listenable.merge([_toss, _wobble]),
              builder: (context, _) {
                final raw = _toss.value;
                final curved = _tossCurve.transform(raw);
                final angle =
                    _startRotation + (_endRotation - _startRotation) * curved;
                final lift = raw == 0 ? 0.0 : _lift.value;
                final tilt = raw == 0 ? 0.0 : _tilt.value;
                final wobble = _wobble.isAnimating
                    ? math.sin(_wobble.value * math.pi * 5) *
                          (1 - _wobble.value) *
                          .28
                    : 0.0;
                return Stack(
                  alignment: Alignment.center,
                  children: [
                    Positioned(
                      bottom: 27,
                      child: AnimatedOpacity(
                        opacity: _result == null ? .25 : .7,
                        duration: const Duration(milliseconds: 250),
                        child: Container(
                          width: 126,
                          height: 18,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: c.accent.withAlpha(
                              _result == null ? 18 : 42,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: c.accent.withAlpha(
                                  _result == null ? 0 : 65,
                                ),
                                blurRadius: 28,
                                spreadRadius: 7,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 17,
                      child: Container(
                        width: 102,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withAlpha(c.dark ? 90 : 30),
                        ),
                      ),
                    ),
                    Transform.translate(
                      offset: Offset(0, lift),
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, .0022)
                          ..rotateX(tilt * math.pi / 180)
                          ..rotateY(angle)
                          ..rotateZ(wobble),
                        child: _buildCoin(c, angle),
                      ),
                    ),
                    if (_result != null && raw == 1)
                      const Positioned.fill(
                        child: IgnorePointer(child: _CoinSparkles()),
                      ),
                  ],
                );
              },
            ),
          ),
          AnimatedOpacity(
            opacity: _result == null ? 0 : 1,
            duration: const Duration(milliseconds: 240),
            child: Text(
              copy.$1,
              textAlign: TextAlign.center,
              style: context.heading(
                size: 18,
                color: _result == _CoinOutcome.edge ? c.stamp : c.accentInk,
              ),
            ),
          ),
          const SizedBox(height: 18),
          AccentButton(
            text: _busy ? '硬币飞舞中…' : '再抛一次',
            onTap: _busy ? null : _flip,
          ),
        ],
      ),
    );
  }

  Widget _buildCoin(CitroColors c, double angle) {
    final front = math.cos(angle) >= 0;
    final edge = math.cos(angle).abs() < .08;
    return SizedBox(
      width: 158,
      height: 158,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (edge)
            Container(
              width: 14,
              height: 150,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFF8F5718),
                    Color(0xFFFFD477),
                    Color(0xFF9A5A16),
                  ],
                ),
                boxShadow: const [
                  BoxShadow(color: Color(0x55A86B20), blurRadius: 14),
                ],
              ),
            ),
          if (!edge)
            Container(
              width: 154,
              height: 154,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFB87923), width: 5),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFFFFE5A0),
                    Color(0xFFE6AA43),
                    Color(0xFFFFD477),
                  ],
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x4D765018),
                    blurRadius: 18,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: front
                  ? Padding(
                      padding: const EdgeInsets.all(19),
                      child: Image.asset(
                        'assets/images/logo.webp',
                        fit: BoxFit.contain,
                      ),
                    )
                  : Transform(
                      alignment: Alignment.center,
                      transform: Matrix4.rotationY(math.pi),
                      child: Center(
                        child: Text(
                          'Citro',
                          style: context.display(
                            size: 30,
                            weight: FontWeight.w700,
                            color: const Color(0xFF875015),
                          ),
                        ),
                      ),
                    ),
            ),
        ],
      ),
    );
  }

  (String, String) _resultCopy(_CoinOutcome? outcome) {
    if (_busy) return ('', '硬币飞舞中…');
    return switch (outcome) {
      _CoinOutcome.front => ('✦ Logo · 正面', '正面朝上，好运相伴！'),
      _CoinOutcome.back => ('Citro · 反面', '沉稳前行，自有收获。'),
      _CoinOutcome.edge => ('立起来了！', '万里挑一的平衡——命运另有安排。'),
      null => ('', '点击「再抛一次」试试手气'),
    };
  }
}

class _CoinSparkles extends StatelessWidget {
  const _CoinSparkles();

  @override
  Widget build(BuildContext context) {
    const points = <Offset>[
      Offset(.16, .25),
      Offset(.82, .22),
      Offset(.12, .53),
      Offset(.88, .5),
      Offset(.24, .72),
      Offset(.76, .72),
      Offset(.34, .14),
      Offset(.67, .13),
    ];
    return LayoutBuilder(
      builder: (context, constraints) => Stack(
        children: [
          for (var i = 0; i < points.length; i++)
            Positioned(
              left: points[i].dx * constraints.maxWidth,
              top: points[i].dy * constraints.maxHeight,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Duration(milliseconds: 420 + i * 25),
                curve: Curves.easeOutBack,
                builder: (context, value, _) => Opacity(
                  opacity: value.clamp(0, 1),
                  child: Transform.scale(
                    scale: value,
                    child: Icon(
                      i.isEven ? Icons.star : Icons.circle,
                      size: i.isEven ? 13 : 6,
                      color: context.c.accentLt,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
