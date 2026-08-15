import 'package:flutter_test/flutter_test.dart';
import 'package:recall_app/models/first_layer_word_state.dart';
import 'package:recall_app/review/review_scheduler.dart';

void main() {
  const scheduler = ReviewScheduler();
  final reviewedAt = DateTime(2026, 8, 14, 23, 30);

  test('5000ms is normal and 5001ms is slow without changing result', () {
    final normal = scheduler.schedule(
      currentIntervalDays: 3,
      result: StudyChoice.known,
      reactionTimeMs: 5000,
      reviewedAt: reviewedAt,
    );
    final slow = scheduler.schedule(
      currentIntervalDays: 3,
      result: StudyChoice.known,
      reactionTimeMs: 5001,
      reviewedAt: reviewedAt,
    );
    expect(normal.fluency, ReviewFluency.normal);
    expect(normal.nextIntervalDays, 7);
    expect(slow.fluency, ReviewFluency.slow);
    expect(slow.nextIntervalDays, 5);
  });

  test('known normal advances through the base ladder', () {
    const expected = {1: 3, 3: 7, 7: 15, 15: 30, 30: 60, 60: 120, 120: 120};
    for (final entry in expected.entries) {
      expect(
        scheduler
            .schedule(
              currentIntervalDays: entry.key,
              result: StudyChoice.known,
              reactionTimeMs: 1000,
              reviewedAt: reviewedAt,
            )
            .nextIntervalDays,
        entry.value,
      );
    }
  });

  test('known slow follows 40 percent progression', () {
    const expected = {1: 2, 3: 5, 7: 10, 15: 21, 30: 42, 60: 84, 120: 120};
    for (final entry in expected.entries) {
      expect(
        scheduler
            .schedule(
              currentIntervalDays: entry.key,
              result: StudyChoice.known,
              reactionTimeMs: 6000,
              reviewedAt: reviewedAt,
            )
            .nextIntervalDays,
        entry.value,
      );
    }
  });

  test('normal non-standard intervals enter the next strict base tier', () {
    const expected = {2: 3, 5: 7, 10: 15, 21: 30, 42: 60, 84: 120};
    for (final entry in expected.entries) {
      expect(
        scheduler
            .schedule(
              currentIntervalDays: entry.key,
              result: StudyChoice.known,
              reactionTimeMs: 1000,
              reviewedAt: reviewedAt,
            )
            .nextIntervalDays,
        entry.value,
      );
    }
  });

  test('slow always progresses at least one day below the cap', () {
    expect(
      scheduler
          .schedule(
            currentIntervalDays: 2,
            result: StudyChoice.known,
            reactionTimeMs: 6000,
            reviewedAt: reviewedAt,
          )
          .nextIntervalDays,
      3,
    );
    expect(
      scheduler
          .schedule(
            currentIntervalDays: 119,
            result: StudyChoice.known,
            reactionTimeMs: 6000,
            reviewedAt: reviewedAt,
          )
          .nextIntervalDays,
      120,
    );
  });

  test('unsure and unknown ignore fluency and schedule from actual date', () {
    for (final reaction in [1000, 9000]) {
      final unsure = scheduler.schedule(
        currentIntervalDays: 30,
        result: StudyChoice.unsure,
        reactionTimeMs: reaction,
        reviewedAt: reviewedAt,
      );
      final unknown = scheduler.schedule(
        currentIntervalDays: 30,
        result: StudyChoice.unknown,
        reactionTimeMs: reaction,
        reviewedAt: reviewedAt,
      );
      expect(unsure.nextIntervalDays, 3);
      expect(unsure.nextReviewDate, DateTime(2026, 8, 17));
      expect(unknown.nextIntervalDays, 1);
      expect(unknown.nextReviewDate, DateTime(2026, 8, 15));
    }
  });
}
