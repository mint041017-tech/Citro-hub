import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/paper.dart';

enum LegalDoc { privacy, terms }

Future<void> showLegalPage(BuildContext context, LegalDoc doc) {
  return Navigator.of(context)
      .push(MaterialPageRoute<void>(builder: (_) => LegalPage(doc: doc)));
}

class LegalPage extends StatelessWidget {
  const LegalPage({super.key, required this.doc});

  final LegalDoc doc;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    final isPrivacy = doc == LegalDoc.privacy;
    final sections = isPrivacy ? kPrivacySections : kTermsSections;
    final width = MediaQuery.sizeOf(context).width;
    final side = math.max(14.0, (width - 720) / 2);
    return Scaffold(
      backgroundColor: c.surface,
      body: PaperBackground(
        child: SafeArea(
          child: SelectionArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(side, 10, side, 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Pressable(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          height: 32,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            color: c.surface2,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: c.line),
                            boxShadow: CitroColors.shadows.paper(c),
                          ),
                          child: Row(
                            children: [
                              AppIcon(
                                strokeSvg(AppIcons.arrowLeft, width: 2.2),
                                size: 15,
                                color: c.ink2,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                '返回',
                                style: context.body(
                                  size: 11.5,
                                  weight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    isPrivacy ? '隐私政策' : '用户协议',
                    style: context.heading(size: 30, color: c.ink),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '生效日期：2026 年 10 月 24 日 · 版本 v1.0',
                    style: context.body(size: 11, color: c.inkSoft),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    decoration: BoxDecoration(
                      color: c.noteY.withAlpha(c.dark ? 110 : 180),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: c.line),
                    ),
                    child: Text(
                      isPrivacy
                          ? '我们不出售你的个人信息，当前未接入广告或第三方统计 SDK。使用社区、AI、天气与语音功能前，请阅读本政策。'
                          : '注册或使用 Citro 即表示你同意本协议。社区内容零容忍违法违规与辱骂攻击；你可以随时举报、拉黑或注销账号。',
                      style: context.body(
                        size: 11.5,
                        color: c.ink2,
                        height: 1.75,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (var i = 0; i < sections.length; i++) ...[
                    const SizedBox(height: 14),
                    _SectionBlock(
                      index: i + 1,
                      title: sections[i].title,
                      paragraphs: sections[i].paragraphs,
                    ),
                  ],
                  const SizedBox(height: 24),
                  DashedLine(color: c.line2.withAlpha(150)),
                  const SizedBox(height: 14),
                  Text(
                    'Citro 运营者\nKOOK：25343821 · 微信：Tangerine-1017',
                    textAlign: TextAlign.center,
                    style: context.body(
                      size: 10.5,
                      color: c.inkSoft,
                      height: 1.7,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '如本页面与线上公布版本不一致，以最新公布版本为准。',
                    textAlign: TextAlign.center,
                    style: context.body(size: 9.5, color: c.inkSoft),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LegalSection {
  const _LegalSection(this.title, this.paragraphs);
  final String title;
  final List<String> paragraphs;
}

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({
    required this.index,
    required this.title,
    required this.paragraphs,
  });

  final int index;
  final String title;
  final List<String> paragraphs;

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.hl,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: c.accent.withAlpha(90)),
              ),
              child: Text(
                '$index',
                style: context.body(
                  size: 10.5,
                  weight: FontWeight.w800,
                  color: c.accentInk,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  title,
                  style: context.heading(size: 17.5, color: c.ink),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        for (final p in paragraphs)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              p,
              style: context.body(size: 12.5, color: c.ink2, height: 1.85),
            ),
          ),
      ],
    );
  }
}

const kPrivacySections = <_LegalSection>[
  _LegalSection('引言', [
    'Citro 由个人运营者提供。我们重视你的个人信息与隐私，本政策说明我们收集哪些信息、为什么收集、如何保存与删除，以及你可以如何行使权利。',
  ]),
  _LegalSection('我们收集的信息', [
    '账号信息：手机号、昵称、加密后的密码（服务端使用 scrypt 加盐哈希，不保存明文）、头像与生日（可选）。',
    '社区内容：你发布的文字、图片、语音、评论、点赞与抱一抱。选择匿名发布时，其他用户看不到你的账号昵称，但服务端仍会为安全审核保留内容归属。',
    '个人工具数据：笔记、食谱、下厨日记、冰箱与购物清单。除你主动公开到「食谱广场」的食谱外，这些数据仅你本人可见。',
    '设备与本机数据：随机生成的访客 ID、主题、通知开关、天气城市、游戏最高分与本机黑名单。',
    '位置信息：仅在你授权定位后读取大致位置，用于获取天气；拒绝授权不会影响其他功能，你可以继续使用默认城市。',
    'AI 与星象：你主动发送给 AI 的对话文本、食谱上下文会发送给第三方 AI 服务用于生成回复；每日星象只发送星座、日期等信息，不发送手机号。',
    '游戏数据：昵称或访客 ID、成绩、排行榜信息、「正在玩」页面中你主动展示的游戏进度，以及玩法抽签的签面与时间。',
    '每日运签：当天抽到的签位、是否使用过转运；跟 CiCi 分享的好事会发送给 AI 生成回复，并在登录状态下自动收录到你的「好事记录」笔记（仅本人可见）。',
  ]),
  _LegalSection('设备权限', [
    '定位：用于天气与本地化信息；可在系统设置中随时关闭。',
    '麦克风：用于录制社区语音消息；仅在按住录音时使用。',
    '相机与相册：用于选择头像、帖子配图与食谱步骤图；仅在你主动选择图片时读取。',
    '通知：用于社区消息与烹饪计时提醒；可在 App 内或系统设置中关闭。',
  ]),
  _LegalSection('使用目的', [
    '提供账号登录、社区互动、食谱日记、游戏排行、天气与星象等功能；保障服务安全、处理举报与违规内容；在你同意的情况下通过第三方 AI 生成回复。',
    '我们不会将你的个人信息用于广告画像，也不会出售个人信息。',
  ]),
  _LegalSection('第三方与共享', [
    '天气：将经纬度发送至 Open-Meteo 获取天气数据。',
    'AI 功能：将你主动提交的对话或食谱上下文发送至智谱 GLM 大语言模型服务生成回复。请勿在对话中发送身份证号、银行卡号、密码等敏感信息。',
    '应用商店与操作系统：使用系统通知、定位、相机、麦克风与相册能力时，由操作系统处理权限。',
    '除上述场景、法律法规要求或保护用户与公众安全所必需外，我们不会向第三方提供你的个人信息。',
  ]),
  _LegalSection('存储与安全', [
    '账号与社区数据存储在运营者控制的服务器中；密码使用加盐哈希，传输使用 HTTPS。我们通过访问控制与最小化收集降低风险。',
    '账号数据保留至你主动注销。注销后，账号、帖子、评论、图片、语音、笔记、食谱、成绩、抽签记录与头像会被删除；因安全审核、争议处理或法律要求必须保留的记录，会在必要期限内保存并限制访问。',
    '本机黑名单只保存在当前设备，不会上传服务器；卸载或清除 App 数据会一并删除。',
  ]),
  _LegalSection('你的权利', [
    '你可以在「我的 → 更改信息」查看并修改头像、昵称与生日，也可以删除自己的帖子与评论。',
    '注销账号：进入「我的 → 账号 → 注销账号」，输入登录密码确认后，账号及个人数据会被永久删除，无法恢复。注销后如需再次使用，需要重新注册。',
    '如需查询、更正或删除其他信息，或撤回授权，可通过下方联系方式联系我们。',
  ]),
  _LegalSection('未成年人', [
    '本服务面向年满 14 周岁的用户。未满 14 周岁请勿注册或使用；未成年人应在监护人指导下使用，并由监护人阅读同意本政策。',
  ]),
  _LegalSection('政策更新', [
    '功能或法规变化时，我们可能更新本政策，并在 App 内公布新版本与生效日期。涉及重大变化的，我们会以更显著的方式提示。',
  ]),
  _LegalSection('联系我们', [
    '运营者联系方式：KOOK 25343821；微信 Tangerine-1017。我们会在合理期限内处理你的隐私请求与举报。',
  ]),
];

const kTermsSections = <_LegalSection>[
  _LegalSection('服务内容', [
    'Citro 提供社区、游戏、食谱日记、天气、星象、笔记、抽签等个人向功能。部分功能需要登录，AI 与天气等功能依赖第三方服务，可能因网络或服务调整而暂时不可用。',
  ]),
  _LegalSection('账号', [
    '注册需要手机号、昵称、密码与邀请码。请妥善保管账号与密码，不要冒用他人信息；因你保管不善造成的损失由你自行承担。',
    '你可以随时退出登录，或在「我的 → 账号 → 注销账号」中永久注销账号。注销会删除账号与个人数据，无法恢复。',
  ]),
  _LegalSection('社区规范（零容忍）', [
    '你在社区发布的文字、图片、语音与评论必须合法、友善。禁止发布：违法违规、暴力恐怖、色情低俗、赌博诈骗、侵犯他人隐私或知识产权、辱骂骚扰、垃圾广告、冒充他人等内容。',
    '对上述内容我们实行零容忍：可以不经事先通知删除内容、限制功能或停用账号；涉嫌违法的，可能依法向有关部门报告。',
    '匿名发布不代表免责。匿名内容同样受本协议约束，服务端会保留必要的归属信息以处理举报与安全事件。',
  ]),
  _LegalSection('举报与拉黑', [
    '每条动态和评论都提供「举报」入口，你可以选择垃圾广告、辱骂攻击、色情低俗、违法违规、侵犯隐私等原因提交。我们会在合理期限内审核处理。',
    '你可以拉黑某个昵称，被拉黑者的动态、评论与消息会从当前设备隐藏。匿名昵称每次随机，匿名内容建议使用举报处理；黑名单只保存在本机，可在「我的 → 黑名单」解除。',
    '请勿滥用举报或拉黑功能；恶意举报可能影响你的账号使用。',
  ]),
  _LegalSection('内容授权', [
    '你保留自己发布内容的权利，并授予运营者为提供、展示、存储、转码与备份服务所必需的非独占许可。你删除内容或注销账号后，该许可随数据删除而终止，法律要求保留的除外。',
  ]),
  _LegalSection('AI 与娱乐内容', [
    'AI 对话、每日星象、抽签与游戏内容仅供娱乐参考，不构成医疗、法律、投资或其他专业建议。AI 可能生成不准确的内容，请自行判断；请勿发送敏感个人信息。',
  ]),
  _LegalSection('游戏与排行榜', [
    '请公平游戏，不要使用外挂、脚本、篡改成绩或其他影响他人体验的方式。发现异常成绩时，我们可以移除记录或限制上榜。',
  ]),
  _LegalSection('知识产权', [
    'Citro 的界面、文字、图标与代码归运营者或相应权利人所有；未经许可不得复制、反编译或用于商业用途。第三方游戏、字体与开源组件遵循其各自许可。',
  ]),
  _LegalSection('第三方链接与资源', [
    '「资源库」等页面可能提供第三方网站或 PC 工具下载链接。这些内容由第三方提供，请自行判断安全性与适用性；我们不对第三方内容承担责任。',
  ]),
  _LegalSection('服务变更与责任', [
    '我们可能因维护、升级或合规要求调整、暂停或终止部分服务。因不可抗力、第三方服务故障或你违反本协议造成的损失，我们在法律允许范围内不承担责任。',
  ]),
  _LegalSection('法律适用与争议', [
    '本协议适用中华人民共和国法律。因本协议产生的争议，双方应先友好协商；协商不成的，可向运营者所在地有管辖权的人民法院提起诉讼。',
  ]),
  _LegalSection('联系我们', [
    '如对本协议、举报或账号注销有疑问，请联系：KOOK 25343821；微信 Tangerine-1017。',
  ]),
];
