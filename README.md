# Recall English Word App

本仓库包含 Recall 考研英语词汇 Android App、AI 语境文章 Worker，以及正式词库的生成与审校工具。

## 仓库结构

```text
English word app/
├── Recall_app/                  # Flutter App、Cloudflare Worker、测试和技术文档
├── scripts/                     # 词义审计与清理脚本
├── 蒸馏/                        # 词库构建脚本、格式说明和生成结果
└── Recall_app_初始化总结报告.md  # 项目初始化历史记录
```

## 从这里开始

- [App 项目说明](Recall_app/README.md)
- [技术文档索引](Recall_app/docs/README.md)
- [AI 交接指南](Recall_app/docs/AI交接指南.md)
- [系统架构](Recall_app/docs/系统架构.md)
- [开发与运维指南](Recall_app/docs/开发与运维指南.md)
- [数据模型与 API](Recall_app/docs/数据模型与API.md)

原始参考 PDF、构建产物、依赖缓存、调试数据库、截图和本地 Secret 不进入 Git。App 运行所需的最终词库 `Recall_app/assets/vocabulary/kaoyan_clean.json` 会随仓库版本化。
