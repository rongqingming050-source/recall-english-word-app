import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:recall_app/context/context_article_generator.dart';
import 'package:recall_app/data/memory_learning_repository.dart';
import 'package:recall_app/models/context_article.dart';
import 'package:recall_app/settings/ai_service_settings.dart';

const request = ContextArticleRequest(
  contextSessionId: 'context-session-1',
  words: [
    ContextArticleWord(
      wordId: 'kaoyan:derive',
      word: 'derive',
      meaning: 'v. 推导出',
      priority: ContextWordPriority.unknown,
    ),
  ],
);

void main() {
  test(
    'no cache calls Worker, sends minimum data, and saves success',
    () async {
      final repository = MemoryLearningRepository();
      var calls = 0;
      final generator = RemoteArticleGenerator(
        repository: repository,
        settings: MemoryAiServiceSettings(
          const AiServiceConfiguration(
            backendUrl: 'https://worker.example.test/',
            accessToken: 'recall-access-token',
          ),
        ),
        client: MockClient((incoming) async {
          calls += 1;
          expect(
            incoming.url.toString(),
            'https://worker.example.test/v1/context-article',
          );
          expect(
            incoming.headers['authorization'],
            'Bearer recall-access-token',
          );
          final body = jsonDecode(incoming.body) as Map<String, dynamic>;
          expect(
            body.keys,
            containsAll(<String>['requestId', 'contextSessionId', 'words']),
          );
          expect(body.keys, hasLength(3));
          expect((body['words'] as List).single, {
            'wordId': 'kaoyan:derive',
            'word': 'derive',
            'meaning': 'v. 推导出',
            'priority': 'unknown',
          });
          return http.Response(
            jsonEncode({
              'requestId': body['requestId'],
              'contextSessionId': request.contextSessionId,
              'title': 'A Source of Insight',
              'article':
                  'Researchers derive a useful result from the evidence.',
              'usedWordIds': ['kaoyan:derive'],
              'provider': 'fake',
              'model': 'fake-context-v1',
              'promptVersion': 'context_article_v1',
              'generatedAt': '2026-08-15T01:00:00.000Z',
            }),
            200,
          );
        }),
      );

      final first = await generator.generateArticle(request);
      final second = await generator.generateArticle(request);

      expect(first.isCached, isFalse);
      expect(second.isCached, isTrue);
      expect(calls, 1);
      expect(
        (await repository.getAllContextArticles()).single.status,
        ContextArticleStatus.success,
      );
    },
  );

  test('network failure is stored and retry is user-driven', () async {
    final repository = MemoryLearningRepository();
    var calls = 0;
    final generator = RemoteArticleGenerator(
      repository: repository,
      settings: MemoryAiServiceSettings(
        const AiServiceConfiguration(
          backendUrl: 'https://worker.example.test',
          accessToken: 'token',
        ),
      ),
      client: MockClient((_) async {
        calls += 1;
        throw http.ClientException('offline');
      }),
    );

    await expectLater(
      generator.generateArticle(request),
      throwsA(isA<ArticleGenerationException>()),
    );
    expect(calls, 1);
    final failed = (await repository.getAllContextArticles()).single;
    expect(failed.status, ContextArticleStatus.failed);
    expect(failed.errorCode, 'network_error');
  });

  test('client timeout is stored as network_timeout', () async {
    final repository = MemoryLearningRepository();
    final generator = RemoteArticleGenerator(
      repository: repository,
      settings: MemoryAiServiceSettings(
        const AiServiceConfiguration(
          backendUrl: 'https://worker.example.test',
          accessToken: 'token',
        ),
      ),
      client: MockClient((_) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return http.Response('{}', 200);
      }),
      timeout: const Duration(milliseconds: 1),
    );

    await expectLater(
      generator.generateArticle(request),
      throwsA(
        isA<ArticleGenerationException>().having(
          (error) => error.code,
          'code',
          'network_timeout',
        ),
      ),
    );
    final failed = (await repository.getAllContextArticles()).single;
    expect(failed.errorCode, 'network_timeout');
  });

  test('rejects a usedWordId whose word is absent from the article', () async {
    final repository = MemoryLearningRepository();
    final generator = RemoteArticleGenerator(
      repository: repository,
      settings: MemoryAiServiceSettings(
        const AiServiceConfiguration(
          backendUrl: 'https://worker.example.test',
          accessToken: 'token',
        ),
      ),
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'title': 'Invalid',
            'article': 'No target vocabulary appears here.',
            'usedWordIds': ['kaoyan:derive'],
            'provider': 'fake',
            'model': 'model',
            'promptVersion': 'context_article_v1',
          }),
          200,
        ),
      ),
    );

    await expectLater(
      generator.generateArticle(request),
      throwsA(
        isA<ArticleGenerationException>().having(
          (error) => error.code,
          'code',
          'invalid_response',
        ),
      ),
    );
  });

  test('skip records skipped status without an HTTP request', () async {
    final repository = MemoryLearningRepository();
    var calls = 0;
    final generator = RemoteArticleGenerator(
      repository: repository,
      settings: MemoryAiServiceSettings(),
      client: MockClient((_) async {
        calls += 1;
        return http.Response('', 500);
      }),
    );

    await generator.skipArticle(request);

    expect(calls, 0);
    final skipped = (await repository.getAllContextArticles()).single;
    expect(skipped.status, ContextArticleStatus.skipped);
    expect(skipped.contextSessionId, request.contextSessionId);
  });
}
