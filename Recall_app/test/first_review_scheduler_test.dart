import 'package:flutter_test/flutter_test.dart';
import 'package:recall_app/learning/first_review_scheduler.dart';
import 'package:recall_app/models/first_layer_word_state.dart';
import 'package:recall_app/models/learning_record.dart';

void main() {
  const scheduler = FirstReviewScheduler();
  final baseDate = DateTime(2026, 12, 31, 23, 59);

  test('first known schedules three local calendar days later', () {
    expect(
      scheduler.calculateFirstReviewDate(
        _record(first: StudyChoice.known),
        baseDate: baseDate,
      ),
      DateTime(2027, 1, 3),
    );
  });

  test('first unsure and finally known schedules two days later', () {
    expect(
      scheduler.calculateFirstReviewDate(
        _record(first: StudyChoice.unsure, third: StudyChoice.known),
        baseDate: baseDate,
      ),
      DateTime(2027, 1, 2),
    );
  });

  test('first unknown and finally known schedules one day later', () {
    expect(
      scheduler.calculateFirstReviewDate(
        _record(first: StudyChoice.unknown, third: StudyChoice.known),
        baseDate: baseDate,
      ),
      DateTime(2027, 1, 1),
    );
  });

  test('third unsure and third unknown both schedule one day later', () {
    for (final third in [StudyChoice.unsure, StudyChoice.unknown]) {
      expect(
        scheduler.calculateFirstReviewDate(
          _record(first: StudyChoice.unsure, third: third),
          baseDate: baseDate,
        ),
        DateTime(2027, 1, 1),
      );
    }
  });
}

LearningRecord _record({required StudyChoice first, StudyChoice? third}) {
  return LearningRecord(
    wordId: 'sample',
    word: 'sample',
    stage: LearningStage.contextStrengthening,
    firstResult: first,
    secondResult: third == null ? null : StudyChoice.known,
    thirdResult: third,
    isDifficult: third == StudyChoice.unknown,
    firstLayerCompletedAt: DateTime(2026, 12, 31, 20),
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
}
