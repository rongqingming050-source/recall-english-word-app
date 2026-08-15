import 'package:flutter/material.dart';

import 'data/learning_repository.dart';
import 'data/memory_learning_repository.dart';
import 'data/vocabulary_repository.dart';
import 'context/context_article_generator.dart';
import 'settings/ai_service_settings.dart';
import 'pages/home_page.dart';
import 'widgets/splash_screen.dart';

class RecallApp extends StatefulWidget {
  const RecallApp({
    super.key,
    this.repository,
    required this.vocabulary,
    this.articleGenerator,
    this.aiServiceSettings,
    this.showSplash = false,
    this.now = DateTime.now,
  });

  final LearningRepository? repository;
  final VocabularyRepository vocabulary;
  final ArticleGenerator? articleGenerator;
  final AiServiceSettings? aiServiceSettings;
  final bool showSplash;
  final DateTime Function() now;

  @override
  State<RecallApp> createState() => _RecallAppState();
}

class _RecallAppState extends State<RecallApp> {
  late final LearningRepository _repository;
  late final ArticleGenerator _articleGenerator;
  late final AiServiceSettings _aiServiceSettings;

  @override
  void initState() {
    super.initState();
    _repository = widget.repository ?? MemoryLearningRepository();
    _aiServiceSettings = widget.aiServiceSettings ?? MemoryAiServiceSettings();
    _articleGenerator = widget.articleGenerator ?? FakeArticleGenerator();
  }

  @override
  Widget build(BuildContext context) {
    final homePage = HomePage(
      repository: _repository,
      vocabulary: widget.vocabulary,
      articleGenerator: _articleGenerator,
      aiServiceSettings: _aiServiceSettings,
      now: widget.now,
    );

    return MaterialApp(
      title: 'Recall',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: widget.showSplash ? SplashGate(child: homePage) : homePage,
    );
  }
}
