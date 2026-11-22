/// 维度解释与结果页文案：白话、行为化、反巴纳姆。
library;

class DimCopy {
  final String title;
  final String subtitle;
  final String explain;
  final String myth;
  final String leftDesc;
  final String rightDesc;

  const DimCopy({
    required this.title,
    required this.subtitle,
    required this.explain,
    required this.myth,
    required this.leftDesc,
    required this.rightDesc,
  });
}

const mbtiDimCopy = <String, DimCopy>{
  'EI': DimCopy(
    title: '精力来源',
    subtitle: '你靠什么回血：热闹，还是独处',
    explain: '这个维度看的是精力流向，不是社交能力。偏外向的人在与外部世界互动时充电，偏内向的人在独处时回血。',
    myth: '内向 ≠ 社恐，外向 ≠ 会来事。内向的人也可以是社交高手，只是社交更耗电。',
    leftDesc: '更像外向（E）的样子：和人待在一起越聊越兴奋；想法边说边成形；独处久了会闷，喜欢主动约人、开启话题。',
    rightDesc: '更像内向（I）的样子：社交后需要独处回血；想法先在心里想清楚再说；不是不合群，只是更在意社交的性价比。',
  ),
  'SN': DimCopy(
    title: '信息偏好',
    subtitle: '你更信眼睛看到的，还是脑子联想到的',
    explain: '偏实感的人先关注具体事实与亲身经验，偏直觉的人先关注可能性、关联与背后的含义。两种都是可靠的认识世界的方式。',
    myth: '直觉 ≠ 更聪明，实感 ≠ 无趣。一个偏向"还有什么新玩法"，一个偏向"先把眼前做好"。',
    leftDesc: '更像实感（S）的样子：描述事情先讲清发生了什么；学东西喜欢从实例和动手开始；信任验证过的经验和具体细节。',
    rightDesc: '更像直觉（N）的样子：听到新观点会自动联想其他用法；喜欢琢磨寓意和可能性；脑子里常同时展开好几条"如果……会怎样"。',
  ),
  'TF': DimCopy(
    title: '决策方式',
    subtitle: '做决定时，先看逻辑，还是先看人',
    explain: '偏思考的人优先看事情本身是否合理一致，偏情感的人优先看相关人的价值与感受。两者都能讲道理，也都有感情。',
    myth: '情感 ≠ 不理性，思考 ≠ 冷血。区别只在决策时的"第一顺位"，不在能力高低。',
    leftDesc: '更像思考（T）的样子：评价方案先看逻辑是否成立；指出问题比较直接；倾诉时容易不自觉开始给建议。',
    rightDesc: '更像情感（F）的样子：朋友倾诉先安抚再分析；拒绝别人会在意对方失望；能敏锐察觉团队里谁情绪不对。',
  ),
  'JP': DimCopy(
    title: '生活方式',
    subtitle: '喜欢有定论，还是留有余地',
    explain: '偏判断的人偏好计划、秩序和"事情定了"的安心感，偏知觉的人偏好灵活、选择和"到时再说"的松弛感。',
    myth: '判断（J）≠ 爱评判别人，知觉（P）≠ 没原则。它说的是你对外部生活的组织方式。',
    leftDesc: '更像判断（J）的样子：出行前做攻略；用清单和日程管理任务；先把正事做完再安心玩，定了的事不喜欢反复改。',
    rightDesc: '更像知觉（P）的样子：计划被打乱也觉得无所谓；死线前集中爆发；喜欢保留选择余地，临时起意反而有趣。',
  ),
  'AT': DimCopy(
    title: '情绪底盘',
    subtitle: '压力下，你的情绪稳不稳',
    explain: '这个附加维度对应情绪稳定性：偏稳定（A）的人自信、抗压、恢复得快，偏敏感（T）的人警觉、自省、感受更细腻。它不影响前面的四字母。',
    myth: '敏感 ≠ 脆弱。敏感型往往更谨慎、更能察觉风险；稳定型也可能因此忽略问题。',
    leftDesc: '更像稳定（A）的样子：压力下也能保持节奏；很少反复纠结已经做的决定；别人的评价不太能动摇你。',
    rightDesc: '更像敏感（T）的样子：容易往最坏的方向想；小失误会引发自我怀疑；情绪起伏明显，别人的一句话会琢磨很久。',
  ),
};

const mbtiSceneTitles = <String, String>{
  'work': '学习与工作',
  'love': '恋爱与亲密',
  'social': '朋友与社交',
  'stress': '压力下的你',
};

const mbtiDisclaimer =
    '本测试基于荣格心理类型理论，题目为中文情境化自编问卷，结果用于自我探索与娱乐参考，'
    '不构成心理学诊断，不应用于招聘、选拔等重要决策。字母只是坐标，百分比和具体描述比字母本身更重要；'
    '人格有情境性，结果反映的是你现阶段的自我认知。';

/// 分享/复制的纯文本结果。
String mbtiShareText({
  required String type,
  required String name,
  required String tagline,
  required List<String> dimLines,
}) {
  return '我的 16 型人格是 $type · $name\n'
      '$tagline\n\n'
      '${dimLines.join('\n')}\n\n'
      '来 Citro 测测你的类型 → https://chimu-claw.xyz/#/mbti';
}
