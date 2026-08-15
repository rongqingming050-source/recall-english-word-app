# Recall_app 正式词库与每日任务系统验收报告

> 历史文档：本文记录 2026-08-14～2026-08-15 的验收快照。当前设计请从[技术文档索引](README.md)进入。

验收日期：2026-08-14～2026-08-15  
项目目录：`E:\workplace1\English word app\Recall_app`

## 1. 验收结论

本阶段核心目标已完成：正式考研词库已经作为只读 asset 接入，5847 个词条通过固定哈希与完整结构校验；每日新词设置、按日批次、历史积压、任务状态、SQLite 持久化、首页编排、Debug 和 JSON 导出已经接通。既有第一层、第二层和复习规则没有被重写。

自动化验收通过，Android Debug APK 构建、覆盖安装和核心中断恢复真机验收通过。

## 2. 正式数据源确认

- 用户提供的 `蒸馏/output/final_cleanup_changes.json` 是 205 条最终释义清洗变更记录，不是完整词库。
- 完整最终词库来自 `蒸馏/output/kaoyan_clean.json`，该文件已经包含上述清洗结果。
- App 内逐字节副本：`assets/vocabulary/kaoyan_clean.json`。
- 词条数：5847。
- SHA-256：`d3a817ddb2d272a22ce51269096f65108b4e360ddeaec5352318dfff182646d1`。
- App 启动时同时校验固定 SHA-256、根结构、元数据、连续 position、必填字段、源 ID 和单词唯一性；异常会明确失败，不会静默跳过词条。

## 3. 正式词条与稳定 ID

- 新增只读 `WordEntry`，保留源 ID、position、word、phonetic、meaning、example。
- 正式学习 ID 使用 `kaoyan_v1:<源文件 id>`，例如 `kaoyan_v1:radiate`。
- 源 ID 原样保留；标准化拼写只用于验证和查询。
- 测试词条已经移出生产代码，放入 `test/fixtures`。
- 无正式命名空间的历史记录继续保留为 legacy，不自动映射、删除或计入正式词库进度。

## 4. 每日新词任务

- 默认目标 10，支持预设 10、20、30、50 及 1～200 自定义值。
- 设置保存在 SQLite，只影响下一个尚未生成的日期；已经生成的当日批次保持不变。
- 每个本地日历日先生成不可变批次，再在同一事务中写入任务。
- 日期主键和全局唯一 word ID 约束保证同日幂等、单词永不重复分配。
- 第一层完成和完整任务完成分别持久化；完整任务只在语境阅读完成并成功安排首次复习后标记。
- 第一层中途退出时，已完成的单词立即落库；重启后未完成单词继续第一层，已完成但未做语境的单词直接恢复语境。

## 5. 跨天与学习顺序

- 历史积压统计全部早于今天且尚未完成的任务，不局限于昨天。
- 今日新增容量为 `max(0, 每日目标 - 历史待完成数)`，并受剩余未分配词数限制。
- 即使今日容量为 0 也创建空批次，确保同日重复调用结果稳定。
- 首页入口按“正式到期复习 → 未完成语境 → 未完成第一层 → 今日完成”编排。
- 历史任务保留原日期，并按日期和任务 ID 从早到晚处理。

## 6. 数据库与旧数据

- SQLite schema 升级到版本 5。
- 新增 `vocabulary_settings`、`daily_task_batches`、`daily_new_word_tasks`。
- 使用正式 migration，不删除或重建用户数据库。
- 原有 `learning_records`、`review_tasks`、`review_attempts` 及设备上的 legacy 数据均被保留。

## 7. 页面、Debug 与导出

- 首页显示到期复习、待完成新词、历史积压、今日新分配、每日目标和词库进度。
- 新增“词库信息”页和“每日新词设置”页。
- Debug 页增加当前日期、每日目标、正式任务 ID、第一层/完整任务状态和词库进度，只读行为不变。
- JSON 导出增加 `vocabularySummary` 和 `dailyNewWordTasks`，未导出完整 5847 词内容。

## 8. 自动化验收

- `flutter analyze`：通过，0 issue。
- `flutter test`：通过，61/61。
- 覆盖内容包括：正式 asset 固定哈希、5847 条解析、坏数据快速失败、同日幂等、词数不足、设置冻结、第一层和语境状态、全历史积压、跨月、跨年、SQLite 重启持久化、复习流程、首页行为和 JSON 导出。

## 9. Android 真机验收

设备：Samsung SM-X610  
序列号：`R52W90EQWCJ`  
Android：16 / API 36

执行结果：

1. 通过 `adb install -r` 覆盖安装，没有清空 App 数据。
2. 首次启动成功加载 5847 词，首页生成 10 个今日任务，总词数、已进入学习数和第一层完成数显示正确。
3. 首次任务依次为 `radiate`、`radiant`、`radical`、`object`、`objective`、`objection`、`obligation`、`oblige`、`obscure`、`observation`，均带 `kaoyan_v1:` 命名空间。
4. 强制结束并重启后，任务数量、顺序和 ID 与重启前逐项一致，没有重复创建或换词。
5. 在 `radiate` 完成第一层后停在下一词并强制结束；重启后首页仍显示“第一层已完成 1”。再次点击学习会直接恢复语境强化，没有让 `radiate` 重做第一层。
6. 设备自然跨到 2026-08-15 后再次重启：10 个未完成任务仍保留 2026-08-14 原日期，首页显示“历史待完成 10、今日新分配 0”，没有因跨日重复分配新词；Debug 页也只显示原 10 个任务。
7. Logcat 未发现本次启动的 fatal exception。

APK：`build/app/outputs/flutter-apk/app-debug.apk`  
大小：146,214,633 bytes  
SHA-256：`3ff12629922d31f5db286770f95e3f3e969986b528ab3301f21540d85601f9cd`

## 10. 未扩展的范围

- 真机没有为了验收清库、改系统日期或伪造到期时间，因此没有手工走完 10 个新词后等待真实的首次复习间隔；相应调度、复习优先级和跨日逻辑由自动化测试覆盖。
- 语境强化继续使用项目原有本地文章和既有交互，本阶段没有新增 AI 文章接口。
- 未开发 FSRS、登录、云同步、通知或多词库管理。

## 11. 证据文件

- 修订后的实施指令：`docs/Recall_app_正式词库与每日任务系统_实施指令.md`
- 首页首次生成：`tmp/recall-v5-home.png`
- 同日任务首次列表：`tmp/recall-v5-debug-reopen.png`
- 重启后相同列表：`tmp/recall-v5-debug-after-restart-2.png`
- 第一层中断点：`tmp/recall-v5-first-layer-partial.png`
- 重启后进度：`tmp/recall-v5-home-after-partial-ready.png`
- 重启后语境恢复：`tmp/recall-v5-context-resume.png`
- 自然跨日后的首页：`tmp/recall-v5-cross-day-home.png`
- 自然跨日后的任务列表：`tmp/recall-v5-cross-day-debug.png`
