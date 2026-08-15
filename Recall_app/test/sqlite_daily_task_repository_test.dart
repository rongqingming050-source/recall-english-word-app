import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:recall_app/data/sqlite_learning_repository.dart';
import 'package:recall_app/data/vocabulary_repository.dart';
import 'package:recall_app/learning/daily_task_service.dart';
import 'package:recall_app/learning/first_review_service.dart';
import 'package:recall_app/models/first_layer_word_state.dart';
import 'package:recall_app/models/word.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('daily batch survives repository close and reopen', () async {
    final directory = await Directory.systemTemp.createTemp('recall_daily_');
    addTearDown(() => directory.delete(recursive: true));
    final path = p.join(directory.path, 'daily.db');
    final vocabulary = ListVocabularyRepository(_words(5));
    final now = DateTime(2026, 8, 14, 9);
    var repository = await SqliteLearningRepository.open(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
    await repository.setDailyNewWordTarget(3);
    var service = DailyTaskService(
      repository: repository,
      vocabulary: vocabulary,
      now: () => now,
    );
    final first = await service.loadOrCreateToday();
    final firstIds = first.pendingTasks.map((task) => task.wordId).toList();
    await repository.close();

    repository = await SqliteLearningRepository.open(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
    addTearDown(repository.close);
    service = DailyTaskService(
      repository: repository,
      vocabulary: vocabulary,
      now: () => now,
    );
    final reopened = await service.loadOrCreateToday();

    expect(reopened.pendingTasks.map((task) => task.wordId), firstIds);
    expect(reopened.todayAssignedCount, 3);
    expect(await repository.getDailyNewWordTarget(), 3);
  });

  test(
    'changed target resizes today and persists the expanded batch',
    () async {
      final directory = await Directory.systemTemp.createTemp('recall_resize_');
      addTearDown(() => directory.delete(recursive: true));
      final path = p.join(directory.path, 'daily.db');
      final vocabulary = ListVocabularyRepository(_words(30));
      final now = DateTime(2026, 8, 14, 9);
      var repository = await SqliteLearningRepository.open(
        factory: databaseFactoryFfi,
        databasePath: path,
      );
      await repository.setDailyNewWordTarget(10);
      var service = DailyTaskService(
        repository: repository,
        vocabulary: vocabulary,
        now: () => now,
      );
      var plan = await service.loadOrCreateToday();
      final completedIds = plan.pendingTasks
          .take(5)
          .map((task) => task.wordId)
          .toList();
      await repository.markDailyTasksFirstLayerCompleted(
        completedIds,
        completedAt: now,
      );
      await repository.markDailyTasksCompleted(completedIds, completedAt: now);
      await repository.setDailyNewWordTarget(20);

      plan = await service.loadOrCreateToday();
      expect(plan.targetCount, 20);
      expect(plan.todayAssignedCount, 20);
      expect(plan.pendingNewWordCount, 15);
      await repository.close();

      repository = await SqliteLearningRepository.open(
        factory: databaseFactoryFfi,
        databasePath: path,
      );
      addTearDown(repository.close);
      service = DailyTaskService(
        repository: repository,
        vocabulary: vocabulary,
        now: () => now,
      );
      plan = await service.loadOrCreateToday();
      expect(plan.targetCount, 20);
      expect(plan.todayAssignedCount, 20);
      expect(plan.pendingNewWordCount, 15);
    },
  );

  test(
    'interrupted first-layer work resumes and later schedules once',
    () async {
      final directory = await Directory.systemTemp.createTemp('recall_resume_');
      addTearDown(() => directory.delete(recursive: true));
      final path = p.join(directory.path, 'daily.db');
      final vocabulary = ListVocabularyRepository(_words(5));
      final now = DateTime(2026, 8, 14, 23, 58);
      var repository = await SqliteLearningRepository.open(
        factory: databaseFactoryFfi,
        databasePath: path,
      );
      await repository.setDailyNewWordTarget(3);
      var service = DailyTaskService(
        repository: repository,
        vocabulary: vocabulary,
        now: () => now,
      );
      var plan = await service.loadOrCreateToday();
      final startedWord = plan.firstLayerWords.first;
      final state = FirstLayerWordState(word: startedWord)
        ..recordJudgment(StudyChoice.known);
      await repository.saveFirstLayerResults([state], completedAt: now);
      await repository.close();

      repository = await SqliteLearningRepository.open(
        factory: databaseFactoryFfi,
        databasePath: path,
      );
      service = DailyTaskService(
        repository: repository,
        vocabulary: vocabulary,
        now: () => now,
      );
      plan = await service.loadOrCreateToday();
      expect(plan.contextWords.map((word) => word.id), [startedWord.id]);
      expect(plan.firstLayerWords, hasLength(2));
      expect(await repository.getAllReviewTasks(), isEmpty);

      await FirstReviewService(
        repository: repository,
      ).scheduleTargetWords([startedWord], now: now);
      await repository.markDailyTasksCompleted([
        startedWord.id,
      ], completedAt: now);
      await repository.close();

      repository = await SqliteLearningRepository.open(
        factory: databaseFactoryFfi,
        databasePath: path,
      );
      addTearDown(repository.close);
      service = DailyTaskService(
        repository: repository,
        vocabulary: vocabulary,
        now: () => now,
      );
      plan = await service.loadOrCreateToday();
      expect(plan.contextWords, isEmpty);
      expect(plan.firstLayerWords, hasLength(2));
      final reviewTasks = await repository.getAllReviewTasks();
      expect(reviewTasks, hasLength(1));
      expect(reviewTasks.single.wordId, startedWord.id);
      expect(reviewTasks.single.reviewDate, DateTime(2026, 8, 17));
    },
  );
}

List<Word> _words(int count) => List.generate(
  count,
  (index) => Word(
    word: 'sqlite$index',
    phonetic: '/s$index/',
    meaning: '词$index',
    example: 'This is sqlite$index.',
  ),
);
