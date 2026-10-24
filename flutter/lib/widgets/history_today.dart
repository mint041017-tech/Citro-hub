import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme/app_theme.dart';
import 'paper.dart';

class HistoryTodayCard extends StatefulWidget {
  const HistoryTodayCard({super.key});

  @override
  State<HistoryTodayCard> createState() => _HistoryTodayCardState();
}

class _HistoryTodayCardState extends State<HistoryTodayCard> {
  List<({String year, String text})> _items = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await Api.historyToday();
      final raw = data['items'];
      final items = <({String year, String text})>[];
      if (raw is List) {
        for (final item in raw) {
          if (item is! Map) continue;
          final year = '${item['year'] ?? ''}'.trim();
          final text = '${item['text'] ?? ''}'.trim();
          if (text.isNotEmpty) items.add((year: year, text: text));
        }
      }
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = items.isEmpty ? '今天的事件还没准备好，稍后再来' : null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '网络错误，稍后再试';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final now = DateTime.now();
    return PaperCard(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('历史上的今天', style: context.heading(size: 15, color: c.ink)),
              const Spacer(),
              Text(
                '${now.month}月${now.day}日',
                style: context.body(size: 10.5, color: c.accentInk),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else if (_error != null)
            Column(
              children: [
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: context.body(size: 11.5, color: c.inkSoft),
                ),
                const SizedBox(height: 6),
                TextButton(onPressed: _load, child: const Text('再试一次')),
              ],
            )
          else
            for (final item in _items)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 42,
                      child: Text(
                        item.year,
                        style: context.display(
                          size: 12,
                          weight: FontWeight.w700,
                          color: c.accentInk,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        item.text,
                        style: context.body(
                          size: 12,
                          height: 1.55,
                          color: c.ink2,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
