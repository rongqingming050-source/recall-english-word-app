import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:recall_app/app.dart';
import 'package:recall_app/data/memory_learning_repository.dart';
import 'package:recall_app/data/vocabulary_repository.dart';
import 'package:recall_app/models/first_layer_word_state.dart';
import 'package:recall_app/models/learning_record.dart';
import 'package:recall_app/review/review_queue.dart';
import 'package:recall_app/pages/review_page.dart';

import 'fixtures/test_words.dart';

final testVocabulary = ListVocabularyRepository(testWords);

void main() {
  testWidgets('home only shows review entry when a task is due', (
    tester,
  ) async {
    final repository = MemoryLearningRepository();
    await tester.pumpWidget(
      RecallApp(repository: repository, vocabulary: testVocabulary),
    );
    await tester.pumpAndSettle();
    expect(find.text('待复习：0'), findsOneWidget);

    await _prepare(
      repository,
      DateTime.now().subtract(const Duration(days: 1)),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      RecallApp(repository: repository, vocabulary: testVocabulary),
    );
    await tester.pumpAndSettle();
    expect(find.text('待复习：1'), findsOneWidget);
    expect(find.text('开始今日学习'), findsOneWidget);
  });

  testWidgets('review hides meaning until reveal and completes the queue', (
    tester,
  ) async {
    final repository = MemoryLearningRepository();
    await _prepare(repository, DateTime.now());
    await tester.pumpWidget(
      RecallApp(repository: repository, vocabulary: testVocabulary),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始今日学习'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(testWords.first.meaning), findsNothing);
    expect(find.text('认识'), findsNothing);
    await tester.pump(const Duration(milliseconds: 25));
    await tester.tap(find.text('查看释义'));
    await tester.pump();
    expect(find.text(testWords.first.meaning), findsOneWidget);
    expect(find.text('认识'), findsOneWidget);
    await tester.tap(find.text('认识'));
    await tester.pumpAndSettle();

    expect(find.text('第一层学习'), findsOneWidget);
    expect(find.text(testWords[1].word), findsOneWidget);
    final record = await repository.getRecord(
      stableWordId(testWords.first.word),
    );
    final tasks = await repository.getAllReviewTasks();
    final task = tasks.first;
    final attempt = (await repository.getAllReviewAttempts()).single;
    expect(record!.stage, LearningStage.waitingReview);
    expect(record.isWaitingReview, isTrue);
    expect(record.nextReviewDate, isNotNull);
    expect(record.reviewCount, 1);
    expect(record.lastReviewResult, StudyChoice.known);
    expect(record.recentReactionMilliseconds, greaterThanOrEqualTo(0));
    expect(
      record.averageReactionMilliseconds,
      record.recentReactionMilliseconds,
    );
    expect(task.isCompleted, isTrue);
    expect(task.completedAt, isNotNull);
    expect(attempt.reviewTaskId, task.id);
    expect(tasks.last.isCompleted, isFalse);
  });

  testWidgets('review shows a numberless five-second circular progress', (
    tester,
  ) async {
    final repository = MemoryLearningRepository();
    await _prepare(repository, DateTime.now());
    final task = (await repository.getAllReviewTasks()).single;
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewPage(
          items: [ReviewQueueItem(task: task, word: testWords.first)],
          repository: repository,
        ),
      ),
    );

    CircularProgressIndicator indicator() =>
        tester.widget(find.byKey(const ValueKey('review-recall-progress')));

    expect(indicator().value, 0);
    expect(indicator().color, const Color(0xFF2E7D32));
    expect(find.text('5'), findsNothing);
    await tester.pump(const Duration(milliseconds: 2500));
    expect(indicator().value, closeTo(0.5, 0.02));
    await tester.pump(const Duration(milliseconds: 2500));
    expect(indicator().value, 1);
    expect(indicator().color, const Color(0xFF2E7D32));
    expect(find.text(testWords.first.meaning), findsNothing);
  });

  testWidgets('circular progress pauses and resumes with the app', (
    tester,
  ) async {
    final repository = MemoryLearningRepository();
    await _prepare(repository, DateTime.now());
    final task = (await repository.getAllReviewTasks()).single;
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewPage(
          items: [ReviewQueueItem(task: task, word: testWords.first)],
          repository: repository,
        ),
      ),
    );
    final finder = find.byKey(const ValueKey('review-recall-progress'));

    await tester.pump(const Duration(seconds: 2));
    final beforePause = tester.widget<CircularProgressIndicator>(finder).value!;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 2));
    expect(
      tester.widget<CircularProgressIndicator>(finder).value,
      closeTo(beforePause, 0.001),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(
      tester.widget<CircularProgressIndicator>(finder).value,
      closeTo(beforePause + 0.2, 0.02),
    );
  });

  testWidgets('rapid double tap submits a review result only once', (
    tester,
  ) async {
    final repository = _SlowMemoryLearningRepository();
    await _prepare(repository, DateTime.now());
    final task = (await repository.getAllReviewTasks()).single;
    await tester.pumpWidget(
      MaterialApp(
        home: ReviewPage(
          items: [ReviewQueueItem(task: task, word: testWords.first)],
          repository: repository,
        ),
      ),
    );

    await tester.tap(find.text('查看释义'));
    await tester.pump();
    await tester.tap(find.text('认识'));
    await tester.tap(find.text('认识'));
    await tester.pump();

    expect(repository.completionCalls, 1);
    await tester.pumpAndSettle();
    expect(await repository.getAllReviewAttempts(), hasLength(1));
  });
}

Future<void> _prepare(
  MemoryLearningRepository repository,
  DateTime date,
) async {
  final state = FirstLayerWordState(word: testWords.first)
    ..recordJudgment(StudyChoice.known);
  await repository.saveFirstLayerResults([state], completedAt: date);
  await repository.scheduleFirstReviews({
    stableWordId(testWords.first.word): date,
  }, now: date);
}

class _SlowMemoryLearningRepository extends MemoryLearningRepository {
  int completionCalls = 0;

  @override
  Future<ReviewAttempt> completeReviewTask({
    required int reviewTaskId,
    required StudyChoice result,
    required int reactionTimeMs,
    required DateTime reviewedAt,
  }) async {
    completionCalls++;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return super.completeReviewTask(
      reviewTaskId: reviewTaskId,
      result: result,
      reactionTimeMs: reactionTimeMs,
      reviewedAt: reviewedAt,
    );
  }
}
