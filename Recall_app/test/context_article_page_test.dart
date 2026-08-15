import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recall_app/context/context_article_generator.dart';
import 'package:recall_app/data/memory_learning_repository.dart';
import 'package:recall_app/learning/first_layer_session.dart';
import 'package:recall_app/models/context_article.dart';
import 'package:recall_app/models/first_layer_word_state.dart';
import 'package:recall_app/models/learning_record.dart';
import 'package:recall_app/models/word.dart';
import 'package:recall_app/pages/context_article_page.dart';

const derive = Word(
  word: 'derive',
  phonetic: '/dɪˈraɪv/',
  meaning: 'v. 推导出',
  example: 'We derive the result from evidence.',
);
const ordinary = Word(
  word: 'ordinary',
  phonetic: '/ˈɔːdnri/',
  meaning: 'adj. 普通的',
  example: 'It was an ordinary day.',
);
const articleRequest = ContextArticleRequest(
  contextSessionId: 'context-page-session',
  words: [
    ContextArticleWord(
      wordId: 'derive',
      word: 'derive',
      meaning: 'v. 推导出',
      priority: ContextWordPriority.unknown,
    ),
    ContextArticleWord(
      wordId: 'ordinary',
      word: 'ordinary',
      meaning: 'adj. 普通的',
      priority: ContextWordPriority.known,
    ),
  ],
);
const summary = FirstLayerSummary(
  targetWordCount: 1,
  firstKnownCount: 1,
  firstUnsureCount: 0,
  firstUnknownCount: 0,
  threeAppearanceCount: 0,
  difficultWordCount: 0,
);

void main() {
  testWidgets('shows loading then success', (tester) async {
    final generator = FakeArticleGenerator(delay: const Duration(seconds: 1));
    await tester.pumpWidget(_page(generator));
    expect(find.byKey(const ValueKey('context-loading')), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.byKey(const ValueKey('context-success')), findsOneWidget);
    expect(find.text('A Deliberate Change'), findsOneWidget);
  });

  testWidgets('shows cached state', (tester) async {
    await tester.pumpWidget(_page(_StaticGenerator(isCached: true)));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('context-cached')), findsOneWidget);
    expect(find.text('已读取缓存'), findsOneWidget);
  });

  testWidgets('manual retry cannot create concurrent requests', (tester) async {
    final generator = _RetryGenerator();
    await tester.pumpWidget(_page(generator));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('context-error')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('context-retry')));
    await tester.tap(
      find.byKey(const ValueKey('context-retry')),
      warnIfMissed: false,
    );
    expect(generator.generationCount, 2);
    generator.completeRetry();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('context-success')), findsOneWidget);
  });

  testWidgets('skip completes learning and preserves first review schedule', (
    tester,
  ) async {
    final repository = MemoryLearningRepository();
    final state = FirstLayerWordState(word: derive)
      ..recordJudgment(StudyChoice.known);
    await repository.saveFirstLayerResults([
      state,
    ], completedAt: DateTime(2026, 8, 15));
    final generator = FakeArticleGenerator(errorCode: 'network_error');
    await tester.pumpWidget(
      _page(
        generator,
        repository: repository,
        targetWords: const [derive],
        now: () => DateTime(2026, 8, 15),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('context-skip')));
    await tester.pumpAndSettle();

    expect(find.text('本轮学习完成'), findsOneWidget);
    expect(generator.skipCount, 1);
    final task = (await repository.getAllReviewTasks()).single;
    expect(task.reviewDate, DateTime(2026, 8, 18));
    expect(
      (await repository.getRecord(derive.id))!.stage,
      LearningStage.waitingReview,
    );
  });

  testWidgets('only usedWordIds are bold and interactive', (tester) async {
    await tester.pumpWidget(_page(_StaticGenerator(isCached: false)));
    await tester.pumpAndSettle();
    final richText = tester.widget<RichText>(
      find.byKey(const ValueKey('context-article')),
    );
    final spans = (richText.text as TextSpan).children!.cast<TextSpan>();
    final deriveSpan = spans.firstWhere(
      (span) => span.text?.toLowerCase() == 'derive',
    );
    expect(deriveSpan.style?.fontWeight, FontWeight.bold);
    expect(deriveSpan.recognizer, isA<TapGestureRecognizer>());
    expect(
      spans.where((span) => span.text?.toLowerCase() == 'ordinary'),
      isEmpty,
    );
    expect(richText.text.toPlainText(), contains('ordinary'));
  });
}

Widget _page(
  ArticleGenerator generator, {
  MemoryLearningRepository? repository,
  List<Word> targetWords = const [derive],
  DateTime Function()? now,
}) => MaterialApp(
  home: ContextArticlePage(
    request: articleRequest,
    focusWords: const [derive, ordinary],
    targetWords: targetWords,
    repository: repository ?? MemoryLearningRepository(),
    summary: summary,
    articleGenerator: generator,
    now: now,
  ),
);

class _StaticGenerator implements ArticleGenerator {
  _StaticGenerator({required this.isCached});

  final bool isCached;

  @override
  Future<ArticleGenerationResult> generateArticle(
    ContextArticleRequest request,
  ) async => ArticleGenerationResult(
    article: ContextArticle(
      contextSessionId: request.contextSessionId,
      requestId: 'static-request',
      title: 'Static title',
      articleText: 'Readers derive an ordinary conclusion from evidence.',
      sourceWordIds: request.words.map((word) => word.wordId).toList(),
      usedWordIds: const ['derive'],
      provider: 'fake',
      model: 'fake-context-v1',
      promptVersion: 'context_article_v1',
      status: ContextArticleStatus.success,
      generatedAt: DateTime(2026, 8, 15),
    ),
    isCached: isCached,
  );

  @override
  Future<ArticleGenerationResult> regenerateArticle(
    ContextArticleRequest request,
  ) => generateArticle(request);

  @override
  Future<void> skipArticle(ContextArticleRequest request) async {}
}

class _RetryGenerator implements ArticleGenerator {
  final Completer<ArticleGenerationResult> _retry = Completer();
  int generationCount = 0;

  @override
  Future<ArticleGenerationResult> generateArticle(
    ContextArticleRequest request,
  ) {
    generationCount += 1;
    if (generationCount == 1) {
      throw const ArticleGenerationException('network_error');
    }
    return _retry.future;
  }

  @override
  Future<ArticleGenerationResult> regenerateArticle(
    ContextArticleRequest request,
  ) => generateArticle(request);

  void completeRetry() {
    _retry.complete(
      ArticleGenerationResult(
        article: ContextArticle(
          contextSessionId: articleRequest.contextSessionId,
          requestId: 'retry-request',
          title: 'Retry succeeded',
          articleText: 'Readers derive a result.',
          sourceWordIds: const ['derive'],
          usedWordIds: const ['derive'],
          provider: 'fake',
          model: 'fake-context-v1',
          promptVersion: 'context_article_v1',
          status: ContextArticleStatus.success,
          generatedAt: DateTime(2026, 8, 15),
        ),
        isCached: false,
      ),
    );
  }

  @override
  Future<void> skipArticle(ContextArticleRequest request) async {}
}
