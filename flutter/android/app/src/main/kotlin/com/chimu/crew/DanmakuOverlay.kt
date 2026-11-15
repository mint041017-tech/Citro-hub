package com.chimu.crew

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.PixelFormat
import android.graphics.Typeface
import android.os.Build
import android.provider.Settings
import android.view.Choreographer
import android.view.Gravity
import android.view.View
import android.view.WindowManager
import kotlin.math.max

/**
 * 观众聊天弹幕的系统悬浮窗。
 *
 * 为什么必须用悬浮窗而不是 App 内的 Widget：主持人共享的是屏幕像素流，
 * Citro 最小化后 App 内的 Widget 就消失、也采不到了；悬浮窗挂在
 * WindowManager 上，悬浮在其他应用之上，MediaProjection 采整屏时会把它
 * 一起采进视频流 —— 弹幕就出现在观众看到的画面里，且应用最小化后仍然滚动。
 *
 * 挂载点：ScreenCaptureService（前台服务，进程保活）。共享停止时服务销毁，
 * [hide] 由服务兜底调用；显示与否由 Dart 侧经 MethodChannel 控制。
 */
object DanmakuOverlay {

    private var view: DanmakuView? = null

    /** Android 6.0 起悬浮窗是特殊权限，需用户在系统设置里授予。 */
    fun canShow(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)

    /**
     * 显示悬浮窗。已显示时幂等返回 true；无权限返回 false（调用方应先
     * 引导用户去 [openPermissionSettings]）。
     */
    @SuppressLint("InflateParams")
    fun show(context: Context): Boolean {
        if (!canShow(context)) return false
        if (view != null) return true
        val appContext = context.applicationContext
        val wm = appContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val v = DanmakuView(appContext)
        // API 26+ 必须用 TYPE_APPLICATION_OVERLAY；更旧的机型用已废弃的
        // TYPE_PHONE（本项目 minSdk 24，覆盖 24/25 两个版本）。
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }
        val params = WindowManager.LayoutParams(
            WindowManager.LayoutParams.MATCH_PARENT,
            WindowManager.LayoutParams.WRAP_CONTENT,
            type,
            // NOT_TOUCHABLE：弹幕不拦截触摸，主持人照常操作底下的应用；
            // NOT_FOCUSABLE：不抢输入焦点；LAYOUT_NO_LIMITS：允许贴屏幕边缘。
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS or
                WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.CENTER_HORIZONTAL
            // 顶部往下留出状态栏 + 摄像头挖孔区。
            y = (72f * appContext.resources.displayMetrics.density).toInt()
        }
        return try {
            wm.addView(v, params)
            view = v
            true
        } catch (_: Throwable) {
            false
        }
    }

    /** 隐藏并回收悬浮窗；未显示时为无害的 no-op。 */
    fun hide(context: Context) {
        val v = view ?: return
        view = null
        try {
            val wm = context.applicationContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager
            wm.removeView(v)
        } catch (_: Throwable) {
            // 窗口可能已被系统回收。
        }
    }

    /** 推一条弹幕（悬浮窗未显示时静默丢弃）。 */
    fun push(name: String, text: String) {
        view?.push(name, text)
    }

    /** 清空正在滚动的弹幕（重进房间时调用，避免残留上一场的消息）。 */
    fun clear() {
        view?.clearMessages()
    }

    /** 打开系统「显示在其他应用上层」设置页；失败返回 false。 */
    fun openPermissionSettings(context: Context): Boolean = try {
        context.startActivity(
            android.content.Intent(
                android.provider.Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                android.net.Uri.parse("package:${context.packageName}")
            ).addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
        )
        true
    } catch (_: Throwable) {
        false
    }
}

/**
 * 弹幕渲染：单 View + Choreographer 帧循环，消息从右向左匀速滚过。
 *
 * 帧循环（而不是给每条消息配 ValueAnimator / TextView）的原因：
 * 聊天高峰每秒可能多条，逐条建 view + 动画有 view churn 和 jank 风险；
 * 单 view 自绘只在 push / 帧步进时改内存字段，onDraw 批量画字符串，
 * GC 压力和掉帧都最小。
 */
private class DanmakuItem(
    val text: String,
    val lane: Int,
    var x: Float,
    val width: Float,
)

class DanmakuView(context: Context) : View(context) {

    companion object {
        /** 弹幕道数：再多文字会叠满整屏顶部，观感差且 CPU 翻倍。 */
        private const val LANES = 4
        /** 横穿全屏的目标时长（秒）。 */
        private const val CROSS_SECONDS = 13f
        private const val MAX_TEXT_LEN = 42
    }

    private val density = resources.displayMetrics.density
    private val laneHeight = 30f * density
    private val laneGap = 6f * density
    private val sidePadding = 12f * density

    private val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        // 用 density（dp）而不是 scaledDensity：跟随字体放大倍数会把 4 条
        // 弹幕道撑爆，弹幕字号固定更稳。
        textSize = 15f * density
        typeface = Typeface.DEFAULT_BOLD
        color = Color.WHITE
        // 黑色投影保证任何背景（浅色网页/深色视频）都可读。
        setShadowLayer(3f * density, 0f, 0f, Color.argb(200, 0, 0, 0))
    }

    private val items = mutableListOf<DanmakuItem>()
    /** 每条道上最新一条弹幕（用于判断该道是否放得下新弹幕）。 */
    private val lanes = arrayOfNulls<DanmakuItem>(LANES)

    private val frameCallback = object : Choreographer.FrameCallback {
        private var lastNanos = 0L
        override fun doFrame(frameTimeNanos: Long) {
            val dt = if (lastNanos == 0L) {
                0f
            } else {
                ((frameTimeNanos - lastNanos) / 1_000_000_000f).coerceIn(0f, 0.1f)
            }
            lastNanos = frameTimeNanos
            step(dt)
            postInvalidateOnAnimation()
            Choreographer.getInstance().postFrameCallback(this)
        }
    }

    override fun onAttachedToWindow() {
        super.onAttachedToWindow()
        Choreographer.getInstance().postFrameCallback(frameCallback)
    }

    override fun onDetachedFromWindow() {
        Choreographer.getInstance().removeFrameCallback(frameCallback)
        super.onDetachedFromWindow()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val height = (LANES * laneHeight + laneGap).toInt()
        setMeasuredDimension(
            getDefaultSize(suggestedMinimumWidth, widthMeasureSpec),
            height
        )
    }

    /** 推一条弹幕；所有道都放不下时丢弃（聊天刷屏时不堆积）。 */
    fun push(name: String, text: String) {
        val w = width.toFloat()
        if (w <= 0f) return
        var body = text.trim()
        if (name.isNotBlank()) body = "${name.trim()}：$body"
        if (body.length > MAX_TEXT_LEN) body = body.take(MAX_TEXT_LEN) + "…"
        if (body.isEmpty()) return
        val textWidth = paint.measureText(body)
        // 选道：先要空道（按道序），再要「最新一条已完全进入屏幕」的道
        // （取推进最远的那条 —— 它右缘离屏幕右边最远，新弹幕最不容易追尾）。
        var chosen = -1
        var bestX = Float.MAX_VALUE
        for (i in 0 until LANES) {
            val last = lanes[i]
            if (last == null) {
                chosen = i
                break
            }
            if (last.x + last.width <= w && last.x < bestX) {
                bestX = last.x
                chosen = i
            }
        }
        if (chosen < 0) return
        val item = DanmakuItem(body, chosen, w, textWidth)
        lanes[chosen] = item
        items.add(item)
    }

    fun clearMessages() {
        items.clear()
        lanes.fill(null)
        invalidate()
    }

    private fun speed(): Float {
        val w = width.toFloat()
        // 屏幕越宽滚得越快，保证横穿时长一致。
        return (w / CROSS_SECONDS).coerceAtLeast(60f * density)
    }

    private fun step(dt: Float) {
        if (items.isEmpty()) return
        val dx = speed() * dt
        val it = items.iterator()
        while (it.hasNext()) {
            val item = it.next()
            item.x -= dx
            if (item.x + item.width < 0f) {
                it.remove()
                if (lanes[item.lane] === item) lanes[item.lane] = null
            }
        }
        invalidate()
    }

    override fun onDraw(canvas: Canvas) {
        super.onDraw(canvas)
        for (item in items) {
            val laneTop = item.lane * laneHeight + laneGap / 2f
            val baseline = laneTop - paint.ascent()
            val x = max(item.x, -item.width) + sidePadding
            canvas.drawText(item.text, x, baseline, paint)
        }
    }
}
