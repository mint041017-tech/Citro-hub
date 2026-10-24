import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme/app_theme.dart';
import 'paper.dart';

class VoiceBubble extends StatefulWidget {
  final String url;
  final int seconds;
  final bool local;
  final double width;
  const VoiceBubble({
    super.key,
    required this.url,
    required this.seconds,
    this.local = false,
    this.width = 176,
  });

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  late final AudioPlayer _player;
  bool playing = false;
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  StreamSubscription? _posSub;
  StreamSubscription? _durSub;
  StreamSubscription? _doneSub;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    duration = Duration(seconds: widget.seconds);
    _posSub = _player.onPositionChanged.listen((d) {
      if (mounted) setState(() => position = d);
    });
    _durSub = _player.onDurationChanged.listen((d) {
      if (mounted && d.inMilliseconds > 0) setState(() => duration = d);
    });
    _doneSub = _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          playing = false;
          position = Duration.zero;
        });
      }
    });
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _doneSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant VoiceBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _player.stop();
      position = Duration.zero;
      duration = Duration(seconds: widget.seconds);
      playing = false;
    } else if (oldWidget.seconds != widget.seconds) {
      duration = Duration(seconds: widget.seconds);
    }
  }

  Future<void> _toggle() async {
    if (playing) {
      await _player.pause();
      if (mounted) setState(() => playing = false);
    } else {
      try {
        final Source source;
        if (widget.local) {
          final comma = widget.url.indexOf(',');
          if (comma < 0) throw const FormatException('invalid data url');
          final header = widget.url.substring(0, comma);
          final mime = header.startsWith('data:')
              ? header.substring(5).split(';').first
              : 'audio/mp4';
          source = BytesSource(
            base64Decode(widget.url.substring(comma + 1)),
            mimeType: mime.isEmpty ? 'audio/mp4' : mime,
          );
        } else {
          source = UrlSource(Api.imageUrl(widget.url));
        }
        await _player.play(source);
        if (mounted) setState(() => playing = true);
      } catch (_) {
        if (mounted) AppToast.show(context, '语音播放失败');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = duration.inMilliseconds <= 0
        ? widget.seconds * 1000
        : duration.inMilliseconds;
    final pct = total <= 0
        ? 0.0
        : (position.inMilliseconds / total).clamp(0.0, 1.0);
    return GestureDetector(
      onTap: _toggle,
      child: Container(
        width: widget.width,
        padding: const EdgeInsets.fromLTRB(8, 6, 10, 6),
        decoration: BoxDecoration(
          color: context.c.dark
              ? const Color(0x22FFFFFF)
              : const Color(0x14F2A43C),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: context.c.line2.withAlpha(150)),
        ),
        child: Row(
          children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: context.c.accent,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Icon(
                  playing ? Icons.pause : Icons.play_arrow,
                  size: 15,
                  color: const Color(0xFF2E2C22),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 4,
                  backgroundColor: context.c.line2.withAlpha(90),
                  valueColor: AlwaysStoppedAnimation(context.c.accentInk),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${widget.seconds}"',
              style: context.body(size: 10, color: context.c.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}
