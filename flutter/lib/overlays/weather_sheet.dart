import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';

Future<void> showWeatherDialog(BuildContext context) async {
  await showCitroDialog(context, builder: (ctx) => const _WeatherDialog());
}

/// 城市选择：搜索（Open-Meteo 地理编码）+ 热门城市兜底。
Future<void> showCityPickerDialog(BuildContext context) async {
  await showCitroDialog(context, builder: (ctx) => const _CityPickerDialog());
}

class _CityHit {
  final String name;
  final double lat;
  final double lon;
  final String region;

  const _CityHit({
    required this.name,
    required this.lat,
    required this.lon,
    this.region = '',
  });

  /// 同名同坐标视为同一个城市，去掉接口返回的重复项。
  @override
  bool operator ==(Object other) =>
      other is _CityHit &&
      other.name == name &&
      other.lat == lat &&
      other.lon == lon;

  @override
  int get hashCode => Object.hash(name, lat, lon);
}

/// 搜索接口失败时也能直接选，不必联网。
const List<_CityHit> _kHotCities = [
  _CityHit(name: '北京', lat: 39.9042, lon: 116.4074),
  _CityHit(name: '上海', lat: 31.2304, lon: 121.4737),
  _CityHit(name: '广州', lat: 23.1291, lon: 113.2644),
  _CityHit(name: '惠州', lat: 23.1115, lon: 114.4152),
  _CityHit(name: '深圳', lat: 22.5431, lon: 114.0579),
  _CityHit(name: '东莞', lat: 23.0207, lon: 113.7518),
  _CityHit(name: '佛山', lat: 23.0219, lon: 113.1214),
  _CityHit(name: '珠海', lat: 22.2707, lon: 113.5767),
  _CityHit(name: '中山', lat: 22.5171, lon: 113.3929),
  _CityHit(name: '汕头', lat: 23.3541, lon: 116.6819),
  _CityHit(name: '成都', lat: 30.5728, lon: 104.0668),
  _CityHit(name: '杭州', lat: 30.2741, lon: 120.1551),
  _CityHit(name: '重庆', lat: 29.5630, lon: 106.5516),
  _CityHit(name: '武汉', lat: 30.5928, lon: 114.3055),
  _CityHit(name: '西安', lat: 34.3416, lon: 108.9398),
  _CityHit(name: '南京', lat: 32.0603, lon: 118.7969),
  _CityHit(name: '天津', lat: 39.3434, lon: 117.3616),
  _CityHit(name: '苏州', lat: 31.2989, lon: 120.5853),
  _CityHit(name: '长沙', lat: 28.2282, lon: 112.9388),
  _CityHit(name: '郑州', lat: 34.7466, lon: 113.6254),
  _CityHit(name: '青岛', lat: 36.0671, lon: 120.3826),
  _CityHit(name: '沈阳', lat: 41.8057, lon: 123.4315),
  _CityHit(name: '哈尔滨', lat: 45.8038, lon: 126.5349),
  _CityHit(name: '厦门', lat: 24.4798, lon: 118.0894),
  _CityHit(name: '昆明', lat: 24.8801, lon: 102.8329),
  _CityHit(name: '海口', lat: 20.0444, lon: 110.1999),
  _CityHit(name: '南宁', lat: 22.8170, lon: 108.3665),
  _CityHit(name: '贵阳', lat: 26.6470, lon: 106.6302),
  _CityHit(name: '兰州', lat: 36.0611, lon: 103.8343),
  _CityHit(name: '银川', lat: 38.4872, lon: 106.2309),
  _CityHit(name: '拉萨', lat: 29.6520, lon: 91.1721),
  _CityHit(name: '乌鲁木齐', lat: 43.8256, lon: 87.6168),
  _CityHit(name: '呼和浩特', lat: 40.8424, lon: 111.7490),
  _CityHit(name: '太原', lat: 37.8706, lon: 112.5489),
  _CityHit(name: '合肥', lat: 31.8206, lon: 117.2272),
  _CityHit(name: '福州', lat: 26.0745, lon: 119.2965),
  _CityHit(name: '南昌', lat: 28.6820, lon: 115.8579),
  _CityHit(name: '长春', lat: 43.8171, lon: 125.3235),
  _CityHit(name: '香港', lat: 22.3193, lon: 114.1694),
  _CityHit(name: '澳门', lat: 22.1987, lon: 113.5439),
  _CityHit(name: '台北', lat: 25.0330, lon: 121.5654),
];

class _CityPickerDialog extends StatefulWidget {
  const _CityPickerDialog();

  @override
  State<_CityPickerDialog> createState() => _CityPickerDialogState();
}

class _CityPickerDialogState extends State<_CityPickerDialog> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  int _requestId = 0;
  bool _loading = false;
  bool _locating = false;
  List<_CityHit> _hits = _kHotCities;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onQueryChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onQueryChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    // 立即重建：空查询时要显示「热门城市」。
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _search(_controller.text),
    );
  }

  Future<void> _search(String keyword) async {
    final q = keyword.trim();
    if (q.isEmpty) {
      _requestId++;
      if (!mounted) return;
      setState(() {
        _hits = _kHotCities;
        _error = null;
        _loading = false;
      });
      return;
    }
    final id = ++_requestId;
    setState(() => _loading = true);
    try {
      final hits = await _searchWithFallback(q);
      if (!mounted || id != _requestId) return;
      setState(() {
        // 搜不到时不把列表清空，直接给热门城市，用户还能继续点。
        _hits = hits.isEmpty ? _kHotCities : hits;
        _error = hits.isEmpty ? '没有找到「$q」，可以试试下面的热门城市' : null;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || id != _requestId) return;
      setState(() {
        // 搜索挂了也要能选：把热门城市放回列表，而不是只留一句提示。
        _hits = _kHotCities;
        _error = '城市搜索失败，可先选下面的热门城市';
        _loading = false;
      });
    }
  }

  /// 地理编码只认行政区名，「惠城区」「深圳南山」这类带区/街道的输入常常
  /// 直接搜不到。这里依次退一步：去掉行政后缀 → 退成前缀城市名。
  Future<List<_CityHit>> _searchWithFallback(String q) async {
    var hits = await _fetchHits(q);
    if (hits.isNotEmpty) return hits;
    final stripped = _stripAdminSuffix(q);
    if (stripped != q && stripped.length >= 2) {
      hits = await _fetchHits(stripped);
      if (hits.isNotEmpty) return hits;
    }
    for (final len in const [2, 3, 4]) {
      if (q.length <= len) continue;
      hits = await _fetchHits(q.substring(0, len));
      if (hits.isNotEmpty) return hits;
    }
    return const [];
  }

  static String _stripAdminSuffix(String q) {
    for (final suffix in const [
      '特别行政区',
      '自治区',
      '自治州',
      '街道',
      '地区',
      '市',
      '区',
      '县',
      '镇',
    ]) {
      if (q.length > suffix.length + 1 && q.endsWith(suffix)) {
        return q.substring(0, q.length - suffix.length).trim();
      }
    }
    return q;
  }

  Future<List<_CityHit>> _fetchHits(String q) async {
    final uri = Uri.https('geocoding-api.open-meteo.com', '/v1/search', {
      'name': q,
      'count': '10',
      'language': 'zh',
      'format': 'json',
    });
    final res = await http.get(uri).timeout(const Duration(seconds: 6));
    if (res.statusCode != 200) throw Exception('${res.statusCode}');
    final body = jsonDecode(utf8.decode(res.bodyBytes));
    final raw = body is Map && body['results'] is List
        ? body['results'] as List
        : <dynamic>[];
    return raw
        .whereType<Map>()
        .map((e) {
          final name = '${e['name'] ?? ''}'.trim();
          final lat = (e['latitude'] as num?)?.toDouble();
          final lon = (e['longitude'] as num?)?.toDouble();
          if (name.isEmpty || lat == null || lon == null) return null;
          final region = [
            if ('${e['admin1'] ?? ''}'.trim().isNotEmpty)
              '${e['admin1']}'.trim(),
            if ('${e['country'] ?? ''}'.trim().isNotEmpty)
              '${e['country']}'.trim(),
          ].join(' · ');
          return _CityHit(name: name, lat: lat, lon: lon, region: region);
        })
        .whereType<_CityHit>()
        .toSet()
        .toList();
  }

  Future<void> _pick(_CityHit hit) async {
    // 写盘 + 换名字都是本地操作，网络刷新在后台跑，不用等。
    await AppState.instance.setWeatherCity(
      city: hit.name,
      lat: hit.lat,
      lon: hit.lon,
    );
    if (!mounted) return;
    AppToast.show(context, '已切换到 ${hit.name}');
    Navigator.of(context).pop();
  }

  Future<void> _locate() async {
    if (_locating) return;
    setState(() => _locating = true);
    final ok = await AppState.instance.refreshWeatherWithLocation(
      fromUser: true,
    );
    if (!mounted) return;
    setState(() => _locating = false);
    if (!ok) {
      AppToast.show(context, '定位失败，手动选个城市吧');
      return;
    }
    AppToast.show(context, '已定位到 ${AppState.instance.weatherCity}');
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final searching = _controller.text.trim().isNotEmpty;
    return PaperDialog(
      maxWidth: 420,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('修改城市', style: context.heading(size: 20)),
                    const SizedBox(height: 3),
                    Text(
                      '当前：${AppState.instance.weatherCity}',
                      style: context.body(
                        size: CitroType.caption,
                        color: c.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
              Pressable(
                onTap: () => Navigator.of(context).pop(),
                hoverLift: 0,
                hoverShadow: false,
                borderRadius: BorderRadius.circular(99),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: c.surface2,
                    shape: BoxShape.circle,
                    border: Border.all(color: c.line),
                  ),
                  child: Center(
                    child: AppIcon(
                      strokeSvg(AppIcons.close, width: 2.2),
                      size: 14,
                      color: c.ink2,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          CitroTextField(
            controller: _controller,
            hint: '搜索城市，如 北京 / 上海',
            prefix: AppIcon(
              strokeSvg(AppIcons.search, width: 2),
              size: 15,
              color: c.inkSoft,
            ),
            textInputAction: TextInputAction.search,
          ),
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerLeft, child: _locateChip(c)),
          const SizedBox(height: 10),
          if (_loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
                ),
              ),
            )
          else ...[
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  _error!,
                  style: context.body(
                    size: CitroType.caption,
                    color: c.inkSoft,
                  ),
                ),
              ),
            if (searching && _error == null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _hits.length,
                  itemBuilder: (ctx, i) => _cityRow(c, _hits[i]),
                ),
              )
            else
              _hotWrap(c),
          ],
        ],
      ),
    );
  }

  /// 「使用当前定位」：不搜城市，直接用系统定位（失败会自动退回 IP 定位）。
  Widget _locateChip(CitroColors c) {
    return Pressable(
      onTap: _locating ? null : _locate,
      hoverLift: 0,
      hoverShadow: false,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: c.accentLt.withAlpha(c.dark ? 70 : 165),
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: c.accent.withAlpha(120)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_locating)
              SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: c.accentInk,
                ),
              )
            else
              AppIcon(
                strokeSvg(AppIcons.location, width: 2),
                size: 13,
                color: c.accentInk,
              ),
            const SizedBox(width: 5),
            Text(
              _locating ? '定位中…' : '使用当前定位',
              style: context.body(size: CitroType.small, color: c.accentInk),
            ),
          ],
        ),
      ),
    );
  }

  Widget _hotWrap(CitroColors c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            AppIcon(
              strokeSvg(AppIcons.location, width: 2),
              size: 13,
              color: c.inkSoft,
            ),
            const SizedBox(width: 4),
            Text(
              '热门城市',
              style: context.body(size: CitroType.caption, color: c.inkSoft),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final hit in _hits) _hotChip(c, hit)],
        ),
      ],
    );
  }

  Widget _hotChip(CitroColors c, _CityHit hit) {
    return Pressable(
      onTap: () => _pick(hit),
      hoverLift: 0,
      hoverShadow: false,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(99),
          border: Border.all(color: c.line),
        ),
        child: Text(
          hit.name,
          style: context.body(size: CitroType.small, color: c.ink),
        ),
      ),
    );
  }

  Widget _cityRow(CitroColors c, _CityHit hit) {
    return Pressable(
      onTap: () => _pick(hit),
      hoverLift: 0,
      hoverShadow: false,
      borderRadius: BorderRadius.circular(CitroColors.radii.small),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
        child: Row(
          children: [
            AppIcon(
              strokeSvg(AppIcons.location, width: 2),
              size: 15,
              color: c.accentInk,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hit.name,
                    style: context.body(
                      size: CitroType.body,
                      weight: CitroType.medium,
                      color: c.ink,
                    ),
                  ),
                  if (hit.region.isNotEmpty)
                    Text(
                      hit.region,
                      style: context.body(
                        size: CitroType.micro,
                        color: c.inkSoft,
                      ),
                    ),
                ],
              ),
            ),
            AppIcon(
              strokeSvg(AppIcons.chevronRight, width: 2.2),
              size: 14,
              color: c.inkSoft,
            ),
          ],
        ),
      ),
    );
  }
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
    // fromUser：用户主动点「定位并刷新」，可以覆盖手动选的城市。
    final ok = await AppState.instance.refreshWeatherWithLocation(
      fromUser: true,
    );
    if (!mounted) return;
    setState(() => locating = false);
    if (!ok) {
      AppToast.show(context, '定位失败，已保留当前城市');
      return;
    }
    AppToast.show(context, '已定位到 ${AppState.instance.weatherCity}');
  }

  Widget _weatherAction(
    CitroColors c,
    String icon,
    String label,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(strokeSvg(icon, width: 2), size: 13, color: c.accentInk),
            const SizedBox(width: 4),
            Text(label, style: context.body(size: 12, color: c.accentInk)),
          ],
        ),
      ),
    );
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
              Expanded(child: Text('天气详情', style: context.heading(size: 20))),
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
                      style: context.hand(
                        size: CitroType.hero,
                        weight: CitroType.medium,
                        color: c.ink,
                        height: 1,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        '°C',
                        style: context.body(
                          size: CitroType.body,
                          color: c.inkSoft,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  '${w.desc} · ${w.city}',
                  style: context.body(size: CitroType.meta, color: c.ink2),
                ),
                if (today != null)
                  Text(
                    '最高 ${today.max.round()}° / 最低 ${today.min.round()}°',
                    style: context.body(
                      size: CitroType.caption,
                      color: c.inkSoft,
                    ),
                  ),
              ],
            ),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '体感 ${w.feels.round()}°',
                  style: context.body(
                    size: CitroType.caption,
                    color: c.inkSoft,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '湿度 ${w.humidity}%',
                  style: context.body(
                    size: CitroType.caption,
                    color: c.inkSoft,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${w.windDirection} ${w.wind.round()} km/h',
                  style: context.body(
                    size: CitroType.caption,
                    color: c.inkSoft,
                  ),
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
                    color: current
                        ? c.accentLt.withAlpha(c.dark ? 70 : 170)
                        : c.surface,
                    borderRadius: BorderRadius.circular(
                      CitroColors.radii.small,
                    ),
                    border: Border.all(color: current ? c.accent : c.line),
                  ),
                  child: Column(
                    children: [
                      Text(
                        current
                            ? '现在'
                            : '${hour.time.hour.toString().padLeft(2, '0')}:00',
                        style: context.body(
                          size: CitroType.small,
                          weight: current
                              ? CitroType.medium
                              : CitroType.regular,
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
                          size: CitroType.caption,
                          weight: CitroType.medium,
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
        CitroDivider(color: c.line2),
        const SizedBox(height: 8),
        if (w.daily.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Text(
              state.weatherError ?? '天气加载中…',
              textAlign: TextAlign.center,
              style: context.body(size: CitroType.caption, color: c.inkSoft),
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
                        size: CitroType.caption,
                        weight: CitroType.medium,
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
                      style: context.body(
                        size: CitroType.caption,
                        color: c.inkSoft,
                      ),
                    ),
                  ),
                  if (d.rain > 0) ...[
                    Text(
                      '${d.rain}%',
                      style: context.body(
                        size: CitroType.small,
                        color: c.mintInk,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    '${d.min.round()}° / ${d.max.round()}°',
                    style: context.body(
                      size: CitroType.caption,
                      weight: CitroType.medium,
                      color: c.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _weatherAction(
                c,
                AppIcons.location,
                locating ? '定位中…' : '定位并刷新',
                _locateAndRefresh,
              ),
            ),
            Container(
              width: 1,
              height: 14,
              margin: const EdgeInsets.symmetric(horizontal: 12),
              color: c.line2,
            ),
            Expanded(
              child: _weatherAction(
                c,
                AppIcons.globe,
                '修改城市',
                () => showCityPickerDialog(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}
