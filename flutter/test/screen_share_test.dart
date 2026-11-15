import 'package:citro/screen_share/danmaku_bridge.dart';
import 'package:citro/screen_share/room_models.dart';
import 'package:citro/screen_share/room_ws.dart';
import 'package:citro/screen_share/screen_capture.dart';
import 'package:citro/screen_share/screen_share_controller.dart';
import 'package:citro/screen_share/screen_share_page.dart';
import 'package:citro/screen_share/screen_share_theme.dart';
import 'package:citro/screen_share/share_quality.dart';
import 'package:citro/screen_share/widgets/danmaku_layer.dart';
import 'package:citro/screen_share/widgets/share_source_picker.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:citro/theme/app_theme.dart';
import 'package:citro/theme/tokens.dart';
import 'package:citro/widgets/paper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await Prefs.init();
  });

  // ── 画质档位 ────────────────────────────────────────────────────────

  group('ShareQuality', () {
    test('六个档位由低到高排列', () {
      expect(ShareQuality.presets, hasLength(6));
      expect(ShareQuality.presets.first, ShareQuality.p720_30);
      expect(ShareQuality.presets.last, ShareQuality.p2k_60);
    });

    test('码率随分辨率和帧率上升', () {
      // 上限值 2026-11 抬过一轮（用户要求不设流量限制）：
      // 720p 6M / 1080p 10M / 2K 20M，60fps 档 ×1.6。
      expect(ShareQuality.p720_30.maxBitrate, 6000000);
      expect(ShareQuality.p720_60.maxBitrate, 9600000);
      expect(ShareQuality.p1080_30.maxBitrate, 10000000);
      expect(ShareQuality.p1080_60.maxBitrate, 16000000);
      expect(ShareQuality.p2k_30.maxBitrate, 20000000);
      expect(ShareQuality.p2k_60.maxBitrate, 32000000);
    });

    test('采集约束只在给了源时才写 deviceId', () {
      final without = ShareQuality.p720_30.captureConstraints();
      final video = without['video'] as Map<String, dynamic>;
      expect(video.containsKey('deviceId'), isFalse);

      final withSource = ShareQuality.p720_30.captureConstraints(
        deviceId: 'src-1',
      );
      final video2 = withSource['video'] as Map<String, dynamic>;
      expect(video2['deviceId'], <String, dynamic>{'exact': 'src-1'});
    });

    test('默认不采系统声音，桌面共享时才打开', () {
      expect(ShareQuality.p720_30.captureConstraints()['audio'], isFalse);
      expect(
        ShareQuality.p720_30.captureConstraints(withSystemAudio: true)['audio'],
        isTrue,
      );
    });

    test('非法画质回落到 720p30', () {
      expect(ShareQuality.fromJson(null), ShareQuality.fallback);
      expect(ShareQuality.fromJson(<String, dynamic>{}), ShareQuality.fallback);
      expect(
        ShareQuality.fromJson(<String, dynamic>{
          'width': 9999,
          'height': 9999,
          'frameRate': 9999,
        }),
        ShareQuality.fallback,
      );
      expect(
        ShareQuality.fromJson(<String, dynamic>{
          'width': 2560,
          'height': 1440,
          'frameRate': 60,
        }),
        ShareQuality.p2k_60,
      );
    });
  });

  // ── track / 成员 ─────────────────────────────────────────────────────

  group('RoomTrack', () {
    test('mid 为空时不写进 json，避免服务端当成空字符串', () {
      final json = const RoomTrack(name: 'screen', kind: 'video').toJson();
      expect(json.containsKey('mid'), isFalse);
    });

    test('mid 会原样往返', () {
      final track = RoomTrack.fromJson(<String, dynamic>{
        'name': 'mic',
        'kind': 'audio',
        'mid': '3',
      });
      expect(track.mid, '3');
      expect(track.isAudio, isTrue);
      expect(track.toJson()['mid'], '3');
    });

    test('kind 非法时按 video 处理', () {
      final track = RoomTrack.fromJson(<String, dynamic>{
        'name': 'screen',
        'kind': 'weird',
      });
      expect(track.isAudio, isFalse);
    });

    test('同名即相等（同一一路共享的不同 mid 视为同一路）', () {
      expect(
        const RoomTrack(name: 'screen', kind: 'video', mid: '2'),
        const RoomTrack(name: 'screen', kind: 'video', mid: '5'),
      );
    });
  });

  group('RoomMember', () {
    test('track 推导角色与能力', () {
      const viewer = RoomMember(
        uid: 'a',
        name: '观众',
        role: 'viewer',
        online: true,
        tracks: <RoomTrack>[],
        sfuSessionId: null,
      );
      expect(viewer.isHost, isFalse);
      expect(viewer.isPublisher, isFalse);
      expect(viewer.hasScreen, isFalse);

      const host = RoomMember(
        uid: 'h',
        name: '主持人',
        role: 'host',
        online: true,
        tracks: <RoomTrack>[
          RoomTrack(name: 'screen', kind: 'video'),
          RoomTrack(name: 'mic', kind: 'audio'),
        ],
        sfuSessionId: 's-1',
      );
      expect(host.isHost, isTrue);
      expect(host.isPublisher, isTrue);
      expect(host.hasScreen, isTrue);
      expect(host.hasMic, isTrue);
      expect(host.displayName, '主持人');
    });

    test('空名字回落到「观众」', () {
      const m = RoomMember(
        uid: 'x',
        name: '',
        role: 'viewer',
        online: false,
        tracks: <RoomTrack>[],
        sfuSessionId: null,
      );
      expect(m.displayName, '观众');
    });
  });

  // ── 房间信息 ────────────────────────────────────────────────────────

  group('RoomInfo', () {
    RoomInfo build() => RoomInfo.fromJson(<String, dynamic>{
      'roomId': '123456-abcd',
      'roomCode': '123456',
      'title': '联调',
      'roomType': 'one_to_many',
      'status': 'waiting',
      'hostUid': 'h',
      'quality': <String, dynamic>{
        'width': 1280,
        'height': 720,
        'frameRate': 30,
      },
      'maxViewers': 50,
      'viewerCount': 1,
      'publisherCount': 0,
    });

    test('邀请链接带房间码', () {
      expect(build().inviteLink, 'https://share.mint1017.cn/?room=123456');
    });

    test('copyWithLive 只覆盖会变的字段', () {
      final base = build();
      final live = base.copyWithLive(
        status: 'live',
        viewerCount: 9,
        quality: ShareQuality.p1080_60,
      );
      expect(live.status, 'live');
      expect(live.viewerCount, 9);
      expect(live.quality, ShareQuality.p1080_60);
      // 不变的部分保持原样
      expect(live.roomId, base.roomId);
      expect(live.roomCode, base.roomCode);
      expect(live.title, base.title);
      expect(live.createdAt, base.createdAt);
      // 原对象没有被改动
      expect(base.status, 'waiting');
      expect(base.viewerCount, 1);
    });

    test('live / ended 判定', () {
      expect(build().live, isTrue);
      expect(build().ended, isFalse);
      expect(build().copyWithLive(status: 'ended').ended, isTrue);
    });

    test('字段缺失时用安全默认值，不崩', () {
      final info = RoomInfo.fromJson(<String, dynamic>{});
      expect(info.roomCode, '');
      expect(info.status, 'waiting');
      expect(info.maxViewers, 50);
      expect(info.quality, ShareQuality.fallback);
    });
  });

  // ── WebSocket 事件 ──────────────────────────────────────────────────

  group('WsEvent', () {
    test('hello 快照解析出自己、房间、成员和聊天记录', () {
      final hello = WsEvent.parse(<String, dynamic>{
        'type': 'hello',
        'self': <String, dynamic>{
          'uid': 'u1',
          'name': '我',
          'role': 'host',
          'online': true,
          'tracks': <dynamic>[],
          'sfuSessionId': null,
          'self': true,
        },
        'room': <String, dynamic>{
          'roomId': '123456-abcd',
          'roomCode': '123456',
          'title': '联调',
          'status': 'waiting',
          'quality': <String, dynamic>{
            'width': 1280,
            'height': 720,
            'frameRate': 30,
          },
          'viewerCount': 2,
          'publisherCount': 0,
        },
        'members': <dynamic>[
          <String, dynamic>{
            'uid': 'u1',
            'name': '我',
            'role': 'host',
            'online': true,
            'tracks': <dynamic>[],
            'sfuSessionId': null,
            'self': true,
          },
          <String, dynamic>{
            'uid': 'u2',
            'name': '朋友',
            'role': 'viewer',
            'online': true,
            'tracks': <dynamic>[],
            'sfuSessionId': null,
            'self': false,
          },
        ],
        'chatHistory': <dynamic>[
          <String, dynamic>{
            'id': 'm1',
            'uid': 'u2',
            'name': '朋友',
            'text': '来了',
            'at': 1,
          },
        ],
      });

      expect(hello.type, 'hello');
      expect(hello.selfMember?.uid, 'u1');
      expect(hello.members, hasLength(2));
      expect(hello.members.first.self, isTrue);
      expect(hello.members.last.self, isFalse);
      expect(hello.room?.roomCode, '123456');
      expect(hello.room?.quality, ShareQuality.p720_30);
      expect(hello.chatHistory.single.text, '来了');
    });

    test('chat 事件取出消息', () {
      final chat = WsEvent.parse(<String, dynamic>{
        'type': 'chat',
        'message': <String, dynamic>{
          'id': 'm2',
          'uid': 'u2',
          'name': '朋友',
          'text': '你好',
          'at': 2,
        },
      });
      expect(chat.chat?.text, '你好');
      // message 是 Map，不是字符串，所以字符串形态的 getter 应为 null
      expect(chat.message, isNull);
    });

    test('publish_state 轨名单只含 screen/system，不再有 mic 轨', () {
      // 麦克风已整体摘除：发布端上报的名单只有 screen（+可选 system）。
      // 这里固化观看端解析广播后的名单形状，防止 mic 轨回潮。
      final ev = WsEvent.parse(<String, dynamic>{
        'type': 'publish_state',
        'uid': 'u1',
        'tracks': <dynamic>[
          <String, dynamic>{'name': 'screen', 'kind': 'video', 'mid': '2'},
          <String, dynamic>{'name': 'system', 'kind': 'audio', 'mid': '3'},
        ],
      });
      expect(ev.type, 'publish_state');
      expect(ev.tracks.map((t) => t.name), <String>['screen', 'system']);
      expect(
        ev.tracks.any((t) => t.name == 'mic'),
        isFalse,
        reason: '麦克风已摘除，发布状态里不该再出现 mic 轨',
      );
    });

    test('publisher_joined 取出 sessionId 和 track 列表', () {
      final ev = WsEvent.parse(<String, dynamic>{
        'type': 'publisher_joined',
        'uid': 'u1',
        'name': '我',
        'sessionId': 's-9',
        'tracks': <dynamic>[
          <String, dynamic>{'name': 'screen', 'kind': 'video', 'mid': '2'},
          <String, dynamic>{'name': 'mic', 'kind': 'audio', 'mid': '3'},
        ],
      });
      expect(ev.sessionId, 's-9');
      expect(ev.tracks, hasLength(2));
      expect(ev.tracks.first.mid, '2');
      expect(ev.tracks.last.isAudio, isTrue);
    });

    test('viewer_count / quality_changed 取值', () {
      expect(
        WsEvent.parse(<String, dynamic>{'type': 'viewer_count', 'count': 7})
            .count,
        7,
      );
      expect(
        WsEvent.parse(<String, dynamic>{
          'type': 'quality_changed',
          'quality': <String, dynamic>{
            'width': 1920,
            'height': 1080,
            'frameRate': 60,
          },
        }).quality,
        ShareQuality.p1080_60,
      );
    });

    test('没有 type 的事件不会崩', () {
      expect(WsEvent.parse(<String, dynamic>{'foo': 1}).type, 'unknown');
    });
  });

  // ── SDP 交换结果 ────────────────────────────────────────────────────

  group('SfuSessionResult', () {
    test('订阅结果带 mid（用来匹配 onTrack）', () {
      final r = SfuSessionResult.fromJson(<String, dynamic>{
        'sessionId': 's-1',
        'sessionDescription': <String, dynamic>{
          'type': 'offer',
          'sdp': 'v=0\r\nfake',
        },
        'mid': '5',
      });
      expect(r.sessionId, 's-1');
      expect(r.type, 'offer');
      expect(r.sdp, contains('v=0'));
      expect(r.mid, '5');
    });

    test('发布结果没有 mid 时留空', () {
      final r = SfuSessionResult.fromJson(<String, dynamic>{
        'sessionId': 's-2',
        'sessionDescription': <String, dynamic>{'type': 'answer', 'sdp': 'v=0'},
      });
      expect(r.mid, '');
      expect(r.type, 'answer');
    });
  });

  // ── 邀请链接解析 ────────────────────────────────────────────────────

  group('extractRoomCode', () {
    test('纯 6 位数字', () {
      expect(extractRoomCode('123456'), '123456');
    });

    test('完整邀请链接', () {
      expect(
        extractRoomCode('https://share.mint1017.cn/?room=654321'),
        '654321',
      );
    });

    test('自由文本里的 6 位数字', () {
      expect(extractRoomCode('房间号 234567 快进来'), '234567');
    });

    test('不是 6 位时原样返回，让服务端去报「房间号不正确」', () {
      expect(extractRoomCode('12345'), '12345');
      expect(extractRoomCode(''), '');
    });

    test('链接里 room 参数不是 6 位时继续找文本里的数字', () {
      expect(extractRoomCode('https://x/?room=abc 我的码是 111222'), '111222');
    });
  });

  // ── 入口页 ──────────────────────────────────────────────────────────

  group('ScreenSharePage', () {
    Widget host(Widget child) => AppScope(
      state: AppState.instance,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildCitroTheme(CitroColors.light),
        home: child,
      ),
    );

    testWidgets('渲染发起一起看与加入房间两张卡', (tester) async {
      await tester.pumpWidget(host(const ScreenSharePage()));
      await tester.pumpAndSettle();

      expect(find.text('一起看'), findsOneWidget);
      expect(find.text('发起一起看'), findsOneWidget);
      expect(find.text('有房间号？'), findsOneWidget);
      expect(find.text('加入'), findsOneWidget);
    });

    testWidgets('邀请链接带进来的房间码直接预填', (tester) async {
      await tester.pumpWidget(
        host(const ScreenSharePage(initialCode: '654321')),
      );
      await tester.pumpAndSettle();

      expect(find.text('654321'), findsOneWidget);
    });

    testWidgets('非 6 位的 initialCode 不预填', (tester) async {
      await tester.pumpWidget(host(const ScreenSharePage(initialCode: 'abc')));
      await tester.pumpAndSettle();

      expect(find.text('abc'), findsNothing);
    });

    testWidgets('最近房间只显示 6 位房间码', (tester) async {
      Prefs.setStringList('citro_share_recent_rooms', <String>[
        '123456:123456-a1b2c3',
      ]);
      addTearDown(
        () => Prefs.setStringList('citro_share_recent_rooms', <String>[]),
      );
      await tester.pumpWidget(host(const ScreenSharePage()));
      await tester.pumpAndSettle();

      expect(find.text('123456'), findsOneWidget);
      expect(find.text('123456:123456-a1b2c3'), findsNothing);
    });

    testWidgets('手机窄屏收紧品牌区，返回贴在页面左上角', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(const ScreenSharePage()));
      await tester.pumpAndSettle();

      final logo = tester.widget<Image>(find.byType(Image));
      expect(logo.width, 68);
      expect(logo.height, 68);

      final back = tester.getTopLeft(
        find
            .ancestor(of: find.text('返回'), matching: find.byType(Pressable))
            .first,
      );
      expect(back.dx, lessThan(20), reason: '返回不该跟着正文列居中');
      expect(back.dy, lessThan(40), reason: '返回应在页面顶部');
    });

    testWidgets('320 宽的小屏不溢出', (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(const ScreenSharePage()));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('宽屏保持大 logo，返回仍在页面左上角', (tester) async {
      await tester.pumpWidget(host(const ScreenSharePage()));
      await tester.pumpAndSettle();

      final logo = tester.widget<Image>(find.byType(Image));
      expect(logo.width, 96);

      final back = tester.getTopLeft(
        find
            .ancestor(of: find.text('返回'), matching: find.byType(Pressable))
            .first,
      );
      expect(back.dx, lessThan(20), reason: '宽屏正文列居中，返回不能跟着漂到中间');
    });
  });

  group('系统音量', () {
    test('默认 100%，拖动只改状态并夹在 0–1', () async {
      final controller = ScreenShareController();
      addTearDown(controller.dispose);
      expect(controller.systemVolume, 1);
      expect(controller.hasSystemAudio, isFalse);

      var ticks = 0;
      controller.addListener(() => ticks++);
      controller.setSystemVolume(.42);
      expect(controller.systemVolume, .42);
      expect(ticks, 1);

      controller.setSystemVolume(-1);
      expect(controller.systemVolume, 0);

      // 没在房间里时提交是安全的空操作。
      await controller.commitSystemVolume();
    });
  });

  group('ShareSourcePicker', () {
    Widget host(Widget child) => AppScope(
      state: AppState.instance,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildCitroTheme(CitroColors.light),
        home: child,
      ),
    );

    testWidgets('选择直播内容：tab 分页、画质/帧率下拉、内容声音开关', (tester) async {
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showShareSourcePicker(context, const <ScreenSource>[
                    ScreenSource(id: 'screen:0', name: '显示器 1', isScreen: true),
                    ScreenSource(id: 'window:1', name: '记事本', isScreen: false),
                  ]),
              child: const Text('打开选源器'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开选源器'));
      await tester.pumpAndSettle();

      // 新版选源器文案（参考稿定稿）。默认停在窗口 tab（有窗口时），
      // 网格里是「记事本」，屏幕源要切 tab 才看到。
      expect(find.text('选择直播内容'), findsOneWidget);
      expect(find.text('选择应用窗口'), findsOneWidget);
      expect(find.text('选择电脑全屏'), findsOneWidget);
      expect(find.text('记事本'), findsOneWidget);
      expect(find.text('720p'), findsOneWidget);
      expect(find.text('30帧'), findsOneWidget);
      expect(find.text('开启内容声音'), findsOneWidget);
      expect(find.text('开始直播'), findsOneWidget);

      // 画质下拉改成 2K。
      await tester.tap(find.text('720p'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('2K').last);
      await tester.pumpAndSettle();
      expect(find.text('2K'), findsOneWidget);

      // 切到全屏分页，选中项自动换成第一个屏幕。
      await tester.tap(find.text('选择电脑全屏'));
      await tester.pumpAndSettle();
      expect(find.text('显示器 1'), findsOneWidget);
    });
  });

  group('DanmakuBridge', () {
    test('弹幕悬浮窗总开关默认开启', () {
      // 观众的文字聊天默认以弹幕形式滚在共享画面上；没有单独的持久化
      // 开关前，enabled 必须是 true，否则静音式吞弹幕很难被发现。
      expect(DanmakuBridge.enabled, isTrue);
    });
  });

  group('DanmakuLayer', () {
    Widget host(Widget child) => AppScope(
      state: AppState.instance,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildCitroTheme(CitroColors.light),
        home: child,
      ),
    );

    testWidgets('只播新消息，历史不补播，播完自动移除', (tester) async {
      final controller = _FakeChatController();
      addTearDown(controller.dispose);
      controller.push(
        const ChatMessage(
          id: 'old',
          uid: 'u1',
          name: '朋友',
          text: '历史消息',
          at: 1,
        ),
      );

      await tester.pumpWidget(
        host(
          ShareTheme(
            child: SizedBox(
              width: 800,
              height: 360,
              child: DanmakuLayer(controller: controller),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.textContaining('历史消息', findRichText: true), findsNothing);

      controller.push(
        const ChatMessage(
          id: 'new',
          uid: 'u2',
          name: '岁禾',
          text: '弹幕来了',
          at: 2,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.textContaining('弹幕来了', findRichText: true), findsOneWidget);

      // 弹幕横穿时长已从 9s 调到 14s（用户反馈速度太快），pump 跟着加。
      await tester.pump(const Duration(seconds: 14));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.textContaining('弹幕来了', findRichText: true), findsNothing);
    });
  });
}

/// 只用来喂弹幕的控制器：不连网，chat 直接由测试写入。
class _FakeChatController extends ScreenShareController {
  final List<ChatMessage> _messages = <ChatMessage>[];

  @override
  List<ChatMessage> get chat => List<ChatMessage>.unmodifiable(_messages);

  void push(ChatMessage message) {
    _messages.add(message);
    notifyListeners();
  }
}
