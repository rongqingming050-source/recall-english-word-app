import '../models/daily_new_word_task.dart';

abstract interface class DailyTaskRepository {
  Future<int> getDailyNewWordTarget();

  Future<void> setDailyNewWordTarget(int target);

  Future<DailyTaskBatch?> getDailyTaskBatch(DateTime date);

  /// Creates a date batch once. Repeated calls for the same local date return
  /// the original batch and never add, replace, or remove assigned words.
  Future<DailyTaskBatch> createDailyTaskBatch({
    required DateTime date,
    required int targetCount,
    required List<String> candidateWordIds,
    required DateTime createdAt,
  });

  /// Applies a changed daily target to an existing date batch.
  ///
  /// Unstarted tasks may be removed when the target is lowered. Tasks that
  /// have entered the learning flow are preserved.
  Future<DailyTaskBatch> resizeDailyTaskBatch({
    required DateTime date,
    required int targetCount,
    required int desiredTaskCount,
    required List<String> candidateWordIds,
    required DateTime changedAt,
  });

  Future<List<DailyNewWordTask>> getAllDailyNewWordTasks();

  Future<void> markDailyTasksFirstLayerCompleted(
    Iterable<String> wordIds, {
    required DateTime completedAt,
  });

  Future<void> markDailyTasksCompleted(
    Iterable<String> wordIds, {
    required DateTime completedAt,
  });
}

abstract final class VocabularySettingsDefaults {
  static const dailyNewWordTarget = 10;
  static const minimumDailyNewWordTarget = 1;
  static const maximumDailyNewWordTarget = 200;
}
