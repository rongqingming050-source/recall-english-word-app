# Recall_app AI语境文章后端与多Provider架构验收报告

> 历史文档：本文记录 2026-08-15 的验收快照。当前设计请从[技术文档索引](README.md)进入。

验收日期：2026-08-15

## 一、结论与范围

本次已完成 Provider 无关的 Flutter 客户端、SQLite V6 缓存、Cloudflare Worker、Fake Provider、DeepSeek Provider、本地 Fake 全链路、错误/跳过机制、Debug/JSON 集成及自动化验证。原有第一层、每日任务、首次正式复习、第二层和动态复习规则未重写。

需要明确区分：

- **代码实现完成**：Provider 抽象、Fake Provider、DeepSeek Provider、Worker API、Flutter 远程客户端、设置安全存储、缓存、页面四态、跳过、Debug、导出和测试均已完成。
- **真实线上 AI 验收未完成**：当前真实配置为 DeepSeek `deepseek-v4-flash`，但尚未输入 `DEEPSEEK_API_KEY`，且 Wrangler 当前未登录 Cloudflare。因此线上部署、真实付费调用、Samsung SM-X610 真实 AI/强制停止缓存测试和真机断网测试均未伪造结果。

## 二、目录与架构

后端与 Flutter 已物理分离，Node/TypeScript 依赖仅位于后端：

```text
Recall_app/
├── lib/
│   ├── context/context_article_generator.dart
│   ├── data/context_article_repository.dart
│   ├── models/context_article.dart
│   ├── pages/context_article_page.dart
│   ├── pages/ai_service_settings_page.dart
│   └── settings/ai_service_settings.dart
├── test/
├── tool/local_fake_integration.dart
└── backend/recall_ai_worker/
    ├── src/
    │   ├── index.ts
    │   ├── input_validator.ts
    │   ├── prompt_builder.ts
    │   ├── context_article_validator.ts
    │   ├── service.ts
    │   ├── errors.ts
    │   ├── types.ts
    │   └── providers/
    │       ├── ai_article_provider.ts
    │       ├── fake_ai_article_provider.ts
    │       ├── deepseek_ai_article_provider.ts
    │       └── provider_factory.ts
    ├── test/worker.test.ts
    ├── wrangler.toml
    ├── .dev.vars.example
    ├── package.json
    └── tsconfig.json
```

运行链路：

```text
ContextArticlePage
  → ArticleGenerator
  → RemoteArticleGenerator
  → SQLite success cache
  → HTTPS POST /v1/context-article
  → Worker Auth
  → Request Validator
  → ContextArticlePromptBuilder
  → AiArticleProvider
  → ContextArticleValidator
  → unified response
  → SQLite V6 cache
```

## 三、逐项验收说明

### 1. Cloudflare Worker 与接口

- `GET /health` 返回 `{ok:true, service:"recall-ai", version:"v1"}`，不认证、不调用 Provider、不返回配置。
- `POST /v1/context-article` 是 Flutter 唯一认识的生成接口。
- 其他路由返回统一错误对象，不返回内部堆栈或上游原始响应。

### 2. AiArticleProvider 设计与 Fake Provider

`AiArticleProvider.generateContextArticle()` 只接受统一的 `ContextArticleGenerationRequest`，只返回 `ContextArticleGenerationResult`。业务服务不依赖任何厂商 SDK 类型。

`FakeAiArticleProvider` 已实现并用于本地开发、Contract Test 和 Worker 自动化测试；它不访问网络或付费 AI。

当前真实 Provider：**DeepSeek 已实现**，使用官方 OpenAI-compatible Chat Completions API、JSON Output 和 `DEEPSEEK_API_KEY`。当前模型为 `deepseek-v4-flash`；已经停用的 `deepseek-chat` 未被采用。没有一次性预写 OpenAI/Gemini/Anthropic/Qwen 等无关 Provider。

### 3. Provider 与模型配置/切换

- `AI_PROVIDER` 由集中式 `ProviderFactory` 解析；当前注册值为 `fake`、`deepseek`，生产配置为 `deepseek`。
- `AI_MODEL` 由 Worker 环境变量传给统一服务及 Provider 请求，不散落硬编码于业务逻辑。
- 将来切换厂商只需新增/注册对应 Provider、修改 `AI_PROVIDER`/`AI_MODEL`、配置该厂商 Secret 并重新部署。Flutter UI、SQLite Schema、重点词算法和学习/复习流程无需修改。

### 4. API Key、RECALL_APP_TOKEN 与 Flutter 隔离

DeepSeek API Key 只能写入 Cloudflare Worker Secret `DEEPSEEK_API_KEY`；本地仅可写入已忽略的 `.dev.vars`。仓库只提供 `.dev.vars.example` 占位模板。

`RECALL_APP_TOKEN` 只保护 Flutter → Recall Worker，和 Worker → AI 厂商的 API Key 完全分离。缺失或错误 Bearer Token 均返回 401，响应不会返回正确 Token。

Flutter 只保存 Worker URL 和 Worker Access Token：URL 用普通首选项保存，Access Token 使用 Android 安全存储。Flutter 没有任何厂商 SDK、厂商 Key 字段或厂商分支，因此拿不到厂商 API Key。

### 5. PromptBuilder 与 PromptVersion

`ContextArticlePromptBuilder` 独立于 Provider，统一规定自然英文、unknown/unsure/known 优先级、权威词义、禁止题目/翻译/词表/建议/聊天/Markdown/HTML等产品规则。

当前版本为 `context_article_v1`，成功响应和 SQLite 记录均保存 `promptVersion`。

### 6. 请求与响应结构

Flutter 最小请求只发送：

```json
{
  "requestId": "req-...",
  "contextSessionId": "context-...",
  "words": [
    {
      "wordId": "kaoyan_v1:...",
      "word": "derive",
      "meaning": "v. 得到；推导出；源于",
      "priority": "unknown"
    }
  ]
}
```

不发送全词库、学习历史、reaction_ms、review_attempts、forget_count、设备或身份信息。

统一成功响应的文章核心为 `title`、`article`、`usedWordIds`；外层同时返回缓存审计所需的 `requestId`、`contextSessionId`、`provider`、`model`、`promptVersion`、`generatedAt`。不返回厂商原始 JSON、AI 词义、HTML、Markdown 或中文翻译。

### 7. 输入与模型输出 Validator

输入检查覆盖 requestId、contextSessionId、非空 words、最大 15 词、wordId/word/meaning/priority、重复 wordId 和字段长度。

`ContextArticleValidator` 集中检查标题/正文非空、usedWordIds 来源合法且不重复、每个 claimed word 实际出现在正文。匹配不区分大小写，使用完整英文词边界，`art` 不会误匹配 `article`。

正式词条不被拆分；对 `railroad/railway`、`cosy/cozy` 提供最小 slash-separated surface-form 支持，合法变体仍映射回同一 wordId。

Flutter 收到响应后还会进行一次本地防御性校验。

### 8. SQLite context_articles 与缓存

数据库从 V5 正式迁移到 V6，新表字段包括：

`id, context_session_id, request_id, title, article_text, source_word_ids_json, used_word_ids_json, provider, model, prompt_version, status, generated_at, error_code`

状态为 `success/failed/skipped`。同一 `contextSessionId` 的成功文章是稳定缓存；再次进入先读成功缓存，不再请求 Worker。失败记录可由用户主动重试更新；成功缓存不会被后续失败/跳过覆盖。Provider 或模型变化不会使旧 session 缓存失效。

迁移测试证明 V5 学习记录在升级到 V6 后仍保留，并可正常写入新表；另有仓库关闭/重建后读取同一文章的持久化测试。

### 9. Flutter 页面、错误与跳过

页面状态已覆盖 `loading/success/error/cached`：生成中显示“正在生成语境文章……”，缓存显示“已读取缓存”。

失败后不后台循环重试；仅用户点击“重新生成”才重新请求。请求进行中有并发闸门，连点不会生成多个调用。错误只显示稳定短消息。

“暂时跳过”写入 `contextArticleStatus=skipped`，随后复用原有阅读完成路径：调度首次正式复习并完成每日任务。测试证明第一层 known 词跳过后仍按原 3 天规则进入 `waitingReview`。AI 失败不会成为学习闭环单点故障。

### 10. 重点词、点击释义和 WordEntry 安全

重点词仍来自现有 `ContextWordSelector` 和本轮第一层完成记录，最多 15 个，不从其他批次补词。发送给 Worker 的 priority 由第一层结果转换。

只有 `usedWordIds` 对应的正文 surface form 被加粗、可点击；普通 source word 即使出现在正文也不可点击。弹层继续读取本地 `Word`/`WordEntry` 的音标、正式中文释义、正式例句，并保留“重学”。AI 响应不存在写回词库的代码路径。

### 11. 统一错误与日志

Worker 错误码类型覆盖：`unauthorized, invalid_request, provider_not_configured, provider_auth_error, provider_rate_limited, provider_timeout, provider_error, invalid_model_output, server_error`。DeepSeek 401 映射为 `provider_auth_error`，429 映射为 `provider_rate_limited`，其他上游 HTTP/网络错误不会把 DeepSeek 原始错误或 Key 返回 Flutter。

Worker 日志只记录 requestId、contextSessionId、耗时、词数、provider、model、HTTP 状态和结果；不记录 Authorization、RECALL_APP_TOKEN、API Key、完整释义或完整正文。

### 12. Debug 与 JSON 导出

Debug 页面新增只读“AI 语境文章”，显示 contextSessionId、status、title、sourceWordIds、usedWordIds、provider、model、promptVersion、generatedAt、errorCode，不显示任何 Secret。

JSON 导出新增 `contextArticles`，包含上述审计字段；选择不导出 `articleText` 和 `requestId`，也不导出任何 URL、Access Token 或厂商 Secret。

## 四、自动化与集成测试结果

- `flutter analyze`：通过，0 issues。
- `flutter test`：通过，72 tests。
- Worker `npm run typecheck`：通过。
- Worker `npm test`：通过，32 tests（含 11 项 DeepSeek Provider/路由测试）。
- Flutter → 本地 Wrangler Worker → Fake Provider：通过；第一次真实 HTTP 200，第二次命中客户端缓存，Worker 日志仅出现一次 POST。

覆盖内容包括 health、鉴权、输入异常、请求上限、Fake Contract、DeepSeek Contract/请求结构/JSON Output/401/429/异常输出、Provider 抛错/超时、未知或重复 usedWordId、空标题/正文、claimed word 不存在、完整词匹配和变体；Flutter 覆盖缓存前后、仓库重建、V5→V6、网络失败、响应校验、四态 UI、主动重试、防并发、跳过及调度、usedWordIds 加粗、点击本地释义、重学和原有全部学习/复习测试。

所有自动化测试均使用 Fake/Mock，不调用真实 AI，不产生真实 AI 费用。

## 五、部署、真机与安全状态

### Worker 部署状态

未部署。`wrangler whoami` 返回未认证，需要用户先执行 `wrangler login`。生产配置已确定为 `AI_PROVIDER=deepseek`、`AI_MODEL=deepseek-v4-flash`；仍需通过 Cloudflare Worker Secret 分别配置 `RECALL_APP_TOKEN` 和 `DEEPSEEK_API_KEY`。不得把 Secret 写入仓库。

### 真实 AI 与真机状态

- DeepSeek 真实 Provider 验收：代码与 Mock Contract 已通过；真实调用未执行，等待 API Key 和 Cloudflare 登录。
- Samsung SM-X610 真实 AI/强制停止缓存测试：未执行。
- 真机断网测试：未执行；自动化网络失败、重试和跳过闭环已通过。

### Secret 泄露检查

全项目排除依赖/构建产物后扫描 `.dev.vars`、`.env`、常见 API Key 前缀、API_KEY、TOKEN、Authorization、Bearer：

- 未发现 `.dev.vars`/`.env` Secret 文件。
- 未发现常见真实 Key 前缀或真实 Token。
- 命中内容仅为变量名、Bearer 实现、`.dev.vars.example` 占位符和测试专用假 Token。
- `.gitignore` 已加入 `.dev.vars`、`.env*`、`node_modules`、`.wrangler`。
- 当前工作区没有 `.git` 元数据，因此无法执行真实 `git diff/status`；未伪造该项结果。

## 六、当前未实现内容与下一步人工输入

当前刻意未执行/实现：真实付费 AI 调用、Cloudflare 正式部署、真机真实 AI 和真机断网验收，以及所有 V2/多模型路由/RAG/Agent/AI 复习算法功能。DeepSeek Provider 代码已经完成。

继续真实验收前需要用户提供或完成：

1. 执行 `wrangler login` 并确认部署账户/权限；
2. 执行 `npx wrangler secret put DEEPSEEK_API_KEY`，在交互提示中输入 DeepSeek Key；
3. 执行 `npx wrangler secret put RECALL_APP_TOKEN`，输入一个与 DeepSeek Key 不同的 Recall 私有访问令牌；
4. 部署 Worker，并在 Flutter“AI 服务设置”中填写 Worker HTTPS URL 和同一个 `RECALL_APP_TOKEN`；
5. 在 Samsung SM-X610 执行 8～15 个真实重点词、强制停止缓存和断网跳过验收。

本阶段在此停止，不继续开发其他 AI Provider 或 V2 功能。
