# Recall

Recall 是一款面向考研英语词汇的 Android 学习应用。客户端使用 Flutter，学习状态保存在设备本地 SQLite；可选的 AI 语境文章由独立的 Cloudflare Worker 生成，客户端不接触模型厂商密钥。

## 当前能力

- 内置 5,847 条只读考研词汇，启动时校验格式与 SHA-256。
- 按本地日历日分配新词，优先清理历史积压，支持 1～200 的每日目标。
- 第一层认知判断、语境强化、首次复习和后续动态复习形成完整闭环。
- 学习记录、复习任务、文章缓存均在 SQLite 中持久化，可在 Debug 页面查看并导出 JSON。
- AI 文章后端支持 `fake` 与 `deepseek` Provider；AI 失败时允许跳过，不阻断学习闭环。

## 技术栈

| 层 | 技术 | 说明 |
| --- | --- | --- |
| Android 客户端 | Flutter 3.44 / Dart 3.12 | Material 3，当前只生成 Android 平台工程 |
| 本地数据 | `sqflite`，Schema V6 | 学习记录、每日任务、复习记录、文章缓存 |
| 本地配置 | `shared_preferences`、`flutter_secure_storage` | Worker URL 与访问令牌分开保存 |
| AI 网关 | Cloudflare Workers / TypeScript | 统一鉴权、校验、Prompt 和 Provider 适配 |
| AI Provider | Fake、DeepSeek | Flutter 不依赖任何厂商 SDK |
| 测试 | `flutter_test`、Vitest | 客户端单元/组件测试与 Worker 测试 |

## 项目结构

```text
Recall_app/
├── assets/vocabulary/           # App 内正式词库
├── backend/recall_ai_worker/    # Cloudflare Worker
├── docs/                        # 当前技术文档和历史验收记录
├── lib/
│   ├── context/                 # AI 文章客户端、重点词选择
│   ├── data/                    # 仓库接口、SQLite、词库加载、导出
│   ├── learning/                # 每日任务、第一层与首次复习编排
│   ├── models/                  # 领域模型
│   ├── pages/                   # 页面
│   ├── review/                  # 正式复习队列与调度规则
│   ├── settings/                # AI 服务配置
│   └── widgets/                 # 通用组件
├── test/                        # Flutter 测试
└── tool/                        # 本地集成测试入口
```

## 快速开始

环境要求：Flutter SDK 满足 `pubspec.yaml` 中的 Dart `^3.12.2`，Android SDK 可用。项目后端另需 Node.js 与 npm。

```powershell
cd "E:\workplace1\English word app\Recall_app"
flutter pub get
flutter analyze
flutter test
flutter run
```

若当前机器没有把 Flutter 加入 `PATH`，可使用本机已安装路径：

```powershell
& "E:\workplace1\.devtools\flutter\bin\flutter.bat" pub get
```

AI 功能需要在 App 的“AI 服务设置”中填写 Worker URL 和 `RECALL_APP_TOKEN`。未配置或后端不可用时，用户仍可跳过文章并完成当次学习。

Worker 的本地运行和部署见[开发与运维指南](docs/开发与运维指南.md)。任何真实密钥都不得写入仓库。

## 文档导航

- [AI 交接指南](docs/AI交接指南.md)
- [技术文档索引](docs/README.md)
- [系统架构](docs/系统架构.md)
- [开发与运维指南](docs/开发与运维指南.md)
- [数据模型与 API](docs/数据模型与API.md)

`docs/` 中带“验收报告”或“实施指令”的文件是阶段性记录，适合追溯历史，不作为当前实现的唯一事实来源。
