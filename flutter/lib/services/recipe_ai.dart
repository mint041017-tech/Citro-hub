import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'ai.dart';

class RecipeDraftIngredient {
  const RecipeDraftIngredient({
    required this.name,
    required this.amount,
    required this.group,
  });

  final String name;
  final String amount;
  final String group;
}

class RecipeDraftStep {
  const RecipeDraftStep({required this.text, required this.timer});

  final String text;

  /// 该步骤需要计时的秒数，0 表示不计时。
  final int timer;
}

class RecipeDraft {
  const RecipeDraft({
    required this.name,
    required this.emoji,
    required this.cuisine,
    required this.dishType,
    required this.prepMin,
    required this.cookMin,
    required this.servings,
    required this.calories,
    required this.tags,
    required this.note,
    required this.ingredients,
    required this.steps,
  });

  final String name;
  final String emoji;
  final String cuisine;
  final String dishType;
  final int prepMin;
  final int cookMin;
  final int servings;
  final int calories;
  final List<String> tags;
  final String note;
  final List<RecipeDraftIngredient> ingredients;
  final List<RecipeDraftStep> steps;
}

/// 用 AI 把一句需求起草成一份可直接编辑的食谱。
class RecipeAi {
  RecipeAi._();

  static const cuisines = [
    '中式',
    '意式',
    '日式',
    '韩式',
    '泰式',
    '墨西哥菜',
    '美式',
    '法式',
    '西班牙菜',
    '印度菜',
    '希腊菜',
    '越南菜',
    '地中海菜',
    '中东菜',
    '土耳其菜',
    '英式',
    '德式',
    '巴西菜',
    '加勒比菜',
  ];

  static const dishTypes = [
    '凉菜',
    '早餐',
    '面食',
    '米饭',
    '主菜',
    '肉类',
    '海鲜',
    '素菜',
    '沙拉',
    '配菜',
    '蘸酱与酱汁',
    '汤类',
    '小吃',
    '烘焙',
    '甜点',
    '饮品',
    '其他',
  ];

  static const _system = '''你是 Citro 的食谱整理助手，只做一件事：把用户的做饭需求整理成结构清晰、能照着做的家常食谱。
只输出严格 JSON，不要代码块，不要解释，不要多余文字。''';

  static String _prompt(String request) =>
      '''
请把下面的需求整理成一份食谱，严格按这个 JSON 结构输出：
{"name":"菜名","emoji":"一个食物 emoji","cuisine":"菜系","dishType":"类型","prepMin":10,"cookMin":15,"servings":2,"calories":300,"tags":["快手","家常"],"note":"一句实用小贴士","ingredients":[{"name":"番茄","amount":"2个","group":"main"},{"name":"盐","amount":"适量","group":"season"}],"steps":[{"text":"先做什么","timer":0},{"text":"再做什么","timer":180}]}

规则：
1. cuisine 只能是：${cuisines.join('、')}。
2. dishType 只能是：${dishTypes.join('、')}。
3. ingredients 至少 3 样，amount 用「2个」「150克」「1汤匙」「半颗」「适量」这类写法；主料 group 用 main，调料 group 用 season，season 至少 1 条。
4. steps 3 到 8 步，按操作顺序写完整；timer 是该步骤需要计时的秒数，不需要就写 0。
5. prepMin、cookMin 单位是分钟，servings 是几人份，calories 是每 100g 大致千卡（不确定就给合理估计）。
6. tags 给 2 到 4 个简短标签，不重复 cuisine 和 dishType。
7. note 只写一句，不要换行。
8. 菜名要具体、口语化，不要「美味佳肴」这类空话。

用户需求：$request''';

  /// 测试可替换生成结果，避免真实请求 AI。
  @visibleForTesting
  static Future<RecipeDraft> Function(String request)? generator;

  static Future<RecipeDraft> generate(String request) async {
    final hook = generator;
    if (hook != null) return hook(request);
    final raw = await AiService.complete(
      prompt: _prompt(request.trim()),
      system: _system,
      maxTokens: 1800,
      temperature: .45,
    );
    final draft = parse(raw);
    if (draft == null) {
      throw AiException('AI 没整理好，换个说法再试一次');
    }
    return draft;
  }

  static RecipeDraft? parse(String raw) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    Object? decoded;
    try {
      decoded = jsonDecode(raw.substring(start, end + 1));
    } catch (_) {
      return null;
    }
    if (decoded is! Map) return null;

    String text(Object? value) => value == null ? '' : '$value'.trim();
    int number(Object? value) {
      if (value is num) return value.round();
      final digits = RegExp(r'-?[0-9]+').firstMatch('$value');
      return digits == null ? 0 : int.tryParse(digits.group(0)!) ?? 0;
    }

    final name = text(decoded['name']);
    if (name.isEmpty) return null;

    final ingredients = <RecipeDraftIngredient>[];
    final rawIngredients = decoded['ingredients'];
    if (rawIngredients is List) {
      for (final item in rawIngredients) {
        if (item is! Map) continue;
        final itemName = text(item['name']);
        if (itemName.isEmpty) continue;
        ingredients.add(
          RecipeDraftIngredient(
            name: itemName,
            amount: text(item['amount']),
            group: _group(item['group']),
          ),
        );
      }
    }
    if (ingredients.isEmpty) return null;
    if (!ingredients.any((e) => e.group == 'season')) {
      ingredients.add(
        const RecipeDraftIngredient(name: '盐', amount: '适量', group: 'season'),
      );
    }

    final steps = <RecipeDraftStep>[];
    final rawSteps = decoded['steps'];
    if (rawSteps is List) {
      for (final item in rawSteps) {
        final stepText = item is Map ? text(item['text']) : text(item);
        if (stepText.isEmpty) continue;
        steps.add(
          RecipeDraftStep(
            text: stepText,
            timer: item is Map ? number(item['timer']).clamp(0, 86400) : 0,
          ),
        );
      }
    }
    if (steps.isEmpty) return null;

    final tags = <String>[];
    final rawTags = decoded['tags'];
    if (rawTags is List) {
      for (final tag in rawTags) {
        final value = text(tag);
        if (value.isNotEmpty) tags.add(value);
      }
    }

    return RecipeDraft(
      name: name,
      emoji: text(decoded['emoji']).isEmpty ? '🍳' : text(decoded['emoji']),
      cuisine: _match(cuisines, text(decoded['cuisine'])) ?? '',
      dishType: _match(dishTypes, text(decoded['dishType'])) ?? '其他',
      prepMin: number(decoded['prepMin']).clamp(0, 600),
      cookMin: number(decoded['cookMin']).clamp(0, 600),
      servings: number(decoded['servings']).clamp(1, 20),
      calories: number(decoded['calories']).clamp(0, 5000),
      tags: tags,
      note: text(decoded['note']),
      ingredients: ingredients,
      steps: steps,
    );
  }

  static String _group(Object? value) {
    final raw = '${value ?? ''}'.toLowerCase();
    if (raw.contains('season') || raw.contains('调料') || raw.contains('酱')) {
      return 'season';
    }
    return 'main';
  }

  static String? _match(List<String> options, String raw) {
    if (raw.isEmpty) return null;
    if (options.contains(raw)) return raw;
    for (final option in options) {
      if (raw.contains(option) || option.contains(raw)) return option;
    }
    return null;
  }
}
