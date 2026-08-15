import '../models/first_layer_word_state.dart';
import '../models/learning_record.dart';
import '../models/word.dart';
import 'daily_task_repository.dart';
import 'context_article_repository.dart';

abstract interface class LearningRepository
    implements DailyTaskRepository, ContextArticleRepository {
  Future<void> saveFirstLayerResults(
    List<FirstLayerWordState> states, {
    required DateTime completedAt,
  });

  /// Applies normal automatic scheduling in one atomic write.
  /// Existing unfinished tasks may be moved earlier, but never later.
  Future<void> scheduleFirstReviews(
    Map<String, DateTime> datesByWordId, {
    required DateTime now,
  });

  Future<LearningRecord?> getRecord(String wordId);

  Future<List<LearningRecord>> getAllRecords();

  /// User override: always changes the unfinished task to tomorrow, even when
  /// that moves an overdue or earlier task later.
  Future<ReviewTask> overrideReviewTaskToTomorrow(
    Word word, {
    required DateTime now,
  });

  Future<bool> hasReviewTask(Word word, DateTime reviewDate);

  Future<List<ReviewTask>> getDueReviewTasks(DateTime today);

  Future<List<ReviewTask>> getAllReviewTasks();

  Future<ReviewAttempt> completeReviewTask({
    required int reviewTaskId,
    required StudyChoice result,
    required int reactionTimeMs,
    required DateTime reviewedAt,
  });

  Future<List<ReviewAttempt>> getAllReviewAttempts();
}
