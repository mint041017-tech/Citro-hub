import 'package:citro/checkin/checkin_models.dart';
import 'package:citro/checkin/checkin_store.dart';
import 'package:citro/checkin/checkin_sync.dart';
import 'package:citro/services/prefs.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    CheckinStore.instance.resetForTest();
    await CheckinStore.instance.ensureInit();
  });

  tearDown(() {
    CheckinStore.instance.resetForTest();
  });

  test('游客打卡：创建当天记录、行动与回签都落本机', () async {
    final store = CheckinStore.instance;
    final entry = await store.syncTodaySnapshot(
      signId: 'sign-01',
      signTitle: '先递一句话',
      levelIndex: 2,
      kind: 'study',
      actionText: '专注十分钟',
    );
    expect(entry, isNotNull);
    expect(store.today, isNotNull);
    expect(entry!.actionType, CheckinActionType.focus);
    expect(entry.actionDone, isFalse);
    expect(entry.rev, 0);

    await store.completeAction(snapshot: entry.actionText);
    expect(store.today!.actionDone, isTrue);
    expect(store.today!.completedActionText, '专注十分钟');

    await store.saveReflection(mood: CheckinMood.same, text: '今天还算稳');
    expect(store.today!.hasReflection, isTrue);
    expect(store.today!.reflectionMood, CheckinMood.same);
    expect(store.today!.reflectionText, '今天还算稳');

    // 游客不上云，队列不应产生云端操作。
    expect(store.isGuest, isTrue);
    expect(store.syncing, isFalse);
  });

  test('心/灵感签：保存回签即自动完成行动', () async {
    final store = CheckinStore.instance;
    await store.syncTodaySnapshot(
      signId: 'sign-heart',
      signTitle: '写一句心情',
      levelIndex: 0,
      kind: 'heart',
      actionText: '写一句今天的心情',
    );
    expect(store.today!.actionDone, isFalse);
    await store.saveReflection(mood: CheckinMood.different, text: '走了自己的路');
    expect(store.today!.actionDone, isTrue);
    expect(store.today!.reflectionMood, CheckinMood.different);
  });

  test('同一天重复打卡只更新一条，不新增历史', () async {
    final store = CheckinStore.instance;
    await store.syncTodaySnapshot(
      signId: 'sign-01',
      signTitle: '先递一句话',
      levelIndex: 2,
      kind: 'career',
      actionText: '把今天最想推进的那件事往前挪一步',
    );
    final first = store.today!;
    await store.syncTodaySnapshot(
      signId: 'sign-01',
      signTitle: '先递一句话',
      levelIndex: 2,
      kind: 'career',
      actionText: '把今天最想推进的那件事往前挪一步',
    );
    expect(store.totalDays, 1);
    expect(store.today!.date, first.date);
    expect(store.today!.rev, 0);
  });

  test('切换账号后看不到上一账号的记录，切回来仍在', () async {
    final store = CheckinStore.instance;
    await store.syncTodaySnapshot(
      signId: 'sign-guest',
      signTitle: '游客签',
      levelIndex: 0,
      kind: 'tiny',
      actionText: '做一小步',
    );
    final guestToday = store.today!;

    await store.onAccountChanged('Alice');
    expect(store.accountName, 'Alice');
    expect(store.today, isNull);
    expect(store.days, isEmpty);

    await store.onAccountChanged(null);
    expect(store.isGuest, isTrue);
    expect(store.today!.date, guestToday.date);
    expect(store.today!.signId, 'sign-guest');
  });

  test('注销清理会清空本机记录与同步队列', () async {
    final store = CheckinStore.instance;
    await store.ensureInit(account: 'Bob');
    await store.syncTodaySnapshot(
      signId: 'sign-bob',
      signTitle: 'Bob 的签',
      levelIndex: 1,
      kind: 'tiny',
      actionText: '做一小步',
    );
    await store.clearLocalForDeletedAccount();
    expect(store.days, isEmpty);
    expect(store.isGuest, isFalse);
    expect(store.conflictDate, isNull);
  });

  test('登录账号离线打卡先写本机，再进待同步队列', () async {
    final store = CheckinStore.instance;
    await store.ensureInit(account: 'Carol');
    await store.syncTodaySnapshot(
      signId: 'sign-carol',
      signTitle: 'Carol 的签',
      levelIndex: 3,
      kind: 'career',
      actionText: '推进一件事',
    );
    expect(store.today, isNotNull);
    final ops = CheckinSync.load('Carol');
    expect(ops, hasLength(1));
    expect(ops.single.kind, 'create');
  });
}
