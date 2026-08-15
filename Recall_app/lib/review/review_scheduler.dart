import '../models/first_layer_word_state.dart';

enum ReviewFluency { normal, slow }

class ReviewPolicy {
  const ReviewPolicy();

  static const slowThresholdMilliseconds = 5000;
  static const slowProgressRatio = 0.4;
  static const intervals = [1, 3, 7, 15, 30, 60, 120];
  static const maximumIntervalDays = 120;
  static const schedulerVersion = 'v1_rule_5s_40pct';
  static const legacySchedulerVersion = 'v0_record_only';
}

class ReviewScheduleDecision {
  const ReviewScheduleDecision({
    required this.fluency,
    required this.previousIntervalDays,
    required this.nextIntervalDays,
    required this.nextReviewDate,
    required this.schedulerVersion,
  });

  final ReviewFluency fluency;
  final int previousIntervalDays;
  final int nextIntervalDays;
  final DateTime nextReviewDate;
  final String schedulerVersion;
}

class ReviewScheduler {
  const ReviewScheduler();

  ReviewScheduleDecision schedule({
    required int currentIntervalDays,
    required StudyChoice result,
    required int reactionTimeMs,
    required DateTime reviewedAt,
  }) {
    if (currentIntervalDays <= 0) {
      throw ArgumentError.value(currentIntervalDays, 'currentIntervalDays');
    }
    if (reactionTimeMs < 0) {
      throw ArgumentError.value(reactionTimeMs, 'reactionTimeMs');
    }
    final fluency = reactionTimeMs <= ReviewPolicy.slowThresholdMilliseconds
        ? ReviewFluency.normal
        : ReviewFluency.slow;
    final nextInterval = switch (result) {
      StudyChoice.unsure => 3,
      StudyChoice.unknown => 1,
      StudyChoice.known when fluency == ReviewFluency.normal =>
        _nextBaseInterval(currentIntervalDays),
      StudyChoice.known => _slowInterval(currentIntervalDays),
    };
    final actualDate = DateTime(
      reviewedAt.year,
      reviewedAt.month,
      reviewedAt.day,
    );
    return ReviewScheduleDecision(
      fluency: fluency,
      previousIntervalDays: currentIntervalDays,
      nextIntervalDays: nextInterval,
      nextReviewDate: DateTime(
        actualDate.year,
        actualDate.month,
        actualDate.day + nextInterval,
      ),
      schedulerVersion: ReviewPolicy.schedulerVersion,
    );
  }

  int _nextBaseInterval(int current) {
    return ReviewPolicy.intervals.firstWhere(
      (interval) => interval > current,
      orElse: () => ReviewPolicy.maximumIntervalDays,
    );
  }

  int _slowInterval(int current) {
    if (current >= ReviewPolicy.maximumIntervalDays) {
      return ReviewPolicy.maximumIntervalDays;
    }
    final nextBase = _nextBaseInterval(current);
    final interpolated =
        (current + (nextBase - current) * ReviewPolicy.slowProgressRatio)
            .round();
    return interpolated
        .clamp(current + 1, ReviewPolicy.maximumIntervalDays)
        .toInt();
  }
}
