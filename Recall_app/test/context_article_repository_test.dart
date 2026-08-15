import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:recall_app/data/sqlite_learning_repository.dart';
import 'package:recall_app/models/context_article.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();

  test('V6 context article cache survives repository reconstruction', () async {
    final directory = await Directory.systemTemp.createTemp('recall_context_');
    final path = '${directory.path}/learning.db';
    addTearDown(() => directory.delete(recursive: true));
    var repository = await SqliteLearningRepository.open(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
    final article = ContextArticle(
      contextSessionId: 'session-1',
      requestId: 'request-1',
      title: 'Cached title',
      articleText: 'Readers derive meaning from context.',
      sourceWordIds: ['derive'],
      usedWordIds: ['derive'],
      provider: 'fake',
      model: 'fake-context-v1',
      promptVersion: 'context_article_v1',
      status: ContextArticleStatus.success,
      generatedAt: DateTime.utc(2026, 8, 15, 1),
    );
    await repository.upsertContextArticle(article);
    await repository.close();

    repository = await SqliteLearningRepository.open(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
    final cached = await repository.getSuccessfulContextArticle('session-1');
    expect(cached, isNotNull);
    expect(cached!.title, 'Cached title');
    expect(cached.usedWordIds, ['derive']);
    expect(cached.provider, 'fake');
    expect(cached.promptVersion, 'context_article_v1');
    await repository.close();
  });

  test('migrates V5 in place and preserves existing learning data', () async {
    final directory = await Directory.systemTemp.createTemp('recall_v5_');
    final path = '${directory.path}/learning.db';
    addTearDown(() => directory.delete(recursive: true));
    final legacy = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 5,
        onCreate: (database, version) async {
          await database.execute('''
            CREATE TABLE learning_records (
              word_id TEXT PRIMARY KEY, word TEXT NOT NULL, stage TEXT NOT NULL,
              first_result TEXT, second_result TEXT, third_result TEXT,
              is_difficult INTEGER NOT NULL DEFAULT 0,
              first_layer_completed_at TEXT,
              is_waiting_review INTEGER NOT NULL DEFAULT 0,
              next_review_date TEXT, last_review_date TEXT,
              review_interval_days INTEGER, review_count INTEGER NOT NULL DEFAULT 0,
              forget_count INTEGER NOT NULL DEFAULT 0,
              recent_reaction_ms INTEGER, average_reaction_ms REAL,
              last_review_result TEXT
            )
          ''');
          await database.execute('''
            CREATE TABLE review_tasks (
              id INTEGER PRIMARY KEY AUTOINCREMENT, word_id TEXT NOT NULL,
              word TEXT NOT NULL, review_date TEXT NOT NULL,
              is_completed INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL,
              completed_at TEXT
            )
          ''');
          await database.execute('''
            CREATE TABLE review_attempts (
              id INTEGER PRIMARY KEY AUTOINCREMENT, word_id TEXT NOT NULL,
              review_task_id INTEGER NOT NULL UNIQUE, reviewed_at TEXT NOT NULL,
              result TEXT NOT NULL, reaction_ms INTEGER NOT NULL,
              fluency TEXT, previous_interval_days INTEGER,
              actual_elapsed_days INTEGER, next_interval_days INTEGER,
              scheduled_review_date TEXT, actual_review_date TEXT,
              next_review_date TEXT, overdue_days INTEGER, scheduler_version TEXT
            )
          ''');
          await database.insert('learning_records', {
            'word_id': 'legacy',
            'word': 'legacy',
            'stage': 'contextStrengthening',
            'first_result': 'known',
            'first_layer_completed_at': '2026-08-14T10:00:00.000',
          });
        },
      ),
    );
    await legacy.close();

    final repository = await SqliteLearningRepository.open(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
    expect((await repository.getRecord('legacy'))!.word, 'legacy');
    expect(await repository.getAllContextArticles(), isEmpty);
    await repository.upsertContextArticle(
      ContextArticle(
        contextSessionId: 'migrated-session',
        requestId: 'request-2',
        title: '',
        articleText: '',
        sourceWordIds: const ['legacy'],
        usedWordIds: const [],
        provider: '',
        model: '',
        promptVersion: '',
        status: ContextArticleStatus.skipped,
        generatedAt: DateTime(2026, 8, 15),
      ),
    );
    expect(
      (await repository.getAllContextArticles()).single.status,
      ContextArticleStatus.skipped,
    );
    await repository.close();
  });
}
