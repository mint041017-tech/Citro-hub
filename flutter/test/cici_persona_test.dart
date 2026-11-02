import 'package:citro/services/ai.dart';
import 'package:citro/services/cici_persona.dart';
import 'package:citro/services/prefs.dart';
import 'package:citro/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('没有自定义性格时沿用内置提示词', () {
    expect(AiService.systemFor(), isNull);
    expect(AiService.systemFor(persona: '   '), isNull);
  });

  test('自定义性格完整替换默认人设，只保留名字与 App 知识', () {
    final system = AiService.systemFor(
      persona: '说话像邻居姐姐，爱用「呀」「啦」结尾。',
      extraSystem: '用户正在查看食谱《番茄炒蛋》。',
    );
    expect(system, isNotNull);
    expect(system, contains('你的名字固定是「CiCi」'));
    expect(system, contains('说话像邻居姐姐'));
    expect(system, contains('番茄炒蛋'));
    expect(system, isNot(contains('嘴硬心软')));
    expect(system, isNot(contains('优先遵循')));
  });

  test('未自定义时仍使用默认性格与完整的 App 说明', () {
    final system = AiService.systemFor(extraSystem: '用户正在查看食谱。');
    expect(system, contains('嘴硬心软'));
    expect(system, contains('听隅'));
    expect(system, contains('食谱日记'));
  });

  test('预设可以识别名称，自由输入归类为自定义', () {
    expect(CiciPersona.labelFor(''), '默认');
    expect(CiciPersona.labelFor(CiciPersona.presets[1].text), '温柔');
    expect(CiciPersona.labelFor('用粤语和我说话'), '自定义');
    expect(CiciPersona.presets.first.text, isEmpty);
  });

  test('性格写入偏好并持久化', () async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.init();
    await AppState.instance.init();

    expect(AppState.instance.ciciPersona, isEmpty);
    await AppState.instance.setCiciPersona('  冷静一点，别卖萌。  ');
    expect(AppState.instance.ciciPersona, '冷静一点，别卖萌。');
    expect(Prefs.getString(PrefKeys.ciciPersona), '冷静一点，别卖萌。');

    await AppState.instance.setCiciPersona('');
    expect(AppState.instance.ciciPersona, isEmpty);
    expect(Prefs.getString(PrefKeys.ciciPersona), '');
  });
}
