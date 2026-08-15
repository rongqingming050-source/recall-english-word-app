# Recall English Word App

本仓库包含 Recall 考研英语词汇 Android App、AI 语境文章 Worker，以及正式词库的生成与审校工具。

## 仓库结构

```text
recall-english-word-app/
├── Recall_app/                  # Flutter App、Cloudflare Worker、测试和技术文档
├── scripts/                     # 词义审计与清理脚本
├── 蒸馏/                        # 词库构建脚本、格式说明和生成结果
└── Recall_app_初始化总结报告.md  # 项目初始化历史记录
```

## 快速开始

```bash
git clone https://github.com/rongqingming050-source/recall-english-word-app.git
cd recall-english-word-app/Recall_app
flutter pub get
flutter analyze
flutter test
flutter run
```

## 从这里开始

- [App 项目说明](Recall_app/README.md)
- [技术文档索引](Recall_app/docs/README.md)
- [AI 交接指南](Recall_app/docs/AI交接指南.md)
- [系统架构](Recall_app/docs/系统架构.md)
- [开发与运维指南](Recall_app/docs/开发与运维指南.md)
- [数据模型与 API](Recall_app/docs/数据模型与API.md)
- [贡献指南](CONTRIBUTING.md)

原始参考 PDF、构建产物、依赖缓存、调试数据库、截图和本地 Secret 不进入 Git。App 运行所需的最终词库 `Recall_app/assets/vocabulary/kaoyan_clean.json` 会随仓库版本化。

## License

Copyright © 2026 qingming Kim. All rights reserved. 源代码公开主要用于学习、交流和项目展示；未经明确许可，不得用于商业用途或重新分发。详见 [LICENSE](LICENSE)。
