#include "danmaku_overlay.h"

#include <windows.h>

#include <algorithm>
#include <list>
#include <string>

namespace danmaku_overlay {

namespace {

// ── 常量：与 Android 端 DanmakuView 保持同一套视觉参数 ──────────────────
constexpr int kLanes = 4;              // 弹幕道数
constexpr float kLaneHeightDp = 30.f;  // 每道高（dp）
constexpr float kLaneGapDp = 6.f;      // 道间距（dp）
constexpr float kTextSizeDp = 15.f;    // 字号（dp）
constexpr float kCrossSeconds = 13.f;  // 横穿全屏的目标时长（秒）
constexpr int kMaxTextLen = 42;        // 单条弹幕最大字符数（UTF-16 计）
constexpr UINT_PTR kFrameTimerId = 4702;  // 帧步进定时器 ID
constexpr wchar_t kClassName[] = L"CitroDanmakuOverlay";

// 品红 colorkey：绘制时先整块填这个颜色，显示时完全透明。弹幕文本用
// 白字黑影，不会撞色。（分层窗口 LWA_COLORKEY 是逐像素比较，纯色背景
// + GDI 文本 = 无 PerPixelAlpha 的逐像素合成开销。）
constexpr COLORREF kColorKey = RGB(255, 0, 255);

struct DanmakuItem {
  std::wstring text;
  int lane;
  float x;     // 左缘 x（客户区坐标，向左递减）
  float width; // 文本像素宽
};

// std::list：erase 后其余元素的指针仍有效 —— lane 追踪存指针的前提。
std::list<DanmakuItem> g_items;
DanmakuItem* g_laneLast[kLanes] = {nullptr, nullptr, nullptr, nullptr};
SIZE g_client = {0, 0};
HFONT g_font = nullptr;
HBRUSH g_keyBrush = nullptr;
HWND g_window = nullptr;
UINT_PTR g_timer = 0;
bool g_timerArmed = false;
LARGE_INTEGER g_lastFrame = {0};
// 进程生命周期内 DPI 基本不变，缓存换算系数避免 WM_PAINT 里反复 GetDC。
float g_dpiScale = -1.f;

float DpToPx(float dp) {
  if (g_dpiScale < 0.f) {
    HDC dc = GetDC(nullptr);
    g_dpiScale = GetDeviceCaps(dc, LOGPIXELSX) / 96.f;
    ReleaseDC(nullptr, dc);
  }
  return dp * g_dpiScale;
}

std::wstring Utf8ToWide(const std::string& s) {
  if (s.empty()) return std::wstring();
  int n = MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), nullptr, 0);
  std::wstring w(n, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, s.data(), (int)s.size(), w.data(), n);
  return w;
}

void ClearState() {
  g_items.clear();
  for (DanmakuItem*& p : g_laneLast) p = nullptr;
}

void TearDown() {
  if (g_timer) {
    KillTimer(g_window, kFrameTimerId);
    g_timer = 0;
  }
  if (g_window) {
    DestroyWindow(g_window);
    g_window = nullptr;
  }
  if (g_font) {
    DeleteObject(g_font);
    g_font = nullptr;
  }
  if (g_keyBrush) {
    DeleteObject(g_keyBrush);
    g_keyBrush = nullptr;
  }
  g_timerArmed = false;
  g_lastFrame = LARGE_INTEGER{0};
  ClearState();
}

// 帧步进：按距上帧的秒数推进所有弹幕，出屏回收，触发重绘。
// 用 QueryPerformanceCounter 计 dt（首帧 dt=0 跳过，只记时间戳）。
void StepFrame() {
  LARGE_INTEGER now;
  if (!QueryPerformanceCounter(&now)) return;
  if (g_lastFrame.QuadPart == 0) {
    g_lastFrame = now;
    return;
  }
  LARGE_INTEGER freq;
  QueryPerformanceFrequency(&freq);
  float dt = (float)(now.QuadPart - g_lastFrame.QuadPart) / (float)freq.QuadPart;
  g_lastFrame = now;
  dt = std::clamp(dt, 0.f, 0.1f);

  if (g_items.empty()) return;

  float speed = std::max(g_client.cx / kCrossSeconds, DpToPx(60.f));
  float dx = speed * dt;
  for (auto it = g_items.begin(); it != g_items.end();) {
    it->x -= dx;
    if (it->x + it->width < 0.f) {
      // 该道若是被删这条占着，清空指针（其余道的指针在 list::erase
      // 后依然指向有效节点）。
      if (g_laneLast[it->lane] == &(*it)) {
        g_laneLast[it->lane] = nullptr;
      }
      it = g_items.erase(it);
    } else {
      ++it;
    }
  }
  InvalidateRect(g_window, nullptr, FALSE);
}

LRESULT CALLBACK OverlayWndProc(HWND hwnd, UINT msg, WPARAM wparam,
                                LPARAM lparam) {
  switch (msg) {
    case WM_ERASEBKGND:
      return 1; // 全部在 WM_PAINT 里画，避免闪烁。
    case WM_PAINT: {
      PAINTSTRUCT ps;
      HDC dc = BeginPaint(hwnd, &ps);
      RECT full;
      GetClientRect(hwnd, &full);
      // 先整块填品红（= 全透明），再画不透明文本。
      FillRect(dc, &full, g_keyBrush);
      HGDIOBJ oldFont = SelectObject(dc, g_font);
      SetBkMode(dc, TRANSPARENT);
      int textHeight = (int)DpToPx(kTextSizeDp) + 4;
      for (const DanmakuItem& item : g_items) {
        float laneTop = item.lane * DpToPx(kLaneHeightDp) + DpToPx(kLaneGapDp) / 2.f;
        int x = (int)item.x;
        int y = (int)laneTop;
        RECT line{x, y, x + (int)item.width + 4, y + textHeight};
        // 黑影：向右下偏 1px 画一遍，白字主体再画一遍 —— 任何背景可读。
        SetTextColor(dc, RGB(0, 0, 0));
        RECT shadow{line.left + 1, line.top + 1, line.right + 1, line.bottom + 1};
        DrawTextW(dc, item.text.c_str(), (int)item.text.size(), &shadow,
                  DT_LEFT | DT_NOCLIP | DT_SINGLELINE);
        SetTextColor(dc, RGB(255, 255, 255));
        DrawTextW(dc, item.text.c_str(), (int)item.text.size(), &line,
                  DT_LEFT | DT_NOCLIP | DT_SINGLELINE);
      }
      SelectObject(dc, oldFont);
      EndPaint(hwnd, &ps);
      return 0;
    }
    case WM_TIMER:
      if ((UINT_PTR)wparam == kFrameTimerId) StepFrame();
      return 0;
    case WM_DISPLAYCHANGE:
      // 分辨率/ DPI 变化：直接收掉。Dart 侧下一条弹幕消息会重新 Show。
      TearDown();
      return 0;
    case WM_DESTROY:
      return 0;
    default:
      return DefWindowProcW(hwnd, msg, wparam, lparam);
  }
}

bool EnsureFont() {
  if (g_font) return true;
  int px = -(int)DpToPx(kTextSizeDp);
  g_font = CreateFontW(px, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
                       DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
                       CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE,
                       L"Microsoft YaHei UI");
  return g_font != nullptr;
}

bool EnsureTimer() {
  if (g_timerArmed) return true;
  UINT_PTR t = SetTimer(g_window, kFrameTimerId, 16, nullptr);
  if (t == 0) return false;
  g_timer = t;
  g_timerArmed = true;
  g_lastFrame = LARGE_INTEGER{0};
  return true;
}

}  // namespace

bool CanShow() {
  // Windows 没有 SYSTEM_ALERT_WINDOW 这类特殊权限门槛。
  return true;
}

bool Show(int top) {
  if (g_window) return true;
  if (!EnsureFont()) return false;
  if (!g_keyBrush) g_keyBrush = CreateSolidBrush(kColorKey);

  HINSTANCE instance = GetModuleHandleW(nullptr);
  WNDCLASSEXW wc = {sizeof(wc)};
  wc.style = CS_HREDRAW | CS_VREDRAW;
  wc.lpfnWndProc = OverlayWndProc;
  wc.hInstance = instance;
  wc.hCursor = nullptr;
  wc.hbrBackground = nullptr;
  wc.lpszClassName = kClassName;
  // show/hide 反复切换会重复注册，忽略「类已存在」。
  RegisterClassExW(&wc);

  RECT work;
  SystemParametersInfoW(SPI_GETWORKAREA, 0, &work, 0);
  int width = work.right - work.left;
  int height = (int)(kLanes * DpToPx(kLaneHeightDp) + DpToPx(kLaneGapDp));

  // TOPMOST 悬浮于其他窗口（含全屏应用）之上；TRANSPARENT + NOACTIVATE
  // 点击穿透不抢焦点；TOOLWINDOW 不进任务栏/Alt-Tab；LAYERED 供 colorkey。
  g_window = CreateWindowExW(
      WS_EX_TOPMOST | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE | WS_EX_LAYERED |
          WS_EX_TOOLWINDOW,
      kClassName, L"", WS_POPUP,
      work.left, work.top + top, width, height,
      nullptr, nullptr, instance, nullptr);
  if (!g_window) return false;

  g_client = SIZE{width, height};
  SetLayeredWindowAttributes(g_window, kColorKey, 0, LWA_COLORKEY);
  ShowWindow(g_window, SW_SHOWNOACTIVATE);
  ClearState();
  if (!EnsureTimer()) {
    TearDown();
    return false;
  }
  return true;
}

void Hide() {
  TearDown();
}

void Push(const std::string& name, const std::string& text) {
  if (!g_window) return;
  std::wstring body = Utf8ToWide(text);
  std::wstring sender = Utf8ToWide(name);
  std::wstring full = sender.empty() ? body : sender + L"：" + body;
  if (full.empty()) return;
  if (full.size() > kMaxTextLen) full = full.substr(0, kMaxTextLen) + L"…";

  HDC dc = GetDC(g_window);
  HGDIOBJ oldFont = SelectObject(dc, g_font);
  SIZE sz;
  GetTextExtentPoint32W(dc, full.c_str(), (int)full.size(), &sz);
  SelectObject(dc, oldFont);
  ReleaseDC(g_window, dc);
  float textWidth = (float)sz.cx;
  if (textWidth <= 0.f) return;

  // 选道：先空道（按道序），再要「最新一条已完全进入屏幕」的道（取推进
  // 最远的那条，右缘离屏右最远，新弹幕最不易追尾）。与 Android 同规则。
  int chosen = -1;
  float bestX = 0.f;
  for (int i = 0; i < kLanes; i++) {
    DanmakuItem* last = g_laneLast[i];
    if (last == nullptr) {
      chosen = i;
      break;
    }
    if (last->x + last->width <= (float)g_client.cx && (chosen < 0 || last->x < bestX)) {
      bestX = last->x;
      chosen = i;
    }
  }
  if (chosen < 0) return; // 全满则丢弃，聊天刷屏时不堆积。

  DanmakuItem item;
  item.text = full;
  item.lane = chosen;
  item.x = (float)g_client.cx;
  item.width = textWidth;
  g_laneLast[chosen] = &g_items.emplace_back(std::move(item));
}

void Clear() {
  ClearState();
  if (g_window) InvalidateRect(g_window, nullptr, FALSE);
}

}  // namespace danmaku_overlay
