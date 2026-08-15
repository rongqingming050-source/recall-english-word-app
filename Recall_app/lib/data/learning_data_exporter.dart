import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'learning_repository.dart';
import 'vocabulary_repository.dart';
import '../learning/daily_task_service.dart';

typedef ExportDirectoryProvider = Future<Directory> Function();

class LearningDataExporter {
  const LearningDataExporter({this.directoryProvider});

  final ExportDirectoryProvider? directoryProvider;

  Future<File> export(
    LearningRepository repository, {
    VocabularyRepository? vocabulary,
    DailyTaskService? dailyTaskService,
  }) async {
    final records = await repository.getAllRecords();
    final tasks = await repository.getAllReviewTasks();
    final attempts = await repository.getAllReviewAttempts();
    final dailyTasks = await repository.getAllDailyNewWordTasks();
    final contextArticles = await repository.getAllContextArticles();
    final dailyTarget = await repository.getDailyNewWordTarget();
    final progress = await dailyTaskService?.getVocabularyProgress();
    final directory =
        await (directoryProvider ?? getApplicationDocumentsDirectory)();
    final file = File(p.join(directory.path, 'recall_learning_data.json'));
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(
      encoder.convert({
        'exportedAt': DateTime.now().toIso8601String(),
        'learningRecords': records.map((record) => record.toJson()).toList(),
        'reviewTasks': tasks.map((task) => task.toJson()).toList(),
        'reviewAttempts': attempts.map((attempt) => attempt.toJson()).toList(),
        'vocabularySummary': {
          'vocabularyId': vocabulary?.book.id,
          'vocabularyName': vocabulary?.book.name,
          'dailyNewWordTarget': dailyTarget,
          if (progress != null) ...progress.toJson(),
        },
        'dailyNewWordTasks': dailyTasks.map((task) => task.toJson()).toList(),
        'contextArticles': contextArticles
            .map((article) => article.toExportJson())
            .toList(),
      }),
      flush: true,
    );
    return file;
  }
}
