import 'package:flutter_test/flutter_test.dart';
import 'package:recall_app/context/context_article_generator.dart';
import 'package:recall_app/data/memory_learning_repository.dart';
import 'package:recall_app/models/context_article.dart';
import 'package:recall_app/settings/ai_service_settings.dart';

void main() {
  test('Flutter client reaches local Fake Worker then reads cache', () async {
    final repository = MemoryLearningRepository();
    final generator = RemoteArticleGenerator(
      repository: repository,
      settings: MemoryAiServiceSettings(
        const AiServiceConfiguration(
          backendUrl: 'http://127.0.0.1:8787',
          accessToken: 'local-integration-token',
        ),
      ),
    );
    const request = ContextArticleRequest(
      contextSessionId: 'local-fake-integration',
      words: [
        ContextArticleWord(
          wordId: 'kaoyan:derive',
          word: 'derive',
          meaning: 'v. 推导出；源于',
          priority: ContextWordPriority.unknown,
        ),
        ContextArticleWord(
          wordId: 'kaoyan:notion',
          word: 'notion',
          meaning: 'n. 概念；想法',
          priority: ContextWordPriority.unsure,
        ),
      ],
    );

    final generated = await generator.generateArticle(request);
    final cached = await generator.generateArticle(request);
    expect(generated.isCached, isFalse);
    expect(cached.isCached, isTrue);
    expect(generated.article.provider, 'fake');
    expect(generated.article.usedWordIds, hasLength(2));
  });
}
