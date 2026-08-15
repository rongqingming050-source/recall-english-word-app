import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recall_app/data/sqlite_learning_repository.dart';
import 'package:recall_app/models/first_layer_word_state.dart';
import 'package:recall_app/models/learning_record.dart';
import 'package:recall_app/models/word.dart';
import 'package:recall_app/review/review_scheduler.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const knownWord = Word(
  word: 'known',
  phonetic: '/known/',
  meaning: '认识的',
  example: 'Known example.',
);
const learnedWord = Word(
  word: 'derive',
  phonetic: '/derive/',
  meaning: '推导',
  example: 'Derive example.',
);
const difficultWord = Word(
  word: 'difficult',
  phonetic: '/difficult/',
  meaning: '困难的',
  example: 'Difficult example.',
);

void main() {
  sqfliteFfiInit();

  group('SqliteLearningRepository', () {
    late Directory tempDirectory;
    late String databasePath;
    late SqliteLearningRepository repository;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp('recall_test_');
      databasePath = '${tempDirectory.path}/learning.db';
      repository = await SqliteLearningRepository.open(
        factory: databaseFactoryFfi,
        databasePath: databasePath,
      );
    });

    tearDown(() async {
      await repository.close();
      await tempDirectory.delete(recursive: true);
    });

    test(
      'saves and reloads a first-known result with empty later results',
      () async {
        final state = _state(knownWord, [StudyChoice.known]);
        final completedAt = DateTime(2026, 8, 13, 10, 30);

        await repository.saveFirstLayerResults([
          state,
        ], completedAt: completedAt);
        final record = await repository.getRecord(stableWordId(knownWord.word));

        expect(record, isNotNull);
        expect(record!.firstResult, StudyChoice.known);
        expect(record.secondResult, isNull);
        expect(record.thirdResult, isNull);
        expect(record.firstLayerCompletedAt, completedAt);
        expect(record.stage, LearningStage.contextStrengthening);
      },
    );

    test('saves and reloads all three first-layer results exactly', () async {
      final state = _state(learnedWord, [
        StudyChoice.unknown,
        StudyChoice.unsure,
        StudyChoice.known,
      ]);

      await repository.saveFirstLayerResults([
        state,
      ], completedAt: DateTime(2026, 8, 13));
      await repository.close();
      repository = await SqliteLearningRepository.open(
        factory: databaseFactoryFfi,
        databasePath: databasePath,
      );
      final record = await repository.getRecord(stableWordId(learnedWord.word));

      expect(record!.firstResult, StudyChoice.unknown);
      expect(record.secondResult, StudyChoice.unsure);
      expect(record.thirdResult, StudyChoice.known);
    });

    test('persists difficult status after reopening the data layer', () async {
      final state = _state(difficultWord, [
        StudyChoice.unknown,
        StudyChoice.unknown,
        StudyChoice.unknown,
      ]);

      await repository.saveFirstLayerResults([
        state,
      ], completedAt: DateTime(2026, 8, 13));
      await repository.close();
      repository = await SqliteLearningRepository.open(
        factory: databaseFactoryFfi,
        databasePath: databasePath,
      );

      final record = await repository.getRecord(
        stableWordId(difficultWord.word),
      );
      expect(record!.isDifficult, isTrue);
    });

    test('creates one tomorrow task and persists it after reopening', () async {
      final now = DateTime(2026, 8, 13, 22, 15);

      await repository.overrideReviewTaskToTomorrow(learnedWord, now: now);
      await repository.overrideReviewTaskToTomorrow(learnedWord, now: now);
      await repository.close();
      repository = await SqliteLearningRepository.open(
        factory: databaseFactoryFfi,
        databasePath: databasePath,
      );

      final tasks = await repository.getAllReviewTasks();
      final record = await repository.getRecord(stableWordId(learnedWord.word));
      expect(tasks, hasLength(1));
      expect(tasks.single.reviewDate, DateTime(2026, 8, 14));
      expect(record!.nextReviewDate, DateTime(2026, 8, 14));
      expect(record.isWaitingReview, isTrue);
    });

    test(
      'queries tasks due today and overdue but excludes future tasks',
      () async {
        await repository.overrideReviewTaskToTomorrow(
          knownWord,
          now: DateTime(2026, 8, 12),
        );
        await repository.overrideReviewTaskToTomorrow(
          learnedWord,
          now: DateTime(2026, 8, 13),
        );
        await repository.overrideReviewTaskToTomorrow(
          difficultWord,
          now: DateTime(2026, 8, 14),
        );

        final due = await repository.getDueReviewTasks(DateTime(2026, 8, 14));

        expect(due.map((task) => task.word), ['known', 'derive']);
      },
    );

    test('tomorrow calculation crosses month and year boundaries', () async {
      final monthTask = await repository.overrideReviewTaskToTomorrow(
        knownWord,
        now: DateTime(2026, 8, 31, 23, 59),
      );
      final yearTask = await repository.overrideReviewTaskToTomorrow(
        learnedWord,
        now: DateTime(2026, 12, 31, 23, 59),
      );

      expect(monthTask.reviewDate, DateTime(2026, 9, 1));
      expect(yearTask.reviewDate, DateTime(2027, 1, 1));
    });

    test(
      'schedules completed first-layer words as waiting for review',
      () async {
        final state = _state(knownWord, [StudyChoice.known]);
        await repository.saveFirstLayerResults([
          state,
        ], completedAt: DateTime(2026, 8, 13));

        await repository.scheduleFirstReviews({
          stableWordId(knownWord.word): DateTime(2026, 8, 16),
        }, now: DateTime(2026, 8, 13));
        final record = await repository.getRecord(stableWordId(knownWord.word));

        expect(record!.stage, LearningStage.waitingReview);
        expect(record.isWaitingReview, isTrue);
        expect(record.nextReviewDate, DateTime(2026, 8, 16));
        expect(record.reviewIntervalDays, 3);
      },
    );

    test('normal scheduling only moves an unfinished task earlier', () async {
      final state = _state(knownWord, [StudyChoice.known]);
      await repository.saveFirstLayerResults([
        state,
      ], completedAt: DateTime(2026, 8, 13));
      final wordId = stableWordId(knownWord.word);

      await repository.scheduleFirstReviews({
        wordId: DateTime(2026, 8, 16),
      }, now: DateTime(2026, 8, 13));
      await repository.scheduleFirstReviews({
        wordId: DateTime(2026, 8, 18),
      }, now: DateTime(2026, 8, 13));
      expect(
        (await repository.getAllReviewTasks()).single.reviewDate,
        DateTime(2026, 8, 16),
      );

      await repository.scheduleFirstReviews({
        wordId: DateTime(2026, 8, 15),
      }, now: DateTime(2026, 8, 13));
      expect(
        (await repository.getAllReviewTasks()).single.reviewDate,
        DateTime(2026, 8, 15),
      );
      expect((await repository.getAllReviewTasks()), hasLength(1));
      expect(
        (await repository.getRecord(wordId))!.nextReviewDate,
        DateTime(2026, 8, 15),
      );
    });

    test('relearn always overrides an existing task to tomorrow', () async {
      final state = _state(knownWord, [StudyChoice.known]);
      await repository.saveFirstLayerResults([
        state,
      ], completedAt: DateTime(2026, 8, 10));
      final wordId = stableWordId(knownWord.word);
      await repository.scheduleFirstReviews({
        wordId: DateTime(2026, 8, 11),
      }, now: DateTime(2026, 8, 10));

      await repository.overrideReviewTaskToTomorrow(
        knownWord,
        now: DateTime(2026, 8, 13, 23, 59),
      );

      final tasks = await repository.getAllReviewTasks();
      expect(tasks, hasLength(1));
      expect(tasks.single.reviewDate, DateTime(2026, 8, 14));
      expect(
        (await repository.getRecord(wordId))!.nextReviewDate,
        DateTime(2026, 8, 14),
      );
      expect((await repository.getRecord(wordId))!.reviewIntervalDays, 1);
    });

    test('completes a review atomically and stores an attempt', () async {
      final state = _state(knownWord, [StudyChoice.known]);
      await repository.saveFirstLayerResults([
        state,
      ], completedAt: DateTime(2026, 8, 10));
      await repository.scheduleFirstReviews({
        stableWordId(knownWord.word): DateTime(2026, 8, 13),
      }, now: DateTime(2026, 8, 10));
      final task = (await repository.getAllReviewTasks()).single;
      final reviewedAt = DateTime(2026, 8, 13, 21, 30);

      await repository.completeReviewTask(
        reviewTaskId: task.id,
        result: StudyChoice.unknown,
        reactionTimeMs: 3420,
        reviewedAt: reviewedAt,
      );

      final record = await repository.getRecord(stableWordId(knownWord.word));
      final tasks = await repository.getAllReviewTasks();
      final completedTask = tasks.first;
      final nextTask = tasks.last;
      final attempt = (await repository.getAllReviewAttempts()).single;
      expect(record!.stage, LearningStage.waitingReview);
      expect(record.isWaitingReview, isTrue);
      expect(record.nextReviewDate, DateTime(2026, 8, 14));
      expect(record.reviewIntervalDays, 1);
      expect(record.lastReviewDate, reviewedAt);
      expect(record.lastReviewResult, StudyChoice.unknown);
      expect(record.reviewCount, 1);
      expect(record.forgetCount, 1);
      expect(record.recentReactionMilliseconds, 3420);
      expect(record.averageReactionMilliseconds, 3420);
      expect(completedTask.isCompleted, isTrue);
      expect(completedTask.completedAt, reviewedAt);
      expect(nextTask.isCompleted, isFalse);
      expect(nextTask.reviewDate, DateTime(2026, 8, 14));
      expect(attempt.result, StudyChoice.unknown);
      expect(attempt.reactionMilliseconds, 3420);
      expect(attempt.fluency, ReviewFluency.normal);
      expect(attempt.previousIntervalDays, 3);
      expect(attempt.nextIntervalDays, 1);
      expect(attempt.schedulerVersion, ReviewPolicy.schedulerVersion);
      expect(await repository.getDueReviewTasks(reviewedAt), isEmpty);
    });

    test(
      'records overdue days but schedules from the planned interval and actual date',
      () async {
        final state = _state(knownWord, [StudyChoice.known]);
        final wordId = stableWordId(knownWord.word);
        await repository.saveFirstLayerResults([
          state,
        ], completedAt: DateTime(2026, 8, 10));
        await repository.scheduleFirstReviews({
          wordId: DateTime(2026, 8, 13),
        }, now: DateTime(2026, 8, 10));
        final task = (await repository.getAllReviewTasks()).single;

        final attempt = await repository.completeReviewTask(
          reviewTaskId: task.id,
          result: StudyChoice.known,
          reactionTimeMs: 5001,
          reviewedAt: DateTime(2026, 8, 15, 23, 20),
        );

        expect(attempt.fluency, ReviewFluency.slow);
        expect(attempt.previousIntervalDays, 3);
        expect(attempt.actualElapsedDays, 5);
        expect(attempt.overdueDays, 2);
        expect(attempt.scheduledReviewDate, DateTime(2026, 8, 13));
        expect(attempt.actualReviewDate, DateTime(2026, 8, 15));
        expect(attempt.nextIntervalDays, 5);
        expect(attempt.nextReviewDate, DateTime(2026, 8, 20));
        final record = await repository.getRecord(wordId);
        expect(record!.reviewIntervalDays, 5);
        expect(record.nextReviewDate, DateTime(2026, 8, 20));
      },
    );

    test('rejects duplicate completion without changing aggregates', () async {
      final state = _state(knownWord, [StudyChoice.known]);
      await repository.saveFirstLayerResults([
        state,
      ], completedAt: DateTime(2026, 8, 10));
      await repository.scheduleFirstReviews({
        stableWordId(knownWord.word): DateTime(2026, 8, 13),
      }, now: DateTime(2026, 8, 10));
      final task = (await repository.getAllReviewTasks()).single;
      await repository.completeReviewTask(
        reviewTaskId: task.id,
        result: StudyChoice.known,
        reactionTimeMs: 3000,
        reviewedAt: DateTime(2026, 8, 13),
      );

      await expectLater(
        repository.completeReviewTask(
          reviewTaskId: task.id,
          result: StudyChoice.unknown,
          reactionTimeMs: 9000,
          reviewedAt: DateTime(2026, 8, 14),
        ),
        throwsStateError,
      );
      final record = await repository.getRecord(stableWordId(knownWord.word));
      expect(record!.reviewCount, 1);
      expect(record.forgetCount, 0);
      expect(await repository.getAllReviewAttempts(), hasLength(1));
    });

    test('rolls back every write when creating the next task fails', () async {
      final state = _state(knownWord, [StudyChoice.known]);
      final wordId = stableWordId(knownWord.word);
      await repository.saveFirstLayerResults([
        state,
      ], completedAt: DateTime(2026, 8, 10));
      await repository.scheduleFirstReviews({
        wordId: DateTime(2026, 8, 13),
      }, now: DateTime(2026, 8, 10));
      final task = (await repository.getAllReviewTasks()).single;
      await repository.close();
      final rawDatabase = await databaseFactoryFfi.openDatabase(databasePath);
      await rawDatabase.execute('''
        CREATE TRIGGER reject_dynamic_next_task
        BEFORE INSERT ON review_tasks
        BEGIN
          SELECT RAISE(ABORT, 'forced next-task failure');
        END
      ''');
      await rawDatabase.close();
      repository = await SqliteLearningRepository.open(
        factory: databaseFactoryFfi,
        databasePath: databasePath,
      );

      await expectLater(
        repository.completeReviewTask(
          reviewTaskId: task.id,
          result: StudyChoice.known,
          reactionTimeMs: 3000,
          reviewedAt: DateTime(2026, 8, 13, 10),
        ),
        throwsA(isA<DatabaseException>()),
      );

      final record = await repository.getRecord(wordId);
      final tasks = await repository.getAllReviewTasks();
      expect(record!.reviewCount, 0);
      expect(record.lastReviewDate, isNull);
      expect(record.reviewIntervalDays, 3);
      expect(await repository.getAllReviewAttempts(), isEmpty);
      expect(tasks, hasLength(1));
      expect(tasks.single.isCompleted, isFalse);
      expect(tasks.single.completedAt, isNull);
    });

    test('calculates cumulative average across review history', () async {
      final state = _state(knownWord, [StudyChoice.known]);
      await repository.saveFirstLayerResults([
        state,
      ], completedAt: DateTime(2026, 8, 10));
      final wordId = stableWordId(knownWord.word);
      await repository.scheduleFirstReviews({
        wordId: DateTime(2026, 8, 13),
      }, now: DateTime(2026, 8, 10));
      var task = (await repository.getAllReviewTasks()).single;
      await repository.completeReviewTask(
        reviewTaskId: task.id,
        result: StudyChoice.known,
        reactionTimeMs: 3000,
        reviewedAt: DateTime(2026, 8, 13),
      );
      await repository.overrideReviewTaskToTomorrow(
        knownWord,
        now: DateTime(2026, 8, 13),
      );
      task = (await repository.getAllReviewTasks()).last;
      await repository.completeReviewTask(
        reviewTaskId: task.id,
        result: StudyChoice.unsure,
        reactionTimeMs: 6000,
        reviewedAt: DateTime(2026, 8, 14),
      );

      final record = await repository.getRecord(wordId);
      expect(record!.reviewCount, 2);
      expect(record.averageReactionMilliseconds, 4500);
      expect(record.recentReactionMilliseconds, 6000);
      expect(await repository.getAllReviewAttempts(), hasLength(2));
      expect(await repository.getAllReviewTasks(), hasLength(3));
    });

    test(
      'migrates V3 attempts and bridges records awaiting scheduling',
      () async {
        await repository.close();
        await databaseFactoryFfi.deleteDatabase(databasePath);
        final legacyDatabase = await databaseFactoryFfi.openDatabase(
          databasePath,
          options: OpenDatabaseOptions(
            version: 3,
            onCreate: (database, version) async {
              await database.execute('''
              CREATE TABLE learning_records (
                word_id TEXT PRIMARY KEY,
                word TEXT NOT NULL,
                stage TEXT NOT NULL,
                first_result TEXT,
                second_result TEXT,
                third_result TEXT,
                is_difficult INTEGER NOT NULL DEFAULT 0,
                first_layer_completed_at TEXT,
                is_waiting_review INTEGER NOT NULL DEFAULT 0,
                next_review_date TEXT,
                last_review_date TEXT,
                review_interval_days INTEGER,
                review_count INTEGER NOT NULL DEFAULT 0,
                forget_count INTEGER NOT NULL DEFAULT 0,
                recent_reaction_ms INTEGER,
                average_reaction_ms REAL,
                last_review_result TEXT
              )
            ''');
              await database.execute('''
              CREATE TABLE review_tasks (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                word_id TEXT NOT NULL,
                word TEXT NOT NULL,
                review_date TEXT NOT NULL,
                is_completed INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL,
                completed_at TEXT
              )
            ''');
              await database.execute('''
              CREATE UNIQUE INDEX review_tasks_one_unfinished_per_word
              ON review_tasks(word_id) WHERE is_completed = 0
            ''');
              await database.execute('''
              CREATE TABLE review_attempts (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                word_id TEXT NOT NULL,
                review_task_id INTEGER NOT NULL UNIQUE,
                reviewed_at TEXT NOT NULL,
                result TEXT NOT NULL,
                reaction_ms INTEGER NOT NULL CHECK(reaction_ms >= 0)
              )
            ''');
            },
          ),
        );
        await legacyDatabase.insert('learning_records', {
          'word_id': stableWordId(knownWord.word),
          'word': knownWord.word,
          'stage': LearningStage.reviewedAwaitingSchedule.name,
          'first_result': StudyChoice.known.name,
          'first_layer_completed_at': DateTime(2026, 8, 10).toIso8601String(),
          'is_waiting_review': 0,
          'next_review_date': null,
          'last_review_date': DateTime(2026, 8, 14, 12).toIso8601String(),
          'review_interval_days': 3,
          'review_count': 1,
          'forget_count': 0,
          'recent_reaction_ms': 6001,
          'average_reaction_ms': 6001.0,
          'last_review_result': StudyChoice.known.name,
        });
        final legacyTaskId = await legacyDatabase.insert('review_tasks', {
          'word_id': stableWordId(knownWord.word),
          'word': knownWord.word,
          'review_date': '2026-08-13',
          'is_completed': 1,
          'created_at': DateTime(2026, 8, 10).toIso8601String(),
          'completed_at': DateTime(2026, 8, 14, 12).toIso8601String(),
        });
        await legacyDatabase.insert('review_attempts', {
          'word_id': stableWordId(knownWord.word),
          'review_task_id': legacyTaskId,
          'reviewed_at': DateTime(2026, 8, 14, 12).toIso8601String(),
          'result': StudyChoice.known.name,
          'reaction_ms': 6001,
        });
        await legacyDatabase.insert('learning_records', {
          'word_id': stableWordId(difficultWord.word),
          'word': difficultWord.word,
          'stage': LearningStage.waitingReview.name,
          'first_result': StudyChoice.known.name,
          'first_layer_completed_at': DateTime(
            2026,
            8,
            13,
            22,
          ).toIso8601String(),
          'is_waiting_review': 1,
          'next_review_date': '2026-08-16',
          'review_interval_days': null,
        });
        await legacyDatabase.insert('review_tasks', {
          'word_id': stableWordId(difficultWord.word),
          'word': difficultWord.word,
          'review_date': '2026-08-16',
          'is_completed': 0,
          'created_at': DateTime(2026, 8, 13, 22).toIso8601String(),
        });
        await legacyDatabase.close();

        repository = await SqliteLearningRepository.open(
          factory: databaseFactoryFfi,
          databasePath: databasePath,
        );

        final attempt = (await repository.getAllReviewAttempts()).single;
        expect(attempt.fluency, ReviewFluency.slow);
        expect(attempt.scheduledReviewDate, DateTime(2026, 8, 13));
        expect(attempt.actualReviewDate, DateTime(2026, 8, 14));
        expect(attempt.overdueDays, 1);
        expect(attempt.schedulerVersion, ReviewPolicy.legacySchedulerVersion);
        expect(attempt.previousIntervalDays, isNull);
        expect(attempt.nextIntervalDays, isNull);

        final record = await repository.getRecord(stableWordId(knownWord.word));
        expect(record!.stage, LearningStage.waitingReview);
        expect(record.isWaitingReview, isTrue);
        expect(record.reviewIntervalDays, 5);
        expect(record.nextReviewDate, DateTime(2026, 8, 19));
        final backfilledRecord = await repository.getRecord(
          stableWordId(difficultWord.word),
        );
        expect(backfilledRecord!.reviewIntervalDays, 3);
        final tasks = await repository.getAllReviewTasks();
        expect(tasks, hasLength(3));
        expect(tasks.where((task) => !task.isCompleted), hasLength(2));
        expect(
          tasks
              .singleWhere(
                (task) =>
                    task.wordId == stableWordId(knownWord.word) &&
                    !task.isCompleted,
              )
              .reviewDate,
          DateTime(2026, 8, 19),
        );

        await repository.close();
        repository = await SqliteLearningRepository.open(
          factory: databaseFactoryFfi,
          databasePath: databasePath,
        );
        expect(
          (await repository.getAllReviewTasks()).where(
            (task) => !task.isCompleted,
          ),
          hasLength(2),
        );
      },
    );
  });
}

FirstLayerWordState _state(Word word, List<StudyChoice> choices) {
  final state = FirstLayerWordState(word: word);
  for (final choice in choices) {
    state.recordJudgment(choice);
  }
  return state;
}
