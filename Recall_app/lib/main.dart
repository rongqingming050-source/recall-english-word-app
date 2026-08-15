import 'package:flutter/material.dart';

import 'app.dart';
import 'data/sqlite_learning_repository.dart';
import 'data/vocabulary_repository.dart';
import 'context/context_article_generator.dart';
import 'settings/ai_service_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final vocabulary = await AssetVocabularyRepository.load();
    final repository = await SqliteLearningRepository.open();
    final settings = SecureAiServiceSettings();
    final articleGenerator = RemoteArticleGenerator(
      repository: repository,
      settings: settings,
    );
    runApp(
      RecallApp(
        repository: repository,
        vocabulary: vocabulary,
        articleGenerator: articleGenerator,
        aiServiceSettings: settings,
        showSplash: true,
      ),
    );
  } on Object catch (error) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('Recall 启动失败：$error'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
