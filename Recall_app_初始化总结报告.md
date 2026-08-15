# Recall_app 开发环境与项目初始化总结报告

## 1. 项目概况

- 项目目录：`E:\workplace1\English word app\Recall_app`
- Flutter 内部项目名：`recall_app`
- 应用包名：`com.example.recall_app`
- 目标平台：Android
- 初始化日期：2026 年 8 月 13 日
- 当前阶段：开发环境安装、Flutter 项目初始化、默认 Demo 编译和真机运行验证已完成

本阶段未设计 UI，未添加数据库、登录系统、服务器、AI 功能、状态管理框架或任何额外业务依赖，也未实现背单词功能。

## 2. 开发环境检查结果

| 工具或组件 | 版本/状态 | 结果 |
| --- | --- | --- |
| Windows | Windows 11 家庭中文版 64 位，23H2 | 正常 |
| Flutter | 3.44.9 Stable | 正常 |
| Dart | 3.12.2 | 正常 |
| Git | 2.45.1.windows.1 | 正常 |
| Java | 17.0.12 LTS | 正常 |
| Android SDK | 36.0.0 | 正常 |
| Android Platform | Android 36 | 正常 |
| Android Build Tools | 36.0.0 | 正常 |
| Android Platform Tools / ADB | 已安装 | 正常 |
| Android Command-line Tools | 已安装 | 正常 |
| Android NDK | 28.2.13676358 | 正常 |
| Android SDK 许可证 | 已全部接受 | 正常 |
| Android Studio | 未安装 | 不影响当前命令行构建 |
| Visual Studio | 未安装 | 仅影响 Windows 桌面开发，不影响 Android |

`flutter doctor -v` 检查确认 Flutter 和 Android 工具链均通过。唯一红项为未安装 Visual Studio，但本项目只开发 Android App，因此无需处理。

## 3. 工具安装位置

开发工具采用本地安装方式，统一存放于：

```text
E:\workplace1\.devtools
```

主要路径如下：

```text
Flutter SDK:
E:\workplace1\.devtools\flutter

Android SDK:
E:\workplace1\.devtools\android-sdk

工具下载缓存:
E:\workplace1\.devtools\downloads
```

安装过程中未修改 Windows 系统 PATH 或注册表。Flutter 已在自身配置中记录 Android SDK 路径。

由于当前网络访问部分海外资源不稳定，Flutter 包和构建资源在安装过程中临时使用了 Flutter 官方文档列出的 CFUG 镜像：

```text
PUB_HOSTED_URL=https://pub.flutter-io.cn
FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
```

这些变量只在执行安装和构建的终端进程中临时设置，未写入系统环境变量。

## 4. 项目初始化结果

项目通过以下方式创建：

```powershell
flutter create --platforms=android --project-name recall_app Recall_app
```

目录名按要求保留为 `Recall_app`。由于 Flutter/Dart 包名必须使用小写字母和下划线，内部项目名使用合法名称 `recall_app`。

已确认以下关键项目文件存在：

```text
Recall_app\pubspec.yaml
Recall_app\pubspec.lock
Recall_app\lib\main.dart
Recall_app\test\widget_test.dart
Recall_app\android\build.gradle.kts
Recall_app\android\app\build.gradle.kts
Recall_app\android\gradlew.bat
```

项目仅生成 Android 平台代码，没有生成不需要的 iOS、Web、Windows、macOS 或 Linux 平台项目目录。

## 5. 项目验证结果

| 验证项目 | 结果 |
| --- | --- |
| `flutter pub get` | 成功 |
| `flutter analyze` | 成功，无静态分析问题 |
| `flutter test` | 成功，默认测试全部通过 |
| `flutter build apk --debug` | 成功 |
| 真机安装 | 成功 |
| 真机启动 | 成功 |

依赖检查提示部分 Flutter 默认包存在较新版本，但这些新版本不符合当前 Flutter 默认约束。该提示不是错误，因此未升级或添加任何依赖。

## 6. Android APK 构建结果

- 构建类型：Debug APK
- 构建状态：成功
- APK 文件：

```text
E:\workplace1\English word app\Recall_app\build\app\outputs\flutter-apk\app-debug.apk
```

- APK 大小：约 139.4 MB
- SHA-256：

```text
517b5c7793a2aaad731a399f9a8df84c9f0ea6bf1fcca95b2f4dbe0f38b9ce21
```

Debug APK 包含多种 CPU 架构和调试资源，因此体积较大，属于正常现象。后续生成 Release APK 或 App Bundle 时，体积通常会明显减小。

## 7. 真机连接与运行结果

测试设备信息：

| 项目 | 信息 |
| --- | --- |
| 设备 | Samsung Galaxy Tab S9 FE+ |
| 型号 | SM-X610 |
| ADB 序列号 | R52W90EQWCJ |
| CPU 架构 | android-arm64 |
| Android 版本 | Android 16 |
| API Level | 36 |
| ADB 状态 | `device`，已授权 |

默认 Flutter Demo 已完成以下操作：

1. 针对真机重新编译 Debug APK。
2. 将 APK 安装到三星平板。
3. 启动 `com.example.recall_app/.MainActivity`。
4. 验证应用进程正在运行。
5. 验证应用 Activity 位于平板前台。

Flutter 引擎在设备上使用 Impeller Vulkan 渲染后端正常启动。

## 8. 安装过程中遇到的问题及处理

### 8.1 初始环境缺失

最初只检测到 Git 和 Java，Flutter、Dart、Android SDK、ADB 和 Android 开发工具均未安装。

处理结果：将 Flutter SDK 和 Android Command-line Tools 安装到本地工具目录，没有直接修改系统环境。

### 8.2 Flutter 官方资源访问缓慢

Flutter 首次初始化时访问 `pub.dev` 长时间无进展。

处理结果：按照 Flutter 官方中国网络说明，仅在当前进程临时使用 CFUG 镜像，初始化随后成功完成。

### 8.3 Gradle 下载被 GitHub 重定向阻塞

Gradle 官方下载地址重定向到 GitHub，当前网络无法正常下载大文件。

处理结果：从阿里云镜像下载相同版本的 Gradle 9.1.0，并使用 Gradle 官方 SHA-256 值进行完整性校验。校验完全一致后才写入 Wrapper 缓存。同时在以下文件中加入官方校验值：

```text
Recall_app\android\gradle\wrapper\gradle-wrapper.properties
```

校验值：

```text
b84e04fa845fecba48551f425957641074fcc00a88a84d2aae5808743b35fc85
```

### 8.4 首次 Android 构建耗时较长

首次构建需要下载 Gradle 插件、Kotlin 构建依赖、Flutter Android 引擎文件及 NDK，耗时明显较长。

处理结果：等待所需组件安装完成后重新构建，最终返回 `BUILD SUCCESSFUL`。后续构建会复用本机缓存，通常会快很多。

### 8.5 手机首次连接未被 ADB 识别

最初 USB 设备描述符请求失败。更换为三星平板后，Windows 能识别文件传输设备，但 ADB 列表仍为空。

处理结果：在平板上开启开发者选项和 USB 调试，并允许当前电脑的调试授权。随后 ADB 和 Flutter 均成功识别设备。

## 9. 当前已知提示

构建过程中出现 Android SDK XML 版本提示：当前命令行工具对部分较新 SDK 元数据发出兼容性警告。该警告未阻止环境检查、APK 构建、安装或运行，当前无需处理。

电脑 BIOS 虚拟化检测结果为未启用，因此暂未安装或配置 Android 模拟器。当前已有可正常使用的三星平板真机，不影响后续开发和调试。

## 10. 后续使用说明

由于未修改系统 PATH，普通新终端默认可能无法直接识别 `flutter`。可使用 Flutter 完整路径：

```powershell
E:\workplace1\.devtools\flutter\bin\flutter.bat --version
```

或者在当前 PowerShell 会话临时设置：

```powershell
$env:ANDROID_HOME="E:\workplace1\.devtools\android-sdk"
$env:ANDROID_SDK_ROOT=$env:ANDROID_HOME
$env:PUB_HOSTED_URL="https://pub.flutter-io.cn"
$env:FLUTTER_STORAGE_BASE_URL="https://storage.flutter-io.cn"
$env:Path="E:\workplace1\.devtools\flutter\bin;E:\workplace1\.devtools\android-sdk\platform-tools;$env:Path"
```

进入项目并运行：

```powershell
cd "E:\workplace1\English word app\Recall_app"
flutter devices
flutter run -d R52W90EQWCJ
```

平板需要保持解锁、开启 USB 调试，并在需要时允许电脑调试授权。

## 11. 下一步建议

环境和项目基础已验证完成。下一阶段建议先确定最小可用版本的页面范围、核心数据结构和本地背单词流程，再开始 UI 与业务开发。

在正式开发前，还可以选择将 Flutter 和 Android SDK 路径写入用户级环境变量，以便新终端直接运行 `flutter`。由于这会修改系统环境，应在明确确认后再执行。

