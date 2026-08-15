import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recall_app/data/learning_data_exporter.dart';
import 'package:recall_app/data/memory_learning_repository.dart';
import 'package:recall_app/data/vocabulary_repository.dart';
import 'package:recall_app/learning/daily_task_service.dart';
import 'package:recall_app/models/first_layer_word_state.dart';
import 'package:recall_app/models/context_article.dart';
import 'package:recall_app/models/word.dart';
import 'package:recall_app/review/review_scheduler.dart';

void main() {
  test('exports learning records and review tasks as JSON', () async {
    final directory = await Directory.systemTemp.createTemp('recall_export_');
    addTearDown(() => directory.delete(recursive: true));
    final repository = MemoryLearningRepository();
    const word = Word(
      word: 'sample',
      phonetic: '/sample/',
      meaning: '样例',
      example: 'Sample.',
    );
    final state = FirstLayerWordState(word: word)
      ..recordJudgment(StudyChoice.known);
    await repository.saveFirstLayerResults([
      state,
    ], completedAt: DateTime(2026, 8, 13));
    final task = await repository.overrideReviewTaskToTomorrow(
      word,
      now: DateTime(2026, 8, 13),
    );
    await repository.completeReviewTask(
      reviewTaskId: task.id,
      result: StudyChoice.known,
      reactionTimeMs: 3240,
      reviewedAt: DateTime(2026, 8, 14, 9, 30),
    );
    await repository.upsertContextArticle(
      ContextArticle(
        contextSessionId: 'session-1',
        requestId: 'request-1',
        title: 'Context title',
        articleText: 'This text is intentionally not exported.',
        sourceWordIds: [word.id],
        usedWordIds: [word.id],
        provider: 'fake',
        model: 'fake-context-v1',
        promptVersion: 'context_article_v1',
        status: ContextArticleStatus.success,
        generatedAt: DateTime(2026, 8, 14),
      ),
    );
    final exporter = LearningDataExporter(
      directoryProvider: () async => directory,
    );
    final vocabulary = ListVocabularyRepository([word]);
    final dailyTaskService = DailyTaskService(
      repository: repository,
      vocabulary: vocabulary,
      now: () => DateTime(2026, 8, 14),
    );

    final file = await exporter.export(
      repository,
      vocabulary: vocabulary,
      dailyTaskService: dailyTaskService,
    );
    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;

    expect(file.path, endsWith('recall_learning_data.json'));
    expect(json['learningRecords'], hasLength(1));
    expect(json['reviewTasks'], hasLength(2));
    expect(json['reviewAttempts'], hasLength(1));
    expect(json['dailyNewWordTasks'], isEmpty);
    final contextArticle = (json['contextArticles'] as List).single as Map;
    expect(contextArticle['contextSessionId'], 'session-1');
    expect(contextArticle['provider'], 'fake');
    expect(contextArticle, isNot(contains('articleText')));
    expect(jsonEncode(json), isNot(contains('request-1')));
    final vocabularySummary = json['vocabularySummary'] as Map;
    expect(vocabularySummary['vocabularyId'], 'fixture');
    expect(vocabularySummary['totalCount'], 1);
    expect(vocabularySummary['firstLayerCompletedCount'], 1);
    expect(vocabularySummary['dailyNewWordTarget'], 10);
    final attempt = (json['reviewAttempts'] as List).single as Map;
    expect(attempt['wordId'], 'sample');
    expect(attempt['result'], StudyChoice.known.name);
    expect(attempt['reactionMs'], 3240);
    expect(attempt['fluency'], ReviewFluency.normal.name);
    expect(attempt['previousIntervalDays'], 1);
    expect(attempt['nextIntervalDays'], 3);
    expect(attempt['scheduledReviewDate'], '2026-08-14T00:00:00.000');
    expect(attempt['actualReviewDate'], '2026-08-14T00:00:00.000');
    expect(attempt['overdueDays'], 0);
    expect(attempt['schedulerVersion'], ReviewPolicy.schedulerVersion);
  });
}
