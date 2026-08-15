import '../models/first_layer_word_state.dart';
import '../models/context_article.dart';
import '../models/daily_new_word_task.dart';
import '../models/learning_record.dart';
import '../models/word.dart';
import '../review/review_scheduler.dart';
import 'daily_task_repository.dart';
import 'learning_repository.dart';

class MemoryLearningRepository implements LearningRepository {
  final Map<String, LearningRecord> _records = {};
  final Map<int, ReviewTask> _tasks = {};
  final List<ReviewAttempt> _attempts = [];
  final Map<DateTime, DailyTaskBatch> _dailyBatches = {};
  final Map<int, DailyNewWordTask> _dailyTasks = {};
  final Map<String, ContextArticle> _contextArticles = {};
  int _nextTaskId = 1;
  int _nextAttemptId = 1;
  int _nextDailyTaskId = 1;
  int _dailyNewWordTarget = VocabularySettingsDefaults.dailyNewWordTarget;
  final ReviewScheduler _scheduler = const ReviewScheduler();

  @override
  Future<void> saveFirstLayerResults(
    List<FirstLayerWordState> states, {
    required DateTime completedAt,
  }) async {
    for (final state in states) {
      final id = state.word.id;
      final previous = _records[id];
      _records[id] = LearningRecord(
        wordId: id,
        word: state.word.word,
        stage: LearningStage.contextStrengthening,
        firstResult: state.firstJudgment,
        secondResult: state.secondJudgment,
        thirdResult: state.thirdJudgment,
        isDifficult: state.isDifficult,
        firstLayerCompletedAt: completedAt,
        isWaitingReview: previous?.isWaitingReview ?? false,
        nextReviewDate: previous?.nextReviewDate,
        lastReviewDate: previous?.lastReviewDate,
        reviewIntervalDays: previous?.reviewIntervalDays,
        reviewCount: previous?.reviewCount ?? 0,
        forgetCount: previous?.forgetCount ?? 0,
        recentReactionMilliseconds: previous?.recentReactionMilliseconds,
        averageReactionMilliseconds: previous?.averageReactionMilliseconds,
        lastReviewResult: previous?.lastReviewResult,
      );
    }
    await markDailyTasksFirstLayerCompleted(
      states.map((state) => state.word.id),
      completedAt: completedAt,
    );
  }

  @override
  Future<void> scheduleFirstReviews(
    Map<String, DateTime> datesByWordId, {
    required DateTime now,
  }) async {
    for (final entry in datesByWordId.entries) {
      final record = _records[entry.key];
      if (record == null) {
        throw StateError('${entry.key} has no learning record.');
      }
      final requestedDate = localDateOnly(entry.value);
      final existing = _unfinishedTask(entry.key);
      final effectiveDate =
          existing == null || requestedDate.isBefore(existing.reviewDate)
          ? requestedDate
          : existing.reviewDate;
      final task = ReviewTask(
        id: existing?.id ?? _nextTaskId++,
        wordId: entry.key,
        word: record.word,
        reviewDate: effectiveDate,
        isCompleted: false,
        createdAt: existing?.createdAt ?? now,
        completedAt: null,
      );
      _tasks[task.id] = task;
      _records[entry.key] = _copyRecord(
        record,
        stage: LearningStage.waitingReview,
        isWaitingReview: true,
        nextReviewDate: effectiveDate,
        reviewIntervalDays: _calendarDayDifference(
          record.firstLayerCompletedAt ?? now,
          effectiveDate,
        ).clamp(1, ReviewPolicy.maximumIntervalDays),
      );
    }
  }

  @override
  Future<ReviewTask> overrideReviewTaskToTomorrow(
    Word word, {
    required DateTime now,
  }) async {
    final wordId = word.id;
    final reviewDate = nextLocalDate(now);
    final existing = _unfinishedTask(wordId);
    final previous = _records[wordId];
    _records[wordId] = _copyRecord(
      previous ?? _emptyRecord(word),
      stage: LearningStage.waitingReview,
      isWaitingReview: true,
      nextReviewDate: reviewDate,
      reviewIntervalDays: 1,
    );
    final task = ReviewTask(
      id: existing?.id ?? _nextTaskId++,
      wordId: wordId,
      word: word.word,
      reviewDate: reviewDate,
      isCompleted: false,
      createdAt: existing?.createdAt ?? now,
      completedAt: null,
    );
    _tasks[task.id] = task;
    return task;
  }

  @override
  Future<ReviewAttempt> completeReviewTask({
    required int reviewTaskId,
    required StudyChoice result,
    required int reactionTimeMs,
    required DateTime reviewedAt,
  }) async {
    if (reactionTimeMs < 0) {
      throw ArgumentError.value(reactionTimeMs);
    }
    final task = _tasks[reviewTaskId];
    if (task == null ||
        task.isCompleted ||
        _attempts.any((a) => a.reviewTaskId == reviewTaskId)) {
      throw StateError('Review task $reviewTaskId is already completed.');
    }
    final record = _records[task.wordId];
    if (record == null) {
      throw StateError('${task.wordId} has no learning record.');
    }
    if (record.reviewCount > 0 && record.averageReactionMilliseconds == null) {
      throw StateError('${task.wordId} has an invalid reaction-time summary.');
    }
    final average = record.reviewCount == 0
        ? reactionTimeMs.toDouble()
        : (record.averageReactionMilliseconds! * record.reviewCount +
                  reactionTimeMs) /
              (record.reviewCount + 1);
    final currentInterval = record.reviewIntervalDays ?? 1;
    final decision = _scheduler.schedule(
      currentIntervalDays: currentInterval,
      result: result,
      reactionTimeMs: reactionTimeMs,
      reviewedAt: reviewedAt,
    );
    final actualDate = localDateOnly(reviewedAt);
    final baseline =
        record.lastReviewDate ??
        record.firstLayerCompletedAt ??
        task.reviewDate.subtract(Duration(days: currentInterval));
    final actualElapsedDays = _calendarDayDifference(
      baseline,
      actualDate,
    ).clamp(0, 1000000);
    final overdueDays = _calendarDayDifference(
      task.reviewDate,
      actualDate,
    ).clamp(0, 1000000);
    final attempt = ReviewAttempt(
      id: _nextAttemptId++,
      wordId: task.wordId,
      reviewTaskId: task.id,
      reviewedAt: reviewedAt,
      result: result,
      reactionMilliseconds: reactionTimeMs,
      fluency: decision.fluency,
      previousIntervalDays: decision.previousIntervalDays,
      actualElapsedDays: actualElapsedDays,
      nextIntervalDays: decision.nextIntervalDays,
      scheduledReviewDate: task.reviewDate,
      actualReviewDate: actualDate,
      nextReviewDate: decision.nextReviewDate,
      overdueDays: overdueDays,
      schedulerVersion: decision.schedulerVersion,
    );
    _attempts.add(attempt);
    _tasks[task.id] = ReviewTask(
      id: task.id,
      wordId: task.wordId,
      word: task.word,
      reviewDate: task.reviewDate,
      isCompleted: true,
      createdAt: task.createdAt,
      completedAt: reviewedAt,
    );
    final nextTask = ReviewTask(
      id: _nextTaskId++,
      wordId: task.wordId,
      word: task.word,
      reviewDate: decision.nextReviewDate,
      isCompleted: false,
      createdAt: reviewedAt,
      completedAt: null,
    );
    _tasks[nextTask.id] = nextTask;
    _records[task.wordId] = _copyRecord(
      record,
      stage: LearningStage.waitingReview,
      isWaitingReview: true,
      nextReviewDate: decision.nextReviewDate,
      reviewIntervalDays: decision.nextIntervalDays,
      lastReviewDate: reviewedAt,
      lastReviewResult: result,
      reviewCount: record.reviewCount + 1,
      forgetCount: record.forgetCount + (result == StudyChoice.unknown ? 1 : 0),
      recentReactionMilliseconds: reactionTimeMs,
      averageReactionMilliseconds: average,
    );
    return attempt;
  }

  @override
  Future<bool> hasReviewTask(Word word, DateTime reviewDate) async {
    final task = _unfinishedTask(word.id);
    return task != null &&
        localDateOnly(task.reviewDate) == localDateOnly(reviewDate);
  }

  @override
  Future<LearningRecord?> getRecord(String wordId) async => _records[wordId];

  @override
  Future<List<LearningRecord>> getAllRecords() async =>
      _records.values.toList()..sort((a, b) => a.word.compareTo(b.word));

  @override
  Future<List<ReviewTask>> getDueReviewTasks(DateTime today) async {
    final date = localDateOnly(today);
    return _tasks.values
        .where((task) => !task.isCompleted && !task.reviewDate.isAfter(date))
        .toList()
      ..sort((a, b) {
        final byDate = a.reviewDate.compareTo(b.reviewDate);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });
  }

  @override
  Future<List<ReviewTask>> getAllReviewTasks() async =>
      _tasks.values.toList()..sort((a, b) => a.id.compareTo(b.id));

  @override
  Future<List<ReviewAttempt>> getAllReviewAttempts() async =>
      List.unmodifiable(_attempts);

  @override
  Future<ContextArticle?> getSuccessfulContextArticle(
    String contextSessionId,
  ) async {
    final article = _contextArticles[contextSessionId];
    return article?.status == ContextArticleStatus.success ? article : null;
  }

  @override
  Future<void> upsertContextArticle(ContextArticle article) async {
    final current = _contextArticles[article.contextSessionId];
    if (current?.status == ContextArticleStatus.success) return;
    _contextArticles[article.contextSessionId] = article;
  }

  @override
  Future<void> deleteContextArticle(String contextSessionId) async {
    _contextArticles.remove(contextSessionId);
  }

  @override
  Future<List<ContextArticle>> getAllContextArticles() async =>
      List.unmodifiable(_contextArticles.values);

  ReviewTask? _unfinishedTask(String wordId) => _tasks.values
      .where((task) => task.wordId == wordId && !task.isCompleted)
      .firstOrNull;

  LearningRecord _emptyRecord(Word word) => LearningRecord(
    wordId: word.id,
    word: word.word,
    stage: LearningStage.unlearned,
    firstResult: null,
    secondResult: null,
    thirdResult: null,
    isDifficult: false,
    firstLayerCompletedAt: null,
    isWaitingReview: false,
    nextReviewDate: null,
    lastReviewDate: null,
    reviewIntervalDays: null,
    reviewCount: 0,
    forgetCount: 0,
    recentReactionMilliseconds: null,
    averageReactionMilliseconds: null,
    lastReviewResult: null,
  );

  LearningRecord _copyRecord(
    LearningRecord r, {
    LearningStage? stage,
    bool? isWaitingReview,
    DateTime? nextReviewDate,
    bool clearNextReviewDate = false,
    DateTime? lastReviewDate,
    StudyChoice? lastReviewResult,
    int? reviewCount,
    int? forgetCount,
    int? recentReactionMilliseconds,
    double? averageReactionMilliseconds,
    int? reviewIntervalDays,
  }) => LearningRecord(
    wordId: r.wordId,
    word: r.word,
    stage: stage ?? r.stage,
    firstResult: r.firstResult,
    secondResult: r.secondResult,
    thirdResult: r.thirdResult,
    isDifficult: r.isDifficult,
    firstLayerCompletedAt: r.firstLayerCompletedAt,
    isWaitingReview: isWaitingReview ?? r.isWaitingReview,
    nextReviewDate: clearNextReviewDate
        ? null
        : nextReviewDate ?? r.nextReviewDate,
    lastReviewDate: lastReviewDate ?? r.lastReviewDate,
    reviewIntervalDays: reviewIntervalDays ?? r.reviewIntervalDays,
    reviewCount: reviewCount ?? r.reviewCount,
    forgetCount: forgetCount ?? r.forgetCount,
    recentReactionMilliseconds:
        recentReactionMilliseconds ?? r.recentReactionMilliseconds,
    averageReactionMilliseconds:
        averageReactionMilliseconds ?? r.averageReactionMilliseconds,
    lastReviewResult: lastReviewResult ?? r.lastReviewResult,
  );

  int _calendarDayDifference(DateTime start, DateTime end) {
    final startUtc = DateTime.utc(start.year, start.month, start.day);
    final endUtc = DateTime.utc(end.year, end.month, end.day);
    return endUtc.difference(startUtc).inDays;
  }

  @override
  Future<int> getDailyNewWordTarget() async => _dailyNewWordTarget;

  @override
  Future<void> setDailyNewWordTarget(int target) async {
    if (target < VocabularySettingsDefaults.minimumDailyNewWordTarget ||
        target > VocabularySettingsDefaults.maximumDailyNewWordTarget) {
      throw ArgumentError.value(target, 'target');
    }
    _dailyNewWordTarget = target;
  }

  @override
  Future<DailyTaskBatch?> getDailyTaskBatch(DateTime date) async =>
      _dailyBatches[localDateOnly(date)];

  @override
  Future<DailyTaskBatch> createDailyTaskBatch({
    required DateTime date,
    required int targetCount,
    required List<String> candidateWordIds,
    required DateTime createdAt,
  }) async {
    final taskDate = localDateOnly(date);
    final existing = _dailyBatches[taskDate];
    if (existing != null) return existing;
    final batch = DailyTaskBatch(
      taskDate: taskDate,
      targetCount: targetCount,
      createdAt: createdAt,
    );
    _dailyBatches[taskDate] = batch;
    final assigned = _dailyTasks.values.map((task) => task.wordId).toSet();
    for (final wordId in candidateWordIds.toSet()) {
      if (assigned.contains(wordId) || _records.containsKey(wordId)) continue;
      final task = DailyNewWordTask(
        id: _nextDailyTaskId++,
        taskDate: taskDate,
        wordId: wordId,
        isFirstLayerCompleted: false,
        isCompleted: false,
        createdAt: createdAt,
        firstLayerCompletedAt: null,
        completedAt: null,
      );
      _dailyTasks[task.id] = task;
      assigned.add(wordId);
    }
    return batch;
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
    final existingBatch = _dailyBatches[taskDate];
    if (existingBatch == null) {
      throw StateError(
        'Cannot resize a daily task batch before it is created.',
      );
    }

    final resizedBatch = DailyTaskBatch(
      taskDate: taskDate,
      targetCount: targetCount,
      createdAt: existingBatch.createdAt,
    );
    _dailyBatches[taskDate] = resizedBatch;

    final todayEntries =
        _dailyTasks.entries
            .where((entry) => entry.value.taskDate == taskDate)
            .toList()
          ..sort((a, b) => b.key.compareTo(a.key));
    var excess = todayEntries.length - desiredTaskCount;
    for (final entry in todayEntries) {
      if (excess <= 0) break;
      final task = entry.value;
      if (task.isFirstLayerCompleted || task.isCompleted) continue;
      _dailyTasks.remove(entry.key);
      excess--;
    }

    var todayTaskCount = _dailyTasks.values
        .where((task) => task.taskDate == taskDate)
        .length;
    final assigned = _dailyTasks.values.map((task) => task.wordId).toSet();
    for (final wordId in candidateWordIds.toSet()) {
      if (todayTaskCount >= desiredTaskCount) break;
      if (assigned.contains(wordId) || _records.containsKey(wordId)) continue;
      final task = DailyNewWordTask(
        id: _nextDailyTaskId++,
        taskDate: taskDate,
        wordId: wordId,
        isFirstLayerCompleted: false,
        isCompleted: false,
        createdAt: changedAt,
        firstLayerCompletedAt: null,
        completedAt: null,
      );
      _dailyTasks[task.id] = task;
      assigned.add(wordId);
      todayTaskCount++;
    }
    return resizedBatch;
  }

  @override
  Future<List<DailyNewWordTask>> getAllDailyNewWordTasks() async =>
      _dailyTasks.values.toList()..sort((a, b) {
        final byDate = a.taskDate.compareTo(b.taskDate);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });

  @override
  Future<void> markDailyTasksFirstLayerCompleted(
    Iterable<String> wordIds, {
    required DateTime completedAt,
  }) async {
    final ids = wordIds.toSet();
    for (final entry in _dailyTasks.entries.toList()) {
      final task = entry.value;
      if (!ids.contains(task.wordId) || task.isFirstLayerCompleted) continue;
      _dailyTasks[entry.key] = DailyNewWordTask(
        id: task.id,
        taskDate: task.taskDate,
        wordId: task.wordId,
        isFirstLayerCompleted: true,
        isCompleted: task.isCompleted,
        createdAt: task.createdAt,
        firstLayerCompletedAt: completedAt,
        completedAt: task.completedAt,
      );
    }
  }

  @override
  Future<void> markDailyTasksCompleted(
    Iterable<String> wordIds, {
    required DateTime completedAt,
  }) async {
    final ids = wordIds.toSet();
    for (final entry in _dailyTasks.entries.toList()) {
      final task = entry.value;
      if (!ids.contains(task.wordId) ||
          !task.isFirstLayerCompleted ||
          task.isCompleted) {
        continue;
      }
      _dailyTasks[entry.key] = DailyNewWordTask(
        id: task.id,
        taskDate: task.taskDate,
        wordId: task.wordId,
        isFirstLayerCompleted: true,
        isCompleted: true,
        createdAt: task.createdAt,
        firstLayerCompletedAt: task.firstLayerCompletedAt,
        completedAt: completedAt,
      );
    }
  }
}
