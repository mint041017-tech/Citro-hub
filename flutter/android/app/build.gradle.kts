import java.util.Properties
import java.io.File

plugins {
    id("com.android.application")
    // Kotlin 插件由 dev.flutter.flutter-gradle-plugin 自动应用（模板惯例，勿显式声明）
    id("dev.flutter.flutter-gradle-plugin")
}

/* release 签名：读 android/app/key.properties（storeFile 为**绝对路径** ——
   构建在 subst 盘符（X:）下进行，相对路径会被盘符根截断，必须用绝对路径
   指向 密钥/citro-release.jks；口令为随机值，密钥与口令一律不入 git）。
   ⚠️ properties 必须用 reader(Charsets.UTF_8) 加载：load(InputStream) 按
   ISO-8859-1 解码，含中文的绝对路径会变乱码 → exists()=false → 静默退回
   debug 签名（2026-10-22 踩坑）。Kotlin 壳时代没这个问题：它的
   keystore.properties 只存 ASCII 文件名，中文目录写在代码里。
   ⚠️ v1.1.1 起换用新密钥：Kotlin 壳时代的 密钥/citro-release.jks 与
   capacitor/android/keystore.properties 已丢失，旧包（≤1.1.0）无法被新包覆盖
   安装 —— 老用户需卸载重装（WebView 本地数据随之清空）。 */
fun resolveStoreFile(raw: String): File {
    val f = File(raw)
    return if (f.isAbsolute) f else rootProject.file("app/$raw")
}
val keystorePropsFile = rootProject.file("app/key.properties")
val keystoreProps = Properties()
val hasKeystore = keystorePropsFile.exists() && run {
    keystorePropsFile.reader(Charsets.UTF_8).use { keystoreProps.load(it) }
    val storeFile = resolveStoreFile(keystoreProps.getProperty("storeFile") ?: "")
    keystoreProps.getProperty("storePassword") != null && storeFile.exists()
}

android {
    // 应用身份保持 com.chimu.crew 不变 —— 与 Kotlin 壳同包名。
    // （v1.1.1 因签名更换无法覆盖升级，但保留包名让系统托盘 / 通知 /
    //   第三方登录回调等按包名识别的逻辑继续成立。）
    namespace = "com.chimu.crew"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // 应用身份保持 com.chimu.crew 不变（namespace 同步）—— 老用户可覆盖安装、
        // 不丢 WebView cookie / 本地数据；用户可见品牌名在 res/values/strings.xml（Citro）。
        applicationId = "com.chimu.crew"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // 版本号来自 pubspec.yaml（version: 1.5.7+1507）：
        //   versionCode 规则：major * 1000 + minor * 100 + patch（1.1.3 → 1103；
        //   1104 为 v1.1.3 启动热修；1105 为界面反馈修正；1106 为卡片铺满与打卡
        //   下划线修正；1107 为卡片等宽、打卡猫避让与社区语音试听修正；
        //   1108 为评论触控区、打卡关闭键与番茄钟回归；
        //   1109 为评论输入失焦、通知权限与定位天气；
        //   1110 调整权限申请顺序；1111 把权限申请移到首帧后；1112 改为定位完成后再申请通知；1113 延后通知申请；1500 为 1.5.0：食谱日记第二轮完善（裁切、分量/热量、食材单位、
        //   步骤按钮、购物清单、吃什么布局、图片加载）；1501 为 1.5.1：食材库回归、封面自由裁切与原版压缩、指定单位、
        //   红色删除、关闭/下拉交互，并把构建内存压到 3G；1502 为 1.5.2：通知开关前置、数量/单位换位、步骤方图、
        //   详情自定义计时、步骤/小记字体、下厨日记只读、食谱卡片方图；1503 为 1.5.3：启动页去掉旧名、CiCi 按钮放大、
        //   计时悬浮卡、后台到点推送（receiver + ProGuard 修复）；1504 为 1.5.4：全站计时胶囊 + 常驻通知、社区新动态通知、
        //   食谱 AI、评论交互重做、动态卡片/字体放大、页面过渡动画、每日一言平衡换行、星象本地兜底后 AI 替换。
        //   1505 为 1.5.5：社区头像进入我的/TA 的发布、搜索移到收件箱右侧、评论框失焦自动收起、
        //   食材/冰箱数量步进器、计时胶囊去下划线、常驻通知倒计时放大（自定义 RemoteViews）、
        //   发动态图片预览防闪烁、更改信息生日滚轮选择器、评论框内按钮不再误触收起。
        //   1506 为 1.5.6：Tab 切换平移动画（全局与食谱日记内部）、我的页隐藏导航栏、
        //   「社区队友」改「社区成员」、收件箱胶囊化、搜索点击聚焦且失焦自动隐藏。
        //   1507 为 1.5.7：主导航切换改为 90ms 单程平移（立即换页，仅新页滑入），进一步加快体感。
        //   versionCode=1507，versionName=1.5.7。
        // ── 逐版变更记录（Kotlin 壳时代的记录见 kotlin/app/build.gradle.kts）──
        //   1.1.3（2026-10-22）：彻底移除 WebView 套壳，改用纯 Flutter Widget
        //     重写全部页面与交互（首页 / 资源 / 13 款小游戏 / 社区 / 食谱 /
        //     我的 / 星象 / 抽签 / 灵敏度），像素级对齐站点 393×852 手账 UI。
        //     引擎 Flutter 3.47.7，不再加载打包进 APK 的网页资源。
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        /* ChimuBridge / 启动页自愈守卫用到的 BuildConfig 字段（AGP 8+ 默认不再生成） */
        buildConfigField("int", "VERSION_CODE", "${flutter.versionCode}")
        buildConfigField("String", "VERSION_NAME", "\"${flutter.versionName}\"")
    }

    /* BuildConfig 需显式开启（AGP 8 起不再默认生成） */
    buildFeatures { buildConfig = true }

    signingConfigs {
        if (hasKeystore) {
            create("release") {
                storeFile = resolveStoreFile(keystoreProps.getProperty("storeFile"))
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            // flutter_local_notifications 依赖 Gson 泛型保存排程，必须保留签名与模型类。
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            // 未生成密钥时退回 debug 签名（flutter/build.js 会先补齐 key.properties，
            // 正常流程走不到这个兜底；裸跑 flutter build 时仅出验证包）。
            signingConfig = if (hasKeystore) signingConfigs.getByName("release")
                            else signingConfigs.getByName("debug")
        }
    }

    // 图片/字体已在源侧压缩，禁止 AAPT 再压缩，避免运行时解压开销
    androidResources {
        noCompress += listOf("ttf", "png", "jpg", "jpeg", "webp")
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // flutter_local_notifications 需要 Java 8+ API 脱糖
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // 原生侧仅保底依赖（Flutter 插件各自声明所需依赖）
    implementation("androidx.core:core-ktx:1.13.1")
    }
