# Recall AI 交接指南

> 面向后续接手本项目的 AI 编程助手。状态快照日期：2026-08-15。

## 1. 交接目标

这份文档帮助新的 AI 在缺少历史对话的情况下安全继续开发。它不替代具体技术文档，而是说明：从哪里开始、哪些事实可信、哪些约束不能破坏、常见改动在哪里完成，以及交付前如何验证。

项目工作目录是 `Recall_app/`，不是外层 `English word app/`。外层的 `蒸馏/` 和 `scripts/` 是词库生成、审校工具，不属于 Flutter 运行时源码。

## 2. 首次接手的阅读顺序

开始修改前，按以下顺序阅读：

1. [项目 README](../README.md)：产品范围、技术栈和目录。
2. [系统架构](系统架构.md)：模块边界、学习闭环和调度规则。
3. [数据模型与 API](数据模型与API.md)：词库、SQLite V6、Worker 契约和安全边界。
4. [开发与运维指南](开发与运维指南.md)：运行、测试、部署与排障命令。
5. 与本次任务直接相关的源码和测试。

`docs/` 中名字带“实施指令”或“验收报告”的文件是带日期的历史快照，只用于了解演进过程。若它们与当前代码、测试或当前维护文档冲突，不要直接照搬历史行为。

## 3. 事实来源优先级

遇到冲突时按下列顺序判断：

1. 用户在当前会话中的明确要求。
2. 当前源码、数据库约束和自动化测试共同体现的行为。
3. 当前维护文档：本文件、系统架构、数据模型与 API、开发与运维指南。
4. 历史实施指令和验收报告。

不要只根据页面文案或旧报告推断业务规则。修改规则前应同时检查服务层、SQLite 实现、内存实现和相关测试。

## 4. 当前系统摘要

```text
Flutter Android App
  ├─ 正式词库 Asset（只读、固定哈希）
  ├─ 学习与复习服务
  ├─ LearningRepository
  │    ├─ SqliteLearningRepository（生产）
  │    └─ MemoryLearningRepository（测试）
  └─ RemoteArticleGenerator
       ├─ SQLite 成功缓存
       └─ Cloudflare Worker
            └─ Fake / DeepSeek Provider
```

生产启动入口是 `lib/main.dart`。客户端核心数据本地优先，AI 文章是可选增强；AI 失败或未配置时，用户必须仍能通过“跳过”完成学习并安排首次复习。

当前版本化常量：

| 项目 | 当前值 | 源码位置 |
| --- | --- | --- |
| 正式词 ID 命名空间 | `kaoyan_v1` | `lib/data/vocabulary_repository.dart` |
| 正式词库数量 | 5,847 | `assets/vocabulary/kaoyan_clean.json` |
| SQLite Schema | `6` | `lib/data/sqlite_learning_repository.dart` |
| Prompt | `context_article_v1` | `backend/recall_ai_worker/src/prompt_builder.ts` |
| 复习调度器 | `v1_rule_5s_40pct` | `lib/review/review_scheduler.dart` |
| Worker API | `/v1/context-article` | `backend/recall_ai_worker/src/index.ts` |

## 5. 不可无意破坏的约束

### 5.1 词库与稳定 ID

- App Asset 是严格只读数据，启动时校验固定 SHA-256、词数、结构、顺序和唯一性。
- 正式持久化 ID 使用 `kaoyan_v1:<sourceId>`；不要改用显示单词、数组下标或临时哈希。
- 不要把没有正式命名空间的 legacy 学习记录自动映射、删除或计入正式进度。
- 修改 Asset 后不能只更新哈希来“让测试通过”；必须先确认生成源、审校结果、词数和 ID 兼容性。

### 5.2 SQLite 与用户数据

- 生产数据库是用户学习历史，禁止通过删库、提高版本后重建全部表等方式完成普通迁移。
- Schema 变化必须增加连续 migration，并验证旧版本数据升级后仍存在。
- `MemoryLearningRepository` 与 `SqliteLearningRepository` 应保持相同业务语义。
- 每个词最多一个未完成复习任务；每日新词的 `word_id` 全局唯一。
- 一次正式复习涉及任务完成、attempt、聚合记录和下一任务，必须保持原子性。

### 5.3 日期与调度

- “天”是设备本地日历日，不是滚动 24 小时，也不是 UTC 日。
- 每日任务先处理全部历史积压；今日新增容量为 `max(0, 目标 - 历史待完成数)`。
- 当天上调目标会补词；下调只移除尚未进入第一层的当天任务。已开始或已完成任务必须保留。
- 首次复习和后续复习规则集中在 scheduler/service 中，不要把算法散落到页面或 SQL 查询中。
- 调度算法发生语义变化时升级版本字符串，并把版本写入复习 attempt。

### 5.4 AI 与安全边界

- Flutter 只能持有 Worker URL 和 `RECALL_APP_TOKEN`，不能持有 DeepSeek 或其他厂商 API Key。
- 厂商密钥只允许出现在 Worker Secret 或未提交的本地 `.dev.vars`。
- 新厂商通过 `AiArticleProvider` 和集中式 factory 接入；不要把厂商 SDK 类型传入客户端 API 或通用业务服务。
- Worker 和 Flutter 都必须校验文章响应；`usedWordIds` 必须来自请求并真实出现在正文。
- 错误响应与日志不得泄露 Authorization、Token、API Key、完整释义、文章正文或上游原始敏感响应。
- 不得让自动重试形成并发请求或付费调用循环。

### 5.5 学习闭环

- 首页优先级保持为：到期正式复习 → 待完成语境 → 待完成第一层 → 今日完成。
- 第一层中断后要能恢复；已完成第一层的词不能因为重启而被要求重学第一层。
- 文章生成失败、网络断开或用户主动跳过时，仍应能完成每日任务并安排首次复习。
- AI 生成内容不能覆盖本地正式释义、音标、例句或词库源数据。

## 6. 常见需求的修改入口

| 需求 | 优先查看 | 必须联动检查 |
| --- | --- | --- |
| 首页流程或统计 | `lib/pages/home_page.dart`、`lib/learning/daily_task_service.dart` | widget、daily task、跨日测试 |
| 第一层学习规则 | `lib/learning/first_layer_session.dart` | state 模型、恢复逻辑、首次复习规则 |
| 首次复习间隔 | `lib/learning/first_review_scheduler.dart` | service、SQLite 写入、scheduler 测试、架构文档 |
| 后续复习算法 | `lib/review/review_scheduler.dart` | repository 两种实现、attempt 字段、版本号、复习测试 |
| 每日任务分配 | `lib/learning/daily_task_service.dart`、`lib/data/daily_task_repository.dart` | SQLite/Memory 实现、设置页、积压与调额测试 |
| SQLite Schema | `lib/data/sqlite_learning_repository.dart` | migration、模型、导出、SQLite 重启/升级测试 |
| 正式词库 | 外层 `蒸馏/`、`assets/vocabulary/`、`lib/data/vocabulary_repository.dart` | 格式说明、哈希、词数、ID 兼容性测试 |
| 文章页面与缓存 | `lib/pages/context_article_page.dart`、`lib/context/context_article_generator.dart` | repository、错误态、缓存、跳过与并发测试 |
| Worker API | `backend/recall_ai_worker/src/index.ts`、`types.ts`、validators | Flutter 请求/响应解析、API 文档、两端测试 |
| 新 AI Provider | `backend/recall_ai_worker/src/providers/` | factory、错误映射、Provider contract、Secrets 文档 |
| AI 设置与密钥存储 | `lib/settings/ai_service_settings.dart`、设置页 | secure storage、日志与导出泄露检查 |
| Debug/数据导出 | Debug 页面、`lib/data/learning_data_exporter.dart` | 隐私边界、JSON 测试 |

## 7. 每次开发任务的推荐流程

### 7.1 修改前

1. 确认用户要求属于客户端、Worker、词库流程还是多个边界。
2. 检查工作区是否存在用户未提交的改动；不要覆盖无关文件。
3. 阅读相关接口、生产实现、内存实现和测试，不要只读单个页面。
4. 先运行或至少记录当前基线；如果基线已失败，区分既有失败与本次引入的失败。
5. 对数据库、词库 ID、网络契约、密钥或付费调用相关变更单独做风险检查。

当前工作区没有 `.git` 元数据，不能依赖 `git status` 或 `git diff` 识别改动。接手 AI 应通过明确的目标文件、文件时间和修改前后内容谨慎控制范围；不要假装已经完成 Git 检查。

### 7.2 修改中

- 优先做最小、可验证的改动，复用现有抽象和测试注入点。
- 业务规则放在 service/scheduler，持久化一致性放在 repository，UI 只处理展示与交互。
- 修改仓库接口时同步修改 SQLite 和 Memory 两种实现。
- 不把临时截图、数据库副本、构建产物、`.dev.vars` 或 `node_modules` 当成源码提交内容。
- 发现文档与代码不一致时，先核对测试和现行行为，再更新当前维护文档；历史报告只增加说明，不改写过去的验收结论。

### 7.3 修改后

最低验证：

```powershell
flutter analyze
flutter test
```

若改动 Worker：

```powershell
cd backend/recall_ai_worker
npm run typecheck
npm test
```

根据风险追加：

- SQLite：旧 Schema → 新 Schema migration、关闭后重开、事务失败回滚。
- 日期/调度：月末、年末、逾期、恰好 5 秒、超过 5 秒、本地日期边界。
- Worker：无 Token、错误 Token、输入上限、Provider 超时/限流/鉴权错误、恶意或不完整输出。
- UI：窄屏无溢出、重复点击、防并发、中断恢复和返回页面后的状态。
- 词库：固定哈希、完整解析、坏结构快速失败、稳定 ID。

最后更新受影响的当前维护文档，并在答复中明确列出：修改文件、行为变化、实际执行的验证、未验证事项和需要人工完成的外部步骤。

## 8. 专项变更检查表

### 8.1 新增或切换 AI Provider

- [ ] 实现 `AiArticleProvider`，不修改 Flutter 统一契约。
- [ ] 在 `provider_factory.ts` 注册明确名称。
- [ ] 模型名通过 `AI_MODEL` 配置，不散落硬编码。
- [ ] 厂商 Key 通过 Worker Secret 注入。
- [ ] 映射鉴权、限流、余额、超时、不可用和未知 HTTP 错误。
- [ ] 继续使用统一 PromptBuilder 与输出 Validator。
- [ ] 添加 Mock/Contract 测试；未经用户授权不要产生真实付费调用。
- [ ] 更新 Worker README、开发运维指南和 API 文档。

### 8.2 修改数据库

- [ ] 增加 `databaseVersion`，保留从所有受支持旧版本连续升级的路径。
- [ ] 不删除用户学习记录，不依赖清除 App 数据。
- [ ] 新约束应用前清理或兼容旧数据冲突。
- [ ] 更新模型映射、导出、Debug 和 Memory Repository。
- [ ] 添加 migration、重启持久化、原子性和约束测试。
- [ ] 更新[数据模型与 API](数据模型与API.md)。

### 8.3 修改词库

- [ ] 从外层词库流水线生成，不直接手改 App Asset 作为长期方案。
- [ ] 核对 schema、词数、position、source ID、重复词和释义质量。
- [ ] 评估 `kaoyan_v1` 是否仍兼容；不兼容时设计数据迁移或新命名空间。
- [ ] 审核并更新固定 SHA-256。
- [ ] 运行完整词库解析测试，不只抽样几个词。

## 9. 当前状态与未确认事项

本次交接文档建立时，本地验证结果为：

- `flutter analyze`：通过。
- `flutter test`：91 项通过。
- Worker `npm run typecheck`：通过。
- Worker `npm test`：36 项通过。
- 当前维护文档的本地链接和 Markdown 代码块检查通过。

这些结果只是 2026-08-15 的本地快照，接手时应重新执行。仓库配置表明生产 Provider 目标为 DeepSeek，但不能仅凭本地文件断言 Worker 已部署、Cloudflare 已登录、Secret 已配置或真实 AI 当前可用；这些属于外部环境，必须单独验证。

当前明确未包含的产品能力：登录、云同步、通知、FSRS、多词库、RAG。若用户要求新增这些能力，应先做架构和迁移设计，不要把它们当作已有基础设施。

发布前还应确认 Android application ID、签名、版本号、隐私说明和 Release 构建流程；当前工程仍源自开发期 Android 项目配置，不能仅凭 Debug APK 通过就视为可发布。

## 10. 给下一位 AI 的启动提示词模板

可以把下面内容和具体需求一起交给新的 AI：

```text
你正在接手 Recall 英语词汇 Android App。

工作目录：Recall_app/
先完整阅读：
1. docs/AI交接指南.md
2. README.md
3. docs/系统架构.md
4. docs/数据模型与API.md
5. docs/开发与运维指南.md

然后阅读与任务相关的源码、生产/内存仓库实现和测试。
请遵守本地日历日、稳定词 ID、SQLite 无损迁移、Provider 中立、客户端不持有厂商 Key、AI 失败不阻断学习闭环等约束。

本次任务：<在这里写清具体目标和验收标准>

修改前说明你确认的现状和影响范围；修改后运行相关静态检查与测试，更新受影响的当前维护文档，并报告实际验证结果与未验证的外部步骤。不要把历史验收报告当作当前行为的唯一依据。
```

## 11. 持续交接记录模板

完成一轮较大修改后，可在新的带日期验收记录或任务说明中留下：

```markdown
## 交接快照 YYYY-MM-DD

- 本轮目标：
- 已完成：
- 修改的关键文件：
- 行为或契约变化：
- Schema / Prompt / 调度器版本变化：
- 已执行验证及结果：
- 未执行验证及原因：
- 外部环境状态：
- 已知风险或待办：
- 建议下一步：
```

不要在交接记录中粘贴真实 Secret、完整用户数据库、设备私有信息或未经脱敏的服务日志。
