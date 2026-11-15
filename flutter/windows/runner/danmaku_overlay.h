#ifndef RUNNER_DANMAKU_OVERLAY_H_
#define RUNNER_DANMAKU_OVERLAY_H_

#include <string>

// 一起看弹幕悬浮窗（Windows 版）。
//
// 主持人共享屏幕时，观众的文字聊天要以弹幕形式滚动在主持人屏幕上
// （应用最小化后仍在）。主窗口最小化后 Flutter UI 树停摆，所以弹幕
// 必须是独立的 Win32 顶层窗口：WS_EX_TOPMOST 置顶、WS_EX_TRANSPARENT
// + WS_EX_NOACTIVATE 点击穿透不抢焦点、层叠窗口品红色 colorkey 透明。
// 渲染走 GDI（主线程消息泵驱动 WM_TIMER 帧步进），与 Android 端的
// DanmakuView 同构：4 条弹幕道、从右向左匀速滚动。
//
// 线程约定：所有方法必须在主（UI）线程调用 —— MethodChannel 回调与
// 窗口消息同线程，无需加锁。
namespace danmaku_overlay {

// 悬浮窗是否可用。Windows 没有特殊权限门槛，恒为 true。
bool CanShow();

// 显示悬浮窗。已显示时幂等返回 true；top 为距屏幕工作区顶部的像素偏移。
// 宽度取主屏工作区全宽。失败返回 false。
bool Show(int top);

// 隐藏并销毁悬浮窗；未显示时为无害 no-op。
void Hide();

// 推一条弹幕（UTF-8 文本；悬浮窗未显示时静默丢弃）。
void Push(const std::string& name, const std::string& text);

// 清空正在滚动的弹幕（重进房间时调用）。
void Clear();

}  // namespace danmaku_overlay

#endif  // RUNNER_DANMAKU_OVERLAY_H_
