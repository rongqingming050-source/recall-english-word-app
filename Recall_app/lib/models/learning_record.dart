import 'first_layer_word_state.dart';
import '../review/review_scheduler.dart';

enum LearningStage {
  unlearned,
  firstLayerLearning,
  contextStrengthening,
  waitingReview,
  reviewing,
  reviewedAwaitingSchedule,
  familiar,
  mastered,
}

class LearningRecord {
  const LearningRecord({
    required this.wordId,
    required this.word,
    required this.stage,
    required this.firstResult,
    required this.secondResult,
    required this.thirdResult,
    required this.isDifficult,
    required this.firstLayerCompletedAt,
    required this.isWaitingReview,
    required this.nextReviewDate,
    required this.lastReviewDate,
    required this.reviewIntervalDays,
    required this.reviewCount,
    required this.forgetCount,
    required this.recentReactionMilliseconds,
    required this.averageReactionMilliseconds,
    required this.lastReviewResult,
  });

  final String wordId;
  final String word;
  final LearningStage stage;
  final StudyChoice? firstResult;
  final StudyChoice? secondResult;
  final StudyChoice? thirdResult;
  final bool isDifficult;
  final DateTime? firstLayerCompletedAt;
  final bool isWaitingReview;
  final DateTime? nextReviewDate;
  final DateTime? lastReviewDate;
  final int? reviewIntervalDays;
  final int reviewCount;
  final int forgetCount;
  final int? recentReactionMilliseconds;
  final double? averageReactionMilliseconds;
  final StudyChoice? lastReviewResult;

  Map<String, Object?> toJson() => {
    'wordId': wordId,
    'word': word,
    'stage': stage.name,
    'firstLayerFirstResult': firstResult?.name,
    'firstLayerSecondResult': secondResult?.name,
    'firstLayerThirdResult': thirdResult?.name,
    'isDifficult': isDifficult,
    'firstLayerCompletedAt': firstLayerCompletedAt?.toIso8601String(),
    'isWaitingReview': isWaitingReview,
    'nextReviewDate': nextReviewDate?.toIso8601String(),
    'lastReviewDate': lastReviewDate?.toIso8601String(),
    'reviewIntervalDays': reviewIntervalDays,
    'reviewCount': reviewCount,
    'forgetCount': forgetCount,
    'recentReactionMilliseconds': recentReactionMilliseconds,
    'averageReactionMilliseconds': averageReactionMilliseconds,
    'lastReviewResult': lastReviewResult?.name,
  };
}

class ReviewTask {
  const ReviewTask({
    required this.id,
    required this.wordId,
    required this.word,
    required this.reviewDate,
    required this.isCompleted,
    required this.createdAt,
    required this.completedAt,
  });

  final int id;
  final String wordId;
  final String word;
  final DateTime reviewDate;
  final bool isCompleted;
  final DateTime createdAt;
  final DateTime? completedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'wordId': wordId,
    'word': word,
    'reviewDate': reviewDate.toIso8601String(),
    'isCompleted': isCompleted,
    'createdAt': createdAt.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
  };
}

class ReviewAttempt {
  const ReviewAttempt({
    required this.id,
    required this.wordId,
    required this.reviewTaskId,
    required this.reviewedAt,
    required this.result,
    required this.reactionMilliseconds,
    required this.fluency,
    required this.previousIntervalDays,
    required this.actualElapsedDays,
    required this.nextIntervalDays,
    required this.scheduledReviewDate,
    required this.actualReviewDate,
    required this.nextReviewDate,
    required this.overdueDays,
    required this.schedulerVersion,
  });

  final int id;
  final String wordId;
  final int reviewTaskId;
  final DateTime reviewedAt;
  final StudyChoice result;
  final int reactionMilliseconds;
  final ReviewFluency? fluency;
  final int? previousIntervalDays;
  final int? actualElapsedDays;
  final int? nextIntervalDays;
  final DateTime? scheduledReviewDate;
  final DateTime? actualReviewDate;
  final DateTime? nextReviewDate;
  final int? overdueDays;
  final String? schedulerVersion;

  Map<String, Object?> toJson() => {
    'id': id,
    'wordId': wordId,
    'reviewTaskId': reviewTaskId,
    'reviewedAt': reviewedAt.toIso8601String(),
    'result': result.name,
    'reactionMilliseconds': reactionMilliseconds,
    'reactionMs': reactionMilliseconds,
    'fluency': fluency?.name,
    'previousIntervalDays': previousIntervalDays,
    'actualElapsedDays': actualElapsedDays,
    'nextIntervalDays': nextIntervalDays,
    'scheduledReviewDate': scheduledReviewDate?.toIso8601String(),
    'actualReviewDate': actualReviewDate?.toIso8601String(),
    'nextReviewDate': nextReviewDate?.toIso8601String(),
    'overdueDays': overdueDays,
    'schedulerVersion': schedulerVersion,
  };
}

/// Legacy/test-fixture ID helper. Formal vocabulary entries carry a namespaced
/// source ID through [Word.id] instead.
String stableWordId(String word) => word.trim().toLowerCase();

DateTime localDateOnly(DateTime date) =>
    DateTime(date.year, date.month, date.day);

DateTime nextLocalDate(DateTime date) =>
    DateTime(date.year, date.month, date.day + 1);
