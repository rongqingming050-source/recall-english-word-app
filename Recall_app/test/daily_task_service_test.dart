import 'package:flutter_test/flutter_test.dart';
import 'package:recall_app/data/memory_learning_repository.dart';
import 'package:recall_app/data/vocabulary_repository.dart';
import 'package:recall_app/learning/daily_task_service.dart';
import 'package:recall_app/learning/first_review_service.dart';
import 'package:recall_app/models/first_layer_word_state.dart';
import 'package:recall_app/models/word.dart';

void main() {
  late MemoryLearningRepository repository;
  late ListVocabularyRepository vocabulary;
  late DateTime current;
  late DailyTaskService service;

  setUp(() {
    repository = MemoryLearningRepository();
    vocabulary = ListVocabularyRepository(_words(8));
    current = DateTime(2026, 8, 14, 9);
    service = DailyTaskService(
      repository: repository,
      vocabulary: vocabulary,
      now: () => current,
    );
  });

  test('same date always returns the original persisted batch', () async {
    await repository.setDailyNewWordTarget(3);

    final first = await service.loadOrCreateToday();
    final second = await service.loadOrCreateToday();

    expect(first.todayAssignedCount, 3);
    expect(
      second.pendingTasks.map((task) => task.wordId),
      first.pendingTasks.map((task) => task.wordId),
    );
    expect((await repository.getAllDailyNewWordTasks()), hasLength(3));
  });

  test('remaining vocabulary smaller than target is not padded', () async {
    vocabulary = ListVocabularyRepository(_words(2));
    service = DailyTaskService(
      repository: repository,
      vocabulary: vocabulary,
      now: () => current,
    );
    await repository.setDailyNewWordTarget(30);

    final plan = await service.loadOrCreateToday();

    expect(plan.todayAssignedCount, 2);
    expect(plan.pendingNewWordCount, 2);
  });

  test(
    'raising the target expands today while preserving completed work',
    () async {
      vocabulary = ListVocabularyRepository(_words(30));
      service = DailyTaskService(
        repository: repository,
        vocabulary: vocabulary,
        now: () => current,
      );
      await repository.setDailyNewWordTarget(10);
      final first = await service.loadOrCreateToday();
      final completedIds = first.pendingTasks
          .take(5)
          .map((task) => task.wordId)
          .toList();
      await repository.markDailyTasksFirstLayerCompleted(
        completedIds,
        completedAt: current,
      );
      await repository.markDailyTasksCompleted(
        completedIds,
        completedAt: current,
      );

      await repository.setDailyNewWordTarget(20);
      final reloaded = await service.loadOrCreateToday();

      expect(reloaded.targetCount, 20);
      expect(reloaded.todayAssignedCount, 20);
      expect(reloaded.pendingNewWordCount, 15);
      expect(reloaded.completedTodayCount, 5);
      expect(reloaded.actualTaskCount, 20);
      expect(
        reloaded.pendingTasks.map((task) => task.wordId),
        isNot(contains(anyOf(completedIds))),
      );
    },
  );

  test('lowering the target only removes unstarted tasks', () async {
    await repository.setDailyNewWordTarget(6);
    final first = await service.loadOrCreateToday();
    final startedId = first.pendingTasks.first.wordId;
    await repository.markDailyTasksFirstLayerCompleted([
      startedId,
    ], completedAt: current);

    await repository.setDailyNewWordTarget(3);
    final reloaded = await service.loadOrCreateToday();

    expect(reloaded.targetCount, 3);
    expect(reloaded.todayAssignedCount, 3);
    expect(reloaded.contextWords.map((word) => word.id), contains(startedId));
  });

  test('repeated target changes never create duplicate daily words', () async {
    vocabulary = ListVocabularyRepository(_words(40));
    service = DailyTaskService(
      repository: repository,
      vocabulary: vocabulary,
      now: () => current,
    );

    for (final target in [10, 20, 5, 30]) {
      await repository.setDailyNewWordTarget(target);
      final plan = await service.loadOrCreateToday();
      final ids = plan.pendingTasks.map((task) => task.wordId).toList();

      expect(plan.targetCount, target);
      expect(plan.todayAssignedCount, target);
      expect(ids.toSet(), hasLength(ids.length));
      expect(
        (await repository.getAllDailyNewWordTasks())
            .map((task) => task.wordId)
            .toSet(),
        hasLength(target),
      );
    }
  });

  test('lowering below completed work preserves every learned task', () async {
    vocabulary = ListVocabularyRepository(_words(20));
    service = DailyTaskService(
      repository: repository,
      vocabulary: vocabulary,
      now: () => current,
    );
    await repository.setDailyNewWordTarget(10);
    var plan = await service.loadOrCreateToday();
    final completedIds = plan.pendingTasks
        .take(7)
        .map((task) => task.wordId)
        .toList();
    await repository.markDailyTasksFirstLayerCompleted(
      completedIds,
      completedAt: current,
    );
    await repository.markDailyTasksCompleted(
      completedIds,
      completedAt: current,
    );

    await repository.setDailyNewWordTarget(5);
    plan = await service.loadOrCreateToday();

    expect(plan.targetCount, 5);
    expect(plan.todayAssignedCount, 7);
    expect(plan.completedTodayCount, 7);
    expect(plan.actualTaskCount, 7);
    final storedIds = (await repository.getAllDailyNewWordTasks())
        .map((task) => task.wordId)
        .toSet();
    expect(storedIds, containsAll(completedIds));
  });

  test('raising target with historical backlog fills the new total', () async {
    vocabulary = ListVocabularyRepository(_words(50));
    service = DailyTaskService(
      repository: repository,
      vocabulary: vocabulary,
      now: () => current,
    );
    await repository.setDailyNewWordTarget(10);
    var plan = await service.loadOrCreateToday();
    final completedIds = plan.pendingTasks
        .take(4)
        .map((task) => task.wordId)
        .toList();
    await repository.markDailyTasksFirstLayerCompleted(
      completedIds,
      completedAt: current,
    );
    await repository.markDailyTasksCompleted(
      completedIds,
      completedAt: current,
    );

    current = DateTime(2026, 8, 15, 9);
    plan = await service.loadOrCreateToday();
    expect(plan.historicalPendingCount, 6);
    expect(plan.todayAssignedCount, 4);
    expect(plan.pendingNewWordCount, 10);

    await repository.setDailyNewWordTarget(20);
    plan = await service.loadOrCreateToday();
    expect(plan.historicalPendingCount, 6);
    expect(plan.todayAssignedCount, 14);
    expect(plan.pendingNewWordCount, 20);
    expect(plan.pendingTasks.map((task) => task.wordId).toSet(), hasLength(20));

    final completedHistoricalIds = plan.pendingTasks
        .where((task) => task.taskDate.isBefore(plan.date))
        .take(3)
        .map((task) => task.wordId)
        .toList();
    await repository.markDailyTasksFirstLayerCompleted(
      completedHistoricalIds,
      completedAt: current,
    );
    await repository.markDailyTasksCompleted(
      completedHistoricalIds,
      completedAt: current,
    );
    plan = await service.loadOrCreateToday();
    expect(plan.completedTodayCount, 3);
    expect(plan.pendingNewWordCount, 17);
    expect(plan.actualTaskCount, 20);
  });

  test(
    'completed first-layer word resumes context instead of first layer',
    () async {
      await repository.setDailyNewWordTarget(3);
      var plan = await service.loadOrCreateToday();
      final completedWord = plan.firstLayerWords.first;
      final state = FirstLayerWordState(word: completedWord)
        ..recordJudgment(StudyChoice.known);

      await repository.saveFirstLayerResults([state], completedAt: current);
      plan = await service.loadOrCreateToday();

      expect(plan.contextWords.map((word) => word.id), [completedWord.id]);
      expect(plan.firstLayerWords, hasLength(2));
      expect(
        plan.firstLayerWords.map((word) => word.id),
        isNot(contains(completedWord.id)),
      );

      await repository.markDailyTasksCompleted([
        completedWord.id,
      ], completedAt: current);
      plan = await service.loadOrCreateToday();
      expect(plan.pendingNewWordCount, 2);
    },
  );

  test(
    'all historical unfinished words have priority over new words',
    () async {
      await repository.setDailyNewWordTarget(3);
      var plan = await service.loadOrCreateToday();
      final firstId = plan.pendingTasks.first.wordId;
      await repository.markDailyTasksFirstLayerCompleted([
        firstId,
      ], completedAt: current);
      await repository.markDailyTasksCompleted([firstId], completedAt: current);

      current = DateTime(2026, 8, 15, 9);
      plan = await service.loadOrCreateToday();
      expect(plan.historicalPendingCount, 2);
      expect(plan.todayAssignedCount, 1);
      expect(plan.pendingNewWordCount, 3);

      current = DateTime(2026, 8, 16, 9);
      plan = await service.loadOrCreateToday();
      expect(plan.historicalPendingCount, 3);
      expect(plan.todayAssignedCount, 0);
      expect(plan.pendingNewWordCount, 3);
    },
  );

  test('local date batches work across month and year boundaries', () async {
    await repository.setDailyNewWordTarget(1);
    current = DateTime(2026, 8, 31, 23, 50);
    var plan = await service.loadOrCreateToday();
    await _complete(repository, plan, current);

    current = DateTime(2026, 9, 1, 0, 5);
    plan = await service.loadOrCreateToday();
    expect(plan.date, DateTime(2026, 9, 1));
    await _complete(repository, plan, current);

    current = DateTime(2026, 12, 31, 23, 50);
    plan = await service.loadOrCreateToday();
    await _complete(repository, plan, current);

    current = DateTime(2027, 1, 1, 0, 5);
    plan = await service.loadOrCreateToday();
    expect(plan.date, DateTime(2027, 1, 1));
    expect(plan.todayAssignedCount, 1);
  });

  test(
    'finishing after midnight assigns reviews from the completion date',
    () async {
      await repository.setDailyNewWordTarget(1);
      current = DateTime(2026, 8, 14, 23, 59);
      final plan = await service.loadOrCreateToday();
      final word = plan.firstLayerWords.single;
      final state = FirstLayerWordState(word: word)
        ..recordJudgment(StudyChoice.known);

      current = DateTime(2026, 8, 15, 0, 1);
      await repository.saveFirstLayerResults([state], completedAt: current);
      await FirstReviewService(
        repository: repository,
      ).scheduleTargetWords([word], now: current);
      await repository.markDailyTasksCompleted([word.id], completedAt: current);

      final reviewTask = (await repository.getAllReviewTasks()).single;
      expect(reviewTask.reviewDate, DateTime(2026, 8, 18));
      final nextDayPlan = await service.loadOrCreateToday();
      expect(nextDayPlan.date, DateTime(2026, 8, 15));
      expect(nextDayPlan.todayAssignedCount, 1);
      expect(nextDayPlan.pendingNewWordCount, 1);
    },
  );
}

List<Word> _words(int count) => List.generate(
  count,
  (index) => Word(
    word: 'word$index',
    phonetic: '/w$index/',
    meaning: '词$index',
    example: 'This is word$index.',
  ),
);

Future<void> _complete(
  MemoryLearningRepository repository,
  TodayTaskPlan plan,
  DateTime at,
) async {
  final ids = plan.pendingTasks.map((task) => task.wordId).toList();
  await repository.markDailyTasksFirstLayerCompleted(ids, completedAt: at);
  await repository.markDailyTasksCompleted(ids, completedAt: at);
}
