import 'dart:math';

import '../data/learning_repository.dart';
import '../data/vocabulary_repository.dart';
import '../models/daily_new_word_task.dart';
import '../models/learning_record.dart';
import '../models/word.dart';

typedef CurrentDateTime = DateTime Function();

class DailyTaskService {
  const DailyTaskService({
    required this.repository,
    required this.vocabulary,
    this.now = DateTime.now,
  });

  final LearningRepository repository;
  final VocabularyRepository vocabulary;
  final CurrentDateTime now;

  Future<TodayTaskPlan> loadOrCreateToday() async {
    final current = now();
    final today = localDateOnly(current);
    final target = await repository.getDailyNewWordTarget();
    var allTasks = await repository.getAllDailyNewWordTasks();
    final historicalPendingCount = allTasks
        .where((task) => !task.isCompleted && task.taskDate.isBefore(today))
        .length;

    var batch = await repository.getDailyTaskBatch(today);
    if (batch == null) {
      final records = await repository.getAllRecords();
      final unavailableIds = <String>{
        ...allTasks.map((task) => task.wordId),
        ...records.map((record) => record.wordId),
      };
      final capacity = max(0, target - historicalPendingCount);
      final candidates = vocabulary.words
          .where((word) => !unavailableIds.contains(word.id))
          .take(capacity)
          .map((word) => word.id)
          .toList(growable: false);
      batch = await repository.createDailyTaskBatch(
        date: today,
        targetCount: target,
        candidateWordIds: candidates,
        createdAt: current,
      );
      allTasks = await repository.getAllDailyNewWordTasks();
    } else if (batch.targetCount != target) {
      final records = await repository.getAllRecords();
      final todayAssignedCount = allTasks
          .where((task) => _sameDate(task.taskDate, today))
          .length;
      final desiredTodayAssignedCount = max(0, target - historicalPendingCount);
      final additionalCount = max(
        0,
        desiredTodayAssignedCount - todayAssignedCount,
      );
      final unavailableIds = <String>{
        ...allTasks.map((task) => task.wordId),
        ...records.map((record) => record.wordId),
      };
      final candidates = vocabulary.words
          .where((word) => !unavailableIds.contains(word.id))
          .take(additionalCount)
          .map((word) => word.id)
          .toList(growable: false);
      batch = await repository.resizeDailyTaskBatch(
        date: today,
        targetCount: target,
        desiredTaskCount: desiredTodayAssignedCount,
        candidateWordIds: candidates,
        changedAt: current,
      );
      allTasks = await repository.getAllDailyNewWordTasks();
    }

    final pending =
        allTasks
            .where((task) => !task.isCompleted && !task.taskDate.isAfter(today))
            .toList()
          ..sort((a, b) {
            final byDate = a.taskDate.compareTo(b.taskDate);
            return byDate != 0 ? byDate : a.id.compareTo(b.id);
          });
    final firstLayerWords = <Word>[];
    final contextWords = <Word>[];
    for (final task in pending) {
      final word = vocabulary.findById(task.wordId);
      if (word == null) {
        throw StateError('每日任务引用了正式词库中不存在的 word_id：${task.wordId}');
      }
      if (task.isFirstLayerCompleted) {
        contextWords.add(word);
      } else {
        firstLayerWords.add(word);
      }
    }
    final todayTasks = allTasks.where(
      (task) => _sameDate(task.taskDate, today),
    );
    final completedTodayCount = allTasks.where((task) {
      final completedAt = task.completedAt;
      return task.isCompleted &&
          completedAt != null &&
          _sameDate(completedAt, today) &&
          vocabulary.findById(task.wordId) != null;
    }).length;
    return TodayTaskPlan(
      date: today,
      targetCount: batch.targetCount,
      historicalPendingCount: pending
          .where((task) => task.taskDate.isBefore(today))
          .length,
      todayAssignedCount: todayTasks.length,
      completedTodayCount: completedTodayCount,
      firstLayerWords: List.unmodifiable(firstLayerWords),
      contextWords: List.unmodifiable(contextWords),
      pendingTasks: List.unmodifiable(pending),
    );
  }

  Future<List<ReviewTask>> getDueFormalReviewTasks() async {
    final tasks = await repository.getDueReviewTasks(now());
    return tasks
        .where((task) => vocabulary.findById(task.wordId) != null)
        .toList(growable: false);
  }

  Future<VocabularyProgress> getVocabularyProgress() async {
    final results = await Future.wait([
      repository.getAllRecords(),
      repository.getAllDailyNewWordTasks(),
    ]);
    final records = results[0] as List<LearningRecord>;
    final tasks = results[1] as List<DailyNewWordTask>;
    final officialIds = vocabulary.words.map((word) => word.id).toSet();
    final lifecycleIds = <String>{
      ...tasks.map((task) => task.wordId).where(officialIds.contains),
      ...records.map((record) => record.wordId).where(officialIds.contains),
    };
    final firstLayerCompleted = records
        .where(
          (record) =>
              officialIds.contains(record.wordId) &&
              record.firstLayerCompletedAt != null,
        )
        .map((record) => record.wordId)
        .toSet()
        .length;
    return VocabularyProgress(
      totalCount: vocabulary.totalCount,
      lifecycleCount: lifecycleIds.length,
      unlearnedCount: vocabulary.totalCount - lifecycleIds.length,
      firstLayerCompletedCount: firstLayerCompleted,
    );
  }

  static bool _sameDate(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

class TodayTaskPlan {
  const TodayTaskPlan({
    required this.date,
    required this.targetCount,
    required this.historicalPendingCount,
    required this.todayAssignedCount,
    required this.completedTodayCount,
    required this.firstLayerWords,
    required this.contextWords,
    required this.pendingTasks,
  });

  final DateTime date;
  final int targetCount;
  final int historicalPendingCount;
  final int todayAssignedCount;
  final int completedTodayCount;
  final List<Word> firstLayerWords;
  final List<Word> contextWords;
  final List<DailyNewWordTask> pendingTasks;

  int get pendingNewWordCount => pendingTasks.length;

  int get actualTaskCount => completedTodayCount + pendingNewWordCount;

  bool get isComplete => pendingTasks.isEmpty;
}

class VocabularyProgress {
  const VocabularyProgress({
    required this.totalCount,
    required this.lifecycleCount,
    required this.unlearnedCount,
    required this.firstLayerCompletedCount,
  });

  final int totalCount;
  final int lifecycleCount;
  final int unlearnedCount;
  final int firstLayerCompletedCount;

  Map<String, Object> toJson() => {
    'totalCount': totalCount,
    'lifecycleCount': lifecycleCount,
    'unlearnedCount': unlearnedCount,
    'firstLayerCompletedCount': firstLayerCompletedCount,
  };
}
