import 'package:flutter/material.dart';

import '../services/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';

Future<void> showWeatherDialog(BuildContext context) async {
  await showCitroDialog(context, builder: (ctx) => const _WeatherDialog());
}

class _WeatherDialog extends StatefulWidget {
  const _WeatherDialog();
  @override
  State<_WeatherDialog> createState() => _WeatherDialogState();
}

class _WeatherDialogState extends State<_WeatherDialog> {
  bool locating = false;

  @override
  void initState() {
    super.initState();
    final state = AppState.instance;
    if (state.weather.daily.isEmpty) state.refreshWeather();
  }

  Future<void> _locateAndRefresh() async {
    if (locating) return;
    setState(() => locating = true);
    final ok = await AppState.instance.refreshWeatherWithLocation(force: true);
    if (!mounted) return;
    setState(() => locating = false);
    if (!ok) AppToast.show(context, '定位未开启，已使用上次位置');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final state = context.app;
    final w = state.weather;
    return PaperDialog(
      maxWidth: 400,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('🌤️ 天气详情', style: context.heading(size: 20)),
              ),
              if (state.weatherLoading || locating)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 1.6),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          _weather(c, w, state),
        ],
      ),
    );
  }

  Widget _weather(CitroColors c, WeatherNow w, AppState state) {
    final today = w.daily.isNotEmpty ? w.daily.first : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(w.emoji, style: const TextStyle(fontSize: 52, height: 1)),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${w.temp.round()}',
                      style: context.display(
                        size: 44,
                        weight: FontWeight.w700,
                        color: c.ink,
                        height: 1,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '°C',
                        style: context.body(size: 14, color: c.inkSoft),
                      ),
                    ),
                  ],
                ),
                Text(
                  '${w.desc} · ${w.city}',
                  style: context.body(size: 13, color: c.ink2),
                ),
                if (today != null)
                  Text(
                    '最高 ${today.max.round()}° / 最低 ${today.min.round()}°',
                    style: context.body(size: 11.5, color: c.inkSoft),
                  ),
              ],
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '体感 ${w.feels.round()}°',
                  style: context.body(size: 12, color: c.inkSoft),
                ),
                const SizedBox(height: 2),
                Text(
                  '湿度 ${w.humidity}%',
                  style: context.body(size: 12, color: c.inkSoft),
                ),
                const SizedBox(height: 2),
                Text(
                  '${w.windDirection} ${w.wind.round()} km/h',
                  style: context.body(size: 12, color: c.inkSoft),
                ),
              ],
            ),
          ],
        ),
        if (w.hourly.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 88,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: w.hourly.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                final hour = w.hourly[index];
                final current = index == 0;
                return Container(
                  width: 58,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  decoration: BoxDecoration(
                    color: current ? c.hl : c.surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: current ? c.accent : c.line),
                  ),
                  child: Column(
                    children: [
                      Text(
                        current
                            ? '现在'
                            : '${hour.time.hour.toString().padLeft(2, '0')}:00',
                        style: context.body(
                          size: 10.5,
                          weight: current ? FontWeight.w700 : FontWeight.w400,
                          color: current ? c.accentInk : c.inkSoft,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        weatherEmoji(hour.code),
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${hour.temp.round()}°',
                        style: context.body(
                          size: 12,
                          weight: FontWeight.w700,
                          color: c.ink,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 12),
        DashedLine(color: c.line2),
        const SizedBox(height: 8),
        if (w.daily.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              state.weatherError ?? '天气加载中…',
              textAlign: TextAlign.center,
              style: context.body(size: 12, color: c.inkSoft),
            ),
          )
        else
          ...w.daily.map(
            (d) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Text(
                      d.date.month == DateTime.now().month &&
                              d.date.day == DateTime.now().day
                          ? '今天'
                          : '周${'一二三四五六日'[d.date.weekday - 1]}',
                      style: context.body(
                        size: 12,
                        weight: FontWeight.w600,
                        color: c.ink2,
                      ),
                    ),
                  ),
                  Text(
                    weatherEmoji(d.code),
                    style: const TextStyle(fontSize: 18),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      weatherText(d.code),
                      style: context.body(size: 12, color: c.inkSoft),
                    ),
                  ),
                  if (d.rain > 0) ...[
                    Text(
                      '${d.rain}%',
                      style: context.body(size: 11, color: c.mintInk),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    '${d.min.round()}° / ${d.max.round()}°',
                    style: context.body(
                      size: 12,
                      weight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _locateAndRefresh,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(
                strokeSvg(AppIcons.location, width: 2),
                size: 13,
                color: c.accentInk,
              ),
              const SizedBox(width: 4),
              Text(
                locating ? '定位中…' : '定位并刷新',
                style: context.body(size: 11.5, color: c.accentInk),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}
