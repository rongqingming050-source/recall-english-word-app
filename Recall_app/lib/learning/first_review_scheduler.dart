import '../models/first_layer_word_state.dart';
import '../models/learning_record.dart';

/// Calculates the first formal review date from completed first-layer data.
///
/// All intervals are local calendar days. Times of day are intentionally
/// discarded so that "tomorrow" never means "24 hours from now".
class FirstReviewScheduler {
  const FirstReviewScheduler();

  DateTime calculateFirstReviewDate(
    LearningRecord record, {
    required DateTime baseDate,
  }) {
    final first = record.firstResult;
    final third = record.thirdResult;

    if (record.firstLayerCompletedAt == null || first == null) {
      throw StateError('${record.word} has no completed first-layer result.');
    }

    final intervalDays = switch ((first, third)) {
      // A third unsure/unknown answer always has the highest priority.
      (_, StudyChoice.unsure || StudyChoice.unknown) => 1,
      // Initially unknown, but finally known.
      (StudyChoice.unknown, StudyChoice.known) => 1,
      // Initially unsure, but finally known.
      (StudyChoice.unsure, StudyChoice.known) => 2,
      // A directly-known word appears only once.
      (StudyChoice.known, null) => 3,
      _ => throw StateError(
        '${record.word} has an invalid first-layer result sequence.',
      ),
    };

    final date = localDateOnly(baseDate);
    return DateTime(date.year, date.month, date.day + intervalDays);
  }
}
