import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/first_layer_word_state.dart';
import '../models/context_article.dart';
import '../models/daily_new_word_task.dart';
import '../models/learning_record.dart';
import '../models/word.dart';
import '../review/review_scheduler.dart';
import 'daily_task_repository.dart';
import 'learning_repository.dart';

class SqliteLearningRepository implements LearningRepository {
  SqliteLearningRepository._(this._database, this._scheduler);

  static const databaseFileName = 'recall_learning.db';
  static const databaseVersion = 6;

  final Database _database;
  final ReviewScheduler _scheduler;

  static Future<SqliteLearningRepository> open({
    DatabaseFactory? factory,
    String? databasePath,
  }) async {
    final selectedFactory = factory ?? databaseFactory;
    final path =
        databasePath ?? p.join(await getDatabasesPath(), databaseFileName);
    final database = await selectedFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: databaseVersion,
        onConfigure: (database) async {
          await database.execute('PRAGMA foreign_keys = ON');
        },
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
              average_reaction_ms REAL
              ,last_review_result TEXT
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
              completed_at TEXT,
              FOREIGN KEY(word_id) REFERENCES learning_records(word_id)
            )
          ''');
          await database.execute('''
            CREATE INDEX review_tasks_due_index
            ON review_tasks(is_completed, review_date)
          ''');
          await database.execute('''
            CREATE UNIQUE INDEX review_tasks_one_unfinished_per_word
            ON review_tasks(word_id)
            WHERE is_completed = 0
          ''');
          await _createReviewAttemptsTable(database);
          await _createDailyTaskTables(database);
          await _createContextArticlesTable(database);
        },
        onUpgrade: (database, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            // Rebuild the V1 table to remove UNIQUE(word_id, review_date).
            // Completed history and the current unfinished task are separate
            // concepts and are allowed to share a date.
            await database.execute(
              'DROP INDEX IF EXISTS review_tasks_due_index',
            );
            await database.execute('''
              CREATE TABLE review_tasks_v2 (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                word_id TEXT NOT NULL,
                word TEXT NOT NULL,
                review_date TEXT NOT NULL,
                is_completed INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL,
                FOREIGN KEY(word_id) REFERENCES learning_records(word_id)
              )
            ''');
            await database.execute('''
              INSERT INTO review_tasks_v2 (
                id, word_id, word, review_date, is_completed, created_at
              )
              SELECT id, word_id, word, review_date, is_completed, created_at
              FROM review_tasks
            ''');
            await database.execute('DROP TABLE review_tasks');
            await database.execute(
              'ALTER TABLE review_tasks_v2 RENAME TO review_tasks',
            );

            // V1 allowed multiple unfinished dates. Keep the earliest task.
            await database.execute('''
              DELETE FROM review_tasks
              WHERE is_completed = 0
                AND id NOT IN (
                  SELECT MIN(candidate.id)
                  FROM review_tasks AS candidate
                  WHERE candidate.is_completed = 0
                    AND candidate.review_date = (
                      SELECT MIN(earliest.review_date)
                      FROM review_tasks AS earliest
                      WHERE earliest.word_id = candidate.word_id
                        AND earliest.is_completed = 0
                    )
                  GROUP BY candidate.word_id
                )
            ''');
            await database.execute('''
              CREATE INDEX review_tasks_due_index
              ON review_tasks(is_completed, review_date)
            ''');
            await database.execute('''
              CREATE UNIQUE INDEX review_tasks_one_unfinished_per_word
              ON review_tasks(word_id)
              WHERE is_completed = 0
            ''');
            await database.execute('''
              UPDATE learning_records
              SET next_review_date = (
                SELECT task.review_date
                FROM review_tasks AS task
                WHERE task.word_id = learning_records.word_id
                  AND task.is_completed = 0
                LIMIT 1
              )
              WHERE EXISTS (
                SELECT 1
                FROM review_tasks AS task
                WHERE task.word_id = learning_records.word_id
                  AND task.is_completed = 0
              )
            ''');
          }
          if (oldVersion < 3) {
            await database.execute(
              'ALTER TABLE learning_records ADD COLUMN last_review_result TEXT',
            );
            await database.execute(
              'ALTER TABLE review_tasks ADD COLUMN completed_at TEXT',
            );
            await _createReviewAttemptsTable(database);
          }
          if (oldVersion >= 3 && oldVersion < 4) {
            for (final definition in const [
              'fluency TEXT',
              'previous_interval_days INTEGER',
              'actual_elapsed_days INTEGER',
              'next_interval_days INTEGER',
              'scheduled_review_date TEXT',
              'actual_review_date TEXT',
              'next_review_date TEXT',
              'overdue_days INTEGER',
              'scheduler_version TEXT',
            ]) {
              await database.execute(
                'ALTER TABLE review_attempts ADD COLUMN $definition',
              );
            }
            await database.execute('''
              UPDATE review_attempts
              SET fluency = CASE
                    WHEN reaction_ms <= ${ReviewPolicy.slowThresholdMilliseconds}
                    THEN '${ReviewFluency.normal.name}'
                    ELSE '${ReviewFluency.slow.name}'
                  END,
                  scheduled_review_date = (
                    SELECT review_date FROM review_tasks
                    WHERE id = review_attempts.review_task_id
                  ),
                  actual_review_date = substr(reviewed_at, 1, 10),
                  overdue_days = MAX(0, CAST(
                    julianday(substr(reviewed_at, 1, 10)) - julianday((
                      SELECT review_date FROM review_tasks
                      WHERE id = review_attempts.review_task_id
                    )) AS INTEGER
                  )),
                  scheduler_version = '${ReviewPolicy.legacySchedulerVersion}'
            ''');
          }
          if (oldVersion < 5) {
            await _createDailyTaskTables(database);
          }
          if (oldVersion < 6) {
            await _createContextArticlesTable(database);
          }
        },
      ),
    );
    final repository = SqliteLearningRepository._(
      database,
      const ReviewScheduler(),
    );
    await repository._backfillMissingReviewIntervals();
    await repository._bridgeLegacyReviewedRecords();
    return repository;
  }

  Future<void> close() => _database.close();

  static Future<void> _createReviewAttemptsTable(
    DatabaseExecutor database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS review_attempts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word_id TEXT NOT NULL,
        review_task_id INTEGER NOT NULL UNIQUE,
        reviewed_at TEXT NOT NULL,
        result TEXT NOT NULL,
        reaction_ms INTEGER NOT NULL CHECK(reaction_ms >= 0),
        fluency TEXT,
        previous_interval_days INTEGER,
        actual_elapsed_days INTEGER,
        next_interval_days INTEGER,
        scheduled_review_date TEXT,
        actual_review_date TEXT,
        next_review_date TEXT,
        overdue_days INTEGER,
        scheduler_version TEXT,
        FOREIGN KEY(word_id) REFERENCES learning_records(word_id),
        FOREIGN KEY(review_task_id) REFERENCES review_tasks(id)
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS review_attempts_word_index
      ON review_attempts(word_id, reviewed_at)
    ''');
  }

  static Future<void> _createDailyTaskTables(DatabaseExecutor database) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS vocabulary_settings (
        id INTEGER PRIMARY KEY CHECK(id = 1),
        daily_new_word_target INTEGER NOT NULL
          CHECK(daily_new_word_target BETWEEN
            ${VocabularySettingsDefaults.minimumDailyNewWordTarget} AND
            ${VocabularySettingsDefaults.maximumDailyNewWordTarget})
      )
    ''');
    await database.rawInsert(
      '''
      INSERT OR IGNORE INTO vocabulary_settings (id, daily_new_word_target)
      VALUES (1, ?)
      ''',
      [VocabularySettingsDefaults.dailyNewWordTarget],
    );
    await database.execute('''
      CREATE TABLE IF NOT EXISTS daily_task_batches (
        task_date TEXT PRIMARY KEY,
        target_count INTEGER NOT NULL CHECK(target_count >= 0),
        created_at TEXT NOT NULL
      )
    ''');
    await database.execute('''
      CREATE TABLE IF NOT EXISTS daily_new_word_tasks (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_date TEXT NOT NULL,
        word_id TEXT NOT NULL UNIQUE,
        first_layer_completed INTEGER NOT NULL DEFAULT 0,
        is_completed INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        first_layer_completed_at TEXT,
        completed_at TEXT,
        CHECK(is_completed = 0 OR first_layer_completed = 1),
        FOREIGN KEY(task_date) REFERENCES daily_task_batches(task_date)
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS daily_new_word_tasks_pending_index
      ON daily_new_word_tasks(is_completed, task_date, id)
    ''');
  }

  static Future<void> _createContextArticlesTable(
    DatabaseExecutor database,
  ) async {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS context_articles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        context_session_id TEXT NOT NULL UNIQUE,
        request_id TEXT NOT NULL,
        title TEXT NOT NULL,
        article_text TEXT NOT NULL,
        source_word_ids_json TEXT NOT NULL,
        used_word_ids_json TEXT NOT NULL,
        provider TEXT NOT NULL,
        model TEXT NOT NULL,
        prompt_version TEXT NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('success', 'failed', 'skipped')),
        generated_at TEXT NOT NULL,
        error_code TEXT
      )
    ''');
    await database.execute('''
      CREATE INDEX IF NOT EXISTS context_articles_status_index
      ON context_articles(status, generated_at)
    ''');
  }

  Future<void> _backfillMissingReviewIntervals() async {
    await _database.rawUpdate('''
      UPDATE learning_records
      SET review_interval_days = COALESCE((
        SELECT MAX(1, MIN(${ReviewPolicy.maximumIntervalDays}, CAST(
          julianday(pending.review_date) - julianday(substr(
            COALESCE(
              learning_records.last_review_date,
              learning_records.first_layer_completed_at
            ),
            1,
            10
          )) AS INTEGER
        )))
        FROM review_tasks AS pending
        WHERE pending.word_id = learning_records.word_id
          AND pending.is_completed = 0
        LIMIT 1
      ), 1)
      WHERE (review_interval_days IS NULL OR review_interval_days <= 0)
        AND EXISTS (
          SELECT 1 FROM review_tasks AS pending
          WHERE pending.word_id = learning_records.word_id
            AND pending.is_completed = 0
        )
    ''');
  }

  Future<void> _bridgeLegacyReviewedRecords() async {
    await _database.transaction((transaction) async {
      final rows = await transaction.rawQuery(
        '''
        SELECT l.*, a.result AS attempt_result,
          a.reaction_ms AS attempt_reaction_ms,
          a.reviewed_at AS attempt_reviewed_at,
          t.review_date AS completed_task_review_date
        FROM learning_records AS l
        JOIN review_attempts AS a ON a.id = (
          SELECT MAX(latest.id) FROM review_attempts AS latest
          WHERE latest.word_id = l.word_id
        )
        JOIN review_tasks AS t ON t.id = a.review_task_id
        WHERE l.stage = ?
          AND NOT EXISTS (
            SELECT 1 FROM review_tasks AS pending
            WHERE pending.word_id = l.word_id
              AND pending.is_completed = 0
          )
      ''',
        [LearningStage.reviewedAwaitingSchedule.name],
      );
      for (final row in rows) {
        final reviewedAt = DateTime.parse(
          row['attempt_reviewed_at']! as String,
        );
        final taskDate = DateTime.parse(
          row['completed_task_review_date']! as String,
        );
        final currentInterval = _currentIntervalFromRow(row, taskDate);
        final decision = _scheduler.schedule(
          currentIntervalDays: currentInterval,
          result: StudyChoice.values.byName(row['attempt_result']! as String),
          reactionTimeMs: row['attempt_reaction_ms']! as int,
          reviewedAt: reviewedAt,
        );
        final nextDateText = _dateToText(decision.nextReviewDate);
        await transaction.insert('review_tasks', {
          'word_id': row['word_id'],
          'word': row['word'],
          'review_date': nextDateText,
          'is_completed': 0,
          'created_at': reviewedAt.toIso8601String(),
        });
        await transaction.update(
          'learning_records',
          {
            'stage': LearningStage.waitingReview.name,
            'is_waiting_review': 1,
            'next_review_date': nextDateText,
            'review_interval_days': decision.nextIntervalDays,
          },
          where: 'word_id = ?',
          whereArgs: [row['word_id']],
        );
      }
    });
  }

  @override
  Future<void> saveFirstLayerResults(
    List<FirstLayerWordState> states, {
    required DateTime completedAt,
  }) async {
    await _database.transaction((transaction) async {
      for (final state in states) {
        await transaction.rawInsert(
          '''
          INSERT INTO learning_records (
            word_id, word, stage, first_result, second_result, third_result,
            is_difficult, first_layer_completed_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(word_id) DO UPDATE SET
            word = excluded.word,
            stage = excluded.stage,
            first_result = excluded.first_result,
            second_result = excluded.second_result,
            third_result = excluded.third_result,
            is_difficult = excluded.is_difficult,
            first_layer_completed_at = excluded.first_layer_completed_at
          ''',
          [
            state.word.id,
            state.word.word,
            LearningStage.contextStrengthening.name,
            state.firstJudgment?.name,
            state.secondJudgment?.name,
            state.thirdJudgment?.name,
            state.isDifficult ? 1 : 0,
            completedAt.toIso8601String(),
          ],
        );
        await transaction.update(
          'daily_new_word_tasks',
          {
            'first_layer_completed': 1,
            'first_layer_completed_at': completedAt.toIso8601String(),
          },
          where: 'word_id = ? AND first_layer_completed = 0',
          whereArgs: [state.word.id],
        );
      }
    });
  }

  @override
  Future<void> scheduleFirstReviews(
    Map<String, DateTime> datesByWordId, {
    required DateTime now,
  }) async {
    await _database.transaction((transaction) async {
      for (final entry in datesByWordId.entries) {
        final requestedDate = localDateOnly(entry.value);
        final requestedDateText = _dateToText(requestedDate);
        final recordRows = await transaction.query(
          'learning_records',
          columns: ['word', 'first_layer_completed_at'],
          where: 'word_id = ?',
          whereArgs: [entry.key],
          limit: 1,
        );
        if (recordRows.isEmpty) {
          throw StateError('${entry.key} has no learning record.');
        }
        final word = recordRows.single['word']! as String;
        final taskRows = await transaction.query(
          'review_tasks',
          where: 'word_id = ? AND is_completed = 0',
          whereArgs: [entry.key],
          limit: 1,
        );

        var effectiveDateText = requestedDateText;
        if (taskRows.isEmpty) {
          await transaction.insert('review_tasks', {
            'word_id': entry.key,
            'word': word,
            'review_date': requestedDateText,
            'is_completed': 0,
            'created_at': now.toIso8601String(),
          });
        } else {
          final existingDateText = taskRows.single['review_date']! as String;
          if (requestedDateText.compareTo(existingDateText) < 0) {
            await transaction.update(
              'review_tasks',
              {'word': word, 'review_date': requestedDateText},
              where: 'id = ?',
              whereArgs: [taskRows.single['id']],
            );
          } else {
            effectiveDateText = existingDateText;
          }
        }

        await transaction.update(
          'learning_records',
          {
            'stage': LearningStage.waitingReview.name,
            'is_waiting_review': 1,
            'next_review_date': effectiveDateText,
            'review_interval_days': _calendarDayDifference(
              _dateTimeFromText(
                    recordRows.single['first_layer_completed_at'] as String?,
                  ) ??
                  now,
              DateTime.parse(effectiveDateText),
            ).clamp(1, ReviewPolicy.maximumIntervalDays),
          },
          where: 'word_id = ?',
          whereArgs: [entry.key],
        );
      }
    });
  }

  @override
  Future<ReviewTask> overrideReviewTaskToTomorrow(
    Word word, {
    required DateTime now,
  }) async {
    final wordId = word.id;
    final reviewDate = nextLocalDate(now);
    final reviewDateText = _dateToText(reviewDate);

    return _database.transaction((transaction) async {
      await transaction.rawInsert(
        '''
        INSERT INTO learning_records (
          word_id, word, stage, is_waiting_review, next_review_date,
          review_interval_days
        ) VALUES (?, ?, ?, 1, ?, 1)
        ON CONFLICT(word_id) DO UPDATE SET
          word = excluded.word,
          stage = excluded.stage,
          is_waiting_review = 1,
          next_review_date = excluded.next_review_date,
          review_interval_days = 1
        ''',
        [wordId, word.word, LearningStage.waitingReview.name, reviewDateText],
      );

      final existingRows = await transaction.query(
        'review_tasks',
        where: 'word_id = ? AND is_completed = 0',
        whereArgs: [wordId],
        limit: 1,
      );
      if (existingRows.isEmpty) {
        await transaction.insert('review_tasks', {
          'word_id': wordId,
          'word': word.word,
          'review_date': reviewDateText,
          'is_completed': 0,
          'created_at': now.toIso8601String(),
        });
      } else {
        await transaction.update(
          'review_tasks',
          {'word': word.word, 'review_date': reviewDateText},
          where: 'id = ?',
          whereArgs: [existingRows.single['id']],
        );
      }

      final rows = await transaction.query(
        'review_tasks',
        where: 'word_id = ? AND is_completed = 0',
        whereArgs: [wordId],
        limit: 1,
      );
      return _reviewTaskFromMap(rows.single);
    });
  }

  @override
  Future<bool> hasReviewTask(Word word, DateTime reviewDate) async {
    final rows = await _database.query(
      'review_tasks',
      columns: ['id'],
      where: 'word_id = ? AND review_date = ?',
      whereArgs: [word.id, _dateToText(reviewDate)],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  @override
  Future<LearningRecord?> getRecord(String wordId) async {
    final rows = await _database.query(
      'learning_records',
      where: 'word_id = ?',
      whereArgs: [wordId],
      limit: 1,
    );
    return rows.isEmpty ? null : _recordFromMap(rows.single);
  }

  @override
  Future<List<LearningRecord>> getAllRecords() async {
    final rows = await _database.query('learning_records', orderBy: 'word');
    return rows.map(_recordFromMap).toList(growable: false);
  }

  @override
  Future<List<ReviewTask>> getDueReviewTasks(DateTime today) async {
    final rows = await _database.query(
      'review_tasks',
      where: 'is_completed = 0 AND review_date <= ?',
      whereArgs: [_dateToText(localDateOnly(today))],
      orderBy: 'review_date, id',
    );
    return rows.map(_reviewTaskFromMap).toList(growable: false);
  }

  @override
  Future<List<ReviewTask>> getAllReviewTasks() async {
    final rows = await _database.query(
      'review_tasks',
      orderBy: 'review_date, id',
    );
    return rows.map(_reviewTaskFromMap).toList(growable: false);
  }

  @override
  Future<ReviewAttempt> completeReviewTask({
    required int reviewTaskId,
    required StudyChoice result,
    required int reactionTimeMs,
    required DateTime reviewedAt,
  }) async {
    if (reactionTimeMs < 0) {
      throw ArgumentError.value(reactionTimeMs, 'reactionTimeMs');
    }

    return _database.transaction((transaction) async {
      final taskRows = await transaction.query(
        'review_tasks',
        where: 'id = ? AND is_completed = 0',
        whereArgs: [reviewTaskId],
        limit: 1,
      );
      if (taskRows.isEmpty) {
        throw StateError('Review task $reviewTaskId is already completed.');
      }
      final wordId = taskRows.single['word_id']! as String;
      final recordRows = await transaction.query(
        'learning_records',
        where: 'word_id = ?',
        whereArgs: [wordId],
        limit: 1,
      );
      if (recordRows.isEmpty) {
        throw StateError('$wordId has no learning record.');
      }
      final recordRow = recordRows.single;
      final oldCount = recordRow['review_count']! as int;
      final oldAverage = (recordRow['average_reaction_ms'] as num?)?.toDouble();
      if (oldCount > 0 && oldAverage == null) {
        throw StateError('$wordId has an invalid reaction-time summary.');
      }
      final newAverage = oldCount == 0
          ? reactionTimeMs.toDouble()
          : (oldAverage! * oldCount + reactionTimeMs) / (oldCount + 1);
      final scheduledDate = DateTime.parse(
        taskRows.single['review_date']! as String,
      );
      final actualDate = localDateOnly(reviewedAt);
      final currentInterval = _currentIntervalFromRow(recordRow, scheduledDate);
      final decision = _scheduler.schedule(
        currentIntervalDays: currentInterval,
        result: result,
        reactionTimeMs: reactionTimeMs,
        reviewedAt: reviewedAt,
      );
      final baseline =
          _dateTimeFromText(recordRow['last_review_date'] as String?) ??
          _dateTimeFromText(recordRow['first_layer_completed_at'] as String?) ??
          scheduledDate.subtract(Duration(days: currentInterval));
      final actualElapsedDays = _calendarDayDifference(
        baseline,
        actualDate,
      ).clamp(0, 1000000);
      final overdueDays = _calendarDayDifference(
        scheduledDate,
        actualDate,
      ).clamp(0, 1000000);
      final nextDateText = _dateToText(decision.nextReviewDate);

      final attemptId = await transaction.insert('review_attempts', {
        'word_id': wordId,
        'review_task_id': reviewTaskId,
        'reviewed_at': reviewedAt.toIso8601String(),
        'result': result.name,
        'reaction_ms': reactionTimeMs,
        'fluency': decision.fluency.name,
        'previous_interval_days': decision.previousIntervalDays,
        'actual_elapsed_days': actualElapsedDays,
        'next_interval_days': decision.nextIntervalDays,
        'scheduled_review_date': _dateToText(scheduledDate),
        'actual_review_date': _dateToText(actualDate),
        'next_review_date': nextDateText,
        'overdue_days': overdueDays,
        'scheduler_version': decision.schedulerVersion,
      });
      final recordCount = await transaction.update(
        'learning_records',
        {
          'stage': LearningStage.waitingReview.name,
          'is_waiting_review': 1,
          'next_review_date': nextDateText,
          'review_interval_days': decision.nextIntervalDays,
          'last_review_date': reviewedAt.toIso8601String(),
          'last_review_result': result.name,
          'review_count': oldCount + 1,
          'forget_count':
              (recordRow['forget_count']! as int) +
              (result == StudyChoice.unknown ? 1 : 0),
          'recent_reaction_ms': reactionTimeMs,
          'average_reaction_ms': newAverage,
        },
        where: 'word_id = ?',
        whereArgs: [wordId],
      );
      final taskCount = await transaction.update(
        'review_tasks',
        {'is_completed': 1, 'completed_at': reviewedAt.toIso8601String()},
        where: 'id = ? AND is_completed = 0',
        whereArgs: [reviewTaskId],
      );
      if (recordCount != 1 || taskCount != 1) {
        throw StateError('Review task $reviewTaskId could not be completed.');
      }
      await transaction.insert('review_tasks', {
        'word_id': wordId,
        'word': taskRows.single['word'],
        'review_date': nextDateText,
        'is_completed': 0,
        'created_at': reviewedAt.toIso8601String(),
      });
      return ReviewAttempt(
        id: attemptId,
        wordId: wordId,
        reviewTaskId: reviewTaskId,
        reviewedAt: reviewedAt,
        result: result,
        reactionMilliseconds: reactionTimeMs,
        fluency: decision.fluency,
        previousIntervalDays: decision.previousIntervalDays,
        actualElapsedDays: actualElapsedDays,
        nextIntervalDays: decision.nextIntervalDays,
        scheduledReviewDate: scheduledDate,
        actualReviewDate: actualDate,
        nextReviewDate: decision.nextReviewDate,
        overdueDays: overdueDays,
        schedulerVersion: decision.schedulerVersion,
      );
    });
  }

  @override
  Future<List<ReviewAttempt>> getAllReviewAttempts() async {
    final rows = await _database.query(
      'review_attempts',
      orderBy: 'reviewed_at, id',
    );
    return rows.map(_reviewAttemptFromMap).toList(growable: false);
  }

  @override
  Future<ContextArticle?> getSuccessfulContextArticle(
    String contextSessionId,
  ) async {
    final rows = await _database.query(
      'context_articles',
      where: 'context_session_id = ? AND status = ?',
      whereArgs: [contextSessionId, ContextArticleStatus.success.name],
      limit: 1,
    );
    return rows.isEmpty ? null : _contextArticleFromMap(rows.single);
  }

  @override
  Future<void> upsertContextArticle(ContextArticle article) async {
    await _database.transaction((transaction) async {
      final successful = await transaction.query(
        'context_articles',
        columns: ['id'],
        where: 'context_session_id = ? AND status = ?',
        whereArgs: [
          article.contextSessionId,
          ContextArticleStatus.success.name,
        ],
        limit: 1,
      );
      if (successful.isNotEmpty) return;
      await transaction.rawInsert(
        '''
        INSERT INTO context_articles (
          context_session_id, request_id, title, article_text,
          source_word_ids_json, used_word_ids_json, provider, model,
          prompt_version, status, generated_at, error_code
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(context_session_id) DO UPDATE SET
          request_id = excluded.request_id,
          title = excluded.title,
          article_text = excluded.article_text,
          source_word_ids_json = excluded.source_word_ids_json,
          used_word_ids_json = excluded.used_word_ids_json,
          provider = excluded.provider,
          model = excluded.model,
          prompt_version = excluded.prompt_version,
          status = excluded.status,
          generated_at = excluded.generated_at,
          error_code = excluded.error_code
        ''',
        [
          article.contextSessionId,
          article.requestId,
          article.title,
          article.articleText,
          jsonEncode(article.sourceWordIds),
          jsonEncode(article.usedWordIds),
          article.provider,
          article.model,
          article.promptVersion,
          article.status.name,
          article.generatedAt.toIso8601String(),
          article.errorCode,
        ],
      );
    });
  }

  @override
  Future<void> deleteContextArticle(String contextSessionId) async {
    await _database.delete(
      'context_articles',
      where: 'context_session_id = ?',
      whereArgs: [contextSessionId],
    );
  }

  @override
  Future<List<ContextArticle>> getAllContextArticles() async {
    final rows = await _database.query('context_articles', orderBy: 'id ASC');
    return rows.map(_contextArticleFromMap).toList(growable: false);
  }

  @override
  Future<int> getDailyNewWordTarget() async {
    final rows = await _database.query(
      'vocabulary_settings',
      columns: ['daily_new_word_target'],
      where: 'id = 1',
      limit: 1,
    );
    return rows.single['daily_new_word_target']! as int;
  }

  @override
  Future<void> setDailyNewWordTarget(int target) async {
    if (target < VocabularySettingsDefaults.minimumDailyNewWordTarget ||
        target > VocabularySettingsDefaults.maximumDailyNewWordTarget) {
      throw ArgumentError.value(target, 'target');
    }
    await _database.update('vocabulary_settings', {
      'daily_new_word_target': target,
    }, where: 'id = 1');
  }

  @override
  Future<DailyTaskBatch?> getDailyTaskBatch(DateTime date) async {
    final rows = await _database.query(
      'daily_task_batches',
      where: 'task_date = ?',
      whereArgs: [_dateToText(localDateOnly(date))],
      limit: 1,
    );
    return rows.isEmpty ? null : _dailyTaskBatchFromMap(rows.single);
  }

  @override
  Future<DailyTaskBatch> createDailyTaskBatch({
    required DateTime date,
    required int targetCount,
    required List<String> candidateWordIds,
    required DateTime createdAt,
  }) async {
    final taskDate = localDateOnly(date);
    final taskDateText = _dateToText(taskDate);
    return _database.transaction((transaction) async {
      final existing = await transaction.query(
        'daily_task_batches',
        where: 'task_date = ?',
        whereArgs: [taskDateText],
        limit: 1,
      );
      if (existing.isNotEmpty) {
        return _dailyTaskBatchFromMap(existing.single);
      }
      await transaction.insert('daily_task_batches', {
        'task_date': taskDateText,
        'target_count': targetCount,
        'created_at': createdAt.toIso8601String(),
      });
      for (final wordId in candidateWordIds.toSet()) {
        await transaction.rawInsert(
          '''
          INSERT OR IGNORE INTO daily_new_word_tasks (
            task_date, word_id, created_at
          )
          SELECT ?, ?, ?
          WHERE NOT EXISTS (
            SELECT 1 FROM learning_records WHERE word_id = ?
          )
          ''',
          [taskDateText, wordId, createdAt.toIso8601String(), wordId],
        );
      }
      return DailyTaskBatch(
        taskDate: taskDate,
        targetCount: targetCount,
        createdAt: createdAt,
      );
    });
  }

  @override
  Future<DailyTaskBatch> resizeDailyTaskBatch({
    required DateTime date,
    required int targetCount,
    required int desiredTaskCount,
    required List<String> candidateWordIds,
    required DateTime changedAt,
  }) async {
    final taskDate = localDateOnly(date);
    final taskDateText = _dateToText(taskDate);
    return _database.transaction((transaction) async {
      final batchRows = await transaction.query(
        'daily_task_batches',
        where: 'task_date = ?',
        whereArgs: [taskDateText],
        limit: 1,
      );
      if (batchRows.isEmpty) {
        throw StateError(
          'Cannot resize a daily task batch before it is created.',
        );
      }
      await transaction.update(
        'daily_task_batches',
        {'target_count': targetCount},
        where: 'task_date = ?',
        whereArgs: [taskDateText],
      );

      final todayRows = await transaction.query(
        'daily_new_word_tasks',
        columns: ['id', 'first_layer_completed', 'is_completed'],
        where: 'task_date = ?',
        whereArgs: [taskDateText],
        orderBy: 'id DESC',
      );
      var excess = todayRows.length - desiredTaskCount;
      for (final row in todayRows) {
        if (excess <= 0) break;
        if (row['first_layer_completed'] == 1 || row['is_completed'] == 1) {
          continue;
        }
        await transaction.delete(
          'daily_new_word_tasks',
          where: 'id = ?',
          whereArgs: [row['id']],
        );
        excess--;
      }

      final countRows = await transaction.rawQuery(
        'SELECT COUNT(*) AS task_count FROM daily_new_word_tasks '
        'WHERE task_date = ?',
        [taskDateText],
      );
      var todayTaskCount = countRows.single['task_count']! as int;
      for (final wordId in candidateWordIds.toSet()) {
        if (todayTaskCount >= desiredTaskCount) break;
        final insertedId = await transaction.rawInsert(
          '''
          INSERT OR IGNORE INTO daily_new_word_tasks (
            task_date, word_id, created_at
          )
          SELECT ?, ?, ?
          WHERE NOT EXISTS (
            SELECT 1 FROM learning_records WHERE word_id = ?
          )
          ''',
          [taskDateText, wordId, changedAt.toIso8601String(), wordId],
        );
        if (insertedId > 0) todayTaskCount++;
      }

      return DailyTaskBatch(
        taskDate: taskDate,
        targetCount: targetCount,
        createdAt: DateTime.parse(batchRows.single['created_at']! as String),
      );
    });
  }

  @override
  Future<List<DailyNewWordTask>> getAllDailyNewWordTasks() async {
    final rows = await _database.query(
      'daily_new_word_tasks',
      orderBy: 'task_date, id',
    );
    return rows.map(_dailyNewWordTaskFromMap).toList(growable: false);
  }

  @override
  Future<void> markDailyTasksFirstLayerCompleted(
    Iterable<String> wordIds, {
    required DateTime completedAt,
  }) async {
    final ids = wordIds.toSet().toList(growable: false);
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await _database.update(
      'daily_new_word_tasks',
      {
        'first_layer_completed': 1,
        'first_layer_completed_at': completedAt.toIso8601String(),
      },
      where: 'word_id IN ($placeholders) AND first_layer_completed = 0',
      whereArgs: ids,
    );
  }

  @override
  Future<void> markDailyTasksCompleted(
    Iterable<String> wordIds, {
    required DateTime completedAt,
  }) async {
    final ids = wordIds.toSet().toList(growable: false);
    if (ids.isEmpty) return;
    final placeholders = List.filled(ids.length, '?').join(', ');
    await _database.update(
      'daily_new_word_tasks',
      {'is_completed': 1, 'completed_at': completedAt.toIso8601String()},
      where:
          'word_id IN ($placeholders) '
          'AND first_layer_completed = 1 AND is_completed = 0',
      whereArgs: ids,
    );
  }

  DailyTaskBatch _dailyTaskBatchFromMap(Map<String, Object?> map) =>
      DailyTaskBatch(
        taskDate: DateTime.parse(map['task_date']! as String),
        targetCount: map['target_count']! as int,
        createdAt: DateTime.parse(map['created_at']! as String),
      );

  DailyNewWordTask _dailyNewWordTaskFromMap(Map<String, Object?> map) =>
      DailyNewWordTask(
        id: map['id']! as int,
        taskDate: DateTime.parse(map['task_date']! as String),
        wordId: map['word_id']! as String,
        isFirstLayerCompleted: map['first_layer_completed'] == 1,
        isCompleted: map['is_completed'] == 1,
        createdAt: DateTime.parse(map['created_at']! as String),
        firstLayerCompletedAt: _dateTimeFromText(
          map['first_layer_completed_at'] as String?,
        ),
        completedAt: _dateTimeFromText(map['completed_at'] as String?),
      );

  LearningRecord _recordFromMap(Map<String, Object?> map) {
    return LearningRecord(
      wordId: map['word_id']! as String,
      word: map['word']! as String,
      stage: LearningStage.values.byName(map['stage']! as String),
      firstResult: _choiceFromText(map['first_result'] as String?),
      secondResult: _choiceFromText(map['second_result'] as String?),
      thirdResult: _choiceFromText(map['third_result'] as String?),
      isDifficult: map['is_difficult'] == 1,
      firstLayerCompletedAt: _dateTimeFromText(
        map['first_layer_completed_at'] as String?,
      ),
      isWaitingReview: map['is_waiting_review'] == 1,
      nextReviewDate: _dateTimeFromText(map['next_review_date'] as String?),
      lastReviewDate: _dateTimeFromText(map['last_review_date'] as String?),
      reviewIntervalDays: map['review_interval_days'] as int?,
      reviewCount: map['review_count']! as int,
      forgetCount: map['forget_count']! as int,
      recentReactionMilliseconds: map['recent_reaction_ms'] as int?,
      averageReactionMilliseconds: (map['average_reaction_ms'] as num?)
          ?.toDouble(),
      lastReviewResult: _choiceFromText(map['last_review_result'] as String?),
    );
  }

  ReviewTask _reviewTaskFromMap(Map<String, Object?> map) {
    return ReviewTask(
      id: map['id']! as int,
      wordId: map['word_id']! as String,
      word: map['word']! as String,
      reviewDate: DateTime.parse(map['review_date']! as String),
      isCompleted: map['is_completed'] == 1,
      createdAt: DateTime.parse(map['created_at']! as String),
      completedAt: _dateTimeFromText(map['completed_at'] as String?),
    );
  }

  ReviewAttempt _reviewAttemptFromMap(Map<String, Object?> map) {
    return ReviewAttempt(
      id: map['id']! as int,
      wordId: map['word_id']! as String,
      reviewTaskId: map['review_task_id']! as int,
      reviewedAt: DateTime.parse(map['reviewed_at']! as String),
      result: StudyChoice.values.byName(map['result']! as String),
      reactionMilliseconds: map['reaction_ms']! as int,
      fluency: _fluencyFromText(map['fluency'] as String?),
      previousIntervalDays: map['previous_interval_days'] as int?,
      actualElapsedDays: map['actual_elapsed_days'] as int?,
      nextIntervalDays: map['next_interval_days'] as int?,
      scheduledReviewDate: _dateTimeFromText(
        map['scheduled_review_date'] as String?,
      ),
      actualReviewDate: _dateTimeFromText(map['actual_review_date'] as String?),
      nextReviewDate: _dateTimeFromText(map['next_review_date'] as String?),
      overdueDays: map['overdue_days'] as int?,
      schedulerVersion: map['scheduler_version'] as String?,
    );
  }

  ContextArticle _contextArticleFromMap(Map<String, Object?> map) {
    List<String> stringList(String key) =>
        (jsonDecode(map[key]! as String) as List).cast<String>();
    return ContextArticle(
      id: map['id']! as int,
      contextSessionId: map['context_session_id']! as String,
      requestId: map['request_id']! as String,
      title: map['title']! as String,
      articleText: map['article_text']! as String,
      sourceWordIds: stringList('source_word_ids_json'),
      usedWordIds: stringList('used_word_ids_json'),
      provider: map['provider']! as String,
      model: map['model']! as String,
      promptVersion: map['prompt_version']! as String,
      status: ContextArticleStatus.values.byName(map['status']! as String),
      generatedAt: DateTime.parse(map['generated_at']! as String),
      errorCode: map['error_code'] as String?,
    );
  }

  ReviewFluency? _fluencyFromText(String? value) =>
      value == null ? null : ReviewFluency.values.byName(value);

  int _currentIntervalFromRow(
    Map<String, Object?> row,
    DateTime scheduledDate,
  ) {
    final stored = row['review_interval_days'] as int?;
    if (stored != null && stored > 0) return stored;
    final firstCompleted = _dateTimeFromText(
      row['first_layer_completed_at'] as String?,
    );
    if (firstCompleted == null) return 1;
    return _calendarDayDifference(
      firstCompleted,
      scheduledDate,
    ).clamp(1, ReviewPolicy.maximumIntervalDays);
  }

  int _calendarDayDifference(DateTime start, DateTime end) {
    final startUtc = DateTime.utc(start.year, start.month, start.day);
    final endUtc = DateTime.utc(end.year, end.month, end.day);
    return endUtc.difference(startUtc).inDays;
  }

  StudyChoice? _choiceFromText(String? value) =>
      value == null ? null : StudyChoice.values.byName(value);

  DateTime? _dateTimeFromText(String? value) =>
      value == null ? null : DateTime.parse(value);

  String _dateToText(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
