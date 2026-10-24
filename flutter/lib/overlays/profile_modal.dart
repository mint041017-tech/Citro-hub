import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/api.dart';
import '../services/media.dart';
import '../services/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/modal.dart';
import '../widgets/paper.dart';

Future<void> showProfileModal(BuildContext context) async {
  await showCitroDialog(context, builder: (ctx) => const _ProfileDialog());
}

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog();
  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  late final TextEditingController name;
  int month = 1;
  int day = 1;
  bool hasBday = false;
  String? avatarDataUrl;
  String? avatarPreview;
  Uint8List? avatarBytes;
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    final u = AppState.instance.user;
    name = TextEditingController(text: u?.name ?? '');
    month = u?.bdayMonth ?? 1;
    day = u?.bdayDay ?? 1;
    hasBday = u?.bdayMonth != null;
    avatarPreview = u?.av != null ? Api.imageUrl(u!.av) : null;
  }

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> _pickAvatar() async {
    try {
      final data = await MediaService.pickImageData(maxWidth: 800, quality: 84);
      if (data == null || !mounted) return;
      final raw = base64Decode(data.substring(data.indexOf(',') + 1));
      setState(() {
        avatarDataUrl = data;
        avatarPreview = null;
        avatarBytes = raw;
      });
    } catch (e) {
      if (mounted) setState(() => error = '无法选择图片：$e');
    }
  }

  Future<void> _save() async {
    final state = context.app;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final j = await Api.saveProfile(
        name: name.text.trim(),
        month: hasBday ? month : null,
        day: hasBday ? day : null,
      );
      User u = User.fromJson(j['user']) ?? state.user!;
      if (avatarDataUrl != null) {
        final a = await Api.uploadAvatar(avatarDataUrl!);
        u = User.fromJson(a['user']) ?? u;
      }
      await state.updateUser(u);
      if (!mounted) return;
      AppToast.show(context, '资料已保存');
      Navigator.of(context).pop();
    } on Exception catch (e) {
      if (mounted)
        setState(() => error = e.toString().replaceFirst('ApiException: ', ''));
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.c;
    return PaperDialog(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '更改信息',
            textAlign: TextAlign.center,
            style: context.heading(size: 22),
          ),
          const SizedBox(height: 4),
          Text(
            '点头像换图片，改完点保存',
            textAlign: TextAlign.center,
            style: context.body(size: 11.5, color: c.inkSoft),
          ),
          const SizedBox(height: 18),
          Center(
            child: GestureDetector(
              onTap: _pickAvatar,
              child: Container(
                width: 76,
                height: 76,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.hl,
                  border: Border.all(color: c.line2),
                  image: avatarBytes != null
                      ? DecorationImage(
                          image: ResizeImage(
                            MemoryImage(avatarBytes!),
                            width: 228,
                          ),
                          fit: BoxFit.cover,
                        )
                      : (avatarPreview != null && avatarPreview!.isNotEmpty
                            ? DecorationImage(
                                image: ResizeImage(
                                  NetworkImage(avatarPreview!),
                                  width: 228,
                                ),
                                fit: BoxFit.cover,
                              )
                            : null),
                ),
                child:
                    avatarBytes == null &&
                        (avatarPreview == null || avatarPreview!.isEmpty)
                    ? Center(
                        child: AppIcon(
                          strokeSvg(AppIcons.user, width: 2),
                          size: 30,
                          color: c.accentInk,
                        ),
                      )
                    : null,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '点击更换头像',
            textAlign: TextAlign.center,
            style: context.body(size: 10.5, color: c.inkSoft),
          ),
          const SizedBox(height: 16),
          CitroField(
            label: '昵称',
            hint: '输入昵称',
            controller: name,
            maxLength: 16,
          ),
          const SizedBox(height: 14),
          Text(
            '生日（公历）',
            style: context.body(
              size: 11.5,
              weight: FontWeight.w700,
              color: c.inkSoft,
              letterSpacing: .46,
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: _bdayBox(c, '$month', ' 月', () => _pickBday(true)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _bdayBox(c, '$day', ' 日', () => _pickBday(false)),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: 10),
            Text(error!, style: context.body(size: 11.5, color: c.stamp)),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Pressable(
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    height: 44,
                    decoration: BoxDecoration(
                      border: Border.all(color: c.line2),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Center(
                      child: Text(
                        '取消',
                        style: context.body(
                          size: 14,
                          weight: FontWeight.w600,
                          color: c.ink2,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: AccentButton(
                  text: '保存',
                  height: 44,
                  loading: loading,
                  onTap: _save,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bdayBox(
    CitroColors c,
    String value,
    String suffix,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: c.surface2,
          border: Border.all(color: c.line2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Text(value, style: context.body(size: 13.5, color: c.ink)),
            Text(suffix, style: context.body(size: 11, color: c.inkSoft)),
            const Spacer(),
            AppIcon(
              strokeSvg(AppIcons.chevronDown, width: 2),
              size: 14,
              color: c.inkSoft,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickBday(bool isMonth) async {
    FocusScope.of(context).unfocus();
    final items = isMonth
        ? List<int>.generate(12, (i) => i + 1)
        : List<int>.generate(31, (i) => i + 1);
    var selected = (isMonth ? month : day).clamp(1, items.length);
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final cc = ctx.c;
        final controller = FixedExtentScrollController(
          initialItem: selected - 1,
        );
        return Container(
          height: 280,
          decoration: BoxDecoration(
            color: cc.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            border: Border.all(color: cc.line),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
                  child: Row(
                    children: [
                      Text(
                        isMonth ? '出生月份' : '出生日期',
                        style: ctx.heading(size: 17),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            '取消',
                            style: ctx.body(size: 12, color: cc.inkSoft),
                          ),
                        ),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(ctx, selected),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            '确定',
                            style: ctx.body(
                              size: 12.5,
                              weight: FontWeight.w700,
                              color: cc.accentInk,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: CupertinoPicker(
                    scrollController: controller,
                    itemExtent: 40,
                    onSelectedItemChanged: (i) => selected = i + 1,
                    children: [
                      for (final i in items)
                        Center(
                          child: Text(
                            isMonth ? '$i 月' : '$i 日',
                            style: ctx.body(
                              size: 15,
                              weight: i == selected
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                              color: i == selected ? cc.accentInk : cc.ink2,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (isMonth) {
        month = picked;
      } else {
        day = picked;
      }
      hasBday = true;
    });
  }
}
